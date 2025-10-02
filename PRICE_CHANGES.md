# Handling Price Changes in Square Subscriptions

## Important: Square Subscription Plans are Immutable

Once a subscription plan variation is created in Square with a specific price, **you cannot change that price**. This is by design to maintain integrity for existing subscribers and ensure billing consistency.

## Why Prices Cannot Be Changed

Square catalog items (subscription plans) are immutable for several important reasons:

1. **Existing Subscriber Protection** - Customers who subscribed at a certain price must continue at that price
2. **Billing Integrity** - Prevents accidental price changes that affect active subscriptions
3. **Financial Auditing** - Maintains a clear history of pricing for accounting purposes
4. **Legal Compliance** - Ensures businesses honor the price customers agreed to

## What to Do When You Need to Change Prices

You have two main approaches:

### Option 1: Create a New Variation (Recommended for Most Cases)

This is the cleanest approach and maintains a clear history:

```json
{
  "plans": {
    "premium": {
      "variations": {
        "monthly": {
          "id": "premium_monthly",
          "name": "Monthly (Legacy)",
          "amount": 999,
          "active": false,
          "sandbox_variation_id": "76DJP5OM7DDWJTRERTHQMCM7"
          // ... other fields
        },
        "monthly_v2": {
          "id": "premium_monthly_v2",
          "name": "Monthly",
          "amount": 1299,
          "active": true,
          "sandbox_variation_id": null,  // Will be filled by setup_plans
          "production_variation_id": null,
          "cadence": "MONTHLY",
          "currency": "USD",
          "price": "$12.99/mo",
          "price_cents": 1299,
          "auto_renews": true,
          "billing_notice": "Billed monthly, auto-renews until cancelled",
          "features": [
            "All premium features",
            "Priority support",
            "Advanced functionality"
          ]
        }
      }
    }
  }
}
```

**Steps:**
1. Set `"active": false` on the old variation (prevents new signups)
2. Add a new variation with the new price (e.g., `monthly_v2`)
3. Run `mix square.setup_plans` to create the new variation in Square
4. The library will automatically use active variations for new signups
5. Existing subscribers remain on their current variation at the old price

### Option 2: Full Replacement (For Major Changes)

If you're doing a complete pricing restructure:

```json
{
  "plans": {
    "premium_legacy": {
      "name": "Premium (Legacy)",
      "active": false,
      "variations": {
        "monthly": {
          "active": false,
          // ... keep IDs for existing subscribers
        }
      }
    },
    "premium_new": {
      "name": "Premium",
      "active": true,
      "sandbox_base_plan_id": null,  // Will create new base plan
      "variations": {
        "monthly": {
          "id": "premium_new_monthly",
          "amount": 1499,
          "active": true,
          // ... new pricing structure
        }
      }
    }
  }
}
```

**Steps:**
1. Deactivate the old plan
2. Create a completely new plan with new variations
3. Run `mix square.setup_plans`
4. Update your application to reference the new plan

## What Happens to Existing Subscribers?

**Existing subscribers are NOT affected by price changes:**

- They continue on their current plan variation at the original price
- Their subscription ID remains the same
- Billing continues as before
- They keep this price until they cancel and re-subscribe

If you want to migrate existing subscribers to a new price:
1. You must handle this at the application level
2. Cancel their old subscription
3. Create a new subscription with the new variation
4. Consider offering them a choice or grandfather them into the old price

## Detecting Accidental Price Changes

The library includes validation to warn you if critical fields change. See `SquareClient.Plans.validate_immutable_fields/2`.

⚠️ **Warning**: If you accidentally change the `amount` field on an existing variation with a Square ID, the library will log an error on startup but will NOT prevent the app from starting. This is intentional to avoid breaking production deployments.

## Best Practices

### 1. Version Your Variations
Use versioning in your variation IDs:
```json
"monthly_v1", "monthly_v2", "monthly_v3"
```

This makes it clear which is the current version and maintains history.

