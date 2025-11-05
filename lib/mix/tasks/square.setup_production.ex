defmodule Mix.Tasks.Square.SetupProduction do
  @moduledoc """
  Set up Square subscription plans in the PRODUCTION environment.

  This task allows you to create production plans from your development environment
  before deploying. It temporarily overrides the environment configuration to use
  production Square APIs.

  ⚠️  WARNING: This creates REAL plans in your PRODUCTION Square account!

  Usage:
      mix square.setup_production
      mix square.setup_production --app my_app
      mix square.setup_production --config custom_plans.json
      mix square.setup_production --dry-run

  Options:
    --app       Optional. The application atom (defaults to current app)
    --config    Optional. Path to config file (default: square_plans.json)
    --dry-run   Show what would be created without actually creating anything

  Prerequisites:
    1. Set SQUARE_PRODUCTION_ACCESS_TOKEN environment variable
    2. Ensure your square_plans.json has sandbox IDs already configured
    3. Have production Square account credentials ready

  This task will:
    1. Switch to production Square API temporarily
    2. Create base plans and variations in production
    3. Update square_plans.json with production IDs
    4. Switch back to your normal environment

  Example workflow:
    1. mix square.setup_plans          # Creates sandbox plans
    2. Test thoroughly in sandbox
    3. export SQUARE_PRODUCTION_ACCESS_TOKEN="your_prod_token"
    4. mix square.setup_production      # Creates production plans
    5. Deploy to production
  """
  use Mix.Task

  alias SquareClient.Catalog

  @shortdoc "Create subscription plans in Square PRODUCTION environment"

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

    # Check for production token
    prod_token = System.get_env("SQUARE_PRODUCTION_ACCESS_TOKEN")

    if !prod_token && !dry_run do
      IO.puts("❌ SQUARE_PRODUCTION_ACCESS_TOKEN environment variable not set")
      IO.puts("\nFor safety, production credentials must be provided via environment variable:")
      IO.puts("  export SQUARE_PRODUCTION_ACCESS_TOKEN=\"your_production_token\"")
      exit(:normal)
    end

    Mix.Task.run("app.start")

    IO.puts("🚨 PRODUCTION SETUP 🚨")
    IO.puts("====================")

    if dry_run do
      IO.puts("🔍 DRY RUN MODE - No changes will be made")
    else
      IO.puts("⚠️  This will create REAL plans in your PRODUCTION Square account!")
      IO.puts("\nPress Enter to continue or Ctrl+C to abort...")
      IO.gets("")
    end

    # Store original config
    original_api_url = Application.get_env(:square_client, :api_url)
    original_token = Application.get_env(:square_client, :access_token)

    try do
      if !dry_run do
        # Switch to production API
        Application.put_env(:square_client, :api_url, "https://connect.squareup.com/v2")
        Application.put_env(:square_client, :access_token, prod_token)

        IO.puts("✓ Switched to production Square API")
      end

      # Load raw plans from JSON config (don't transform for environment)
      plan_configs = load_raw_plans(app, config_path)

      # Check what needs to be created
      production_plans = filter_production_unconfigured(plan_configs)

      if Enum.empty?(production_plans) do
        IO.puts("\n✅ All plans already have production IDs configured!")
        IO.puts("\nCurrent production configuration:")
        show_production_config(plan_configs)

        if !dry_run do
          IO.puts("\n🔄 Syncing active status with Square...")
          sync_production_status(app, plan_configs, config_path)
        else
          IO.puts("\n🔄 Would sync active status with Square (dry-run mode)")
        end
      else
        IO.puts("\n📋 Plans needing production setup:")

        Enum.each(production_plans, fn {plan_key, plan_config} ->
          if !plan_config["production_base_plan_id"] do
            IO.puts("  - #{plan_config["name"]} (#{plan_key}) - NEW BASE PLAN NEEDED")
          else
            IO.puts(
              "  - #{plan_config["name"]} (#{plan_key}) - Adding variations to existing plan"
            )
          end

          if plan_config["variations"] do
            Enum.each(plan_config["variations"], fn {_var_key, var_config} ->
              cond do
                !var_config["production_variation_id"] && var_config["active"] != false ->
                  IO.puts("    • #{var_config["name"]} variation - TO BE CREATED")

                var_config["active"] == false ->
                  IO.puts("    • #{var_config["name"]} variation - SKIPPED (inactive)")

                true ->
                  nil
              end
            end)
          end
        end)

        if !dry_run do
          IO.puts("\n🚀 Creating production plans...")

          # Process each plan that needs production setup
          Enum.each(production_plans, fn {plan_key, plan_config} ->
            IO.puts("\n📦 Processing: #{plan_config["name"]}")

            # Use existing base plan or create new one if needed
            production_base_id =
              if plan_config["production_base_plan_id"] do
                IO.puts(
                  "  ✓ Using existing production base plan: #{plan_config["production_base_plan_id"]}"
                )

                plan_config["production_base_plan_id"]
              else
                create_production_base_plan(app, plan_key, plan_config, config_path)
              end

            # Create variations if base plan exists
            if production_base_id && plan_config["variations"] do
              create_production_variations(
                app,
                plan_key,
                plan_config,
                production_base_id,
                config_path
              )
            end
          end)

          IO.puts("\n✅ Production setup complete!")
          IO.puts("\n📝 Updated square_plans.json with production IDs")

          # Also sync status for all plans including newly created ones
          IO.puts("\n🔄 Syncing all plan status with Square...")
          # Reload config to get newly saved IDs
          updated_plan_configs = load_raw_plans(app, config_path)
          sync_production_status(app, updated_plan_configs, config_path)
        else
          IO.puts("\n📋 Dry run complete. Run without --dry-run to create these plans.")
        end
      end
    after
      # Always restore original config
      if original_api_url, do: Application.put_env(:square_client, :api_url, original_api_url)
      if original_token, do: Application.put_env(:square_client, :access_token, original_token)

      if !dry_run do
        IO.puts("\n✓ Restored original Square API configuration")
      end
    end

    IO.puts("\nNext steps:")
    IO.puts("1. Review the updated square_plans.json")
    IO.puts("2. Commit the configuration changes")
    IO.puts("3. Deploy to production with the updated configuration")
  end

  defp get_app(nil) do
    Mix.Project.config()[:app] ||
      raise "Could not determine application. Please specify --app explicitly."
  end

  defp get_app(app_string) when is_binary(app_string) do
    String.to_atom(app_string)
  end

  defp load_raw_plans(app, config_path) do
    priv_path = :code.priv_dir(app)
    path = Path.join(priv_path, config_path)

    case File.read(path) do
      {:ok, content} ->
        case JSON.decode(content) do
          {:ok, %{"plans" => plans}} -> plans
          _ -> %{}
        end

      {:error, _} ->
        %{}
    end
  end

  defp filter_production_unconfigured(plan_configs) do
    plan_configs
    |> Enum.filter(fn {plan_key, config} ->
      # Skip free plans
      if config["type"] == "free" do
        false
      else
        has_base = config["production_base_plan_id"] != nil

        needs_variations =
          if config["variations"] do
            Enum.any?(config["variations"], fn {_var_key, var} ->
              # Only check active variations
              var["active"] != false && !var["production_variation_id"]
            end)
          else
            false
          end

        result = !has_base || needs_variations

        if result do
          IO.puts(
            "Plan #{plan_key} needs setup: has_base=#{has_base}, needs_variations=#{needs_variations}"
          )
        end

        result
      end
    end)
    |> Enum.into(%{})
  end

  defp show_production_config(plan_configs) do
    Enum.each(plan_configs, fn {plan_key, config} ->
      if config["type"] != "free" do
        IO.puts("\n  #{config["name"]} (#{plan_key}):")
        IO.puts("    Base ID: #{config["production_base_plan_id"] || "NOT SET"}")

        if config["variations"] do
          Enum.each(config["variations"], fn {_var_key, var} ->
            IO.puts("    #{var["name"]}: #{var["production_variation_id"] || "NOT SET"}")
          end)
        end
      end
    end)
  end

  defp sync_production_status(app, plan_configs, _config_path) do
    # Sync active status and names for all configured production plans and variations
    Enum.each(plan_configs, fn {_plan_key, config} ->
      if config["type"] != "free" do
        prefixed_name = get_prefixed_plan_name(app, config["name"])
        IO.puts("\n📦 Syncing: #{prefixed_name}")

        # Update base plan name if it has a production ID
        if config["production_base_plan_id"] do
          update_plan_name(config["production_base_plan_id"], prefixed_name, "base plan")
        end

        if config["variations"] do
          Enum.each(config["variations"], fn {_var_key, variation_config} ->
            variation_id = variation_config["production_variation_id"]
            is_active = variation_config["active"] != false

            cond do
              # Has production ID and should be active - ensure it's active and name is updated
              variation_id && is_active ->
                ensure_production_variation_active(variation_id, variation_config["name"])
                update_plan_name(variation_id, variation_config["name"], "variation")

              # Has production ID but should be inactive - ensure it's deactivated
              variation_id && !is_active ->
                ensure_production_variation_inactive(variation_id, variation_config["name"])

              # No production ID and inactive - nothing to do
              !variation_id && !is_active ->
                IO.puts(
                  "  ⏭️  Skipping inactive variation without ID: #{variation_config["name"]}"
                )

              # No production ID but active - warn that it needs to be created
              !variation_id && is_active ->
                IO.puts(
                  "  ⚠️  Active variation missing production ID: #{variation_config["name"]}"
                )

                IO.puts("      Run without existing IDs to create this variation")

              true ->
                nil
            end
          end)
        end
      end
    end)

    IO.puts("\n✅ Production sync complete!")
  end

  defp create_production_base_plan(app, plan_key, plan_config, config_path) do
    IO.puts("  📝 Creating production base plan...")

    # Add app prefix to plan name for clarity in Square Dashboard
    prefixed_name = get_prefixed_plan_name(app, plan_config["name"])

    case Catalog.create_base_subscription_plan(%{
           name: prefixed_name,
           description: plan_config["description"]
         }) do
      {:ok, result} ->
        IO.puts("  ✅ Created base plan: #{result.plan_id}")

        # Update the production ID field in config
        update_production_base_plan_id(app, plan_key, result.plan_id, config_path)

        result.plan_id

      {:error, reason} ->
        IO.puts("  ❌ Failed to create base plan: #{inspect(reason)}")
        nil
    end
  end

  defp create_production_variations(app, plan_key, plan_config, base_plan_id, config_path) do
    Enum.each(plan_config["variations"] || %{}, fn {variation_key, variation_config} ->
      variation_id = variation_config["production_variation_id"]
      is_active = variation_config["active"] != false

      cond do
        # Has ID and is active - ensure it's active in Square
        variation_id && is_active ->
          ensure_production_variation_active(variation_id, variation_config["name"])

        # Has ID but inactive - ensure it's deactivated in Square
        variation_id && !is_active ->
          ensure_production_variation_inactive(variation_id, variation_config["name"])

        # No ID but active - create it
        !variation_id && is_active ->
          IO.puts("  📝 Creating production variation: #{variation_config["name"]}")

          case Catalog.create_plan_variation(%{
                 base_plan_id: base_plan_id,
                 name: variation_config["name"],
                 cadence: variation_config["cadence"],
                 amount: variation_config["amount"],
                 currency: variation_config["currency"]
               }) do
            {:ok, result} ->
              IO.puts("  ✅ Created variation: #{result.variation_id}")

              # Update the production ID field in config
              update_production_variation_id(
                app,
                plan_key,
                variation_key,
                result.variation_id,
                config_path
              )

            {:error, reason} ->
              IO.puts("  ❌ Failed to create variation: #{inspect(reason)}")
          end

        # No ID and inactive - skip
        true ->
          IO.puts("  ⏭️  Skipping inactive variation: #{variation_config["name"]}")
      end
    end)
  end

  defp ensure_production_variation_active(variation_id, name) do
    case get_catalog_status(variation_id) do
      {:ok, :active} ->
        IO.puts("  ✓ Production variation '#{name}' is active: #{variation_id}")

      {:ok, :deleted} ->
        IO.puts("  🔄 Reactivating variation '#{name}': #{variation_id}")
        update_catalog_status(variation_id, false)

      {:error, :not_found} ->
        IO.puts("  ⚠️  Variation '#{name}' not found in Square: #{variation_id}")

      _ ->
        IO.puts("  ✓ Production variation '#{name}' exists: #{variation_id}")
    end
  end

  defp ensure_production_variation_inactive(variation_id, name) do
    case get_catalog_status(variation_id) do
      {:ok, :active} ->
        IO.puts("  🔄 Deactivating variation '#{name}': #{variation_id}")
        update_catalog_status(variation_id, true)

      {:ok, :deleted} ->
        IO.puts("  ✓ Variation '#{name}' is already deactivated: #{variation_id}")

      {:error, :not_found} ->
        IO.puts("  ⏭️  Variation '#{name}' doesn't exist (inactive): #{variation_id}")

      _ ->
        IO.puts("  ⏭️  Skipping inactive variation '#{name}': #{variation_id}")
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
    with {:ok, current_object} <- Catalog.get(object_id) do
      # Set present_at_all_locations to false to deactivate, true to activate
      updated_object = Map.put(current_object, "present_at_all_locations", !should_deactivate)

      case update_catalog_object(object_id, updated_object) do
        :ok ->
          action = if should_deactivate, do: "Deactivated", else: "Reactivated"
          IO.puts("    ✅ #{action} successfully")
          :ok

        {:error, reason} ->
          IO.puts("    ❌ Failed to update status: #{reason}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        IO.puts("    ❌ Failed to get current object: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper to update production base plan ID
  defp update_production_base_plan_id(app, plan_key, base_plan_id, config_path) do
    config = load_raw_config(app, config_path)

    updated_config =
      config
      |> ensure_plan_exists(plan_key)
      |> put_in(["plans", plan_key, "production_base_plan_id"], base_plan_id)

    save_config(app, updated_config, config_path)
  end

  # Helper to update production variation ID
  defp update_production_variation_id(app, plan_key, variation_key, variation_id, config_path) do
    config = load_raw_config(app, config_path)

    updated_config =
      config
      |> ensure_variation_exists(plan_key, variation_key)
      |> put_in(
        ["plans", plan_key, "variations", variation_key, "production_variation_id"],
        variation_id
      )

    save_config(app, updated_config, config_path)
  end

  defp load_raw_config(app, config_path) do
    path = Application.app_dir(app, Path.join("priv", config_path))

    case File.read(path) do
      {:ok, content} ->
        case JSON.decode(content) do
          {:ok, config} -> config
          {:error, _} -> %{"plans" => %{}, "one_time_purchases" => %{}}
        end

      {:error, _} ->
        %{"plans" => %{}, "one_time_purchases" => %{}}
    end
  end

  defp save_config(app, config, config_path) do
    path = Application.app_dir(app, Path.join("priv", config_path))

    Path.dirname(path) |> File.mkdir_p!()

    content = JSON.encode!(config)
    formatted = format_json(content)
    File.write!(path, formatted)

    :ok
  end

  defp format_json(json_string) do
    json_string
    |> String.replace(~r/,(?=")/, ",\n    ")
    |> String.replace("{\"", "{\n  \"")
    |> String.replace("\"}", "\"\n}")
    |> String.replace(":{", ": {")
    |> String.replace("},", "},\n")
    |> String.replace("[{", "[\n  {")
    |> String.replace("}]", "}\n]")
  end

  defp ensure_plan_exists(config, plan_key) do
    config = Map.put_new(config, "plans", %{})

    default_plan = %{
      "sandbox_base_plan_id" => nil,
      "production_base_plan_id" => nil
    }

    existing_plan = config["plans"][plan_key] || default_plan
    put_in(config, ["plans", plan_key], existing_plan)
  end

  defp ensure_variation_exists(config, plan_key, variation_key) do
    config
    |> ensure_plan_exists(plan_key)
    |> put_in(
      ["plans", plan_key, "variations"],
      config["plans"][plan_key]["variations"] || %{}
    )
    |> put_in(
      ["plans", plan_key, "variations", variation_key],
      config["plans"][plan_key]["variations"][variation_key] || %{}
    )
  end

  defp extract_error_message(%{"errors" => [%{"detail" => detail} | _]}), do: detail
  defp extract_error_message(%{"errors" => errors}) when is_list(errors), do: "#{inspect(errors)}"
  defp extract_error_message(body), do: "HTTP error: #{inspect(body)}"

  defp update_plan_name(object_id, new_name, object_type) do
    with {:ok, current_object} <- Catalog.get(object_id) do
      current_name = get_object_name(current_object)

      if current_name == new_name do
        IO.puts("  ✓ #{String.capitalize(object_type)} name is already '#{new_name}'")
        :ok
      else
        IO.puts("  🔄 Updating #{object_type} name from '#{current_name}' to '#{new_name}'")

        # Update the name in the appropriate field based on object type
        updated_object = update_object_name(current_object, new_name)

        case update_catalog_object(object_id, updated_object) do
          :ok ->
            IO.puts("     ✅ Name updated successfully")
            :ok

          {:error, reason} ->
            IO.puts("     ❌ Failed to update name: #{reason}")
            {:error, reason}
        end
      end
    else
      {:error, reason} ->
        IO.puts("  ⚠️  Could not check #{object_type} name: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Common function to update a catalog object in Square
  defp update_catalog_object(_object_id, updated_object) do
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
        :ok

      {:ok, %{status: _status, body: body}} ->
        error_msg = extract_error_message(body)
        {:error, error_msg}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp get_object_name(%{"subscription_plan_data" => %{"name" => name}}), do: name
  defp get_object_name(%{"subscription_plan_variation_data" => %{"name" => name}}), do: name
  defp get_object_name(%{"item_data" => %{"name" => name}}), do: name
  defp get_object_name(_), do: "Unknown"

  defp update_object_name(%{"subscription_plan_data" => _data} = object, new_name) do
    put_in(object, ["subscription_plan_data", "name"], new_name)
  end

  defp update_object_name(%{"subscription_plan_variation_data" => _data} = object, new_name) do
    put_in(object, ["subscription_plan_variation_data", "name"], new_name)
  end

  defp update_object_name(%{"item_data" => _data} = object, new_name) do
    put_in(object, ["item_data", "name"], new_name)
  end

  defp update_object_name(object, _new_name), do: object

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
