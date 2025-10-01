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

  alias SquareClient.{Plans, Catalog}

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

      # Load plans from JSON config
      plan_configs = Plans.get_plans(app, config_path)

      # Check what needs to be created
      production_plans = filter_production_unconfigured(plan_configs)

      if Enum.empty?(production_plans) do
        IO.puts("\n✅ All plans already have production IDs configured!")
        IO.puts("\nCurrent production configuration:")
        show_production_config(plan_configs)
      else
        IO.puts("\n📋 Plans needing production setup:")

        Enum.each(production_plans, fn {plan_key, plan_config} ->
          IO.puts("  - #{plan_config["name"]} (#{plan_key})")

          if plan_config["variations"] do
            Enum.each(plan_config["variations"], fn {_var_key, var_config} ->
              if !var_config["production_variation_id"] do
                IO.puts("    • #{var_config["name"]} variation")
              end
            end)
          end
        end)

        if !dry_run do
          IO.puts("\n🚀 Creating production plans...")

          # Process each plan that needs production setup
          Enum.each(production_plans, fn {plan_key, plan_config} ->
            IO.puts("\n📦 Processing: #{plan_config["name"]}")

            # Create base plan if needed
            production_base_id =
              if !plan_config["production_base_plan_id"] do
                create_production_base_plan(app, plan_key, plan_config, config_path)
              else
                plan_config["production_base_plan_id"]
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

  defp filter_production_unconfigured(plan_configs) do
    plan_configs
    |> Enum.filter(fn {_key, config} ->
      # Skip free plans
      # Check if base plan needs production ID
      # Or if any variations need production IDs
      config["type"] != "free" &&
        (!config["production_base_plan_id"] ||
           (config["variations"] &&
              Enum.any?(config["variations"], fn {_var_key, var} ->
                !var["production_variation_id"]
              end)))
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

  defp create_production_base_plan(app, plan_key, plan_config, config_path) do
    IO.puts("  📝 Creating production base plan...")

    case Catalog.create_base_subscription_plan(%{
           name: plan_config["name"],
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
      if !variation_config["production_variation_id"] do
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
      end
    end)
  end

  # Helper to update production base plan ID
  defp update_production_base_plan_id(app, plan_key, base_plan_id, config_path) do
    config = load_config(app, config_path)

    updated_config =
      config
      |> ensure_plan_exists(plan_key)
      |> put_in(["plans", plan_key, "production_base_plan_id"], base_plan_id)

    save_config(app, updated_config, config_path)
  end

  # Helper to update production variation ID
  defp update_production_variation_id(app, plan_key, variation_key, variation_id, config_path) do
    config = load_config(app, config_path)

    updated_config =
      config
      |> ensure_variation_exists(plan_key, variation_key)
      |> put_in(
        ["plans", plan_key, "variations", variation_key, "production_variation_id"],
        variation_id
      )

    save_config(app, updated_config, config_path)
  end

  defp load_config(app, config_path) do
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
end
