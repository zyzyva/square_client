defmodule SquareClient.PaymentsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias SquareClient.Payments

  setup do
    bypass = Bypass.open()

    # Configure Square client for testing
    original_config = Application.get_all_env(:square_client)

    Application.put_env(:square_client, :api_url, "http://localhost:#{bypass.port}/v2")
    Application.put_env(:square_client, :access_token, "test_token")
    Application.put_env(:square_client, :location_id, "test_location")
    Application.put_env(:square_client, :disable_retries, true)

    on_exit(fn ->
      # Restore original configuration
      Enum.each(original_config, fn {key, value} ->
        Application.put_env(:square_client, key, value)
      end)
    end)

    {:ok, bypass: bypass}
  end

  describe "create/4" do
    test "creates a payment successfully", %{bypass: bypass} do
      payment_id = "PAYMENT_123"

      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Verify request structure
        assert request["source_id"] == "cnon:card-nonce"
        assert request["amount_money"]["amount"] == 1000
        assert request["amount_money"]["currency"] == "USD"
        assert request["location_id"] == "test_location"
        assert request["idempotency_key"] != nil

        response = %{
          "payment" => %{
            "id" => payment_id,
            "status" => "APPROVED",
            "amount_money" => %{
              "amount" => 1000,
              "currency" => "USD"
            },
            "created_at" => "2024-01-01T00:00:00Z"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} = Payments.create("cnon:card-nonce", 1000, "USD")
          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result.payment_id == payment_id
      assert result.status == "APPROVED"
      assert result.amount == 1000
      assert result.currency == "USD"
    end

    test "creates a payment with optional fields", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Verify optional fields
        assert request["customer_id"] == "CUSTOMER_123"
        assert request["reference_id"] == "order-456"
        assert request["note"] == "Test payment"
        assert request["autocomplete"] == false

        response = %{
          "payment" => %{
            "id" => "PAYMENT_456",
            "status" => "PENDING",
            "amount_money" => %{
              "amount" => 2000,
              "currency" => "USD"
            },
            "created_at" => "2024-01-01T00:00:00Z"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} =
            Payments.create("cnon:card-nonce", 2000, "USD",
              customer_id: "CUSTOMER_123",
              reference_id: "order-456",
              note: "Test payment",
              autocomplete: false
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result.payment_id == "PAYMENT_456"
      assert result.status == "PENDING"
    end

    test "handles payment creation errors", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        response = %{
          "errors" => [
            %{
              "category" => "PAYMENT_METHOD_ERROR",
              "code" => "INVALID_CARD",
              "detail" => "Card declined"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:error, error} = Payments.create("bad-nonce", 1000, "USD")
          send(self(), {:error, error})
        end)

      assert_received {:error, "Card declined"}
    end

    test "handles network errors", %{bypass: bypass} do
      Bypass.down(bypass)

      _log =
        capture_log(fn ->
          {:error, error} = Payments.create("cnon:card-nonce", 1000, "USD")
          send(self(), {:error, error})
        end)

      assert_received {:error, :api_unavailable}
    end
  end

  describe "get/1" do
    test "retrieves payment details", %{bypass: bypass} do
      payment_id = "PAYMENT_123"

      Bypass.expect_once(bypass, "GET", "/v2/payments/#{payment_id}", fn conn ->
        response = %{
          "payment" => %{
            "id" => payment_id,
            "status" => "COMPLETED",
            "amount_money" => %{
              "amount" => 1000,
              "currency" => "USD"
            },
            "created_at" => "2024-01-01T00:00:00Z",
            "updated_at" => "2024-01-01T00:01:00Z"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      {:ok, payment} = Payments.get(payment_id)

      assert payment["id"] == payment_id
      assert payment["status"] == "COMPLETED"
    end

    test "handles payment not found", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/payments/NONEXISTENT", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, JSON.encode!(%{"errors" => [%{"code" => "NOT_FOUND"}]}))
      end)

      assert {:error, :not_found} = Payments.get("NONEXISTENT")
    end
  end

  describe "complete/1" do
    test "completes a pending payment", %{bypass: bypass} do
      payment_id = "PAYMENT_123"

      Bypass.expect_once(bypass, "POST", "/v2/payments/#{payment_id}/complete", fn conn ->
        response = %{
          "payment" => %{
            "id" => payment_id,
            "status" => "COMPLETED",
            "amount_money" => %{
              "amount" => 1000,
              "currency" => "USD"
            }
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, payment} = Payments.complete(payment_id)
          send(self(), {:payment, payment})
        end)

      assert_received {:payment, payment}
      assert payment["id"] == payment_id
      assert payment["status"] == "COMPLETED"
    end

    test "handles complete errors", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/payments/PAYMENT_123/complete", fn conn ->
        response = %{
          "errors" => [
            %{
              "code" => "INVALID_REQUEST_ERROR",
              "detail" => "Payment already completed"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:error, error} = Payments.complete("PAYMENT_123")
          send(self(), {:error, error})
        end)

      assert_received {:error, "Payment already completed"}
    end
  end

  describe "cancel/1" do
    test "cancels a payment", %{bypass: bypass} do
      payment_id = "PAYMENT_123"

      Bypass.expect_once(bypass, "POST", "/v2/payments/#{payment_id}/cancel", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(%{}))
      end)

      _log =
        capture_log(fn ->
          :ok = Payments.cancel(payment_id)
          send(self(), :canceled)
        end)

      assert_received :canceled
    end

    test "handles cancel errors", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/payments/PAYMENT_123/cancel", fn conn ->
        response = %{
          "errors" => [
            %{
              "code" => "INVALID_REQUEST_ERROR",
              "detail" => "Payment cannot be canceled"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:error, error} = Payments.cancel("PAYMENT_123")
          send(self(), {:error, error})
        end)

      assert_received {:error, "Payment cannot be canceled"}
    end
  end

  describe "refund/4" do
    test "creates a refund", %{bypass: bypass} do
      payment_id = "PAYMENT_123"
      refund_id = "REFUND_456"

      Bypass.expect_once(bypass, "POST", "/v2/refunds", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["payment_id"] == payment_id
        assert request["amount_money"]["amount"] == 500
        assert request["amount_money"]["currency"] == "USD"

        response = %{
          "refund" => %{
            "id" => refund_id,
            "payment_id" => payment_id,
            "amount_money" => %{
              "amount" => 500,
              "currency" => "USD"
            },
            "status" => "PENDING"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} = Payments.refund(payment_id, 500, "USD")
          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result.refund_id == refund_id
      assert result.payment_id == payment_id
      assert result.amount == 500
      assert result.status == "PENDING"
    end

    test "creates a refund with reason", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/refunds", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["reason"] == "Customer requested"

        response = %{
          "refund" => %{
            "id" => "REFUND_789",
            "payment_id" => "PAYMENT_123",
            "amount_money" => %{
              "amount" => 1000,
              "currency" => "USD"
            },
            "status" => "APPROVED"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, _result} =
            Payments.refund("PAYMENT_123", 1000, "USD", reason: "Customer requested")
        end)
    end
  end

  describe "list/1" do
    test "lists payments", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/payments", fn conn ->
        query = URI.decode_query(conn.query_string || "")

        # Verify location_id is included
        assert query["location_id"] == "test_location"

        response = %{
          "payments" => [
            %{
              "id" => "PAYMENT_1",
              "amount_money" => %{"amount" => 1000, "currency" => "USD"},
              "status" => "COMPLETED"
            },
            %{
              "id" => "PAYMENT_2",
              "amount_money" => %{"amount" => 2000, "currency" => "USD"},
              "status" => "APPROVED"
            }
          ],
          "cursor" => "next_page_cursor"
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      {:ok, result} = Payments.list()

      assert length(result.payments) == 2
      assert result.cursor == "next_page_cursor"
      assert Enum.at(result.payments, 0)["id"] == "PAYMENT_1"
      assert Enum.at(result.payments, 1)["id"] == "PAYMENT_2"
    end

    test "lists payments with filters", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/payments", fn conn ->
        query = URI.decode_query(conn.query_string || "")

        assert query["begin_time"] == "2024-01-01T00:00:00Z"
        assert query["end_time"] == "2024-01-31T23:59:59Z"
        assert query["sort_order"] == "DESC"
        assert query["limit"] == "10"
        assert query["cursor"] == "previous_cursor"

        response = %{
          "payments" => [],
          "cursor" => nil
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      {:ok, result} =
        Payments.list(
          begin_time: "2024-01-01T00:00:00Z",
          end_time: "2024-01-31T23:59:59Z",
          sort_order: "DESC",
          limit: 10,
          cursor: "previous_cursor"
        )

      assert result.payments == []
      assert result.cursor == nil
    end

    test "handles list errors", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v2/payments", fn conn ->
        response = %{
          "errors" => [
            %{
              "code" => "INVALID_REQUEST_ERROR",
              "detail" => "Invalid date format"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:error, error} = Payments.list(begin_time: "invalid")
          send(self(), {:error, error})
        end)

      assert_received {:error, "Invalid date format"}
    end
  end

  describe "create_one_time/4" do
    test "creates a one-time payment successfully", %{bypass: bypass} do
      payment_id = "PAYMENT_ONE_TIME_123"
      customer_id = "CUSTOMER_123"

      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Verify request structure
        assert request["source_id"] == "cnon:card-nonce"
        assert request["amount_money"]["amount"] == 2999
        assert request["amount_money"]["currency"] == "USD"
        assert request["customer_id"] == customer_id
        assert request["note"] == "30-day premium access"
        assert String.starts_with?(request["reference_id"], "test_app:otp:")
        assert request["idempotency_key"] != nil

        response = %{
          "payment" => %{
            "id" => payment_id,
            "status" => "APPROVED",
            "amount_money" => %{
              "amount" => 2999,
              "currency" => "USD"
            },
            "created_at" => "2024-01-15T12:00:00Z"
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} =
            Payments.create_one_time(customer_id, "cnon:card-nonce", 2999,
              description: "30-day premium access",
              app_name: :test_app
            )

          send(self(), {:ok, result})
        end)

      assert_received {:ok, payment}
      assert payment.payment_id == payment_id
      assert payment.status == "APPROVED"
      assert payment.amount == 2999
    end

    test "uses default values when options not provided", %{bypass: bypass} do
      customer_id = "CUSTOMER_123"

      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Verify default values are used
        assert request["amount_money"]["currency"] == "USD"
        assert request["note"] == "One-time purchase"
        assert String.starts_with?(request["reference_id"], "app:otp:")

        response = %{
          "payment" => %{
            "id" => "PAYMENT_456",
            "status" => "APPROVED",
            "amount_money" => %{
              "amount" => 1000,
              "currency" => "USD"
            },
            "created_at" => "2024-01-15T12:00:00Z"
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} = Payments.create_one_time(customer_id, "cnon:card-nonce", 1000)
          send(self(), {:ok, result})
        end)

      assert_received {:ok, payment}
      assert payment.payment_id == "PAYMENT_456"
    end

    test "handles card declined errors", %{bypass: bypass} do
      customer_id = "CUSTOMER_123"

      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        response = %{
          "errors" => [
            %{
              "code" => "CARD_DECLINED",
              "detail" => "Card was declined",
              "category" => "PAYMENT_METHOD_ERROR"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(400, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:error, error} =
            Payments.create_one_time(customer_id, "cnon:card-nonce", 1000,
              description: "Test purchase"
            )

          send(self(), {:error, error})
        end)

      assert_received {:error, "Card was declined"}
    end

    test "supports different currency options", %{bypass: bypass} do
      customer_id = "CUSTOMER_123"

      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        # Verify custom currency is used
        assert request["amount_money"]["currency"] == "EUR"

        response = %{
          "payment" => %{
            "id" => "PAYMENT_789",
            "status" => "APPROVED",
            "amount_money" => %{
              "amount" => 5000,
              "currency" => "EUR"
            },
            "created_at" => "2024-01-15T12:00:00Z"
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          {:ok, result} =
            Payments.create_one_time(customer_id, "cnon:card-nonce", 5000,
              description: "Annual pass",
              currency: "EUR"
            )

          send(self(), {:ok, result})
        end)

      assert_received {:ok, payment}
      assert payment.payment_id == "PAYMENT_789"
      assert payment.currency == "EUR"
    end
  end
end
