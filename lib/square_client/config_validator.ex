defmodule SquareClient.ConfigValidator do
  @moduledoc """
  Validates Square Client configuration at application startup.
  """

  require Logger

  @doc """
  Validates that all subscription plans have been synced to Square.

  Also checks for accidental changes to immutable fields on existing variations.

  Logs errors for any plans/variations that are missing Square IDs for the current environment.
  Returns :ok regardless to allow the application to start.
  """
  def validate_plans(app_name, config_path \\ "square_plans.json") do
    # Check for immutable field changes first
    check_immutable_changes(app_name, config_path)

    # Then check for unconfigured plans
    case SquareClient.Plans.unconfigured_items(app_name, config_path) do
      %{base_plans: [], variations: []} ->
        :ok

      %{base_plans: base_plans, variations: variations} ->
        env = SquareClient.Plans.environment(app_name)

        unless Enum.empty?(base_plans) do
          plan_names = Enum.map(base_plans, fn {key, _} -> key end) |> Enum.join(", ")

          Logger.error("""
          ⚠️  Square subscription plans are not configured for #{env} environment!

          Missing base plan IDs for: #{plan_names}

          Run the following command to sync plans to Square:
            mix square.setup_plans

          Or for production:
            mix square.setup_production

          Subscription features will not work until plans are configured.
          """)
        end

        unless Enum.empty?(variations) do
          variation_info =
            variations
            |> Enum.map(fn {plan_key, var_key, _variation, _base_id} ->
              "#{plan_key}/#{var_key}"
            end)
            |> Enum.join(", ")

          Logger.error("""
          ⚠️  Square subscription plan variations are not configured for #{env} environment!

          Missing variation IDs for: #{variation_info}

          Run the following command to sync plans to Square:
            mix square.setup_plans

          Or for production:
            mix square.setup_production
          """)
        end

        :ok
    end
  end

  defp check_immutable_changes(app_name, config_path) do
    case SquareClient.Plans.validate_immutable_fields(app_name, config_path) do
      {:ok, []} ->
        # No changes detected
        :ok

      {:warning, changes} ->
        # Log each change as an error
        Logger.error("""
        ⚠️  CRITICAL: Immutable subscription plan fields have been modified!

        Square subscription plans cannot be modified once created. You must create
        NEW variations instead of changing existing ones.
        """)

        Enum.each(changes, fn change ->
          Logger.error("""
            Plan: #{change.plan}
            Variation: #{change.variation}
            Square ID: #{change.variation_id}
            #{change.message}
          """)
        end)

        Logger.error("""

        To fix this:
        1. Revert the changes to existing variations
        2. Create NEW variations with the new values (e.g., monthly_v2)
        3. Set the old variation to "active": false

        See PRICE_CHANGES.md for detailed instructions.
        """)

        :ok

      {:error, reason} ->
        # Git not available or other error - log as info, not error
        Logger.info("Could not validate immutable fields: #{reason}")
        :ok
    end
  end
end
