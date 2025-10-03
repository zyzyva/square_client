defmodule APP_MODULE.Payments.SquareWebhookHandlerTest do
  use ExUnit.Case, async: true

  # Ensure the module is loaded before tests run
  setup_all do
    Code.ensure_loaded!(APP_MODULE.Payments.SquareWebhookHandler)
    :ok
  end

  describe "behaviour implementation" do
    test "implements SquareClient.WebhookHandler behaviour" do
      # Verify that our production handler implements the behaviour correctly
      behaviours = APP_MODULE.Payments.SquareWebhookHandler.__info__(:attributes)[:behaviour]
      assert SquareClient.WebhookHandler in behaviours
    end

    test "handler has handle_event/1 function exported" do
      # Ensure module is loaded before checking
      Code.ensure_loaded!(APP_MODULE.Payments.SquareWebhookHandler)

      # Verify the handler exports the required function
      assert function_exported?(APP_MODULE.Payments.SquareWebhookHandler, :handle_event, 1),
             "handle_event/1 should be exported"
    end

    test "handle_event/1 responds to unhandled events" do
      # Test that the function handles unknown events gracefully
      event = %{event_type: "unknown_event", data: %{}}
      assert APP_MODULE.Payments.SquareWebhookHandler.handle_event(event) == :ok
    end

    test "handle_event/1 responds to customer events" do
      # Test customer events that don't require database interaction
      customer_created = %{
        event_type: "customer.created",
        data: %{"customer" => %{"id" => "cust_123"}}
      }

      assert APP_MODULE.Payments.SquareWebhookHandler.handle_event(customer_created) == :ok

      customer_updated = %{
        event_type: "customer.updated",
        data: %{"customer" => %{"id" => "cust_123"}}
      }

      assert APP_MODULE.Payments.SquareWebhookHandler.handle_event(customer_updated) == :ok
    end
  end
end