### 2. Keep Historical Variations
Never delete old variations from your JSON if they have Square IDs - existing subscribers may still be using them:

```json
"monthly_legacy_2023": {
  "active": false,
  "sandbox_variation_id": "ABC123",
  "amount": 999  // Keep for reference
}
```

### 3. Use Descriptive Names
When deactivating old variations, update the name to indicate it's legacy:

```json
"name": "Monthly (Legacy - $9.99)"
```

### 4. Document Price Changes
Add a comment in your JSON when making price changes:

```json
// Price increased from $9.99 to $12.99 on 2025-10-15
// Old variation: premium_monthly (ABC123)
// New variation: premium_monthly_v2 (XYZ789)
```

### 5. Test in Sandbox First
Always test price changes in sandbox before production:
```bash
# Sandbox
mix square.setup_plans

# Then production
mix square.setup_production
```

## Handling Promotional Pricing

For temporary price changes or promotions:

### Option A: Create Temporary Variations
```json
"monthly_holiday_2024": {
  "id": "premium_monthly_holiday_2024",
  "amount": 799,
  "active": true,
  "features": [
    "Holiday special - $7.99 first month",
    "Then $9.99/month",
    "All premium features"
  ]
}
```

After the promotion, deactivate it and ensure the regular variation is active.

### Option B: Use Square's Trial Periods
Configure trial periods in your application logic rather than creating new variations.

## Migration Strategy for Price Increases

When increasing prices for a user base:

### Grandfathering (Recommended)
1. Create new variation with increased price
2. Let existing users stay on old price
3. New users get new price
4. Communicate clearly in UI which price tier each user is on

### Forced Migration
1. Create new variation
2. Send notification emails to existing subscribers
3. Give 30+ days notice
4. Programmatically cancel old subscriptions
5. Create new subscriptions at new price
6. Handle payment failures gracefully

### Phased Rollout
1. Create new variation
2. Gradually move users over time
3. Offer incentives for early migration
4. Provide opt-in rather than forcing

## Common Mistakes to Avoid

❌ **Don't**: Change the `amount` field on an existing variation
✅ **Do**: Create a new variation with the new amount

❌ **Don't**: Delete old variations that have Square IDs
✅ **Do**: Set them to `"active": false`

❌ **Don't**: Reuse variation IDs for different prices
✅ **Do**: Create unique IDs for each price point

❌ **Don't**: Make price changes without testing in sandbox
✅ **Do**: Always test with `mix square.setup_plans` first

❌ **Don't**: Assume the JSON price change will update Square
✅ **Do**: Understand you must create new variations

## Checking for Immutable Field Changes

The library provides a utility to check if critical fields have changed:

```elixir
# In your deployment script or CI/CD
case SquareClient.Plans.validate_immutable_fields(:my_app) do
  {:ok, []} ->
    IO.puts("No immutable field changes detected")

  {:warning, changes} ->
    IO.warn("⚠️  Immutable fields changed:")
    Enum.each(changes, fn change ->
      IO.warn("  #{change.plan}/#{change.variation}: #{change.field} changed from #{change.old} to #{change.new}")
    end)
    IO.warn("You may need to create new variations instead of modifying existing ones.")

  {:error, reason} ->
    IO.puts("Error checking: #{reason}")
end
```

## Summary

- **Prices are immutable** once a plan is created in Square
- **Create new variations** for price changes
- **Deactivate old variations** instead of deleting them
- **Existing subscribers** keep their current price
- **Version your plan IDs** (e.g., `monthly_v2`)
- **Test in sandbox first** with `mix square.setup_plans`
- **Document changes** in your JSON with comments

For questions or issues, see:
- [Square Subscriptions API Documentation](https://developer.squareup.com/docs/subscriptions-api/overview)
- [JSON_PLANS.md](./JSON_PLANS.md) for JSON structure
- [MULTI_APP_PAYMENTS.md](./MULTI_APP_PAYMENTS.md) for multi-app scenarios
