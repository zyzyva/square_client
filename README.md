# SquareClient

A flexible Elixir client library for Square API integration, focused on subscription management and payment processing.

## Features

- **Direct Square API integration** - No proxy service or message queue required
- **Subscription plan and variation management** - Following Square's recommended patterns
- **Synchronous REST API** - Immediate feedback for payment processing
- **Environment-aware configuration** - Automatic sandbox/production switching
- **Comprehensive test coverage** - Fast (0.1s), clean tests with mocked API calls
- **Multiple configuration methods** - Application config, environment variables, or defaults

## Installation

Add `square_client` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:square_client, github: "zyzyva/square_client"}
  ]
end
```

## Configuration

SquareClient supports flexible configuration with clear precedence:

### API Key Management

**Single Set of Keys (Recommended)**
Most organizations should use one Square account across all apps:
- Single business entity with multiple applications
- All payments go to one bank account
- Simpler Square dashboard management
- Easier reconciliation and reporting

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

### Method 2: Environment Variables

Set these environment variables:

- `SQUARE_ACCESS_TOKEN` - Your Square API access token (required)
- `SQUARE_ENVIRONMENT` - Controls API endpoint selection:
  - `"production"` - Uses Square production API
  - `"sandbox"` (default) - Uses Square sandbox API
  - `"test"` - Uses test URL (for mocking)
- `SQUARE_API_TEST_URL` - Custom URL for test environment
- `SQUARE_APPLICATION_ID` - Your Square application ID
- `SQUARE_LOCATION_ID` - Your Square location ID

Example:
```bash
export SQUARE_ACCESS_TOKEN="YOUR_SANDBOX_TOKEN"
export SQUARE_ENVIRONMENT="sandbox"
export SQUARE_APPLICATION_ID="YOUR_APP_ID"
export SQUARE_LOCATION_ID="YOUR_LOCATION_ID"
```

## Usage

### Managing Subscription Plans

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

```elixir
# Process a payment via the payment service
{:ok, payment} = SquareClient.Payments.create(
  source_id,
  amount,
  currency,
  customer_id: customer_id,
  reference_id: "order-123"
)
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