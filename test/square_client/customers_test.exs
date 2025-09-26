defmodule SquareClient.CustomersTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SquareClient.Customers

  setup do
    bypass = Bypass.open()
    api_url = "http://localhost:#{bypass.port}/v2"

    # Configure the client to use our test endpoint
    Application.put_env(:square_client, :api_url, api_url)
    Application.put_env(:square_client, :access_token, "test_token")

    on_exit(fn ->
      Application.delete_env(:square_client, :api_url)
      Application.delete_env(:square_client, :access_token)
    end)

    {:ok, bypass: bypass}
  end

  describe "create/1" do
    test "creates a customer successfully", %{bypass: bypass} do
      customer_data = %{
        email_address: "test@example.com",
        reference_id: "ref_123",
        given_name: "John",
        family_name: "Doe",
        phone_number: "+15555551234",
        note: "Test customer"
      }

      expected_response = %{
        "customer" => %{
          "id" => "CUST_123ABC",
          "created_at" => "2024-01-15T10:00:00Z",
          "updated_at" => "2024-01-15T10:00:00Z",
          "given_name" => "John",
          "family_name" => "Doe",
          "email_address" => "test@example.com"
        }
      }

      Bypass.expect_once(bypass, "POST", "/v2/customers", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["email_address"] == "test@example.com"
        assert request["reference_id"] == "ref_123"
        assert request["given_name"] == "John"
        assert request["family_name"] == "Doe"
        assert request["phone_number"] == "+15555551234"
        assert request["note"] == "Test customer"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(expected_response))
      end)

      assert {:ok, response} = Customers.create(customer_data)
      assert response["customer"]["id"] == "CUST_123ABC"
      assert response["customer"]["email_address"] == "test@example.com"
    end

    test "creates customer with minimal data", %{bypass: bypass} do
      customer_data = %{
        email_address: "minimal@example.com"
      }

      expected_response = %{
        "customer" => %{
          "id" => "CUST_MINIMAL",
          "email_address" => "minimal@example.com"
        }
      }

      Bypass.expect_once(bypass, "POST", "/v2/customers", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["email_address"] == "minimal@example.com"
        assert request["note"] == "Created via SquareClient"
        # Other fields should not be present
        refute Map.has_key?(request, "given_name")
        refute Map.has_key?(request, "family_name")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(expected_response))
      end)

      assert {:ok, response} = Customers.create(customer_data)
      assert response["customer"]["id"] == "CUST_MINIMAL"
    end

    test "handles customer creation with duplicate email", %{bypass: bypass} do
      customer_data = %{
        email_address: "duplicate@example.com",
        given_name: "Jane"
      }

      error_response = %{
        "errors" => [
          %{
            "code" => "DUPLICATE_EMAIL",
            "detail" => "A customer with this email already exists",
            "category" => "INVALID_REQUEST_ERROR"
          }
        ]
      }

      Bypass.expect_once(bypass, "POST", "/v2/customers", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(error_response))
      end)

      log =
        capture_log(fn ->
          assert {:error, "A customer with this email already exists"} =
                   Customers.create(customer_data)
        end)

      assert log =~ "Square API error (400)"
    end

    test "handles API unavailable", %{bypass: bypass} do
      customer_data = %{email_address: "test@example.com"}

      Bypass.down(bypass)

      log =
        capture_log(fn ->
          assert {:error, :api_unavailable} = Customers.create(customer_data)
        end)

      assert log =~ "Square API request failed"
    end

    test "retries on transient failures when retries enabled", %{bypass: bypass} do
      Application.delete_env(:square_client, :disable_retries)

      customer_data = %{email_address: "retry@example.com"}

      # Will fail first, then succeed
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "POST", "/v2/customers", fn conn ->
        count = Agent.get_and_update(agent, fn c -> {c, c + 1} end)

        if count == 0 do
          # First attempt fails with 500
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            500,
            JSON.encode!(%{"errors" => [%{"detail" => "Internal server error"}]})
          )
        else
          # Retry succeeds
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, JSON.encode!(%{"customer" => %{"id" => "CUST_RETRY"}}))
        end
      end)

      capture_log(fn ->
        assert {:ok, response} = Customers.create(customer_data)
        assert response["customer"]["id"] == "CUST_RETRY"
      end)

      Agent.stop(agent)
    end

    test "does not retry when retries disabled", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      customer_data = %{email_address: "no_retry@example.com"}

      Bypass.expect_once(bypass, "POST", "/v2/customers", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, JSON.encode!(%{"errors" => [%{"detail" => "Server error"}]}))
      end)

      log =
        capture_log(fn ->
          result = Customers.create(customer_data)
          assert {:error, _} = result
        end)

      assert log =~ "Square API error (500)"

      Application.delete_env(:square_client, :disable_retries)
    end
  end

  describe "get/1" do
    test "retrieves customer successfully", %{bypass: bypass} do
      customer_id = "CUST_GET_123"

      expected_response = %{
        "customer" => %{
          "id" => customer_id,
          "email_address" => "found@example.com",
          "given_name" => "Found",
          "family_name" => "Customer"
        }
      }

      Bypass.expect_once(bypass, "GET", "/v2/customers/#{customer_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(expected_response))
      end)

      assert {:ok, response} = Customers.get(customer_id)
      assert response["customer"]["id"] == customer_id
      assert response["customer"]["email_address"] == "found@example.com"
    end

    test "returns not_found for missing customer", %{bypass: bypass} do
      customer_id = "CUST_MISSING"

      Bypass.expect_once(bypass, "GET", "/v2/customers/#{customer_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          404,
          JSON.encode!(%{
            "errors" => [%{"detail" => "Customer not found"}]
          })
        )
      end)

      assert {:error, :not_found} = Customers.get(customer_id)
    end

    test "handles unauthorized access", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      customer_id = "CUST_UNAUTH"

      Bypass.expect_once(bypass, "GET", "/v2/customers/#{customer_id}", fn conn ->
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
          assert {:error, "Invalid access token"} = Customers.get(customer_id)
        end)

      assert log =~ "Square API error (401)"

      Application.delete_env(:square_client, :disable_retries)
    end
  end

  describe "create_card/2" do
    test "creates card on file successfully", %{bypass: bypass} do
      customer_id = "CUST_CARD_123"
      card_nonce = "cnon:card_nonce_from_square_123"

      expected_response = %{
        "card" => %{
          "id" => "CARD_SAVED_123",
          "customer_id" => customer_id,
          "card_brand" => "VISA",
          "last_4" => "1234",
          "exp_month" => 12,
          "exp_year" => 2025
        }
      }

      Bypass.expect_once(bypass, "POST", "/v2/cards", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Verify idempotency key is present
        assert request["idempotency_key"] != nil
        assert String.length(request["idempotency_key"]) == 32

        assert request["source_id"] == card_nonce
        assert request["card"]["customer_id"] == customer_id

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(expected_response))
      end)

      assert {:ok, response} = Customers.create_card(customer_id, card_nonce)
      assert response["card"]["id"] == "CARD_SAVED_123"
      assert response["card"]["customer_id"] == customer_id
      assert response["card"]["last_4"] == "1234"
    end

    test "handles declined card", %{bypass: bypass} do
      customer_id = "CUST_DECLINED"
      card_nonce = "cnon:card_declined"

      error_response = %{
        "errors" => [
          %{
            "code" => "CARD_DECLINED",
            "detail" => "Card was declined",
            "category" => "PAYMENT_METHOD_ERROR"
          }
        ]
      }

      Bypass.expect_once(bypass, "POST", "/v2/cards", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(402, JSON.encode!(error_response))
      end)

      log =
        capture_log(fn ->
          assert {:error, "Card was declined"} = Customers.create_card(customer_id, card_nonce)
        end)

      assert log =~ "Square API error (402)"
    end

    test "handles invalid nonce", %{bypass: bypass} do
      customer_id = "CUST_BAD_NONCE"
      card_nonce = "invalid_nonce"

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
          assert {:error, "Invalid card nonce"} = Customers.create_card(customer_id, card_nonce)
        end)

      assert log =~ "Square API error (400)"
    end

    test "generates unique idempotency keys", %{bypass: bypass} do
      customer_id = "CUST_IDEM"
      card_nonce = "cnon:test"

      # Capture parent process ID to send messages from Bypass
      parent_pid = self()

      Bypass.expect(bypass, "POST", "/v2/cards", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Capture the idempotency key - send to parent process
        send(parent_pid, {:key, request["idempotency_key"]})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          JSON.encode!(%{"card" => %{"id" => "CARD_#{request["idempotency_key"]}"}})
        )
      end)

      # Make two requests
      {:ok, _} = Customers.create_card(customer_id, card_nonce)
      assert_receive {:key, key1}

      {:ok, _} = Customers.create_card(customer_id, card_nonce)
      assert_receive {:key, key2}

      # Keys should be different
      assert key1 != key2
      assert String.length(key1) == 32
      assert String.length(key2) == 32
    end
  end

  describe "request headers" do
    test "includes correct headers", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/customers/TEST", fn conn ->
        assert {"authorization", "Bearer test_token"} in conn.req_headers
        assert {"square-version", "2025-01-23"} in conn.req_headers

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(%{"customer" => %{"id" => "TEST"}}))
      end)

      {:ok, _} = Customers.get("TEST")
    end
  end

  describe "error parsing" do
    test "handles malformed error response", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      Bypass.expect_once(bypass, "GET", "/v2/customers/BAD", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, JSON.encode!(%{"not_errors" => "something bad"}))
      end)

      log =
        capture_log(fn ->
          assert {:error, "Square API error"} = Customers.get("BAD")
        end)

      assert log =~ "Square API error (500)"

      Application.delete_env(:square_client, :disable_retries)
    end

    test "handles empty error array", %{bypass: bypass} do
      Application.put_env(:square_client, :disable_retries, true)

      Bypass.expect_once(bypass, "GET", "/v2/customers/EMPTY", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(%{"errors" => []}))
      end)

      log =
        capture_log(fn ->
          assert {:error, "Square API error"} = Customers.get("EMPTY")
        end)

      assert log =~ "Square API error (400)"

      Application.delete_env(:square_client, :disable_retries)
    end
  end
end
