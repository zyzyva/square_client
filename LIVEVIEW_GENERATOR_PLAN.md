# LiveView Generator Plan

## Problem Statement

The current square_client installer generates backend components (schema, webhook handler, migration, config) but requires apps to manually create their subscription UI. The payments branch has a complete LiveView implementation, but it uses hardcoded PlanTypes that duplicate information already in the JSON plan configuration.

## Current Issues

1. **PlanTypes module is redundant** - It hardcodes plan atoms (`:premium_monthly`, `:premium_yearly`) that are already defined in the JSON configuration
2. **No LiveView generation** - Apps must manually create subscription UI
3. **Tight coupling** - LiveView code assumes specific plan names and structure
4. **Mixed data sources** - Plan data comes from JSON but plan constants come from PlanTypes module

## Proposed Solution: JSON-Driven Everything

### Core Principle
All plan information should come from the JSON configuration. No hardcoded plan types or constants except what's absolutely necessary for the library.

### Architecture Changes

#### 1. Remove PlanTypes Module
**Current approach:**
```elixir
# Hardcoded in PlanTypes
@premium_monthly :premium_monthly
def premium_monthly, do: @premium_monthly
```

**New approach:**
```elixir
# Plans come from JSON via SquareClient.Plans.Formatter
plans = PlanFormatter.get_subscription_plans(:my_app, "square_plans.json")
# Each plan has: %{id: :premium_monthly, name: "Premium Monthly", ...}
# Use plan.id directly in pattern matching
```

#### 2. Enhance SquareClient.Plans.Formatter

Add helper functions to the library for common plan operations:

```elixir
defmodule SquareClient.Plans.Helpers do
  @doc """
  Get free plan from JSON configuration.
  Every app needs a free plan, so provide a standard way to access it.
  """
  def get_free_plan(plans) do
    Enum.find(plans, &(&1.type == :free))
  end

  @doc """
  Get plan by ID atom.
  """
  def get_plan_by_id(plans, plan_id) do
    Enum.find(plans, &(&1.id == plan_id))
  end

  @doc """
  Determine recommended plan based on current plan.
  Logic: Free -> Monthly, Weekly -> Monthly, Monthly -> Yearly, Yearly -> nil
  """
  def get_recommended_plan(plans, current_plan_id) do
    case current_plan_id do
      :free -> get_plan_by_id(plans, :premium_monthly)
      :premium_weekly -> get_plan_by_id(plans, :premium_monthly)
      :premium_monthly -> get_plan_by_id(plans, :premium_yearly)
      :premium_yearly -> nil
      _ -> get_plan_by_id(plans, :premium_monthly)
    end
  end

  @doc """
  Check if plan is active subscription (not free, not one-time).
  """
  def active_subscription?(plan_id) when plan_id in [:premium_monthly, :premium_yearly, :premium_weekly], do: true
  def active_subscription?(_), do: false
end
```

#### 3. Generated LiveView Structure

The installer should generate:

**Files to generate:**
1. `lib/app_web/live/subscription_live/index.ex` - Main subscription page
2. `lib/app_web/live/subscription_live/manage.ex` - Manage subscription page
3. `lib/app/payments.ex` - Payments context module
4. `assets/js/hooks/square_payment.js` - Square payment form JavaScript
5. `priv/square_plans.json` - Example plan configuration

**Template approach:**
- Replace `Contacts4us` with `#{module_prefix}`
- Replace `:contacts4us` atoms with app name from `Mix.Project.config()[:app]`
- Remove all references to PlanTypes
- Use JSON plan data directly via `SquareClient.Plans.Formatter`
- Make business-specific text generic ("Unlock premium features" instead of "for business card scanning")

#### 4. LiveView Pattern Matching Without PlanTypes

**Current pattern (with PlanTypes):**
```elixir
@free_plan PlanTypes.free()
@premium_monthly PlanTypes.premium_monthly()

defp handle_plan_selection(socket, %{id: @free_plan} = _plan) do
  # Handle free plan
end

defp get_button_text(%{id: @premium_yearly}, @premium_monthly) do
  "Upgrade to Yearly"
end
```

