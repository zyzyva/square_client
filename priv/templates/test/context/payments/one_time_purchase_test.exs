defmodule APP_MODULE.Payments.OneTimePurchaseTest do
  use APP_MODULE.DataCase

  alias APP_MODULE.Payments
  alias APP_MODULE.Payments.Subscription
  alias APP_MODULE.ACCOUNTS_CONTEXT

  setup do
    # Create a test user
    {:ok, user} =
      ACCOUNTS_CONTEXT.register_user(%{
        email: "test@example.com",
        password: "password123456",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, user: user}
  end

  describe "has_premium?/1 with one-time purchases" do
    test "returns true for active one-time purchase", %{user: user} do
      # Create one-time purchase expiring in 10 days
      started_at = DateTime.utc_now() |> DateTime.truncate(:second)
      expires_at = DateTime.add(DateTime.utc_now(), 10, :day) |> DateTime.truncate(:second)

      {:ok, _subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          plan_id: "premium_week_pass",
          status: "ACTIVE",
          started_at: started_at,
          next_billing_at: expires_at,
          square_subscription_id: nil
        })
        |> APP_MODULE.Repo.insert()

      assert Payments.has_premium?(user)
    end

    test "returns false for expired one-time purchase", %{user: user} do
      # Create an expired one-time purchase subscription
      started_at = DateTime.add(DateTime.utc_now(), -8, :day) |> DateTime.truncate(:second)
      expires_at = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.truncate(:second)

      alias APP_MODULE.Payments.Subscription

      {:ok, _subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          plan_id: "premium_week_pass",
          status: "ACTIVE",
          started_at: started_at,
          next_billing_at: expires_at,
          square_subscription_id: nil
        })
        |> APP_MODULE.Repo.insert()

      refute Payments.has_premium?(user)
    end

    test "returns true for subscription without expiration", %{user: user} do
      # Regular subscription (no expiration date)
      {:ok, _subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          plan_id: "premium_monthly",
          status: "ACTIVE",
          square_subscription_id: "sub_123",
          next_billing_at: nil
        })
        |> APP_MODULE.Repo.insert()

      assert Payments.has_premium?(user)
    end

    test "returns false for past_due status regardless of expiration", %{user: user} do
      # Even with future expiration, past_due means no access
      expires_at = DateTime.add(DateTime.utc_now(), 10, :day) |> DateTime.truncate(:second)

      {:ok, _subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          plan_id: "premium_week_pass",
          status: "DELINQUENT",  # Square's past_due status
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          next_billing_at: expires_at,
          square_subscription_id: nil
        })
        |> APP_MODULE.Repo.insert()

      refute Payments.has_premium?(user)
    end

    test "handles edge case of expiration exactly now", %{user: user} do
      # Create a one-time purchase expiring exactly now
      started_at = DateTime.add(DateTime.utc_now(), -7, :day) |> DateTime.truncate(:second)
      expires_at = DateTime.utc_now() |> DateTime.truncate(:second)

      alias APP_MODULE.Payments.Subscription

      {:ok, _subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          plan_id: "premium_week_pass",
          status: "ACTIVE",
          started_at: started_at,
          next_billing_at: expires_at,
          square_subscription_id: nil
        })
        |> APP_MODULE.Repo.insert()

      # Should be considered expired (comparison is :gt, not :eq or :lt)
      refute Payments.has_premium?(user)
    end

    test "returns false for free tier regardless of expiration", %{user: user} do
      # User with no subscription is free tier
      refute Payments.has_premium?(user)
    end
  end
end
