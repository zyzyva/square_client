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

  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_options(args)

    Mix.Task.run("app.start")

    IO.puts("Square Subscription Plans Configuration")
    IO.puts(String.duplicate("=", 50))
    IO.puts("")

    plan_configs = Plans.get_plans(opts.app, opts.config_path)

    ensure_plans_present!(plan_configs, opts)

    # Check overall status
    print_overall_status(Plans.all_configured?(opts.app, opts.config_path))

    # List each plan
    Enum.each(plan_configs, fn {plan_key, plan_config} ->
      display_plan(plan_key, plan_config)
    end)

    # Show unconfigured items
    show_unconfigured_items(Plans.unconfigured_items(opts.app, opts.config_path), opts)
  end

  defp parse_options(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    %{
      app: get_app(opts[:app]),
      config_path: opts[:config] || "square_plans.json"
    }
  end

  defp ensure_plans_present!(plan_configs, opts) when map_size(plan_configs) == 0 do
    IO.puts("No plans configured.")
    IO.puts("\nInitialize a config file with:")
    IO.puts("   mix square.init_plans --app #{opts.app}")
    exit(:normal)
  end

  defp ensure_plans_present!(_plan_configs, _opts), do: :ok

  defp print_overall_status(true = _all_configured) do
    IO.puts("✅ All plans and variations are configured in Square\n")
  end

  defp print_overall_status(false = _all_configured) do
    IO.puts("⚠️  Some items need to be created in Square\n")
  end

  defp show_unconfigured_items(unconfigured, opts) do
    if length(unconfigured.base_plans) > 0 or length(unconfigured.variations) > 0 do
      print_unconfigured_items(unconfigured, opts)
    else
      :ok
    end
  end

  defp print_unconfigured_items(unconfigured, opts) do
    IO.puts("\n" <> String.duplicate("-", 50))
    IO.puts("Items needing creation:")

    print_unconfigured_base_plans(unconfigured.base_plans)
    print_unconfigured_variations(unconfigured.variations)

    IO.puts("\nRun 'mix square.setup_plans --app #{opts.app}' to create these items")
  end

  defp print_unconfigured_base_plans([]), do: :ok

  defp print_unconfigured_base_plans(base_plans) do
    IO.puts("\n📦 Base Plans:")

    Enum.each(base_plans, fn {key, plan} ->
      IO.puts("   - #{key}: #{plan["name"]}")
    end)
  end

  defp print_unconfigured_variations([]), do: :ok

  defp print_unconfigured_variations(variations) do
    IO.puts("\n📋 Variations:")

    Enum.each(variations, fn {plan_key, var_key, var, _base_id} ->
      IO.puts("   - #{plan_key}.#{var_key}: #{var["name"] || var_key}")
    end)
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

    maybe_print_description(plan_config["description"])

    display_variations(plan_config["variations"] || %{})

    IO.puts("")
  end

  defp maybe_print_description(nil), do: :ok

  defp maybe_print_description(description) do
    IO.puts("   Description: #{description}")
  end

  defp display_variations(variations) when map_size(variations) == 0 do
    IO.puts("   No variations configured")
  end

  defp display_variations(variations) do
    IO.puts("   Variations:")

    Enum.each(variations, fn {var_key, var_config} ->
      display_variation(var_key, var_config)
    end)
  end

  defp display_variation(var_key, var_config) do
    var_status = if var_config["variation_id"], do: "✅", else: "❌"

    IO.puts("      #{var_status} #{var_key}:")
    IO.puts("         Name: #{var_config["name"] || var_key}")

    print_variation_id(var_config["variation_id"])
    maybe_print_amount(var_config["amount"], var_config["currency"])
    maybe_print_cadence(var_config["cadence"])
  end

  defp print_variation_id(nil) do
    IO.puts("         ID: Not created")
  end

  defp print_variation_id(variation_id) do
    IO.puts("         ID: #{variation_id}")
  end

  defp maybe_print_amount(nil, _currency), do: :ok

  defp maybe_print_amount(amount, currency) do
    amount_display = format_amount(amount, currency)
    IO.puts("         Amount: #{amount_display}")
  end

  defp maybe_print_cadence(nil), do: :ok

  defp maybe_print_cadence(cadence) do
    IO.puts("         Cadence: #{cadence}")
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
