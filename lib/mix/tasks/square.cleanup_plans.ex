defmodule Mix.Tasks.Square.CleanupPlans do
  @moduledoc """
  Clean up (delete) UNUSED Square subscription plans from your account.

  ⚠️  IMPORTANT LIMITATIONS:
  - Plans can ONLY be deleted if they have NEVER been used to create subscriptions
  - Once a plan has been used (even once), it CANNOT be deleted from Square
  - This task is primarily useful for cleaning up test plans during development
  - For production plans with active subscriptions, you must cancel subscriptions instead

  Usage:
      mix square.cleanup_plans
      mix square.cleanup_plans --app my_app
      mix square.cleanup_plans --config custom_plans.json
      mix square.cleanup_plans --confirm

  Options:
    --app       Optional. The application atom (defaults to current app)
    --config    Optional. Path to config file (default: square_plans.json)
    --confirm   Skip confirmation prompt (for scripting)

  This will attempt to:
  1. Delete subscription variations from Square (if unused)
  2. Delete base plans from Square (if unused)
  3. Clear the IDs from your configuration file

  Note: Deletion will fail with an error if the plan has been used.
  In production, consider archiving plans instead of deleting them.
  """
  use Mix.Task

  alias SquareClient.{Plans, Catalog}

  @shortdoc "Delete UNUSED subscription plans from Square (development only!)"

  @switches [
    app: :string,
    config: :string,
    confirm: :boolean
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    app = get_app(opts[:app])
    config_path = opts[:config] || "square_plans.json"
    auto_confirm = opts[:confirm] || false

    Mix.Task.run("app.start")

    IO.puts("⚠️  Square Subscription Plans Cleanup (Development Only)")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("\nWARNING: This will attempt to DELETE plans from Square!")
    IO.puts("NOTE: Plans can only be deleted if they have NEVER been used.")
    IO.puts("Plans with existing subscriptions CANNOT be deleted.\n")

    plan_configs = Plans.get_plans(app, config_path)

    if map_size(plan_configs) == 0 do
      IO.puts("No plans configured to clean up.")
      exit(:normal)
    end

    # Show what will be deleted
    IO.puts("Plans to be deleted:")

    Enum.each(plan_configs, fn {plan_key, plan_config} ->
      IO.puts("\n📦 #{plan_key}: #{plan_config["name"] || plan_key}")

      if plan_config["base_plan_id"] do
        IO.puts("   Base Plan ID: #{plan_config["base_plan_id"]}")
      end

      variations = plan_config["variations"] || %{}

      Enum.each(variations, fn {var_key, var_config} ->
        if var_config["variation_id"] do
          IO.puts("   - #{var_key}: #{var_config["variation_id"]}")
        end
      end)
    end)

    # Confirm unless auto-confirm
    unless auto_confirm do
      IO.puts("\nAre you sure you want to delete these plans? (yes/no)")
      confirmation = IO.gets("") |> String.trim() |> String.downcase()

      unless confirmation in ["yes", "y"] do
        IO.puts("Cleanup cancelled.")
        exit(:normal)
      end
    end

    IO.puts("\n🗑️  Starting cleanup...")

    # Delete variations first, then base plans
    Enum.each(plan_configs, fn {plan_key, plan_config} ->
      delete_plan_items(app, plan_key, plan_config, config_path)
    end)

    IO.puts("\n✅ Cleanup complete!")
    IO.puts("\nThe configuration file has been updated.")
    IO.puts("Plan and variation IDs have been cleared.")
  end

  defp get_app(nil) do
    # Infer from the current Mix project
    Mix.Project.config()[:app] ||
      raise "Could not determine application. Please specify --app explicitly."
  end

  defp get_app(app_string) when is_binary(app_string) do
    String.to_atom(app_string)
  end

  defp delete_plan_items(app, plan_key, plan_config, config_path) do
    IO.puts("\nProcessing #{plan_config["name"] || plan_key}...")

    # Delete variations first
    variations = plan_config["variations"] || %{}

    Enum.each(variations, fn {var_key, var_config} ->
      if var_config["variation_id"] do
        IO.write("   Deleting variation #{var_key}... ")

        case Catalog.delete_catalog_object(var_config["variation_id"]) do
          {:ok, _} ->
            IO.puts("✅")
            # Clear from config
            Plans.update_variation_id(app, plan_key, var_key, nil, config_path)

          {:error, :not_found} ->
            IO.puts("⚠️  Already deleted")
            # Clear from config anyway
            Plans.update_variation_id(app, plan_key, var_key, nil, config_path)

          {:error, reason} ->
            IO.puts("❌ Failed: #{inspect(reason)}")
        end
      end
    end)

    # Delete base plan
    if plan_config["base_plan_id"] do
      IO.write("   Deleting base plan... ")

      case Catalog.delete_catalog_object(plan_config["base_plan_id"]) do
        {:ok, _} ->
          IO.puts("✅")
          # Clear from config
          Plans.update_base_plan_id(app, plan_key, nil, config_path)

        {:error, :not_found} ->
          IO.puts("⚠️  Already deleted")
          # Clear from config anyway
          Plans.update_base_plan_id(app, plan_key, nil, config_path)

        {:error, reason} ->
          IO.puts("❌ Failed: #{inspect(reason)}")
      end
    end
  end
end
