defmodule SquareClient.Subscriptions.Refunds do
  @moduledoc """
  Prorated refund calculations and processing for subscription upgrades.

  This module provides utilities for calculating and processing prorated refunds
  when users upgrade from one subscription to another.

  ## Configuration

  You can configure plan pricing for refund calculations:

      config :square_client, :refund_config,
        plans: %{
          "premium_week_pass" => %{price_cents: 499, duration_days: 7},
          "premium_monthly" => %{price_cents: 999, duration_days: 30},
          "premium_yearly" => %{price_cents: 9999, duration_days: 365}
        }

  ## Usage

      # Calculate remaining days
      days = SquareClient.Subscriptions.Refunds.calculate_remaining_days(subscription)

      # Calculate refund amount
      amount = SquareClient.Subscriptions.Refunds.calculate_prorated_refund(subscription, days, plan_config)

      # Process automatic refund
      SquareClient.Subscriptions.Refunds.process_automatic_refund(subscription, amount)
  """

  require Logger

  @doc """
  Calculate the number of days remaining on an active subscription.

  Returns 0 if:
  - Subscription is nil
  - Subscription is not ACTIVE
  - No next_billing_at date
  - Already past the billing date

  ## Examples

      iex> subscription = %{status: "ACTIVE", next_billing_at: ~U[2024-12-31 23:59:59Z]}
      iex> # Assuming today is 2024-12-25
      iex> SquareClient.Subscriptions.Refunds.calculate_remaining_days(subscription)
      6
  """
  def calculate_remaining_days(nil), do: 0

  def calculate_remaining_days(%{status: "ACTIVE", next_billing_at: next_billing})
      when not is_nil(next_billing) do
    now = DateTime.utc_now()

    case DateTime.diff(next_billing, now, :day) do
      days when days > 0 -> days
      _ -> 0
    end
  end

  def calculate_remaining_days(_subscription), do: 0

  @doc """
  Calculate prorated refund amount in cents based on remaining days.

  Requires a plan configuration map with pricing information.

  ## Plan Configuration Format

      %{
        "plan_id" => %{price_cents: 999, duration_days: 30}
      }

  ## Examples

      plan_config = %{"premium_monthly" => %{price_cents: 999, duration_days: 30}}
      subscription = %{plan_id: "premium_monthly"}
      SquareClient.Subscriptions.Refunds.calculate_prorated_refund(subscription, 15, plan_config)
      #=> 500 (approximately half of 999 cents)
  """
  def calculate_prorated_refund(nil, _, _plan_config), do: 0
  def calculate_prorated_refund(_, 0, _plan_config), do: 0

  def calculate_prorated_refund(subscription, remaining_days, plan_config)
      when is_map(plan_config) do
    case Map.get(plan_config, subscription.plan_id) do
      %{price_cents: price, duration_days: days} ->
        daily_rate = price / days
        round(daily_rate * remaining_days)

      nil ->
        Logger.warning("No refund configuration found for plan: #{subscription.plan_id}")
        0
    end
  end

  @doc """
  Process an automatic refund for a subscription upgrade.

  Attempts to refund the payment if:
  - Refund amount is greater than 0
  - Subscription has a payment_id

  Returns `:ok` in all cases (logs errors but doesn't fail).

  ## Options

    * `:reason` - Reason for the refund (default: "Prorated refund for subscription upgrade")
    * `:currency` - Currency code (default: "USD")

  ## Examples

      SquareClient.Subscriptions.Refunds.process_automatic_refund(
        subscription,
        500,
        reason: "Upgrade refund"
      )
  """
  def process_automatic_refund(subscription, refund_amount, opts \\ [])

  def process_automatic_refund(nil, _, _opts), do: :ok
  def process_automatic_refund(_, 0, _opts), do: :ok

  def process_automatic_refund(subscription, refund_amount, opts)
      when refund_amount > 0 do
    reason = Keyword.get(opts, :reason, "Prorated refund for subscription upgrade")
    currency = Keyword.get(opts, :currency, "USD")

    # Only process refund if we have a payment_id
    if Map.get(subscription, :payment_id) do
      case SquareClient.Payments.refund(
             subscription.payment_id,
             refund_amount,
             currency,
             reason: reason
           ) do
        {:ok, _refund} ->
          Logger.info(
            "Processed automatic refund of #{refund_amount} cents for subscription #{inspect(Map.get(subscription, :id))}"
          )

          :ok

        {:error, reason} ->
          # Log the error but don't fail the upgrade
          Logger.error("Failed to process automatic refund: #{inspect(reason)}")
          :ok
      end
    else
      # No payment_id available, skip automatic refund
      Logger.info(
        "No payment_id available for automatic refund of subscription #{inspect(Map.get(subscription, :id))}"
      )

      :ok
    end
  end

  def process_automatic_refund(_, _, _opts), do: :ok

  @doc """
  Build a refund info map for displaying to users.

  Returns a map with:
  - `refund_amount` - Amount in cents
  - `remaining_days` - Days remaining
  - `refund_message` - User-friendly message
  - `refund_status` - "processed" or "pending"

  ## Examples

      SquareClient.Subscriptions.Refunds.build_refund_info(500, 5, processed: true)
      #=> %{
      #     refund_amount: 500,
      #     remaining_days: 5,
      #     refund_message: "You'll receive a $5.00 refund for your remaining 5 days.",
      #     refund_status: "processed"
      #   }
  """
  def build_refund_info(refund_amount, remaining_days, opts \\ [])

  def build_refund_info(refund_amount, remaining_days, opts) when refund_amount > 0 do
    processed = Keyword.get(opts, :processed, true)
    refund_dollars = :erlang.float_to_binary(refund_amount / 100.0, decimals: 2)

    %{
      refund_amount: refund_amount,
      remaining_days: remaining_days,
      refund_message:
        "You'll receive a $#{refund_dollars} refund for your remaining #{remaining_days} days.",
      refund_status: if(processed, do: "processed", else: "pending")
    }
  end

  def build_refund_info(0, _, _opts), do: nil
  def build_refund_info(_, 0, _opts), do: nil
end
