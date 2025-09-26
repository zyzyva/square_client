defmodule Mix.Tasks.Square.ListPlans do
  @moduledoc """
  List all configured Square subscription plans and their status.

  Usage:
      mix square.list_plans
      mix square.list_plans --app my_app
      mix square.list_plans --config custom_plans.json

  Options:
    --app       Optional. The application atom (defaults to current app)
    --config    Optional. Path to config file (default: square_plans.json)

  Shows:
  - All configured plans and variations
  - Which items have been created in Square (have IDs)
  - Which items still need to be created
  """
  use Mix.Task

  alias SquareClient.Plans

  @shortdoc "List configured Square subscription plans and their status"

  @switches [
    app: :string,
    config: :string
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    app = get_app(opts[:app])
    config_path = opts[:config] || "square_plans.json"

    Mix.Task.run("app.start")

    IO.puts("Square Subscription Plans Configuration")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("")

    plan_configs = Plans.get_plans(app, config_path)

    if map_size(plan_configs) == 0 do
      IO.puts("No plans configured.")
      IO.puts("\nInitialize a config file with:")
      IO.puts("   mix square.init_plans --app #{app}")
      exit(:normal)
    end

    # Check overall status
    all_configured = Plans.all_configured?(app, config_path)

    if all_configured do
      IO.puts("✅ All plans and variations are configured in Square\n")
    else
      IO.puts("⚠️  Some items need to be created in Square\n")
    end

    # List each plan
    Enum.each(plan_configs, fn {plan_key, plan_config} ->
      display_plan(plan_key, plan_config)
    end)

    # Show unconfigured items
    unconfigured = Plans.unconfigured_items(app, config_path)

    if length(unconfigured.base_plans) > 0 or length(unconfigured.variations) > 0 do
      IO.puts("\n" <> String.duplicate("-", 50))
      IO.puts("Items needing creation:")

      if length(unconfigured.base_plans) > 0 do
        IO.puts("\n📦 Base Plans:")

        Enum.each(unconfigured.base_plans, fn {key, plan} ->
          IO.puts("   - #{key}: #{plan["name"]}")
        end)
      end

      if length(unconfigured.variations) > 0 do
        IO.puts("\n📋 Variations:")

        Enum.each(unconfigured.variations, fn {plan_key, var_key, var, _base_id} ->
          IO.puts("   - #{plan_key}.#{var_key}: #{var["name"] || var_key}")
        end)
      end

      IO.puts("\nRun 'mix square.setup_plans --app #{app}' to create these items")
    end
  end

  defp get_app(nil) do
    # Infer from the current Mix project
    Mix.Project.config()[:app] ||
      raise "Could not determine application. Please specify --app explicitly."
  end

  defp get_app(app_string) when is_binary(app_string) do
    String.to_atom(app_string)
  end

  defp display_plan(plan_key, plan_config) do
    base_status = if plan_config["base_plan_id"], do: "✅", else: "❌"

    IO.puts("📦 #{plan_key}: #{plan_config["name"] || plan_key}")
    IO.puts("   #{base_status} Base Plan ID: #{plan_config["base_plan_id"] || "Not created"}")

    if plan_config["description"] do
      IO.puts("   Description: #{plan_config["description"]}")
    end

    variations = plan_config["variations"] || %{}

    if map_size(variations) > 0 do
      IO.puts("   Variations:")

      Enum.each(variations, fn {var_key, var_config} ->
        var_status = if var_config["variation_id"], do: "✅", else: "❌"

        IO.puts("      #{var_status} #{var_key}:")
        IO.puts("         Name: #{var_config["name"] || var_key}")

        if var_config["variation_id"] do
          IO.puts("         ID: #{var_config["variation_id"]}")
        else
          IO.puts("         ID: Not created")
        end

        if var_config["amount"] do
          amount_display = format_amount(var_config["amount"], var_config["currency"])
          IO.puts("         Amount: #{amount_display}")
        end

        if var_config["cadence"] do
          IO.puts("         Cadence: #{var_config["cadence"]}")
        end
      end)
    else
      IO.puts("   No variations configured")
    end

    IO.puts("")
  end

  defp format_amount(amount_cents, "USD") do
    dollars = div(amount_cents, 100)
    cents = rem(amount_cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end

  defp format_amount(amount, currency) do
    "#{amount} #{currency || "?"}"
  end
end
