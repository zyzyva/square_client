# SquareClient

A flexible Elixir client library for Square API integration, focused on subscription management and payment processing.

## Documentation

- 💳 [JSON-Driven Payment Plans](JSON_PLANS.md) - Complete guide for JSON-based plan management
- 🚀 [Multi-App Payments](MULTI_APP_PAYMENTS.md) - Strategy for multiple apps sharing Square
- 📖 [Webhook Integration Guide](WEBHOOK.md) - Complete guide for webhook implementation
- 📝 [Changelog](CHANGELOG.md) - Version history and changes
- 🧪 [Test Cards](TEST_CARDS.md) - Test credit card numbers for sandbox

## Features

- **JSON-driven payment plans** - Manage plans and pricing without code changes
- **Direct Square API integration** - No proxy service or message queue required
- **Webhook handling infrastructure** - Standardized webhook processing with signature verification
- **Subscription plan and variation management** - Following Square's recommended patterns
- **Reusable subscription schema** - Drop-in Ecto schema with Square sync capabilities
- **Prorated refund calculations** - Automatic refund processing for subscription cancellations
- **One-time purchase support** - Sell passes and time-limited access
- **Synchronous REST API** - Immediate feedback for payment processing
- **Environment-aware configuration** - Automatic sandbox/production switching
- **Runtime configuration validation** - Catch missing config at app startup with helpful errors
- **Comprehensive test coverage** - Fast (0.1s), clean tests with mocked API calls
- **Multiple configuration methods** - Application config, environment variables, or defaults
- **Behaviour-based extensibility** - Implement webhooks consistently across all apps

## Installation

Add `square_client` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:square_client, github: "zyzyva/square_client"}
  ]
end
```

## Quick Start

### 1. Add to your application

```elixir
# In your application.ex
def start(_type, _args) do
  # Validate Square config at startup
  SquareClient.Config.validate_runtime!()

  children = [
    # ... your other children
  ]
  # ...
end
```

### 2. Configure Square credentials

```elixir
# config/config.exs
config :square_client,
  api_url: "https://connect.squareupsandbox.com/v2",
  access_token: System.get_env("SQUARE_ACCESS_TOKEN"),
  location_id: System.get_env("SQUARE_LOCATION_ID"),
  webhook_handler: MyApp.Payments.SquareWebhookHandler

# config/prod.exs
config :square_client,
  api_url: "https://connect.squareup.com/v2"  # Production URL
```

### 3. Create your subscription schema

```elixir
defmodule MyApp.Payments.Subscription do
  use SquareClient.Subscriptions.Schema,
    repo: MyApp.Repo,
    belongs_to: [
      {:user, MyApp.Accounts.User}
    ]
end
```

### 4. Implement webhook handler

```elixir
defmodule MyApp.Payments.SquareWebhookHandler do
  @behaviour SquareClient.WebhookHandler

  def handle_event(%{event_type: "subscription.created", data: data}) do
    # Sync subscription to your database
    :ok
  end

  def handle_event(_event), do: :ok
end
```

That's it! You now have a complete Square integration with subscriptions, webhooks, and refunds.

## Configuration

SquareClient supports flexible configuration with clear precedence:

### API Key Management

**Single Set of Keys with Separate Plans (Recommended)**
Use one Square account across all apps with app-specific plans:
- Single business entity with multiple applications
- All payments go to one bank account
- Each app maintains its own subscription plans with unique IDs
- Clear attribution through plan naming and reference IDs
- See [MULTI_APP_PAYMENTS.md](MULTI_APP_PAYMENTS.md) for implementation details

**Multiple Sets of Keys**
Only needed when:
- Different legal entities (each app is a separate business)
- Marketplace model (each app represents different merchants)
- Compliance requirements for payment isolation
- Payments need separate bank account destinations

### Configuration Precedence (highest to lowest)

1. **Application Config** - Set in your app's config files
2. **Environment Variables** - For deployment and secrets
3. **Default Values** - Sensible defaults for development

### Method 1: Application Configuration (Recommended)

**For Shared Keys Across All Apps:**
```elixir
# Each app uses the same Square account
# config/config.exs in each app
config :square_client,
  api_url: "https://connect.squareupsandbox.com/v2",
  access_token: System.get_env("SQUARE_ACCESS_TOKEN")  # Same token for all apps
