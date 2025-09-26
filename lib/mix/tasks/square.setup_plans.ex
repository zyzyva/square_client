defmodule Mix.Tasks.Square.SetupPlans do
  @moduledoc """
  Set up Square subscription plans using the recommended pattern:
  - Base plans (what you're selling)
  - Variations (how it's sold - monthly, yearly, etc.)

  Usage:
      mix square.setup_plans
      mix square.setup_plans --app my_app
      mix square.setup_plans --config custom_plans.json

  Options:
    --app       Optional. The application atom (defaults to current app)
    --config    Optional. Path to config file (default: square_plans.json)

  This will create the subscription plans and variations in your Square account
  and update the configuration file with the generated IDs.
  """
  use Mix.Task

  alias SquareClient.{Plans, Catalog}

  @shortdoc "Create subscription plans and variations in Square"

  @switches [
    app: :string,
    config: :string
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    app = get_app(opts[:app])
    config_path = opts[:config] || "square_plans.json"

    Mix.Task.run("app.start")

    IO.puts("Setting up Square subscription plans...")
    IO.puts("Using Square's recommended pattern: base plans with variations\n")

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

    IO.puts("\n✅ Setup complete!")
    IO.puts("\nNext steps:")
    IO.puts("1. Verify plans: mix square.list_plans --app #{app}")
    IO.puts("2. Commit the updated configuration to version control")
    IO.puts("3. Use variation IDs in your subscription code")
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
    if plan_config["base_plan_id"] do
      IO.puts("   ✓ Base plan already exists: #{plan_config["base_plan_id"]}")
      plan_config["base_plan_id"]
    else
      IO.puts("   📝 Creating base plan...")

      case Catalog.create_base_subscription_plan(%{
             name: plan_config["name"],
             description: plan_config["description"]
           }) do
        {:ok, result} ->
          IO.puts("   ✅ Created base plan: #{result.plan_id}")

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
      if variation_config["variation_id"] do
        IO.puts(
          "   ✓ Variation '#{variation_config["name"]}' already exists: #{variation_config["variation_id"]}"
        )
      else
        IO.puts("   📝 Creating variation: #{variation_config["name"]}")

        case Catalog.create_plan_variation(%{
               base_plan_id: base_plan_id,
               name: variation_config["name"],
               cadence: variation_config["cadence"],
               amount: variation_config["amount"],
               currency: variation_config["currency"]
             }) do
          {:ok, result} ->
            IO.puts("   ✅ Created variation: #{result.variation_id}")

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
      end
    end)
  end
end
