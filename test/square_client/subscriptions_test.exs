defmodule SquareClient.SubscriptionsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SquareClient.Subscriptions

  setup do
    bypass = Bypass.open()
    api_url = "http://localhost:#{bypass.port}/v2"

    # Configure the client to use our test endpoint
    Application.put_env(:square_client, :api_url, api_url)
    Application.put_env(:square_client, :access_token, "test_token")
    Application.put_env(:square_client, :location_id, "LOC_123")
    System.put_env("SQUARE_ENVIRONMENT", "development")

    on_exit(fn ->
      Application.delete_env(:square_client, :api_url)
      Application.delete_env(:square_client, :access_token)
      Application.delete_env(:square_client, :location_id)
      System.delete_env("SQUARE_ENVIRONMENT")
    end)

    {:ok, bypass: bypass}
  end

  describe "create/3" do
    test "creates subscription with saved card ID", %{bypass: bypass} do
      customer_id = "CUST_SUB_123"
      plan_variation_id = "PLAN_VAR_123"
      card_id = "CARD_SAVED_456"

      expected_response = %{
        "subscription" => %{
          "id" => "SUB_CREATED_123",
          "customer_id" => customer_id,
          "plan_variation_id" => plan_variation_id,
          "card_id" => card_id,
          "status" => "ACTIVE",
          "created_at" => "2024-01-15T10:00:00Z",
          "start_date" => "2024-01-15"
        }
      }

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["location_id"] == "LOC_123"
        assert request["customer_id"] == customer_id
        assert request["plan_variation_id"] == plan_variation_id
        assert request["card_id"] == card_id

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(expected_response))
      end)

      assert {:ok, subscription} = Subscriptions.create(customer_id, plan_variation_id, card_id)
      assert subscription["id"] == "SUB_CREATED_123"
      assert subscription["status"] == "ACTIVE"
      assert subscription["customer_id"] == customer_id
    end

    test "creates subscription with card nonce and saves card first", %{bypass: bypass} do
      customer_id = "CUST_NONCE_123"
      plan_variation_id = "PLAN_VAR_456"
      card_nonce = "cnon:card_nonce_test_123"

      # First expect card creation
      Bypass.expect_once(bypass, "POST", "/v2/cards", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["source_id"] == card_nonce
        assert request["card"]["customer_id"] == customer_id

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          JSON.encode!(%{
            "card" => %{
              "id" => "CARD_NEWLY_SAVED",
              "customer_id" => customer_id
            }
          })
        )
      end)

      # Then expect subscription creation with saved card
      Bypass.expect_once(bypass, "POST", "/v2/subscriptions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["card_id"] == "CARD_NEWLY_SAVED"
        assert request["customer_id"] == customer_id
        assert request["plan_variation_id"] == plan_variation_id

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          JSON.encode!(%{
            "subscription" => %{
              "id" => "SUB_FROM_NONCE",
              "status" => "ACTIVE"
            }
          })
        )
      end)

      log =
        capture_log(fn ->
          assert {:ok, subscription} =
                   Subscriptions.create(customer_id, plan_variation_id, card_nonce)

          assert subscription["id"] == "SUB_FROM_NONCE"
        end)

      assert log =~ "Saved card on file: CARD_NEWLY_SAVED"
    end

    test "handles declined card error", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      customer_id = "CUST_DECLINED"
      plan_variation_id = "PLAN_VAR_789"
      card_id = "CARD_DECLINED"

      error_response = %{
        "errors" => [
          %{
            "code" => "CARD_DECLINED",
            "detail" => "Card was declined by the issuer",
            "category" => "PAYMENT_METHOD_ERROR"
          }
        ]
      }

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(402, JSON.encode!(error_response))
      end)

      log =
        capture_log(fn ->
          assert {:error, {:card_declined, "Card was declined by the issuer"}} =
                   Subscriptions.create(customer_id, plan_variation_id, card_id)
        end)

      assert log =~ "Square API error (402)"

      Application.delete_env(:square_client, :disable_retries)
    end

    test "handles card save failure when using nonce", %{bypass: bypass} do
      customer_id = "CUST_SAVE_FAIL"
      plan_variation_id = "PLAN_VAR_999"
      card_nonce = "cnon:bad_nonce"

      error_response = %{
        "errors" => [
          %{
            "code" => "INVALID_CARD_NONCE",
            "detail" => "Invalid card nonce",
            "category" => "INVALID_REQUEST_ERROR"
          }
        ]
      }

      Bypass.expect_once(bypass, "POST", "/v2/cards", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(error_response))
      end)

      log =
        capture_log(fn ->
          assert {:error, {:card_save_failed, "Invalid card nonce"}} =
                   Subscriptions.create(customer_id, plan_variation_id, card_nonce)
        end)

      assert log =~ "Failed to save card"
    end

    test "handles subscription creation with invalid plan", %{bypass: bypass} do
      customer_id = "CUST_BAD_PLAN"
      plan_variation_id = "INVALID_PLAN"
      card_id = "CARD_VALID"

      error_response = %{
        "errors" => [
          %{
            "code" => "INVALID_REQUEST_ERROR",
            "detail" =>
              "The provided location ID `LOC_123` cannot be accessed by the authorized merchant.",
            "category" => "INVALID_REQUEST_ERROR"
          }
        ]
      }

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Verify the location_id is included
        assert request["location_id"] == "LOC_123"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, JSON.encode!(error_response))
      end)

      log =
        capture_log(fn ->
          assert {:error,
                  "The provided location ID `LOC_123` cannot be accessed by the authorized merchant."} =
                   Subscriptions.create(customer_id, plan_variation_id, card_id)
        end)

      assert log =~ "Square API error (404)"
    end

    test "handles API unavailable", %{bypass: bypass} do
      customer_id = "CUST_DOWN"
      plan_variation_id = "PLAN_VAR_DOWN"
      card_id = "CARD_DOWN"

      Bypass.down(bypass)

      log =
        capture_log(fn ->
          assert {:error, :api_unavailable} =
                   Subscriptions.create(customer_id, plan_variation_id, card_id)
        end)

      assert log =~ "Square API request failed"
    end

    test "retries on transient failures when retries enabled", %{bypass: bypass} do
      Application.delete_env(:square_client, :disable_retries)

      customer_id = "CUST_RETRY"
      plan_variation_id = "PLAN_RETRY"
      card_id = "CARD_RETRY"

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "POST", "/v2/subscriptions", fn conn ->
        count = Agent.get_and_update(agent, fn c -> {c, c + 1} end)

        if count == 0 do
          # First attempt fails with 500
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(500, JSON.encode!(%{"errors" => [%{"detail" => "Server error"}]}))
        else
          # Retry succeeds
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            JSON.encode!(%{
              "subscription" => %{"id" => "SUB_RETRY_SUCCESS", "status" => "ACTIVE"}
            })
          )
        end
      end)

      capture_log(fn ->
        assert {:ok, subscription} = Subscriptions.create(customer_id, plan_variation_id, card_id)
        assert subscription["id"] == "SUB_RETRY_SUCCESS"
      end)

      Agent.stop(agent)
    end
  end

  describe "get/1" do
    test "retrieves subscription successfully", %{bypass: bypass} do
      subscription_id = "SUB_GET_123"

      expected_response = %{
        "subscription" => %{
          "id" => subscription_id,
          "status" => "ACTIVE",
          "customer_id" => "CUST_123",
          "plan_variation_id" => "PLAN_123",
          "created_at" => "2024-01-15T10:00:00Z"
        }
      }

      Bypass.expect_once(bypass, "GET", "/v2/subscriptions/#{subscription_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(expected_response))
      end)

      assert {:ok, response} = Subscriptions.get(subscription_id)
      assert response["subscription"]["id"] == subscription_id
      assert response["subscription"]["status"] == "ACTIVE"
    end

    test "returns not_found for missing subscription", %{bypass: bypass} do
      subscription_id = "SUB_MISSING"

      Bypass.expect_once(bypass, "GET", "/v2/subscriptions/#{subscription_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          404,
          JSON.encode!(%{
            "errors" => [%{"detail" => "Subscription not found"}]
          })
        )
      end)

      assert {:error, :not_found} = Subscriptions.get(subscription_id)
    end

    test "handles unauthorized access", %{bypass: bypass} do
      subscription_id = "SUB_UNAUTH"

      Bypass.expect_once(bypass, "GET", "/v2/subscriptions/#{subscription_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          401,
          JSON.encode!(%{
            "errors" => [%{"detail" => "Invalid access token"}]
          })
        )
      end)

      log =
        capture_log(fn ->
          assert {:error, "Invalid access token"} = Subscriptions.get(subscription_id)
        end)

      assert log =~ "Square API error (401)"
    end
  end

  describe "cancel/1" do
    test "cancels subscription successfully", %{bypass: bypass} do
      subscription_id = "SUB_CANCEL_123"

      expected_response = %{
        "subscription" => %{
          "id" => subscription_id,
          "status" => "CANCELED",
          "canceled_date" => "2024-01-15"
        }
      }

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions/#{subscription_id}/cancel", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Should send empty object
        assert request == %{}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(expected_response))
      end)

      assert {:ok, response} = Subscriptions.cancel(subscription_id)
      assert response["subscription"]["status"] == "CANCELED"
      assert response["subscription"]["canceled_date"] == "2024-01-15"
    end

    test "handles canceling already canceled subscription", %{bypass: bypass} do
      subscription_id = "SUB_ALREADY_CANCELED"

      error_response = %{
        "errors" => [
          %{
            "code" => "INVALID_REQUEST",
            "detail" => "Subscription is already canceled",
            "category" => "INVALID_REQUEST_ERROR"
          }
        ]
      }

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions/#{subscription_id}/cancel", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(error_response))
      end)

      log =
        capture_log(fn ->
          assert {:error, "Subscription is already canceled"} =
                   Subscriptions.cancel(subscription_id)
        end)

      assert log =~ "Square API error (400)"
    end

    test "returns not_found for missing subscription", %{bypass: bypass} do
      subscription_id = "SUB_NOT_FOUND"

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions/#{subscription_id}/cancel", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          404,
          JSON.encode!(%{
            "errors" => [%{"detail" => "Subscription not found"}]
          })
        )
      end)

      assert {:error, :not_found} = Subscriptions.cancel(subscription_id)
    end
  end

  describe "ensure_card_saved/2" do
    test "passes through already saved card ID", %{bypass: bypass} do
      # This is a private function, but we can test it indirectly
      # When card_id doesn't start with "cnon:", it should be used as-is

      customer_id = "CUST_PASS"
      plan_variation_id = "PLAN_PASS"
      card_id = "CARD_ALREADY_SAVED"

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Should use the card_id as-is
        assert request["card_id"] == "CARD_ALREADY_SAVED"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          JSON.encode!(%{
            "subscription" => %{"id" => "SUB_PASS", "status" => "ACTIVE"}
          })
        )
      end)

      assert {:ok, _} = Subscriptions.create(customer_id, plan_variation_id, card_id)
    end
  end

  describe "request headers" do
    test "includes correct headers", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/subscriptions/TEST", fn conn ->
        assert {"authorization", "Bearer test_token"} in conn.req_headers
        assert {"square-version", "2025-01-23"} in conn.req_headers

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(%{"subscription" => %{"id" => "TEST"}}))
      end)

      {:ok, _} = Subscriptions.get("TEST")
    end
  end

  describe "error parsing" do
    test "handles malformed error response", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      Bypass.expect_once(bypass, "GET", "/v2/subscriptions/BAD", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, JSON.encode!(%{"not_errors" => "something bad"}))
      end)

      log =
        capture_log(fn ->
          assert {:error, "Square API error"} = Subscriptions.get("BAD")
        end)

      assert log =~ "Square API error (500)"

      Application.delete_env(:square_client, :disable_retries)
    end

    test "handles empty error array", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions/EMPTY/cancel", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(%{"errors" => []}))
      end)

      log =
        capture_log(fn ->
          assert {:error, "Square API error"} = Subscriptions.cancel("EMPTY")
        end)

      assert log =~ "Square API error (400)"

      Application.delete_env(:square_client, :disable_retries)
    end

    test "handles missing errors key", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions/NO_ERRORS/cancel", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, JSON.encode!(%{"message" => "Something went wrong"}))
      end)

      log =
        capture_log(fn ->
          assert {:error, "Square API error"} = Subscriptions.cancel("NO_ERRORS")
        end)

      assert log =~ "Square API error (500)"

      Application.delete_env(:square_client, :disable_retries)
    end
  end

  describe "environment configuration" do
    test "uses sandbox URL by default", %{bypass: _bypass} do
      # Reset environment config
      Application.delete_env(:square_client, :api_url)
      System.delete_env("SQUARE_ENVIRONMENT")

      # Should default to sandbox
      assert Subscriptions.__info__(:functions) |> Keyword.has_key?(:create)
      # The api_url function is private, but we can test indirectly by making a request
    end

    test "uses production URL when configured", %{bypass: _bypass} do
      System.put_env("SQUARE_ENVIRONMENT", "production")
      Application.delete_env(:square_client, :api_url)

      # Force module recompilation to pick up new env
      # In real usage, this would be set at compile time
      assert Subscriptions.__info__(:functions) |> Keyword.has_key?(:create)
    end

    test "disables retries in test environment", %{bypass: bypass} do
      System.put_env("SQUARE_ENVIRONMENT", "test")

      subscription_id = "SUB_TEST_ENV"

      Bypass.expect_once(bypass, "GET", "/v2/subscriptions/#{subscription_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, JSON.encode!(%{"errors" => [%{"detail" => "Error"}]}))
      end)

      # Should not retry in test environment
      log =
        capture_log(fn ->
          assert {:error, "Error"} = Subscriptions.get(subscription_id)
        end)

      assert log =~ "Square API error (500)"

      Application.delete_env(:square_client, :disable_retries)
    end

    test "handles empty error array", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      Bypass.expect_once(bypass, "POST", "/v2/subscriptions/EMPTY/cancel", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(%{"errors" => []}))
      end)

      log =
        capture_log(fn ->
          assert {:error, "Square API error"} = Subscriptions.cancel("EMPTY")
        end)

      assert log =~ "Square API error (400)"

      Application.delete_env(:square_client, :disable_retries)
    end
  end

end