```

**For App-Specific Keys:**
```elixir
# contacts4us/config/config.exs
config :square_client,
  access_token: System.get_env("CONTACTS4US_SQUARE_TOKEN")

# analytics_app/config/config.exs
config :square_client,
  access_token: System.get_env("ANALYTICS_SQUARE_TOKEN")
```

For environment-specific configuration:

```elixir
# config/prod.exs
config :square_client,
  api_url: "https://connect.squareup.com/v2"  # Production API

# config/test.exs
config :square_client,
  api_url: "http://localhost:4001/v2",  # Mock server for tests
  disable_retries: true  # Faster test execution
```

### Method 2: Environment Variables (Optional Fallback)

For deployments where you can't modify config files, set these environment variables:

- `SQUARE_ACCESS_TOKEN` - Your Square API access token (required)
- `SQUARE_ENVIRONMENT` - Controls which plan IDs to use:
  - `"production"` - Uses production plan IDs
  - `"sandbox"` (default) - Uses sandbox plan IDs
- `SQUARE_APPLICATION_ID` - Your Square application ID
- `SQUARE_LOCATION_ID` - Your Square location ID

Example:
```bash
export SQUARE_ACCESS_TOKEN="YOUR_SANDBOX_TOKEN"
export SQUARE_ENVIRONMENT="sandbox"
export SQUARE_APPLICATION_ID="YOUR_APP_ID"
export SQUARE_LOCATION_ID="YOUR_LOCATION_ID"
```

**Note:** Application config takes precedence over environment variables.

## Usage

### JSON-Driven Payment Plans (Recommended)

The library includes a complete JSON-driven payment system. See [JSON_PLANS.md](JSON_PLANS.md) for full documentation.

**Quick Start:**
```bash
# Initialize plans configuration
mix square.init_plans --app my_app

# Edit priv/square_plans.json to define your plans

# Use in your LiveView
alias SquareClient.Plans.Formatter
plans = Formatter.get_subscription_plans(:my_app)
```

### Managing Subscription Plans (Programmatic API)

Square recommends using base plans with variations for different billing periods. This allows better catalog organization and pricing flexibility.

```elixir
# Create a base subscription plan
{:ok, plan} = SquareClient.Catalog.create_base_subscription_plan(%{
  name: "Premium Plan",
  description: "Access to premium features"
})

# Create pricing variations
{:ok, monthly} = SquareClient.Catalog.create_plan_variation(%{
  base_plan_id: plan.plan_id,
  name: "Monthly",
  cadence: "MONTHLY",
  amount: 999,  # $9.99 in cents
  currency: "USD"
})

{:ok, annual} = SquareClient.Catalog.create_plan_variation(%{
  base_plan_id: plan.plan_id,
  name: "Annual",
  cadence: "ANNUAL",
  amount: 9900,  # $99.00 in cents
  currency: "USD"
})
```

### Listing Plans and Variations

```elixir
# List all subscription plans
{:ok, plans} = SquareClient.Catalog.list_subscription_plans()

# List all plan variations
{:ok, variations} = SquareClient.Catalog.list_plan_variations()

# Get a specific catalog object
{:ok, object} = SquareClient.Catalog.get(object_id)
```

### Payment Processing

#### Standard Payments

```elixir
# Process a payment with full control
{:ok, payment} = SquareClient.Payments.create(
  source_id,
  amount,
  currency,
  customer_id: customer_id,
  reference_id: "order-123"
)
```

#### One-Time Purchases

Perfect for selling time-based access (30-day passes, yearly access, etc.) instead of auto-renewing subscriptions:

```elixir
# Simple one-time payment for time-based access
{:ok, payment} = SquareClient.Payments.create_one_time(
  customer_id,
  source_id,      # Card nonce or saved card ID
  9999,           # Amount in cents ($99.99)
  description: "30-day premium access",
  app_name: :my_app
)

