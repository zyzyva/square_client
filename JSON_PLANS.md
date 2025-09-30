# JSON-Driven Payment Plans

The SquareClient library provides a complete JSON-driven payment plan system that makes it easy to manage subscription plans and one-time purchases without code changes.

> 📚 **For multi-app deployments**, see [MULTI_APP_PAYMENTS.md](MULTI_APP_PAYMENTS.md) for important guidance on plan separation and payment attribution.

## Quick Start

1. **Initialize your plans configuration:**
```bash
mix square.init_plans --app my_app
```

2. **Edit `priv/square_plans.json`** to define your plans

3. **Use the plans in your LiveView:**
```elixir
alias SquareClient.Plans.Formatter

# Get formatted plans for display
plans = Formatter.get_subscription_plans(:my_app)
one_time = Formatter.get_one_time_purchases(:my_app)
```

## JSON Structure

The JSON configuration uses a unified structure that works across all environments.

**Note:** Use clean names in your JSON for better UX. The app name prefix can be added when creating plans in Square's catalog:

```json
{
  "plans": {
    "free": {
      "name": "Free",
      "description": "Basic features",
      "type": "free",
      "active": true,
      "price": "$0",
      "price_cents": 0,
      "features": [
        "5 items per month",
        "Basic support"
      ]
    },
    "premium": {
      "name": "Premium",
      "description": "Professional features",
      "type": "subscription",
      "sandbox_base_plan_id": "SANDBOX_ID_HERE",
      "production_base_plan_id": "PROD_ID_HERE",
      "variations": {
        "monthly": {
          "name": "Monthly",
          "amount": 999,
          "currency": "USD",
          "cadence": "MONTHLY",
          "sandbox_variation_id": "SANDBOX_VAR_ID",
          "production_variation_id": "PROD_VAR_ID",
          "active": true,
          "price": "$9.99/mo",
          "price_cents": 999,
          "auto_renews": true,
          "billing_notice": "Billed monthly, auto-renews",
          "features": [
            "Unlimited items",
            "Priority support",
            "API access"
          ]
        },
        "yearly": {
          "name": "Annual",
          "amount": 9900,
          "currency": "USD",
          "cadence": "ANNUAL",
          "sandbox_variation_id": "SANDBOX_YEAR_ID",
          "production_variation_id": "PROD_YEAR_ID",
          "active": true,
          "price": "$99/year",
          "price_cents": 9900,
          "auto_renews": true,
          "billing_notice": "Billed annually, save $20",
          "features": [
            "Everything in monthly",
            "Save $20 per year"
          ]
        }
      }
    }
  },
  "one_time_purchases": {
    "week_pass": {
      "active": true,
      "name": "7-Day Pass",
      "description": "Try premium for a week",
      "price": "$4.99",
      "price_cents": 499,
      "duration_days": 7,
      "auto_renews": false,
      "billing_notice": "One-time payment, NO auto-renewal",
      "features": [
        "7 days unlimited access",
        "All premium features",
        "No recurring charges"
      ]
    }
  }
}
```

## Core Modules

### SquareClient.Plans
Manages the raw JSON configuration and Square API integration:

```elixir
# Get all plans (transformed for current environment)
plans = SquareClient.Plans.get_plans(:my_app)

# Get specific plan
plan = SquareClient.Plans.get_plan(:my_app, "premium")

# Get one-time purchases
purchases = SquareClient.Plans.get_one_time_purchases(:my_app)

# Update IDs after creating in Square
SquareClient.Plans.update_base_plan_id(:my_app, "premium", "SQUARE_ID")
SquareClient.Plans.update_variation_id(:my_app, "premium", "monthly", "SQUARE_VAR_ID")
```

### SquareClient.Plans.Formatter
Formats plan data for UI display:

```elixir
# Get all subscription plans formatted for display
plans = Formatter.get_subscription_plans(:my_app, opts)

# Options include:
# - include_inactive: false (default) - Filter out inactive plans
# - plan_types: MyApp.PlanTypes - Module with plan type definitions

# Get specific plan by ID
plan = Formatter.get_plan_by_id(:my_app, :premium_monthly)

# Mark recommended plans based on current plan
plans = Formatter.mark_recommended_plans(plans, :free)
```

## LiveView Integration

```elixir
defmodule MyAppWeb.SubscriptionLive.Index do
  use MyAppWeb, :live_view

  alias SquareClient.Plans.Formatter
  alias MyApp.PlanTypes

  def mount(_params, _session, socket) do
    plans = Formatter.get_subscription_plans(:my_app,
      plan_types: PlanTypes,
      include_inactive: false
    )

    one_time = Formatter.get_one_time_purchases(:my_app)

    {:ok, assign(socket, plans: plans, one_time_purchases: one_time)}
  end

  def handle_event("select_plan", %{"plan_id" => plan_id}, socket) do
    plan = Formatter.get_plan_by_id(:my_app, plan_id)
    # Process payment...
  end
end
```

## PlanTypes Module

Each app should define a PlanTypes module with plan atoms:

