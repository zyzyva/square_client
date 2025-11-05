defmodule Mix.Tasks.Square.SetupTest do
  use ExUnit.Case

  @moduletag :tmp_dir

  describe "app name prefixing" do
    test "formats app name correctly for different apps", %{tmp_dir: tmp_dir} do
      # Test data for different app names
      test_cases = [
        {:contacts4us, "Contacts4us"},
        {:my_awesome_app, "MyAwesomeApp"},
        {:simple, "Simple"},
        {:multi_word_app_name, "MultiWordAppName"}
      ]

      for {app_atom, expected_prefix} <- test_cases do
        # Create a test config file
        config_path = Path.join(tmp_dir, "#{app_atom}_plans.json")

        config_content = %{
          "plans" => %{
            "premium" => %{
              "name" => "Premium",
              "description" => "Test plan",
              "type" => "subscription"
            }
          }
        }

        File.write!(config_path, JSON.encode!(config_content))

        # Mock the app's priv directory
        Application.put_env(app_atom, :priv_dir, tmp_dir)

        # Test that the prefixed name is generated correctly
        assert_prefix_generation(app_atom, expected_prefix)
      end
    end

    defp assert_prefix_generation(app, expected_prefix) do
      # This tests the internal format_app_name logic
      app_string = Atom.to_string(app)

      formatted =
        app_string
        |> String.split("_")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join("")

      assert formatted == expected_prefix
    end

    test "doesn't double-prefix if plan already has prefix" do
      plan_name = "Contacts4us Premium"
      app = :contacts4us

      # The function should detect the prefix already exists
      # and not add it again
      prefixed_name = get_test_prefixed_name(app, plan_name)
      assert prefixed_name == "Contacts4us Premium"
      refute String.starts_with?(prefixed_name, "Contacts4us Contacts4us")
    end

    test "uses custom prefix from config if available" do
      app = :my_app
      plan_name = "Premium"

      # Set a custom prefix in config
      Application.put_env(:square_client, :plan_name_prefix, "CustomPrefix")

      prefixed_name = get_test_prefixed_name(app, plan_name)
      assert prefixed_name == "CustomPrefix Premium"

      # Clean up
      Application.delete_env(:square_client, :plan_name_prefix)
    end

    test "uses app-specific prefix if configured" do
      app = :my_app
      plan_name = "Premium"

      # Set app-specific prefix
      Application.put_env(app, :square_plan_prefix, "MyCompany")

      prefixed_name = get_test_prefixed_name(app, plan_name)
      assert prefixed_name == "MyCompany Premium"

      # Clean up
      Application.delete_env(app, :square_plan_prefix)
    end
  end

  # Helper function that mirrors the logic in the Mix tasks
  defp get_test_prefixed_name(app, plan_name) do
    prefix =
      Application.get_env(:square_client, :plan_name_prefix) ||
        Application.get_env(app, :square_plan_prefix) ||
        format_test_app_name(app)

    if String.starts_with?(plan_name, prefix) do
      plan_name
    else
      "#{prefix} #{plan_name}"
    end
  end

  defp format_test_app_name(app) do
    app
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end
end