# In your app, grant time-limited access after successful payment:
expires_at = DateTime.add(DateTime.utc_now(), 30, :day)
# Update user with expiration date
```

**When to use one-time purchases vs subscriptions:**
- **One-time**: User manually renews, better for annual plans or trial offers
- **Subscriptions**: Auto-renews, better for monthly plans and regular revenue
- **Both**: Offer choice - some users prefer control over auto-renewal

```elixir
# Example: Offering both subscription and one-time options
plans = [
  %{type: :subscription, name: "Monthly Premium", price: 999},     # Auto-renews
  %{type: :one_time, name: "30-Day Pass", price: 999, days: 30},  # Manual renewal
  %{type: :one_time, name: "Annual Pass", price: 9999, days: 365}  # Better value
]
```

### Subscription Management

The library provides complete subscription management infrastructure that you can drop into your app.

#### 1. Subscription Schema

Use the reusable schema macro to create your subscription table:

```elixir
defmodule MyApp.Payments.Subscription do
  use SquareClient.Subscriptions.Schema,
    repo: MyApp.Repo,
    belongs_to: [
      {:user, MyApp.Accounts.User}
    ]

  # Optional: Add app-specific helper functions
  defdelegate get_active_for_user(user_or_id), to: __MODULE__, as: :get_active_for_owner
end
```

This automatically gives you:
- Complete Ecto schema with all Square subscription fields
- `square_subscription_id`, `status`, `tier`, billing dates, etc.
- Query helpers: `active/0`, `for_owner/2`, `get_active_for_owner/1`
- Automatic Square sync capabilities

**Generate the migration:**

```bash
mix ecto.gen.migration create_subscriptions
```

```elixir
defmodule MyApp.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :square_subscription_id, :string, null: false
      add :square_customer_id, :string
      add :status, :string, null: false
      add :tier, :string, null: false
      add :charged_through_date, :date
      add :canceled_date, :date
      add :start_date, :date
      add :next_billing_date, :date
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:square_subscription_id])
    create index(:subscriptions, [:user_id])
    create index(:subscriptions, [:status])
  end
end
```

#### 2. Creating Subscriptions

```elixir
# Create subscription with Square
{:ok, subscription} = SquareClient.Subscriptions.create_with_plan_lookup(
  customer_id,
  "premium_monthly",  # Plan key from your config
  card_token
)

# Sync to your database
SquareClient.Subscriptions.Context.sync_from_square(
  MyApp.Payments.Subscription,
  MyApp.Repo,
  subscription
)
```

#### 3. Syncing from Webhooks

```elixir
defmodule MyApp.Payments.SquareWebhookHandler do
  @behaviour SquareClient.WebhookHandler

  alias MyApp.Payments.Subscription
  alias MyApp.Repo

  def handle_event(%{event_type: "subscription.updated", data: %{"object" => %{"subscription" => square_sub}}}) do
    # Automatically sync changes from Square
    SquareClient.Subscriptions.Context.sync_from_square(
      Subscription,
      Repo,
      square_sub
    )
    :ok
  end

  def handle_event(_event), do: :ok
end
```

#### 4. Canceling with Prorated Refunds

```elixir
alias SquareClient.Subscriptions.Refunds

# Cancel subscription
{:ok, _} = SquareClient.Subscriptions.cancel(subscription.square_subscription_id)

# Calculate prorated refund
subscription = Repo.get!(MyApp.Payments.Subscription, subscription_id)
days_remaining = Refunds.calculate_remaining_days(subscription)

refund_amount = Refunds.calculate_prorated_refund(
  subscription,
  days_remaining,
  %{monthly: 999, yearly: 9999}  # Your plan pricing
)

# Process automatic refund
Refunds.process_automatic_refund(
  subscription,
  refund_amount,
  payment_id: last_payment_id
)
```

#### 5. Query Helpers

The schema provides built-in query helpers:

```elixir
# Get active subscription for a user
subscription = MyApp.Payments.Subscription.get_active_for_owner(user.id)

