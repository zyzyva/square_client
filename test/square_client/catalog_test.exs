defmodule SquareClient.CatalogTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias SquareClient.Catalog

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

  describe "create_base_subscription_plan/1" do
    test "creates a base plan with name and description", %{bypass: bypass} do
      plan_id = "TEST_PLAN_ID_123"
      plan_name = "Test Premium Plan"
      plan_description = "A test subscription plan"

      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # Verify request structure
        assert request["object"]["type"] == "SUBSCRIPTION_PLAN"
        assert request["object"]["subscription_plan_data"]["name"] == plan_name
        assert request["object"]["subscription_plan_data"]["description"] == plan_description
        assert request["idempotency_key"] != nil

        response = %{
          "catalog_object" => %{
            "id" => plan_id,
            "type" => "SUBSCRIPTION_PLAN",
            "subscription_plan_data" => %{
              "name" => plan_name,
              "description" => plan_description
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
            Catalog.create_base_subscription_plan(%{
              name: plan_name,
              description: plan_description
            })

          send(self(), {:result, result})
        end)

      assert_received {:result, result}

      assert result.plan_id == plan_id
      assert result.name == plan_name
      assert result.type == "base_plan"
    end

    test "creates a base plan with only name", %{bypass: bypass} do
      plan_id = "TEST_PLAN_ID_456"
      plan_name = "Basic Plan"

      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # Verify description is not included when not provided
        assert request["object"]["subscription_plan_data"]["name"] == plan_name
        refute Map.has_key?(request["object"]["subscription_plan_data"], "description")

        response = %{
          "catalog_object" => %{
            "id" => plan_id,
            "type" => "SUBSCRIPTION_PLAN",
            "subscription_plan_data" => %{
              "name" => plan_name
            }
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} = Catalog.create_base_subscription_plan(%{name: plan_name})
          send(self(), {:result, result})
        end)

      assert_received {:result, result}

      assert result.plan_id == plan_id
      assert result.name == plan_name
    end

    test "handles API errors gracefully", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        error_response = %{
          "errors" => [
            %{
              "category" => "INVALID_REQUEST_ERROR",
              "code" => "BAD_REQUEST",
              "detail" => "Plan name already exists"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, Jason.encode!(error_response))
      end)

      _log =
        capture_log(fn ->
          {:error, message} =
            Catalog.create_base_subscription_plan(%{
              name: "Duplicate Plan"
            })

          send(self(), {:message, message})
        end)

      assert_received {:message, message}

      assert message == "Plan name already exists"
    end
  end

  describe "create_plan_variation/1" do
    test "creates a monthly variation with correct pricing", %{bypass: bypass} do
      base_plan_id = "BASE_PLAN_123"
      variation_id = "VARIATION_MONTHLY_456"

      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # Verify variation structure
        assert request["object"]["type"] == "SUBSCRIPTION_PLAN_VARIATION"

        assert request["object"]["subscription_plan_variation_data"]["subscription_plan_id"] ==
                 base_plan_id

        assert request["object"]["subscription_plan_variation_data"]["name"] == "Monthly"

        # Verify pricing structure (new API format)
        [phase] = request["object"]["subscription_plan_variation_data"]["phases"]
        assert phase["cadence"] == "MONTHLY"
        assert phase["pricing"]["type"] == "STATIC"
        assert phase["pricing"]["price_money"]["amount"] == 999
        assert phase["pricing"]["price_money"]["currency"] == "USD"

        response = %{
          "catalog_object" => %{
            "id" => variation_id,
            "type" => "SUBSCRIPTION_PLAN_VARIATION",
            "subscription_plan_variation_data" => %{
              "subscription_plan_id" => base_plan_id,
              "name" => "Monthly",
              "phases" => [
                %{
                  "cadence" => "MONTHLY",
                  "pricing" => %{
                    "type" => "STATIC",
                    "price_money" => %{
                      "amount" => 999,
                      "currency" => "USD"
                    }
                  }
                }
              ]
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
              base_plan_id: base_plan_id,
              name: "Monthly",
              cadence: "MONTHLY",
              amount: 999,
              currency: "USD"
            })

          send(self(), {:result, result})
        end)

      assert_received {:result, result}

      assert result.variation_id == variation_id
      assert result.base_plan_id == base_plan_id
      assert result.name == "Monthly"
      assert length(result.phases) == 1
    end

    test "creates an annual variation", %{bypass: bypass} do
      base_plan_id = "BASE_PLAN_789"
      variation_id = "VARIATION_ANNUAL_999"

      Bypass.expect_once(bypass, "POST", "/v2/catalog/object", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        [phase] = request["object"]["subscription_plan_variation_data"]["phases"]
        assert phase["cadence"] == "ANNUAL"
        assert phase["pricing"]["price_money"]["amount"] == 9900

        response = %{
          "catalog_object" => %{
            "id" => variation_id,
            "type" => "SUBSCRIPTION_PLAN_VARIATION",
            "subscription_plan_variation_data" => %{
              "subscription_plan_id" => base_plan_id,
              "name" => "Annual",
              "phases" => [
                %{
                  "cadence" => "ANNUAL",
                  "pricing" => %{
                    "type" => "STATIC",
                    "price_money" => %{
                      "amount" => 9900,
                      "currency" => "USD"
                    }
                  }
                }
              ]
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
              base_plan_id: base_plan_id,
              name: "Annual",
              cadence: "ANNUAL",
              amount: 9900,
              currency: "USD"
            })

          send(self(), {:result, result})
        end)

      assert_received {:result, result}

      assert result.variation_id == variation_id
      assert result.name == "Annual"
    end
  end

  describe "list_subscription_plans/0" do
    test "returns list of subscription plans", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/catalog/list", fn conn ->
        assert conn.query_params["types"] == "SUBSCRIPTION_PLAN"

        response = %{
          "objects" => [
            %{
              "id" => "PLAN_1",
              "type" => "SUBSCRIPTION_PLAN",
              "subscription_plan_data" => %{
                "name" => "Premium Plan",
                "description" => "Premium features"
              }
            },
            %{
              "id" => "PLAN_2",
              "type" => "SUBSCRIPTION_PLAN",
              "subscription_plan_data" => %{
                "name" => "Basic Plan"
              }
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, plans} = Catalog.list_subscription_plans()

      assert length(plans) == 2
      assert Enum.at(plans, 0).id == "PLAN_1"
      assert Enum.at(plans, 0).name == "Premium Plan"
      assert Enum.at(plans, 0).description == "Premium features"
      assert Enum.at(plans, 1).id == "PLAN_2"
      assert Enum.at(plans, 1).name == "Basic Plan"
      assert Enum.at(plans, 1).description == nil
    end

    test "returns empty list when no plans exist", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/catalog/list", fn conn ->
        response = %{"objects" => nil}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, plans} = Catalog.list_subscription_plans()
      assert plans == []
    end
  end

  describe "list_plan_variations/0" do
    test "returns list of variations with pricing details", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/catalog/list", fn conn ->
        assert conn.query_params["types"] == "SUBSCRIPTION_PLAN_VARIATION"

        response = %{
          "objects" => [
            %{
              "id" => "VAR_1",
              "type" => "SUBSCRIPTION_PLAN_VARIATION",
              "subscription_plan_variation_data" => %{
                "subscription_plan_id" => "PLAN_1",
                "name" => "Monthly",
                "phases" => [
                  %{
                    "cadence" => "MONTHLY",
                    "pricing" => %{
                      "type" => "STATIC",
                      "price_money" => %{
                        "amount" => 999,
                        "currency" => "USD"
                      }
                    }
                  }
                ]
              }
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, variations} = Catalog.list_plan_variations()

      assert length(variations) == 1
      assert Enum.at(variations, 0).variation_id == "VAR_1"
      assert Enum.at(variations, 0).base_plan_id == "PLAN_1"
      assert Enum.at(variations, 0).name == "Monthly"
    end
  end

  describe "get/1" do
    test "retrieves a specific catalog object", %{bypass: bypass} do
      object_id = "TEST_OBJECT_123"

      Bypass.expect_once(bypass, "GET", "/v2/catalog/object/#{object_id}", fn conn ->
        response = %{
          "object" => %{
            "id" => object_id,
            "type" => "SUBSCRIPTION_PLAN",
            "subscription_plan_data" => %{
              "name" => "Test Plan"
            }
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, object} = Catalog.get(object_id)

      assert object["id"] == object_id
      assert object["type"] == "SUBSCRIPTION_PLAN"
    end

    test "returns not_found for missing object", %{bypass: bypass} do
      object_id = "NONEXISTENT"

      Bypass.expect_once(bypass, "GET", "/v2/catalog/object/#{object_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(%{"errors" => [%{"code" => "NOT_FOUND"}]}))
      end)

      {:error, :not_found} = Catalog.get(object_id)
    end
  end

  describe "delete/1" do
    test "deletes a catalog object", %{bypass: bypass} do
      object_id = "DELETE_ME_123"

      Bypass.expect_once(bypass, "DELETE", "/v2/catalog/object/#{object_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{}))
      end)

      _log =
        capture_log(fn ->
          assert :ok = Catalog.delete(object_id)
        end)
    end

    test "returns error when deletion fails", %{bypass: bypass} do
      object_id = "PROTECTED_123"

      Bypass.expect_once(bypass, "DELETE", "/v2/catalog/object/#{object_id}", fn conn ->
        error_response = %{
          "errors" => [
            %{
              "category" => "INVALID_REQUEST_ERROR",
              "code" => "BAD_REQUEST",
              "detail" => "Catalog Object cannot be deleted"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, Jason.encode!(error_response))
      end)

      _log =
        capture_log(fn ->
          {:error, message} = Catalog.delete(object_id)
          send(self(), {:message, message})
        end)

      assert_received {:message, message}
      assert message == "Catalog Object cannot be deleted"
    end
  end

  describe "API error handling" do
    test "handles network errors", %{bypass: bypass} do
      # Close the bypass to simulate network error
      Bypass.down(bypass)

      _log =
        capture_log(fn ->
          assert {:error, :api_unavailable} = Catalog.list_subscription_plans()
        end)
    end

    test "handles malformed JSON response", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/catalog/list", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, "not valid json")
      end)

      _log =
        capture_log(fn ->
          assert {:error, _} = Catalog.list_subscription_plans()
        end)
    end
  end
end
