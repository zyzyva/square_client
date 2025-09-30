defmodule Mix.Tasks.Square.InitPlans do
  @moduledoc """
  Initialize a Square plans configuration file for your application.

  Usage:
      mix square.init_plans
      mix square.init_plans --app my_app
      mix square.init_plans --config custom_plans.json

  Options:
    --app       Optional. The application atom (defaults to current app)
    --config    Optional. Path to config file (default: square_plans.json)

  This creates a configuration file template that you can customize
  with your subscription plans.
  """
  use Mix.Task

  alias SquareClient.Plans

  @shortdoc "Initialize a Square plans configuration file"

  @switches [
    app: :string,
    config: :string
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    app = get_app(opts[:app])
    config_path = opts[:config] || "square_plans.json"

    Mix.Task.run("app.start")

    IO.puts("Initializing Square plans configuration...")

    case Plans.init_config(app, config_path) do
      {:ok, path} ->
        IO.puts("✅ Created configuration file: #{path}")
        IO.puts("\nExample configuration structure added.")
        IO.puts("\nNext steps:")
        IO.puts("1. Edit #{path} to define your subscription plans")
        IO.puts("2. Run 'mix square.setup_plans --app #{app}' to create them in Square")
        IO.puts("3. Commit the configuration file to version control")

        # Add example configuration
        add_example_config(app, config_path)

      {:error, :already_exists} ->
        IO.puts("⚠️  Configuration file already exists")
        IO.puts("\nUse 'mix square.list_plans --app #{app}' to view current configuration")
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

  defp add_example_config(app, config_path) do
    # Add an example plan structure with unified environment handling
    example_config = %{
      "plans" => %{
        "free" => %{
          "name" => "Free",
          "description" => "Basic features for getting started",
          "type" => "free",
          "active" => true,
          "price" => "$0",
          "price_cents" => 0,
          "features" => [
            "5 items per month",
            "Basic support",
            "Community access"
          ]
        },
        "premium" => %{
          "name" => "Premium",
          "description" => "Professional features for power users",
          "type" => "subscription",
          "sandbox_base_plan_id" => nil,
          "production_base_plan_id" => nil,
          "variations" => %{
            "monthly" => %{
              "name" => "Monthly",
              "amount" => 999,
              "currency" => "USD",
              "cadence" => "MONTHLY",
              "sandbox_variation_id" => nil,
              "production_variation_id" => nil,
              "active" => true,
              "price" => "$9.99/mo",
              "price_cents" => 999,
              "auto_renews" => true,
              "billing_notice" => "Billed monthly, auto-renews until cancelled",
              "features" => [
                "Unlimited items",
                "Priority support",
                "API access",
                "Advanced analytics"
              ]
            },
            "yearly" => %{
              "name" => "Annual",
              "amount" => 9900,
              "currency" => "USD",
              "cadence" => "ANNUAL",
              "sandbox_variation_id" => nil,
              "production_variation_id" => nil,
              "active" => true,
              "price" => "$99/year",
              "price_cents" => 9900,
              "auto_renews" => true,
              "billing_notice" => "Billed annually, save $20",
              "features" => [
                "Everything in monthly",
                "Save $20 per year",
                "Early access to features"
              ]
            }
          }
        }
      },
      "one_time_purchases" => %{
        "week_pass" => %{
          "active" => true,
          "name" => "7-Day Pass",
          "description" => "Try premium features for a week",
          "price" => "$4.99",
          "price_cents" => 499,
          "duration_days" => 7,
          "auto_renews" => false,
          "billing_notice" => "One-time payment, NO auto-renewal",
          "features" => [
            "7 days unlimited access",
            "All premium features",
            "No recurring charges",
            "Perfect for events"
          ]
        }
      }
    }

    path = Application.app_dir(app, Path.join("priv", config_path))

    # Format and save
    content = JSON.encode!(example_config)
    formatted = format_json(content)
    File.write!(path, formatted)

    IO.puts("\n📝 Added example payment plans:")
    IO.puts("   - Free: $0 (basic features)")
    IO.puts("   - Premium Monthly: $9.99/month (auto-renews)")
    IO.puts("   - Premium Annual: $99/year (save $20)")
    IO.puts("   - 7-Day Pass: $4.99 (one-time purchase)")
    IO.puts("\nCustomize these plans in the configuration file.")
    IO.puts("\n✨ Key features:")
    IO.puts("   - Unified structure for all environments")
    IO.puts("   - Separate IDs for sandbox and production")
    IO.puts("   - Support for both subscriptions and one-time purchases")
    IO.puts("\nSee JSON_PLANS.md for full documentation.")
  end

  # Basic JSON formatting for readability
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
end