# Query active subscriptions
active_subs =
  MyApp.Payments.Subscription
  |> MyApp.Payments.Subscription.active()
  |> Repo.all()

# Query subscriptions for a specific user
user_subs =
  MyApp.Payments.Subscription
  |> MyApp.Payments.Subscription.for_owner(user.id)
  |> Repo.all()
```

### Subscription Constants

Access Square status and tier constants:

```elixir
alias SquareClient.Subscriptions.Constants

# Tier constants
Constants.tier_free()      # "free"
Constants.tier_premium()   # "premium"

# Status constants
Constants.status_active()     # "active"
Constants.status_canceled()   # "canceled"
Constants.status_past_due()   # "past_due"

# Square status constants
Constants.square_status_active()      # "ACTIVE"
Constants.square_status_canceled()    # "CANCELED"
Constants.square_status_delinquent()  # "DELINQUENT"

# Convert Square status to internal status
internal_status = Constants.square_to_internal_status("ACTIVE")  # "active"
```

## Mix Tasks for Apps

Apps using this library can create Mix tasks for plan management:

```elixir
# In your app, create lib/mix/tasks/square.setup_plans.ex
defmodule Mix.Tasks.Square.SetupPlans do
  use Mix.Task

  def run(_) do
    Mix.Task.run("app.start")

    # Create your app's subscription plans
    {:ok, plan} = SquareClient.Catalog.create_base_subscription_plan(%{
      name: "MyApp Premium"
    })

    # Save plan IDs to your config/database
    IO.puts("Created plan: #{plan.plan_id}")
  end
end
```

## Testing

The library includes comprehensive tests with mocked API responses:

```bash
# Run tests (0.1s execution time)
mix test

# Tests use Bypass to mock Square API - no real API calls
# All logs are captured for clean output using ExUnit.CaptureLog
```

### Testing in Your App

When testing code that uses SquareClient:

```elixir
# In your test config
config :square_client,
  api_url: "http://localhost:#{bypass_port}/v2",
  disable_retries: true  # Important for test speed
```

### Test Performance

Tests run in 0.1 seconds because:
- API calls are mocked with Bypass (no network requests)
- Retries are disabled in test environment
- Logs are captured to prevent output noise

## API Version

This library uses Square API version **2025-01-23** (latest stable).

Key differences from older versions:
- Uses `pricing` field for variations (not `recurring_price_money`)
- Supports latest subscription features
- Improved error messages

## Architecture Decisions

### Why REST API Instead of Message Queues

This library uses synchronous REST API calls instead of message queues (RabbitMQ) because:

1. **Immediate feedback** - Payment processing needs instant response for:
   - Card declines
   - Validation errors
   - Insufficient funds

2. **Simpler error handling** - Direct error responses vs async callbacks

3. **Easier debugging** - Synchronous flow is easier to trace

4. **No infrastructure dependencies** - No need for RabbitMQ, Broadway, etc.

5. **Better UX** - Users get immediate feedback on payment issues

### Thin Client Approach

Each app manages its own Square resources (plans, customers) rather than centralizing in a payment service:

- **Flexibility** - Apps can have different subscription models
- **Direct control** - Apps manage their own pricing and plans
- **Easier testing** - No dependency on external services
- **No single point of failure** - Each app is independent

### Configuration Flexibility

The library checks multiple configuration sources in order:
1. Application config (for app-specific overrides)
2. Environment variables (for deployment flexibility)
3. Defaults (for quick development start)

This allows apps to:
- Override settings in their config files
- Deploy with environment variables
- Start developing with zero configuration

## Webhook Handling

> 📖 **For comprehensive webhook documentation, see [WEBHOOK.md](WEBHOOK.md)**

SquareClient provides a standardized webhook infrastructure for all your apps:

### Features
- **Automatic signature verification** - Ensures webhooks are from Square
- **Standardized behaviour** - Consistent webhook handling across all apps
- **Plug-based architecture** - Easy integration with Phoenix/Plug applications
- **Comprehensive error handling** - Graceful handling of invalid webhooks

### Quick Start

1. **Implement the webhook handler behaviour** in your app:

```elixir
defmodule MyApp.SquareWebhookHandler do
  @behaviour SquareClient.WebhookHandler

  @impl true
  def handle_event(%{event_type: "payment.created", data: data}) do
    # Process payment
    MyApp.Payments.process_payment(data)
    :ok
  end

  @impl true
  def handle_event(%{event_type: "subscription.created", data: data}) do
    # Create local subscription record
    MyApp.Subscriptions.create_from_square(data)
    :ok
  end

  # Catch-all for unhandled events
  @impl true
  def handle_event(_event) do
    # Log or ignore
    :ok
  end
