# Square Webhook Integration Guide

This guide provides comprehensive documentation for integrating Square webhooks with your application using the SquareClient library.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Implementation Steps](#implementation-steps)
- [Event Types](#event-types)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

The SquareClient library provides a complete webhook handling solution that:
- Verifies webhook signatures automatically
- Parses and validates webhook events
- Routes events to your application's business logic
- Provides consistent error handling across all your apps

## Architecture

```
Square API → Your App Endpoint → WebhookPlug → Your Handler → Response
                                       ↓
                              Signature Verification
                                       ↓
                                Event Parsing
                                       ↓
                              Handler Invocation
```

### Components

1. **SquareClient.WebhookHandler** - Behaviour that defines the contract for handling webhooks
2. **SquareClient.WebhookPlug** - Plug that handles verification and parsing
3. **SquareClient.Webhooks** - Utility functions for webhook processing
4. **Your Implementation** - Your app's business logic for handling events

## Implementation Steps

### Step 1: Create Your Handler Module

Create a module that implements the `SquareClient.WebhookHandler` behaviour:

```elixir
defmodule MyApp.Payments.SquareWebhookHandler do
  @behaviour SquareClient.WebhookHandler

  require Logger
  alias MyApp.Payments

  @impl true
  def handle_event(%{event_type: "payment.created", data: data} = event) do
    Logger.info("Processing payment: #{event.event_id}")

    case Payments.create_payment(data) do
      {:ok, _payment} -> :ok
      {:error, reason} ->
        Logger.error("Failed to process payment: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def handle_event(%{event_type: "subscription.created", data: data} = event) do
    Logger.info("Processing subscription: #{event.event_id}")
    Payments.handle_subscription_created(data)
    :ok
  end

  @impl true
  def handle_event(%{event_type: "subscription.canceled", data: data} = event) do
    Logger.info("Processing subscription cancellation: #{event.event_id}")
    Payments.handle_subscription_canceled(data)
    :ok
  end

  @impl true
  def handle_event(%{event_type: "invoice.payment_made", data: data} = event) do
    Logger.info("Processing invoice payment: #{event.event_id}")
    Payments.handle_invoice_payment(data)
    :ok
  end

  @impl true
  def handle_event(%{event_type: "invoice.payment_failed", data: data} = event) do
    Logger.warning("Invoice payment failed: #{event.event_id}")
    Payments.handle_failed_payment(data)
    :ok
  end

  # Catch-all for unhandled events
  @impl true
  def handle_event(%{event_type: event_type} = event) do
    Logger.debug("Unhandled webhook event: #{event_type}")
    :ok  # Return :ok to acknowledge receipt
  end
end
```

### Step 2: Configure the Library

Add configuration to your `config/config.exs`:

```elixir
config :square_client,
  webhook_handler: MyApp.Payments.SquareWebhookHandler
```

Add to `config/runtime.exs` for production:

```elixir
config :square_client,
  webhook_signature_key: System.get_env("SQUARE_WEBHOOK_SIGNATURE_KEY")
```

### Step 3: Set Up Router Pipeline

In your Phoenix router:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # Define the webhook pipeline
  pipeline :square_webhook do
    plug :accepts, ["json"]
    plug SquareClient.WebhookPlug
  end

  # Set up the webhook endpoint
  scope "/webhooks", MyAppWeb do
    pipe_through :square_webhook

    post "/square", SquareWebhookController, :handle
  end
end
```

### Step 4: Create the Controller

```elixir
defmodule MyAppWeb.SquareWebhookController do
  use MyAppWeb, :controller
  require Logger

  def handle(conn, _params) do
    handle_webhook_result(conn, conn.assigns[:square_event])
  end

  defp handle_webhook_result(conn, {:ok, event}) do
    Logger.info("Successfully processed Square webhook: #{event.event_type}")

    conn
    |> put_status(:ok)
    |> json(%{received: true, event_id: event.event_id})
  end

  defp handle_webhook_result(conn, {:error, :invalid_signature}) do
    Logger.warning("Received Square webhook with invalid signature")

    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid signature"})
  end

  defp handle_webhook_result(conn, {:error, :missing_signature}) do
    Logger.warning("Received Square webhook without signature")

    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Missing signature"})
  end

  defp handle_webhook_result(conn, {:error, reason}) do
    Logger.error("Square webhook processing failed: #{inspect(reason)}")

    conn
    |> put_status(:bad_request)
    |> json(%{error: "Webhook processing failed"})
  end
end
```

### Step 5: Configure Square Dashboard

1. Log into your Square Dashboard
2. Navigate to Webhooks settings
3. Add your webhook endpoint URL: `https://yourapp.com/webhooks/square`
4. Select the events you want to receive
5. Copy the Signature Key and add to your environment variables

## Event Types

### Payment Events

```elixir
def handle_event(%{event_type: "payment.created", data: data}) do
  # data contains:
  # - payment.id
  # - payment.amount_money
  # - payment.status
  # - payment.created_at
end

def handle_event(%{event_type: "payment.updated", data: data}) do
  # Handle payment updates (status changes, etc.)
end
```

### Subscription Events

```elixir
def handle_event(%{event_type: "subscription.created", data: data}) do
  # data contains:
  # - subscription.id
  # - subscription.customer_id
  # - subscription.plan_id
  # - subscription.status
end

def handle_event(%{event_type: "subscription.updated", data: data}) do
  # Handle plan changes, pauses, resumes
end

def handle_event(%{event_type: "subscription.canceled", data: data}) do
  # Handle cancellations
end
```

### Invoice Events

```elixir
def handle_event(%{event_type: "invoice.payment_made", data: data}) do
  # Successful subscription renewal
  # - invoice.id
  # - invoice.subscription_id
  # - invoice.payment_requests
end

def handle_event(%{event_type: "invoice.payment_failed", data: data}) do
  # Failed payment (card declined, expired, etc.)
  # Handle retry logic or notifications
end
```

## Testing

### Unit Testing Your Handler

```elixir
defmodule MyApp.SquareWebhookHandlerTest do
  use ExUnit.Case, async: true
  alias MyApp.Payments.SquareWebhookHandler

  describe "handle_event/1" do
    test "processes payment.created event" do
      event = %{
        event_type: "payment.created",
        data: %{
          "payment" => %{
            "id" => "pay_123",
            "amount_money" => %{"amount" => 1000, "currency" => "USD"}
          }
        },
        event_id: "evt_123",
        created_at: "2025-01-26T12:00:00Z"
      }

      assert :ok = SquareWebhookHandler.handle_event(event)
      # Assert your business logic was executed
    end
  end
end
```

### Integration Testing

```elixir
defmodule MyAppWeb.SquareWebhookControllerTest do
  use MyAppWeb.ConnCase
  import ExUnit.CaptureLog

  setup do
    # Configure test signature key
    Application.put_env(:square_client, :webhook_signature_key, "test_key")
    :ok
  end

  test "processes valid webhook", %{conn: conn} do
    body = ~s({"type": "payment.created", "data": {"payment": {"id": "pay_123"}}, "event_id": "evt_123"})
    signature = generate_signature(body, "test_key")

    log = capture_log([level: :info], fn ->
      conn =
        conn
        |> put_req_header("x-square-hmacsha256-signature", signature)
        |> post("/webhooks/square", body)

      assert json_response(conn, 200) == %{
        "received" => true,
        "event_id" => "evt_123"
      }
    end)

    assert log =~ "Successfully processed Square webhook"
  end

  test "rejects invalid signature", %{conn: conn} do
    body = ~s({"type": "payment.created", "data": {}})

    conn =
      conn
      |> put_req_header("x-square-hmacsha256-signature", "invalid")
      |> post("/webhooks/square", body)

    assert json_response(conn, 401) == %{"error" => "Invalid signature"}
  end

  defp generate_signature(payload, key) do
    :crypto.mac(:hmac, :sha256, key, payload)
    |> Base.encode64()
  end
end
```

### Local Testing with ngrok

1. Install ngrok: `brew install ngrok`
2. Start your Phoenix server: `mix phx.server`
3. Expose your local server: `ngrok http 4000`
4. Use the ngrok URL in Square Dashboard for testing

## Troubleshooting

### Common Issues

**"Invalid signature" errors:**
- Verify the signature key is correctly configured
- Ensure you're using the raw request body (not parsed JSON)
- Check that the header name is exactly `x-square-hmacsha256-signature`

**Events not being received:**
- Verify webhook URL is correct in Square Dashboard
- Check that your endpoint is publicly accessible
- Ensure the events are enabled in Square Dashboard
- Look for timeout issues (respond within 10 seconds)

**"Missing signature" errors:**
- Square always sends the signature header
- This usually means the request isn't coming from Square
- Check for proxy/load balancer issues stripping headers

**Handler not being called:**
- Verify the handler module is configured correctly
- Check that the module implements the behaviour
- Look for compilation errors in your handler

### Debug Logging

Enable debug logging to troubleshoot issues:

```elixir
# In config/dev.exs
config :logger, level: :debug

# In your handler
require Logger

def handle_event(event) do
  Logger.debug("Received event: #{inspect(event)}")
  # Your logic here
end
```

## Best Practices

### 1. Idempotency

Square may send the same webhook multiple times. Use the `event_id` to ensure idempotency:

```elixir
def handle_event(%{event_id: event_id} = event) do
  case MyApp.Events.already_processed?(event_id) do
    true ->
      Logger.debug("Skipping duplicate event: #{event_id}")
      :ok
    false ->
      MyApp.Events.mark_processed(event_id)
      process_event(event)
  end
end
```

### 2. Fast Response Times

Respond to webhooks quickly to avoid timeouts:

```elixir
def handle_event(event) do
  # Queue for background processing instead of inline processing
  MyApp.JobQueue.enqueue(ProcessWebhookJob, event)
  :ok  # Return immediately
end
```

### 3. Error Handling

Don't let handler errors crash the webhook processing:

```elixir
def handle_event(event) do
  try do
    process_event(event)
    :ok
  rescue
    error ->
      Logger.error("Handler error: #{inspect(error)}")
      Sentry.capture_exception(error)
      :ok  # Still acknowledge receipt
  end
end
```

### 4. Event Filtering

Only process events you care about:

```elixir
@handled_events ~w[
  payment.created
  subscription.created
  subscription.canceled
  invoice.payment_made
  invoice.payment_failed
]

def handle_event(%{event_type: event_type} = event) when event_type in @handled_events do
  # Process known events
end

def handle_event(%{event_type: event_type}) do
  Logger.debug("Ignoring event: #{event_type}")
  :ok
end
```

### 5. Monitoring

Add monitoring and alerting:

```elixir
def handle_event(event) do
  start_time = System.monotonic_time()

  result = process_event(event)

  duration = System.monotonic_time() - start_time
  :telemetry.execute(
    [:webhook, :processed],
    %{duration: duration},
    %{event_type: event.event_type, status: result}
  )

  result
end
```

## Security Considerations

1. **Always use HTTPS** in production
2. **Never log sensitive data** (card numbers, CVV, etc.)
3. **Validate webhook data** before processing
4. **Rate limit your endpoints** to prevent abuse
5. **Monitor for suspicious patterns** (unusual volume, repeated failures)
6. **Rotate signature keys** periodically
7. **Use separate keys** for sandbox and production

## Additional Resources

- [Square Webhooks Documentation](https://developer.squareup.com/docs/webhooks)
- [Square API Reference](https://developer.squareup.com/reference/square)
- [Phoenix Framework Guides](https://hexdocs.pm/phoenix/overview.html)
- [Plug Documentation](https://hexdocs.pm/plug/readme.html)