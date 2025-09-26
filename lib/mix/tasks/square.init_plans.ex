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
    # Add an example plan structure
    example_config = %{
      "development" => %{
        "plans" => %{
          "basic" => %{
            "name" => "Basic Plan",
            "description" => "Essential features for individuals",
            "base_plan_id" => nil,
            "variations" => %{
              "weekly" => %{
                "name" => "Weekly",
                "amount" => 350,
                "currency" => "USD",
                "cadence" => "WEEKLY",
                "variation_id" => nil
              },
              "monthly" => %{
                "name" => "Monthly",
                "amount" => 999,
                "currency" => "USD",
                "cadence" => "MONTHLY",
                "variation_id" => nil
              },
              "yearly" => %{
                "name" => "Annual (Save 17%)",
                "amount" => 9900,
                "currency" => "USD",
                "cadence" => "ANNUAL",
                "variation_id" => nil
              }
            }
          },
          "premium" => %{
            "name" => "Premium Plan",
            "description" => "Advanced features for teams",
            "base_plan_id" => nil,
            "variations" => %{
              "weekly" => %{
                "name" => "Weekly",
                "amount" => 1050,
                "currency" => "USD",
                "cadence" => "WEEKLY",
                "variation_id" => nil
              },
              "monthly" => %{
                "name" => "Monthly",
                "amount" => 2999,
                "currency" => "USD",
                "cadence" => "MONTHLY",
                "variation_id" => nil
              },
              "yearly" => %{
                "name" => "Annual (Save 17%)",
                "amount" => 29900,
                "currency" => "USD",
                "cadence" => "ANNUAL",
                "variation_id" => nil
              }
            }
          }
        }
      },
      "production" => %{
        "plans" => %{}
      }
    }

    path = Application.app_dir(app, Path.join("priv", config_path))

    # Format and save
    content = JSON.encode!(example_config)
    formatted = format_json(content)
    File.write!(path, formatted)

    IO.puts("\n📝 Added example subscription plans:")
    IO.puts("   - Basic Plan: $3.50/week, $9.99/month, $99/year")
    IO.puts("   - Premium Plan: $10.50/week, $29.99/month, $299/year")
    IO.puts("\nCustomize these plans in the configuration file.")
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