end
```

2. **Configure the handler and signature key**:

```elixir
# In config/config.exs
config :square_client,
  webhook_handler: MyApp.SquareWebhookHandler,
  webhook_signature_key: System.get_env("SQUARE_WEBHOOK_SIGNATURE_KEY")
```

3. **Add the webhook plug to your router**:

```elixir
# In your Phoenix router
pipeline :square_webhook do
  plug :accepts, ["json"]
  plug SquareClient.WebhookPlug
end

scope "/webhooks", MyAppWeb do
  pipe_through :square_webhook
  post "/square", WebhookController, :handle
end
```

4. **Create a webhook controller using the library behavior**:

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller
  use SquareClient.Controllers.WebhookController

  # That's it! The behavior provides complete webhook handling
  # You can optionally override any response handlers:

  # def handle_success(conn, event) do
  #   # Custom success response
  #   conn |> put_status(:accepted) |> json(%{ok: true})
  # end
end
```

**Manual Implementation (if you prefer):**

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller

  def handle(conn, _params) do
    case conn.assigns[:square_event] do
      {:ok, event} ->
        # Event was processed by your handler
        json(conn, %{received: true})

      {:error, :invalid_signature} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid signature"})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid webhook"})
    end
  end
end
```

### How It Works

1. **Square sends webhook** to your endpoint
2. **WebhookPlug intercepts** the request
3. **Signature is verified** using HMAC-SHA256
4. **Event is parsed** from JSON
5. **Handler is called** with the parsed event
6. **Result stored** in `conn.assigns.square_event`
7. **Controller responds** based on the result

### Configuration Options

```elixir
config :square_client,
  # Required: Square API URL
  api_url: "https://connect.squareupsandbox.com/v2",  # or production URL

  # Required: Square access token
  access_token: System.get_env("SQUARE_ACCESS_TOKEN"),

  # Required: Square location ID
  location_id: System.get_env("SQUARE_LOCATION_ID"),

  # Required: Your webhook handler module
  webhook_handler: MyApp.SquareWebhookHandler,

  # Optional: Square webhook signature key (from Square dashboard)
  webhook_signature_key: System.get_env("SQUARE_WEBHOOK_SIGNATURE_KEY")
```

**Configuration Validation:**

The library validates all required configuration at app startup:

```elixir
# In your application.ex
def start(_type, _args) do
  # Validates api_url, access_token, location_id, and webhook_handler
  # Raises clear error with examples if anything is missing
  SquareClient.Config.validate_runtime!()

  children = [...]
  # ...
end
```

If configuration is invalid, you'll get a helpful error message:

```
SquareClient configuration is invalid:

  • API URL is not configured. Add :api_url to your config :square_client
  • Webhook handler is not configured. Add :webhook_handler to your config :square_client if you use webhooks

Required configuration:

  config :square_client,
    api_url: "https://connect.squareupsandbox.com/v2",  # or production URL
    access_token: System.get_env("SQUARE_ACCESS_TOKEN"),
    location_id: System.get_env("SQUARE_LOCATION_ID"),
    webhook_handler: MyApp.Payments.SquareWebhookHandler  # if using webhooks

Environment variables:
  SQUARE_ACCESS_TOKEN - Your Square API access token (required)
  SQUARE_LOCATION_ID - Your Square location ID (required)

