defmodule SquareClient.CatalogStructTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias SquareClient.Catalog
  alias SquareClient.Catalog.{BasePlan, PlanVariation}

  setup do
    bypass = Bypass.open()

    # Configure test environment
    System.put_env("SQUARE_ENVIRONMENT", "test")
    System.put_env("SQUARE_API_TEST_URL", "http://localhost:#{bypass.port}/v2")
    System.put_env("SQUARE_ACCESS_TOKEN", "test_token")

    on_exit(fn ->
      System.delete_env("SQUARE_ENVIRONMENT")
      System.delete_env("SQUARE_API_TEST_URL")
      System.delete_env("SQUARE_ACCESS_TOKEN")
    end)

    {:ok, bypass: bypass}
  end

  describe "create_base_subscription_plan/1 with structs" do
    test "accepts BasePlan struct", %{bypass: bypass} do
      plan =
        BasePlan.new(%{
          name: "Struct Plan",
          description: "Created with struct"
        })

      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # Verify the struct was properly converted
        assert request["object"]["type"] == "SUBSCRIPTION_PLAN"
        assert request["object"]["id"] == "#Struct_Plan"
        assert request["object"]["subscription_plan_data"]["name"] == "Struct Plan"
        assert request["object"]["subscription_plan_data"]["description"] == "Created with struct"

        response = %{
          "catalog_object" => %{
            "id" => "STRUCT_PLAN_ID",
            "type" => "SUBSCRIPTION_PLAN",
            "subscription_plan_data" => %{
              "name" => "Struct Plan",
              "description" => "Created with struct"
            }
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} = Catalog.create_base_subscription_plan(plan)
          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result.plan_id == "STRUCT_PLAN_ID"
      assert result.name == "Struct Plan"
      assert result.type == "base_plan"
    end

    test "accepts plain map and converts to struct", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["object"]["type"] == "SUBSCRIPTION_PLAN"
        assert request["object"]["subscription_plan_data"]["name"] == "Map Plan"

        response = %{
          "catalog_object" => %{
            "id" => "MAP_PLAN_ID",
            "type" => "SUBSCRIPTION_PLAN",
            "subscription_plan_data" => %{
              "name" => "Map Plan"
            }
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} = Catalog.create_base_subscription_plan(%{name: "Map Plan"})
          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result.plan_id == "MAP_PLAN_ID"
    end
  end

  describe "create_plan_variation/1 with structs" do
    test "accepts PlanVariation struct", %{bypass: bypass} do
      variation =
        PlanVariation.new(%{
          base_plan_id: "BASE123",
          name: "Monthly Struct",
          cadence: "MONTHLY",
          amount: 1999,
          currency: "USD"
        })

      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # Verify the struct was properly converted
        assert request["object"]["type"] == "SUBSCRIPTION_PLAN_VARIATION"
        assert request["object"]["id"] == "#BASE123_Monthly Struct"

        variation_data = request["object"]["subscription_plan_variation_data"]
        assert variation_data["name"] == "Monthly Struct"
        assert variation_data["subscription_plan_id"] == "BASE123"

        [phase] = variation_data["phases"]
        assert phase["cadence"] == "MONTHLY"
        assert phase["pricing"]["price_money"]["amount"] == 1999
        assert phase["pricing"]["price_money"]["currency"] == "USD"

        response = %{
          "catalog_object" => %{
            "id" => "VARIATION_ID",
            "type" => "SUBSCRIPTION_PLAN_VARIATION",
            "subscription_plan_variation_data" => %{
              "name" => "Monthly Struct",
              "subscription_plan_id" => "BASE123",
              "phases" => [phase]
            }
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} = Catalog.create_plan_variation(variation)
          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result.variation_id == "VARIATION_ID"
      assert result.base_plan_id == "BASE123"
      assert result.name == "Monthly Struct"
    end

    test "accepts plain map and converts to struct", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        variation_data = request["object"]["subscription_plan_variation_data"]
        assert variation_data["name"] == "Annual Map"

        [phase] = variation_data["phases"]

        response = %{
          "catalog_object" => %{
            "id" => "ANNUAL_ID",
            "type" => "SUBSCRIPTION_PLAN_VARIATION",
            "subscription_plan_variation_data" => %{
              "name" => "Annual Map",
              "subscription_plan_id" => "BASE456",
              "phases" => [phase]
            }
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} =
            Catalog.create_plan_variation(%{
              base_plan_id: "BASE456",
              name: "Annual Map",
              cadence: "ANNUAL",
              amount: 9900
            })

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result.variation_id == "ANNUAL_ID"
    end

    test "defaults currency to USD when not provided", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        [phase] = request["object"]["subscription_plan_variation_data"]["phases"]
        assert phase["pricing"]["price_money"]["currency"] == "USD"

        response = %{
          "catalog_object" => %{
            "id" => "VAR_ID",
            "type" => "SUBSCRIPTION_PLAN_VARIATION",
            "subscription_plan_variation_data" => %{
              "name" => "Test",
              "subscription_plan_id" => "BASE",
              "phases" => [phase]
            }
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, _result} =
            Catalog.create_plan_variation(%{
              base_plan_id: "BASE",
              name: "Test",
              cadence: "MONTHLY",
              amount: 100
              # currency not provided - should default to USD
            })
        end)
    end
  end
end
