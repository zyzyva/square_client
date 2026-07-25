defmodule Mix.Tasks.Square.ProvisioningPreflightTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Mix.Tasks.Square.SetupPlans
  alias Mix.Tasks.Square.SetupProduction

  @test_app :square_client
  @test_config "preflight_test_plans.json"

  setup do
    bypass = Bypass.open()

    original_config = Application.get_all_env(:square_client)

    Application.put_env(:square_client, :api_url, "http://localhost:#{bypass.port}/v2")
    Application.put_env(:square_client, :access_token, "test_token")
    Application.put_env(:square_client, :disable_retries, true)

    path = Application.app_dir(@test_app, Path.join("priv", @test_config))
    File.mkdir_p!(Application.app_dir(@test_app, "priv"))

    on_exit(fn ->
      File.rm(path)
      System.delete_env("SQUARE_PRODUCTION_ACCESS_TOKEN")

      Enum.each(original_config, fn {key, value} ->
        Application.put_env(:square_client, key, value)
      end)
    end)

    {:ok, bypass: bypass, path: path}
  end

  defp write_config!(path, config) do
    File.write!(path, JSON.encode!(config))
  end

  defp plan_response(request) do
    %{
      "catalog_object" => %{
        "id" => "PLAN_NEW_1",
        "type" => "SUBSCRIPTION_PLAN",
        "subscription_plan_data" => %{
          "name" => request["object"]["subscription_plan_data"]["name"]
        }
      }
    }
  end

  defp variation_response(request) do
    variation_data = request["object"]["subscription_plan_variation_data"]

    %{
      "catalog_object" => %{
        "id" => "VAR_NEW_1",
        "type" => "SUBSCRIPTION_PLAN_VARIATION",
        "subscription_plan_variation_data" => %{
          "subscription_plan_id" => variation_data["subscription_plan_id"],
          "name" => variation_data["name"],
          "phases" => variation_data["phases"]
        }
      }
    }
  end

  defp respond_by_object_type(conn, on_plan, on_variation) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    request = JSON.decode!(body)

    case request["object"]["type"] do
      "SUBSCRIPTION_PLAN" -> on_plan.(conn, request)
      "SUBSCRIPTION_PLAN_VARIATION" -> on_variation.(conn, request)
    end
  end

  defp json_response(conn, status, payload) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, JSON.encode!(payload))
  end

  describe "mix square.setup_plans — invalid config aborts before any request (T-A)" do
    test "reports the plan, variation, and field; makes zero HTTP requests", %{path: path} do
      write_config!(path, %{
        "plans" => %{
          "premium" => %{
            "name" => "Premium Plan",
            "sandbox_base_plan_id" => nil,
            "production_base_plan_id" => nil,
            "variations" => %{
              "monthly" => %{
                "name" => "Monthly",
                "cadence" => "MONTHLY",
                "amount" => nil,
                "sandbox_variation_id" => nil,
                "production_variation_id" => nil,
                "active" => true
              }
            }
          }
        }
      })

      _log =
        capture_log(fn ->
          output =
            capture_io(fn ->
              assert_raise Mix.Error, fn ->
                SetupPlans.run([
                  "--app",
                  "square_client",
                  "--config",
                  @test_config
                ])
              end
            end)

          send(self(), {:output, output})
        end)

      assert_received {:output, output}
      assert output =~ "premium"
      assert output =~ "monthly"
      assert output =~ "amount"
      assert output =~ "Nothing was created"
    end
  end

  describe "mix square.setup_plans — valid config creates as before (T-B)" do
    test "creation proceeds and the config file is updated with the new sandbox ids", %{
      bypass: bypass,
      path: path
    } do
      write_config!(path, %{
        "plans" => %{
          "premium" => %{
            "name" => "Premium Plan",
            "sandbox_base_plan_id" => nil,
            "production_base_plan_id" => nil,
            "variations" => %{
              "monthly" => %{
                "name" => "Monthly",
                "cadence" => "MONTHLY",
                "amount" => 999,
                "currency" => "USD",
                "sandbox_variation_id" => nil,
                "production_variation_id" => nil,
                "active" => true
              }
            }
          }
        }
      })

      Bypass.expect(bypass, "POST", "/v2/catalog/object", fn conn ->
        respond_by_object_type(
          conn,
          fn conn, request -> json_response(conn, 200, plan_response(request)) end,
          fn conn, request -> json_response(conn, 200, variation_response(request)) end
        )
      end)

      _log =
        capture_log(fn ->
          output =
            capture_io(fn ->
              SetupPlans.run([
                "--app",
                "square_client",
                "--config",
                @test_config
              ])
            end)

          send(self(), {:output, output})
        end)

      assert_received {:output, output}
      assert output =~ "✅ Sandbox setup complete!"

      {:ok, saved} = path |> File.read!() |> JSON.decode()
      plan = saved["plans"]["premium"]

      assert plan["sandbox_base_plan_id"] == "PLAN_NEW_1"
      assert plan["variations"]["monthly"]["sandbox_variation_id"] == "VAR_NEW_1"
    end
  end

  describe "mix square.setup_plans — mid-run variation failure aborts and reports (T-C)" do
    test "reports the created base plan id, mentions cleanup_plans, no success banner", %{
      bypass: bypass,
      path: path
    } do
      write_config!(path, %{
        "plans" => %{
          "premium" => %{
            "name" => "Premium Plan",
            "sandbox_base_plan_id" => nil,
            "production_base_plan_id" => nil,
            "variations" => %{
              "monthly" => %{
                "name" => "Monthly",
                "cadence" => "MONTHLY",
                "amount" => 999,
                "currency" => "USD",
                "sandbox_variation_id" => nil,
                "production_variation_id" => nil,
                "active" => true
              }
            }
          }
        }
      })

      Bypass.expect(bypass, "POST", "/v2/catalog/object", fn conn ->
        respond_by_object_type(
          conn,
          fn conn, request -> json_response(conn, 200, plan_response(request)) end,
          fn conn, _request ->
            error_response = %{
              "errors" => [
                %{
                  "category" => "INVALID_REQUEST_ERROR",
                  "code" => "BAD_REQUEST",
                  "detail" => "INVALID_REQUEST"
                }
              ]
            }

            json_response(conn, 400, error_response)
          end
        )
      end)

      _log =
        capture_log(fn ->
          output =
            capture_io(fn ->
              assert_raise Mix.Error, fn ->
                SetupPlans.run([
                  "--app",
                  "square_client",
                  "--config",
                  @test_config
                ])
              end
            end)

          send(self(), {:output, output})
        end)

      assert_received {:output, output}
      assert output =~ "PLAN_NEW_1"
      assert output =~ "cleanup_plans"
      refute output =~ "✅ Sandbox setup complete!"
    end
  end

  describe "mix square.setup_production — invalid config aborts before the confirmation prompt (T-D)" do
    test "raises before reaching Press Enter to continue", %{path: path} do
      System.put_env("SQUARE_PRODUCTION_ACCESS_TOKEN", "dummy_prod_token")

      write_config!(path, %{
        "plans" => %{
          "premium" => %{
            "name" => "Premium Plan",
            "production_base_plan_id" => nil,
            "variations" => %{
              "monthly" => %{
                "name" => "Monthly",
                "cadence" => "MONTHLY",
                "amount" => nil,
                "production_variation_id" => nil,
                "active" => true
              }
            }
          }
        }
      })

      _log =
        capture_log(fn ->
          output =
            capture_io(fn ->
              assert_raise Mix.Error, fn ->
                SetupProduction.run([
                  "--app",
                  "square_client",
                  "--config",
                  @test_config
                ])
              end
            end)

          send(self(), {:output, output})
        end)

      assert_received {:output, output}
      assert output =~ "premium"
      assert output =~ "monthly"
      assert output =~ "amount"
      refute output =~ "Press Enter to continue"
    end
  end
end