Get these from: https://developer.squareup.com/apps
```

Or use environment variables:
- `SQUARE_ACCESS_TOKEN` - Your Square API access token (required)
- `SQUARE_LOCATION_ID` - Your Square location ID (required)
- `SQUARE_WEBHOOK_SIGNATURE_KEY` - Your webhook signature key

### Testing Webhooks

In your tests:

```elixir
defmodule MyAppWeb.WebhookControllerTest do
  use MyAppWeb.ConnCase

  test "processes valid webhook", %{conn: conn} do
    body = ~s({"type": "payment.created", "data": {...}})
    signature = generate_signature(body, "test_key")

    conn =
      conn
      |> put_req_header("x-square-hmacsha256-signature", signature)
      |> post("/webhooks/square", body)

    assert json_response(conn, 200) == %{"received" => true}
  end

  defp generate_signature(payload, key) do
    :crypto.mac(:hmac, :sha256, key, payload)
    |> Base.encode64()
  end
end
```

### Webhook Events Reference

Common Square webhook events your handler might receive:

**Payments:**
- `payment.created` - Payment completed
- `payment.updated` - Payment status changed

**Subscriptions:**
- `subscription.created` - New subscription started
- `subscription.updated` - Subscription modified
- `subscription.canceled` - Subscription ended

**Invoices:**
- `invoice.payment_made` - Subscription payment successful
- `invoice.payment_failed` - Payment failed (card declined, etc.)

**Customers:**
- `customer.created` - New customer created
- `customer.updated` - Customer information changed

**Refunds:**
- `refund.created` - Refund processed
- `refund.updated` - Refund status changed

### Security Best Practices

1. **Always verify signatures** - The plug handles this automatically
2. **Use HTTPS only** - Never accept webhooks over HTTP in production
3. **Validate event data** - Don't trust webhook data without validation
4. **Idempotency** - Handle duplicate webhooks gracefully (Square may retry)
5. **Timeout handling** - Respond quickly (< 10 seconds) to avoid retries

## Environment Detection

The library automatically detects and adapts to the environment:

- **Test** (`MIX_ENV=test`)
  - Disables HTTP retries for fast tests
  - Can use custom test URL for mocking

- **Development** (`MIX_ENV=dev`)
  - Uses sandbox API by default
  - Full retry behavior enabled

- **Production** (`MIX_ENV=prod`)
  - Ready for production API
  - Set `SQUARE_ENVIRONMENT=production` to use live API

## Troubleshooting

### Tests are slow
- Ensure `disable_retries: true` is set in test config
- Check that `SQUARE_ENVIRONMENT` isn't overriding test settings
- Verify Bypass is running (check for port conflicts)

### API calls failing
- Verify `SQUARE_ACCESS_TOKEN` is set correctly
- Check you're using the right environment (sandbox vs production)
- Ensure API version compatibility (check Square dashboard)
- Look for rate limiting (Square has API rate limits)

### Can't delete subscription plans
- Square doesn't allow deletion of subscription plans once created
- This is by design to maintain historical records
- Use new plan names for testing
- Plans can be archived but not deleted

### Configuration not working
- Check configuration precedence (app config > env vars > defaults)
- Use `Application.get_env(:square_client, :api_url)` to verify
- Ensure config files are loaded (`import_config`)

## Square Dashboard URLs

- **Sandbox Dashboard**: https://squareupsandbox.com/dashboard
- **Production Dashboard**: https://squareup.com/dashboard
- **Developer Dashboard**: https://developer.squareup.com/apps

## Test Cards

For testing in sandbox:
- Success: 4111 1111 1111 1111
- Declined: 4000 0000 0000 0002
- See `TEST_CARDS.md` for complete list

## Contributing

1. Write tests for new features
   - Use `capture_log` for clean test output
   - Mock API calls with Bypass

2. Follow Elixir best practices
   - Pattern matching over conditionals
   - Function heads for different cases
   - Meaningful function and variable names

3. Update documentation
   - Keep this README current
   - Document new configuration options
   - Add examples for new features

4. Ensure fast tests
   - All tests should complete in < 1 second
   - Disable retries in test environment
   - Mock all external API calls

## License

MIT