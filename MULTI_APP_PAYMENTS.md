# Multi-App Payment Strategy

This guide explains how to use SquareClient across multiple applications in your ecosystem while maintaining clear separation and attribution.

## Architecture: Shared Account, Separate Plans

We use a single Square account across all apps, but each app maintains its own distinct subscription plans. This provides the best balance of simplicity and flexibility.

### Why This Approach?

✅ **Single Square Dashboard** - One place to view all revenue
✅ **Unified Bank Deposits** - Simpler accounting for one business
✅ **Independent Pricing** - Each app can change prices independently
✅ **Clear Attribution** - Know which app generated each payment
✅ **Separate Configuration** - Each app manages its own plans

## Implementation Guide

### 1. Plan Naming Convention

**For Square Dashboard:** Use app-specific names for clarity in the Square account
**For App Display:** Use clean names without app prefix (users know which app they're in)

```json
// In your square_plans.json
{
  "plans": {
    "premium": {
      "name": "Premium",  // Clean name for app UI
      "square_name": "Contacts4us Premium"  // Optional: for Square dashboard clarity
    }
  }
}
```

**Note:** When creating plans in Square, you should still use app-specific names (e.g., "Contacts4us Premium") in the Square catalog for dashboard clarity. But in your JSON configuration, use clean names for better UX within the app.

### 2. File Structure

Each app maintains its own `square_plans.json`:

```
contacts_ecosystem/
├── contacts4us/
│   └── priv/
│       └── square_plans.json      # Contacts4us-specific plans
├── analytics_app/
│   └── priv/
│       └── square_plans.json      # Analytics-specific plans
└── square_client/                  # Shared library
```

### 3. Setting Up Plans for Each App

Each app creates its own plans independently:

```bash
# For Contacts4us
cd contacts4us
mix square.init_plans --app contacts4us
# Edit priv/square_plans.json with Contacts4us-specific plans
mix square.setup_plans --app contacts4us

# For Analytics App
cd analytics_app
mix square.init_plans --app analytics_app
# Edit priv/square_plans.json with Analytics-specific plans
mix square.setup_plans --app analytics_app
```

### 4. Reference ID Strategy

Always include app identifier in reference IDs:

```elixir
# In Contacts4us
def create_subscription(user, plan) do
  SquareClient.Subscriptions.create(%{
    plan_variation_id: plan.variation_id,
    customer_id: user.square_customer_id,
    reference_id: "contacts4us:user:#{user.id}",
    note: "Contacts4us subscription for #{user.email}"
  })
end

# In Analytics App
def create_subscription(user, plan) do
  SquareClient.Subscriptions.create(%{
    plan_variation_id: plan.variation_id,
    customer_id: user.square_customer_id,
    reference_id: "analytics:user:#{user.id}",
    note: "Analytics subscription for #{user.email}"
  })
end
```

### 5. Customer Management

You have two options for customer records:

#### Option A: Shared Customers (Recommended)
One Square customer record used across all apps:

```elixir
# Create customer once (in whichever app they use first)
{:ok, customer} = SquareClient.Customers.create(%{
  email: "user@example.com",
  given_name: "John",
  family_name: "Doe",
  reference_id: "ecosystem:user:#{user_id}",  # Ecosystem-wide ID
  note: "Customer across multiple apps"
})

# Each app stores the same square_customer_id
```

**Benefits:**
- Single customer record in Square
- Customer can use saved cards across apps
- Unified customer view in Square Dashboard

#### Option B: Separate Customers Per App
Create separate Square customers for each app:

```elixir
# In Contacts4us
{:ok, customer} = SquareClient.Customers.create(%{
  email: "user@example.com",
  reference_id: "contacts4us:user:#{user_id}",
  note: "Contacts4us customer"
})

# In Analytics (different Square customer for same user)
{:ok, customer} = SquareClient.Customers.create(%{
  email: "user@example.com",
  reference_id: "analytics:user:#{user_id}",
  note: "Analytics customer"
})
```

**Benefits:**
- Complete isolation between apps
- Apps can't affect each other's customer data

### 6. Webhook Processing

Each app should filter webhooks to only process its own events:

```elixir
defmodule MyApp.SquareWebhookHandler do
  @behaviour SquareClient.WebhookHandler

  @impl true
  def handle_event(%{event_type: "subscription.created", data: data}) do
    # Check if this subscription belongs to our app
    case parse_reference_id(data.subscription.reference_id) do
      {:ok, "contacts4us", user_id} ->
        # This is our subscription
        process_subscription(user_id, data)
      _ ->
        # Not our subscription, ignore
        :ok
    end
  end

  defp parse_reference_id(ref_id) when is_binary(ref_id) do
    case String.split(ref_id, ":", parts: 3) do
      [app, "user", id] -> {:ok, app, id}
      _ -> :error
    end
  end
end
```

### 7. Payment Attribution

For one-time payments, always include app attribution:

```elixir
# In Contacts4us
SquareClient.Payments.create(
  source_id,
  amount,
  currency,
  reference_id: "contacts4us:payment:#{order_id}",
  note: "Contacts4us one-time purchase",
  app_fee_money: %{
    amount: 0,
    currency: "USD"
  }
)
```

## Example: Complete Multi-App Setup

### Contacts4us Plans (contacts4us/priv/square_plans.json)

```json
{
  "plans": {
    "free": {
      "name": "Free",  // Clean for app UI
      "type": "free",
      "features": ["5 card scans per month"]
    },
    "premium": {
      "name": "Premium",  // Clean for app UI
      "description": "Premium contact management",
      "sandbox_base_plan_id": "CONTACTS_BASE_SANDBOX",
      "production_base_plan_id": "CONTACTS_BASE_PROD",
      "variations": {
        "monthly": {
          "name": "Monthly",  // Clean for app UI
          "amount": 999,
          "cadence": "MONTHLY",
          "sandbox_variation_id": "CONTACTS_MONTHLY_SANDBOX",
          "production_variation_id": "CONTACTS_MONTHLY_PROD"
        }
      }
    }
  },
  "one_time_purchases": {
    "week_pass": {
      "name": "7-Day Pass",  // Clean for app UI
      "price_cents": 499
    }
  }
}
```

### Analytics App Plans (analytics_app/priv/square_plans.json)

```json
{
  "plans": {
    "basic": {
      "name": "Analytics Basic",
      "type": "free",
      "features": ["Basic reports"]
    },
    "professional": {
      "name": "Analytics Professional",
      "description": "Advanced analytics and reporting",
      "sandbox_base_plan_id": "ANALYTICS_BASE_SANDBOX",
      "production_base_plan_id": "ANALYTICS_BASE_PROD",
      "variations": {
        "monthly": {
          "name": "Analytics Monthly",
          "amount": 1999,
          "cadence": "MONTHLY",
          "sandbox_variation_id": "ANALYTICS_MONTHLY_SANDBOX",
          "production_variation_id": "ANALYTICS_MONTHLY_PROD"
        }
      }
    }
  }
}
```

## Reporting and Analytics

### Square Dashboard View

With proper naming, your Square Dashboard will show:
- "Contacts4us Premium" - $9.99/month
- "Analytics Professional" - $19.99/month
- Clear distinction between apps

### Custom Reporting

Build reports by filtering on reference_id patterns:

```elixir
def revenue_by_app(start_date, end_date) do
  payments = SquareClient.Payments.list(
    begin_time: start_date,
    end_time: end_date
  )

  payments
  |> Enum.group_by(&parse_app_from_reference_id/1)
  |> Enum.map(fn {app, payments} ->
    {app, calculate_total(payments)}
  end)
end
```

## Best Practices

### ✅ DO:
- Use app-specific plan names
- Include app identifier in all reference_ids
- Test each app's payment flow independently
- Document which Square IDs belong to which app
- Use consistent naming patterns

### ❌ DON'T:
- Share plan IDs between apps
- Use generic plan names
- Mix reference_id formats
- Forget to filter webhooks by app
- Process another app's webhooks

## Testing Strategy

### Development Workflow
1. Each developer works with sandbox plans
2. Apps can share the same sandbox Square account
3. Use app prefixes to avoid confusion

### Test Isolation
```elixir
# In tests, use app-specific prefixes
test "subscription creation" do
  reference_id = "test_contacts4us:user:#{UUID.generate()}"
  # Test continues...
end
```

## Migration Path

If you're migrating from separate payment systems:

1. **Audit Existing Plans** - List all current subscription plans
2. **Create New Plans** - Use app-specific names
3. **Migrate Active Subscriptions** - Update reference_ids
4. **Update Webhook Handlers** - Add app filtering
5. **Test Thoroughly** - Verify attribution works

## Troubleshooting

### Common Issues

**Issue: Payments showing up in wrong app**
- Check reference_id format
- Verify webhook filtering logic
- Ensure plan IDs are unique per app

**Issue: Can't tell which app generated revenue**
- Add app prefix to plan names
- Use reference_ids consistently
- Generate app-specific reports

**Issue: Price change affected multiple apps**
- Ensure each app has its own plan IDs
- Never share variation IDs
- Check square_plans.json for duplicates

## FAQ

**Q: Can a user have subscriptions to multiple apps?**
A: Yes! They'll have separate subscriptions with different plan IDs, all under the same Square customer (if using shared customers).

**Q: What if two apps need the exact same price point?**
A: Still create separate plans. This allows independent changes later and maintains clear attribution.

**Q: How do we handle refunds?**
A: Include app identifier in refund reference_id to track which app processed it.

**Q: Can apps have different currencies?**
A: Yes, but Square requires one currency per location. Use different locations for different currencies.

## Summary

The key to successful multi-app payments is **clear separation through naming and reference IDs** while using a shared Square infrastructure. Each app:

1. Maintains its own square_plans.json
2. Uses app-specific plan names
3. Includes app identifier in all reference_ids
4. Filters webhooks to its own events
5. Can modify plans independently

This approach scales to any number of apps while maintaining clarity and flexibility.