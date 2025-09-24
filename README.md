# SquareClient

Async payment processing client for Elixir applications using RabbitMQ message queuing.

## Overview

SquareClient enables applications to process payments asynchronously through a centralized payment service. Instead of making direct API calls to Square, this library:

1. **Publishes payment requests** to RabbitMQ via HTTP (no AMQP dependencies needed)
2. **Payment service processes** the requests with Square API
3. **Receives callbacks** with results via webhooks

This architecture provides resilience, retry capability, and centralized Square credential management.

## Architecture

```
Your App → RabbitMQ (HTTP) → Payment Service → Square API
    ↑                                  ↓
    ←──────── Webhook Callback ────────┘
```

## Installation

Add `square_client` to your dependencies:

```elixir
def deps do
  [
    {:square_client, github: "zyzyva/square_client"}
  ]
end
```

## Configuration

Configure the client in your `config/runtime.exs`:

```elixir
config :my_app, :payment_service,
  rabbitmq_url: System.get_env("RABBITMQ_MANAGEMENT_URL", "http://localhost:15672"),
  app_id: "my_app",  # Identifies your app to the payment service
  callback_url: System.get_env("PAYMENT_CALLBACK_URL", "https://myapp.com/webhooks/payments"),
  queue_name: "payments",
  exchange: "payments",
  rabbitmq_username: System.get_env("RABBITMQ_USERNAME", "guest"),
  rabbitmq_password: System.get_env("RABBITMQ_PASSWORD", "guest")
```

Initialize in your application startup:

```elixir
# In lib/my_app/application.ex
def start(_type, _args) do
  # Configure payment client
  payment_config = Application.get_env(:my_app, :payment_service)
  SquareClient.configure(payment_config)

  # ... rest of your supervision tree
end
```

## Usage

All operations are asynchronous and return immediately with a correlation ID:

### Creating a Customer

```elixir
{:ok, :pending, correlation_id} = SquareClient.PaymentQueue.create_customer(%{
  email_address: "customer@example.com",
  reference_id: "my_app:user:123"
})

# Payment service will POST to your callback URL when complete
```

### Creating a Subscription

```elixir
{:ok, :pending, correlation_id} = SquareClient.PaymentQueue.create_subscription(
  customer_id,
  plan_id,
  card_id: card_id
)
```

### Processing a Payment

```elixir
{:ok, :pending, correlation_id} = SquareClient.PaymentQueue.create_payment(
  source_id,
  1000,  # Amount in cents
  "USD",
  customer_id: customer_id,
  note: "Order #1234"
)
```

### Canceling a Subscription

```elixir
{:ok, :pending, correlation_id} = SquareClient.PaymentQueue.cancel_subscription(
  subscription_id
)
```

## Webhook Callbacks

The payment service will POST results to your configured `callback_url`. Set up a webhook controller:

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller

  def payment_callback(conn, %{"correlation_id" => correlation_id} = params) do
    case params do
      %{"operation" => "subscription.create", "success" => true, "data" => data} ->
        # Handle successful subscription creation

      %{"operation" => "payment.create", "success" => false, "error" => error} ->
        # Handle failed payment

      # ... handle other operations
    end

    conn
    |> put_status(:ok)
    |> json(%{received: true})
  end
end
```

Add the route:

```elixir
scope "/webhooks", MyAppWeb do
  pipe_through :api

  post "/payments", WebhookController, :payment_callback
end
```

## Message Flow

1. **Your app** calls `SquareClient.PaymentQueue.create_payment(...)`
2. **SquareClient** publishes to RabbitMQ with:
   - Your `app_id` for tracking
   - A unique `correlation_id`
   - Your `callback_url` for the response
3. **Payment service** processes with Square API
4. **Payment service** POSTs result to your callback URL
5. **Your webhook** handles the async response

## Benefits

- **No Square credentials in your app** - Only the payment service needs them
- **Automatic retry** - Payment service handles transient failures
- **Multi-app support** - Each app identified by its `app_id`
- **Resilient** - Messages queued if payment service is down
- **Simple** - No AMQP/Broadway dependencies needed

## How It Works

The library publishes messages to RabbitMQ's management API (typically port 15672) using HTTP, similar to how `swoosh_rabbitmq` handles email. This avoids the need for AMQP connections and Broadway consumers in your application.

Each message includes:
- `operation`: The payment operation to perform
- `app_id`: Your application identifier
- `callback_url`: Where to send the result
- `correlation_id`: To match requests with responses
- `params`: Operation-specific parameters

## Environment Variables

### Required for Payment Processing

- `SQUARE_APPLICATION_ID`: Your Square application ID
- `SQUARE_LOCATION_ID`: Your Square location ID
- `SQUARE_ACCESS_TOKEN`: Your Square access token (only needed by payment service)
- `SQUARE_WEBHOOK_SIGNATURE_KEY`: For webhook verification
- `SQUARE_ENVIRONMENT`: Set to "production" for live payments (default: "sandbox")

### RabbitMQ Configuration

- `RABBITMQ_MANAGEMENT_URL`: RabbitMQ management API URL (default: `http://localhost:15672`)
- `RABBITMQ_USERNAME`: RabbitMQ username (default: `guest`)
- `RABBITMQ_PASSWORD`: RabbitMQ password (default: `guest`)
- `PAYMENT_CALLBACK_URL`: Your webhook endpoint for receiving results

### Square Web Payments SDK

For the frontend Square SDK, configure in your app's `config/prod.exs`:

```elixir
# config/prod.exs
config :my_app, :square_sdk_url, "https://web.squarecdn.com/v1/square.js"
```

Default for development is the sandbox URL: `https://sandbox.web.squarecdn.com/v1/square.js`

Then in your layout:

```heex
<%= if assigns[:load_square_sdk] do %>
  <script type="text/javascript" src={Application.get_env(:my_app, :square_sdk_url, "https://sandbox.web.squarecdn.com/v1/square.js")}>
  </script>
<% end %>
```

## Testing

For local development, you can use Docker to run RabbitMQ:

```bash
docker run -d \
  --name rabbitmq \
  -p 5672:5672 \
  -p 15672:15672 \
  rabbitmq:management
```

## License

MIT