```elixir
defmodule MyApp.PlanTypes do
  @plans [
    :free,
    :premium_weekly,
    :premium_monthly,
    :premium_yearly
  ]

  def all, do: @plans

  def free, do: :free
  def premium_weekly, do: :premium_weekly
  def premium_monthly, do: :premium_monthly
  def premium_yearly, do: :premium_yearly

  def from_string("free"), do: {:ok, :free}
  def from_string("premium_weekly"), do: {:ok, :premium_weekly}
  # ... etc

  def is_premium?(plan) when plan in [:premium_weekly, :premium_monthly, :premium_yearly], do: true
  def is_premium?(_), do: false

  def is_recommended?(:premium_monthly, :free), do: true
  def is_recommended?(:premium_yearly, :premium_monthly), do: true
  def is_recommended?(_, _), do: false
end
```

## Mix Tasks

### Initialize Configuration
```bash
mix square.init_plans --app my_app
```
Creates `priv/square_plans.json` with example structure.

### List Current Plans
```bash
mix square.list_plans --app my_app
```
Shows all plans and their configuration status.

### Setup Plans in Square

#### Development/Sandbox Setup
```bash
mix square.setup_plans --app my_app
```
Creates plans in Square SANDBOX and updates JSON with sandbox IDs.

#### Production Setup (from development environment)
```bash
# First ensure sandbox plans are created and tested
mix square.setup_plans --app my_app

# Then set production token and create production plans
export SQUARE_PRODUCTION_ACCESS_TOKEN="your_production_token"
mix square.setup_production --app my_app
```

The production task will:
1. Temporarily switch to production Square API
2. Create plans in your production account
3. Update square_plans.json with production IDs
4. Switch back to sandbox configuration

**Important:** You set up production plans from your development environment BEFORE deploying, since Mix tasks aren't available in Elixir releases.

## Environment Handling

The library automatically selects the correct IDs based on environment:

- **Development/Test**: Uses `sandbox_base_plan_id` and `sandbox_variation_id`
- **Production**: Uses `production_base_plan_id` and `production_variation_id`

### Configuration

Set the Square environment in your Phoenix app's config files:

```elixir
# config/dev.exs
config :my_app, :square_environment, :sandbox

# config/test.exs
config :my_app, :square_environment, :sandbox

# config/prod.exs
config :my_app, :square_environment, :production
```

The library checks configuration in this order:
1. Application-specific config (`:my_app, :square_environment`)
2. Library config (`:square_client, :environment`)
3. Environment variable (`SQUARE_ENVIRONMENT`)
4. Defaults to sandbox for safety

**Note:** The library does NOT use Mix.env() as it's not available in Elixir releases.

## Benefits

1. **No Code Deployment for Price Changes**
   - Update JSON file
   - Restart app (or implement hot reload)
   - Changes take effect immediately

2. **Business-Friendly**
   - Non-developers can understand and modify plans
   - Clear structure for pricing and features
   - Version control tracks all pricing history

3. **Multi-App Consistency**
   - Share the same payment infrastructure
   - Each app has its own `square_plans.json`
   - Library handles all the complexity

4. **Testing Friendly**
   - Same structure in all environments
   - Only IDs differ between sandbox/production
   - Easy to test different pricing scenarios

## Best Practices

1. **Always test in sandbox first**
   - Create plans with `mix square.setup_plans`
   - Verify IDs are saved to JSON
   - Test full payment flow

2. **Use app-specific naming**
   - Prefix all plans with app name (e.g., "Contacts4us Premium")
   - Never share plan IDs between apps
   - See [MULTI_APP_PAYMENTS.md](MULTI_APP_PAYMENTS.md) for details

3. **Keep features up-to-date**
   - Features array should reflect actual functionality
   - Update when adding new features
   - Remove features no longer available

4. **Use semantic pricing**
   - Weekly < Monthly < Yearly (per period)
   - Offer discounts for longer commitments
   - Keep one-time purchases as alternatives

5. **Version control your JSON**
   - Track all pricing changes
   - Easy rollback if needed
   - Document changes in commits

## Troubleshooting

### Plans not showing up
- Check `active: true` in JSON
- Verify JSON is valid (use `mix square.list_plans`)
- Ensure correct environment (sandbox vs production)

### IDs not being saved
- Check file permissions on `priv/square_plans.json`
- Verify Square API credentials
- Look for errors in `mix square.setup_plans` output

### Wrong prices showing
- Remember amounts are in cents (999 = $9.99)
- Check both `amount` and `price_cents` fields
- Verify `currency` matches your Square account

## Migration from Hardcoded Plans

If you have existing hardcoded plans:

1. Create JSON structure matching your current plans
2. Run `mix square.init_plans` and customize
3. Update LiveViews to use `SquareClient.Plans.Formatter`
4. Remove old hardcoded plan modules
5. Test thoroughly before deploying

## Future Enhancements

The JSON-driven system is designed to support:

- Multiple currencies
- Promotional codes and discounts
- Time-limited offers
- A/B testing different price points
- Admin UI for plan management
- Hot-reloading without restart