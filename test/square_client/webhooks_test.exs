defmodule SquareClient.WebhooksTest do
  use ExUnit.Case, async: true

  alias SquareClient.Webhooks

  describe "verify_signature/3" do
    test "verifies valid signature" do
      payload = ~s({"type":"payment.created","data":{"id":"123"}})
      signature_key = "test_key"

      # Generate correct signature
      signature = :crypto.mac(:hmac, :sha256, signature_key, payload) |> Base.encode64()

      assert Webhooks.verify_signature(payload, signature, signature_key) == true
    end

    test "rejects invalid signature" do
      payload = ~s({"type":"payment.created","data":{"id":"123"}})
      signature_key = "test_key"
      invalid_signature = "invalid_signature"

      assert Webhooks.verify_signature(payload, invalid_signature, signature_key) == false
    end

    test "rejects modified payload" do
      original_payload = ~s({"type":"payment.created","data":{"id":"123"}})
      modified_payload = ~s({"type":"payment.created","data":{"id":"456"}})
      signature_key = "test_key"

      # Generate signature for original payload
      signature = :crypto.mac(:hmac, :sha256, signature_key, original_payload) |> Base.encode64()

      # Try to verify with modified payload
      assert Webhooks.verify_signature(modified_payload, signature, signature_key) == false
    end

    test "handles nil inputs gracefully" do
      assert Webhooks.verify_signature(nil, "signature", "key") == false
      assert Webhooks.verify_signature("payload", nil, "key") == false
      assert Webhooks.verify_signature("payload", "signature", nil) == false
    end

    test "handles empty strings" do
      assert Webhooks.verify_signature("", "", "") == false
    end
  end

  describe "parse_event/1" do
    test "parses valid subscription created event" do
      payload = ~s({
        "type": "subscription.created",
        "event_id": "evt_123",
        "created_at": "2024-01-01T00:00:00Z",
        "merchant_id": "MERCHANT_123",
        "data": {
          "object": {
            "subscription": {
              "id": "sub_123",
              "status": "ACTIVE"
            }
          }
        }
      })

      assert {:ok, event} = Webhooks.parse_event(payload)
      assert event.event_type == "subscription.created"
      assert event.event_id == "evt_123"
      assert event.created_at == "2024-01-01T00:00:00Z"
      assert event.merchant_id == "MERCHANT_123"
      assert event.data["object"]["subscription"]["id"] == "sub_123"
    end

    test "parses payment event" do
      payload = ~s({
        "type": "payment.created",
        "event_id": "evt_456",
        "data": {
          "object": {
            "payment": {
              "id": "pay_123",
              "amount_money": {
                "amount": 1000,
                "currency": "USD"
              }
            }
          }
        }
      })

      assert {:ok, event} = Webhooks.parse_event(payload)
      assert event.event_type == "payment.created"
      assert event.data["object"]["payment"]["id"] == "pay_123"
    end

    test "parses already decoded event" do
      event = %{
        "type" => "invoice.payment_failed",
        "data" => %{"object" => %{"invoice" => %{"id" => "inv_123"}}}
      }

      assert {:ok, parsed} = Webhooks.parse_event(event)
      assert parsed.event_type == "invoice.payment.failed"
      assert parsed.data["object"]["invoice"]["id"] == "inv_123"
    end

    test "handles invalid JSON" do
      assert {:error, _} = Webhooks.parse_event("invalid json {")
    end

    test "handles missing required fields" do
      assert {:error, :invalid_event_format} = Webhooks.parse_event(~s({"missing": "type"}))
    end
  end

  describe "event type checks" do
    test "subscription_event?/1" do
      assert Webhooks.subscription_event?("subscription.created") == true
      assert Webhooks.subscription_event?("subscription.updated") == true
      assert Webhooks.subscription_event?("subscription.canceled") == true
      assert Webhooks.subscription_event?("payment.created") == false
      assert Webhooks.subscription_event?("invoice.sent") == false
    end

    test "payment_event?/1" do
      assert Webhooks.payment_event?("payment.created") == true
      assert Webhooks.payment_event?("payment.updated") == true
      assert Webhooks.payment_event?("subscription.created") == false
    end

    test "customer_event?/1" do
      assert Webhooks.customer_event?("customer.created") == true
      assert Webhooks.customer_event?("customer.updated") == true
      assert Webhooks.customer_event?("payment.created") == false
    end

    test "invoice_event?/1" do
      assert Webhooks.invoice_event?("invoice.sent") == true
      assert Webhooks.invoice_event?("invoice.payment_failed") == true
      assert Webhooks.invoice_event?("subscription.created") == false
    end
  end

  describe "get_subscription_id/1" do
    test "extracts from subscription object" do
      event = %{
        data: %{
          "object" => %{
            "subscription" => %{"id" => "sub_123"}
          }
        }
      }

      assert {:ok, "sub_123"} = Webhooks.get_subscription_id(event)
    end

    test "extracts from invoice object" do
      event = %{
        data: %{
          "object" => %{
            "invoice" => %{"subscription_id" => "sub_456"}
          }
        }
      }

      assert {:ok, "sub_456"} = Webhooks.get_subscription_id(event)
    end

    test "extracts from direct subscription_id" do
      event = %{
        data: %{
          "object" => %{"subscription_id" => "sub_789"}
        }
      }

      assert {:ok, "sub_789"} = Webhooks.get_subscription_id(event)
    end

    test "extracts from subscription event type" do
      event = %{
        event_type: "subscription.created",
        data: %{"id" => "sub_direct"}
      }

      assert {:ok, "sub_direct"} = Webhooks.get_subscription_id(event)
    end

    test "returns error when not found" do
      event = %{data: %{"object" => %{"payment" => %{"id" => "pay_123"}}}}
      assert {:error, :subscription_id_not_found} = Webhooks.get_subscription_id(event)
    end

    test "returns error for nil subscription_id in invoice" do
      event = %{
        data: %{
          "object" => %{
            "invoice" => %{"subscription_id" => nil}
          }
        }
      }

      assert {:error, :subscription_id_not_found} = Webhooks.get_subscription_id(event)
    end
  end

  describe "get_customer_id/1" do
    test "extracts from customer object" do
      event = %{
        data: %{
          "object" => %{
            "customer" => %{"id" => "cust_123"}
          }
        }
      }

      assert {:ok, "cust_123"} = Webhooks.get_customer_id(event)
    end

    test "extracts from customer_id field" do
      event = %{
        data: %{
          "object" => %{"customer_id" => "cust_456"}
        }
      }

      assert {:ok, "cust_456"} = Webhooks.get_customer_id(event)
    end

    test "extracts from customer event type" do
      event = %{
        event_type: "customer.created",
        data: %{"id" => "cust_direct"}
      }

      assert {:ok, "cust_direct"} = Webhooks.get_customer_id(event)
    end

    test "returns error when not found" do
      event = %{data: %{"object" => %{"payment" => %{"id" => "pay_123"}}}}
      assert {:error, :customer_id_not_found} = Webhooks.get_customer_id(event)
    end
  end

  describe "get_payment_id/1" do
    test "extracts from payment object" do
      event = %{
        data: %{
          "object" => %{
            "payment" => %{"id" => "pay_123"}
          }
        }
      }

      assert {:ok, "pay_123"} = Webhooks.get_payment_id(event)
    end

    test "extracts from payment event type" do
      event = %{
        event_type: "payment.created",
        data: %{"id" => "pay_direct"}
      }

      assert {:ok, "pay_direct"} = Webhooks.get_payment_id(event)
    end

    test "returns error when not found" do
      event = %{data: %{"object" => %{"subscription" => %{"id" => "sub_123"}}}}
      assert {:error, :payment_id_not_found} = Webhooks.get_payment_id(event)
    end
  end
end
