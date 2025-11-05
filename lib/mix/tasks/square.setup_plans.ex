defmodule Mix.Tasks.Square.SetupPlans do
  @moduledoc """
  Set up Square subscription plans in the SANDBOX environment.

  Uses Square's recommended pattern:
  - Base plans (what you're selling)
  - Variations (how it's sold - monthly, yearly, etc.)

  Usage:
      mix square.setup_plans
      mix square.setup_plans --app my_app
      mix square.setup_plans --config custom_plans.json
      mix square.setup_plans --dry-run

  Options:
    --app       Optional. The application atom (defaults to current app)
    --config    Optional. Path to config file (default: square_plans.json)
    --dry-run   Preview changes without creating anything

  This will create the subscription plans and variations in your Square SANDBOX account
  and update the configuration file with the sandbox IDs.

  For production setup, use: mix square.setup_production
  """
  use Mix.Task

  alias SquareClient.{Plans, Catalog}

  @shortdoc "Create subscription plans in Square SANDBOX environment"

  @switches [
    app: :string,
    config: :string,
    dry_run: :boolean
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    app = get_app(opts[:app])
    config_path = opts[:config] || "square_plans.json"
    dry_run = opts[:dry_run] || false

    Mix.Task.run("app.start")

    IO.puts("Setting up Square SANDBOX subscription plans...")
    IO.puts("Using Square's recommended pattern: base plans with variations\n")

    if dry_run do
      IO.puts("🔍 DRY RUN MODE - No changes will be made\n")
    end

    # Load plans from JSON config
    plan_configs = Plans.get_plans(app, config_path)

    if map_size(plan_configs) == 0 do
      IO.puts("❌ No plans configured in #{config_path}")
      IO.puts("   Please configure your plans first.")
      IO.puts("\nYou can initialize a config file with:")
      IO.puts("   mix square.init_plans --app #{app}")
      exit(:normal)
    end

    # Process each plan
    if !dry_run do
      Enum.each(plan_configs, fn {plan_key, plan_config} ->
        IO.puts("📦 Processing plan: #{plan_config["name"]}")

        # Step 1: Create or update base plan
        base_plan_id = ensure_base_plan(app, plan_key, plan_config, config_path)

        # Step 2: Create or update variations
        if base_plan_id do
          create_variations(app, plan_key, plan_config, base_plan_id, config_path)
        end

        IO.puts("")
      end)

      IO.puts("\n✅ Sandbox setup complete!")
    else
      IO.puts("📋 Plans that would be processed:")

      Enum.each(plan_configs, fn {_plan_key, plan_config} ->
        IO.puts("  - #{plan_config["name"]}")

        if plan_config["variations"] do
          Enum.each(plan_config["variations"], fn {_var_key, var} ->
            if var["active"] != false do
              status =
                if var["variation_id"] || var["sandbox_variation_id"],
                  do: "exists",
                  else: "would be created"

              IO.puts("    • #{var["name"]} (#{status})")
            else
              IO.puts("    • #{var["name"]} (inactive - skipped)")
            end
          end)
        end
      end)

      IO.puts("\n📋 Dry run complete. Run without --dry-run to apply changes.")
    end

    IO.puts("\nNext steps:")
    IO.puts("1. Verify plans: mix square.list_plans --app #{app}")
    IO.puts("2. Test thoroughly in sandbox")
    IO.puts("3. When ready for production: mix square.setup_production --app #{app}")
    IO.puts("4. Commit the updated configuration to version control")
  end

  defp get_app(nil) do
    # Infer from the current Mix project
    Mix.Project.config()[:app] ||
      raise "Could not determine application. Please specify --app explicitly."
  end

  defp get_app(app_string) when is_binary(app_string) do
    String.to_atom(app_string)
  end

  defp ensure_base_plan(app, plan_key, plan_config, config_path) do
    # Check for sandbox ID (after environment transformation)
    if plan_config["base_plan_id"] do
      IO.puts("   ✓ Sandbox base plan already exists: #{plan_config["base_plan_id"]}")
      plan_config["base_plan_id"]
    else
      IO.puts("   📝 Creating base plan...")

      # Add app prefix to plan name for clarity in Square Dashboard
      prefixed_name = get_prefixed_plan_name(app, plan_config["name"])

      case Catalog.create_base_subscription_plan(%{
             name: prefixed_name,
             description: plan_config["description"]
           }) do
        {:ok, result} ->
          IO.puts("   ✅ Created sandbox base plan: #{result.plan_id}")

          # Save to config
          Plans.update_base_plan_id(app, plan_key, result.plan_id, config_path)

          result.plan_id

        {:error, reason} ->
          IO.puts("   ❌ Failed to create base plan: #{inspect(reason)}")
          nil
      end
    end
  end

  defp create_variations(app, plan_key, plan_config, base_plan_id, config_path) do
    Enum.each(plan_config["variations"] || %{}, fn {variation_key, variation_config} ->
      variation_id = variation_config["variation_id"] || variation_config["sandbox_variation_id"]
      is_active = variation_config["active"] != false

      cond do
        # Has ID and is active - ensure it's active in Square
        variation_id && is_active ->
          ensure_variation_active(variation_id, variation_config["name"])

        # Has ID but inactive - ensure it's deactivated in Square
        variation_id && !is_active ->
          ensure_variation_inactive(variation_id, variation_config["name"])

        # No ID but active - create it
        !variation_id && is_active ->
          IO.puts("   📝 Creating variation: #{variation_config["name"]}")

          case Catalog.create_plan_variation(%{
                 base_plan_id: base_plan_id,
                 name: variation_config["name"],
                 cadence: variation_config["cadence"],
                 amount: variation_config["amount"],
                 currency: variation_config["currency"]
               }) do
            {:ok, result} ->
              IO.puts("   ✅ Created sandbox variation: #{result.variation_id}")

              # Save to config
              Plans.update_variation_id(
                app,
                plan_key,
                variation_key,
                result.variation_id,
                config_path
              )

            {:error, reason} ->
              IO.puts("   ❌ Failed to create variation: #{inspect(reason)}")
          end

        # No ID and inactive - skip
        true ->
          IO.puts("   ⏭️  Skipping inactive variation: #{variation_config["name"]}")
      end
    end)
  end

  defp ensure_variation_active(variation_id, name) do
    case get_catalog_status(variation_id) do
      {:ok, :active} ->
        IO.puts("   ✓ Sandbox variation '#{name}' is active: #{variation_id}")

      {:ok, :deleted} ->
        IO.puts("   🔄 Reactivating variation '#{name}': #{variation_id}")
        update_catalog_status(variation_id, false)

      {:error, :not_found} ->
        IO.puts("   ⚠️  Variation '#{name}' not found in Square: #{variation_id}")

      _ ->
        IO.puts("   ✓ Sandbox variation '#{name}' exists: #{variation_id}")
    end
  end

  defp ensure_variation_inactive(variation_id, name) do
    case get_catalog_status(variation_id) do
      {:ok, :active} ->
        IO.puts("   🔄 Deactivating variation '#{name}': #{variation_id}")
        update_catalog_status(variation_id, true)

      {:ok, :deleted} ->
        IO.puts("   ✓ Variation '#{name}' is already deactivated: #{variation_id}")

      {:error, :not_found} ->
        IO.puts("   ⏭️  Variation '#{name}' doesn't exist (inactive): #{variation_id}")

      _ ->
        IO.puts("   ⏭️  Skipping inactive variation '#{name}': #{variation_id}")
    end
  end

  defp get_catalog_status(object_id) do
    case Catalog.get(object_id) do
      {:ok, %{"present_at_all_locations" => false}} -> {:ok, :deleted}
      {:ok, _} -> {:ok, :active}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :unknown}
    end
  end

  defp update_catalog_status(object_id, should_deactivate) do
    case Catalog.get(object_id) do
      {:ok, current_object} ->
        # Set present_at_all_locations to false to deactivate, true to activate
        updated_object = Map.put(current_object, "present_at_all_locations", !should_deactivate)

        body = %{
          idempotency_key: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
          object: updated_object
        }

        api_url = SquareClient.Config.api_url!()
        access_token = SquareClient.Config.access_token!()

        case Req.post(
               "#{api_url}/catalog/object",
               json: body,
               headers: [
                 {"Authorization", "Bearer #{access_token}"},
                 {"Square-Version", "2025-01-23"}
               ]
             ) do
          {:ok, %{status: status}} when status in 200..299 ->
            action = if should_deactivate, do: "Deactivated", else: "Reactivated"
            IO.puts("     ✅ #{action} successfully")
            :ok

          {:ok, %{status: status, body: body}} ->
            error_msg = extract_error_message(body)
            IO.puts("     ❌ Failed to update status: #{error_msg}")
            {:error, status}

          {:error, reason} ->
            IO.puts("     ❌ Failed to update: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("     ❌ Failed to get current object: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_error_message(%{"errors" => [%{"detail" => detail} | _]}), do: detail
  defp extract_error_message(%{"errors" => errors}) when is_list(errors), do: "#{inspect(errors)}"
  defp extract_error_message(body), do: "HTTP error: #{inspect(body)}"

  defp get_prefixed_plan_name(app, plan_name) do
    # Check if custom prefix is configured
    prefix =
      Application.get_env(:square_client, :plan_name_prefix) ||
        Application.get_env(app, :square_plan_prefix) ||
        format_app_name(app)

    # Don't double-prefix if it already starts with the prefix
    if String.starts_with?(plan_name, prefix) do
      plan_name
    else
      "#{prefix} #{plan_name}"
    end
  end

  defp format_app_name(app) do
    app
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end
end