**New pattern (JSON-driven):**
```elixir
# Load free plan once in mount
free_plan = SquareClient.Plans.Helpers.get_free_plan(all_plans)

defp handle_plan_selection(socket, plan) do
  if plan.type == :free do
    # Handle free plan
  else
    # Handle paid plan
  end
end

defp get_button_text(plan, current_plan_id) do
  cond do
    plan.id == :free && current_plan_id == :free -> "Stay on Free"
    plan.id == :free -> "Downgrade to Free"
    plan.id == :premium_yearly && current_plan_id == :premium_monthly -> "Upgrade to Yearly"
    plan.id == :premium_monthly && current_plan_id == :premium_yearly -> "Downgrade"
    current_plan_id == :free && plan.price_cents > 0 -> "Upgrade Now"
    true -> "Select Plan"
  end
end
```

### Implementation Steps

1. **Add helper functions to SquareClient.Plans.Helpers**
   - `get_free_plan/1`
   - `get_plan_by_id/2`
   - `get_recommended_plan/2`
   - `active_subscription?/1`
   - `parse_plan_id/1` - Convert string plan IDs to atoms safely

2. **Update Mix.Tasks.SquareClient.Install to generate:**
   - Subscription LiveView index page (templated)
   - Subscription LiveView manage page (templated)
   - Payments context module (templated)
   - Square payment JavaScript hook (templated)
   - Example square_plans.json file
   - Update router.ex with LiveView routes

3. **Template all generated files:**
   - Module names: `Contacts4us` → `#{module_prefix}`
   - App atoms: `:contacts4us` → `app_name`
   - Owner module: `Contacts4us.Accounts.User` → `#{owner_module}`
   - Repo: `Contacts4us.Repo` → `#{repo_module}`
   - Remove business-specific text
   - Remove PlanTypes references
   - Use SquareClient.Plans helpers instead

4. **Router updates:**
   ```elixir
   # Add to installer
   live_session :require_authenticated_user, on_mount: [...] do
     live "/subscription", SubscriptionLive.Index, :index
     live "/subscription/manage", SubscriptionLive.Manage, :manage
   end
   ```

### Benefits

1. **Single source of truth** - All plan data comes from JSON
2. **No duplication** - Plan IDs defined once in JSON, used everywhere
3. **Flexible** - Apps can add/remove plans by editing JSON
4. **Reusable** - Generated LiveViews work for any app with minimal customization
5. **Type safe** - Plan IDs are still atoms, just derived from JSON
6. **Maintainable** - No need to update PlanTypes when adding new plans

### Migration Path for Existing Apps

For contacts4us on the payments branch:
1. Remove `lib/contacts4us/payments/plan_types.ex`
2. Replace all `PlanTypes.foo()` calls with JSON-based helpers
3. Update pattern matching to use `plan.id` and conditionals
4. Verify all tests pass

### Example JSON Structure

```json
{
  "plans": {
    "free": {
      "name": "Free",
      "type": "free",
      "id": "free",
      "price": "$0",
      "price_cents": 0,
      "features": ["Basic features"]
    },
    "premium": {
      "name": "Premium",
      "type": "subscription",
      "variations": {
        "monthly": {
          "id": "premium_monthly",
          "name": "Monthly",
          "amount": 999,
          "price": "$9.99/mo",
          "price_cents": 999,
          "features": ["All features"]
        },
        "yearly": {
          "id": "premium_yearly",
          "name": "Yearly",
          "amount": 9900,
          "price": "$99/yr",
          "price_cents": 9900,
          "features": ["All features", "Save 20%"]
        }
      }
    }
  },
  "one_time_purchases": {
    "week_pass": {
      "id": "week_pass",
      "name": "7-Day Pass",
      "type": "one_time",
      "price": "$4.99",
      "price_cents": 499,
      "duration_days": 7,
      "features": ["7 days full access"]
    }
  }
}
```

### Future Enhancements

1. **Plan validation** - Validate JSON structure on app startup
2. **Plan migrations** - Handle plan changes in production
3. **Multi-tier support** - Support apps with more complex plan hierarchies
4. **Customization hooks** - Allow apps to override plan logic
5. **Admin UI** - Generate admin pages for viewing subscription analytics

## Decision

Use pure JSON-driven plans, remove PlanTypes module, and generate complete LiveView UI via the installer. This provides maximum reusability while maintaining type safety and flexibility.
