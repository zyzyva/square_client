defmodule SquareClient.Subscriptions.Constants do
  @moduledoc """
  Constants for subscription tiers and statuses.

  Provides a single source of truth for subscription-related values that are
  consistent across Square-integrated applications.

  ## Subscription Tiers

  Standard subscription tiers used across applications:
  - `free` - Free tier with limited features
  - `premium` - Premium tier with advanced features
  - `enterprise` - Enterprise tier with all features

  ## Statuses

  Application-level statuses for user subscription state:
  - `active` - User has an active, paid subscription
  - `inactive` - User's subscription is inactive
  - `canceled` - User's subscription was canceled
  - `past_due` - User's payment failed

  ## Square Statuses

  Square API subscription statuses (from Square webhooks):
  - `PENDING` - Subscription created but not yet active
  - `ACTIVE` - Subscription is active and billing
  - `CANCELED` - Subscription was canceled
  - `PAUSED` - Subscription is temporarily paused
  - `DELINQUENT` - Payment failed, subscription at risk
  """

  # Subscription Tiers
  @tier_free "free"
  @tier_premium "premium"
  @tier_enterprise "enterprise"

  # Subscription Statuses (for user.subscription_status)
  @status_active "active"
  @status_inactive "inactive"
  @status_canceled "canceled"
  @status_past_due "past_due"

  # Square Subscription Statuses (from Square API)
  @square_status_pending "PENDING"
  @square_status_active "ACTIVE"
  @square_status_canceled "CANCELED"
  @square_status_paused "PAUSED"
  @square_status_delinquent "DELINQUENT"

  # Getters for tiers
  def tier_free, do: @tier_free
  def tier_premium, do: @tier_premium
  def tier_enterprise, do: @tier_enterprise

  def all_tiers, do: [@tier_free, @tier_premium, @tier_enterprise]

  # Getters for statuses
  def status_active, do: @status_active
  def status_inactive, do: @status_inactive
  def status_canceled, do: @status_canceled
  def status_past_due, do: @status_past_due

  def all_statuses, do: [@status_active, @status_inactive, @status_canceled, @status_past_due]

  # Getters for Square statuses
  def square_status_pending, do: @square_status_pending
  def square_status_active, do: @square_status_active
  def square_status_canceled, do: @square_status_canceled
  def square_status_paused, do: @square_status_paused
  def square_status_delinquent, do: @square_status_delinquent

  def all_square_statuses,
    do: [
      @square_status_pending,
      @square_status_active,
      @square_status_canceled,
      @square_status_paused,
      @square_status_delinquent
    ]

  # Helper functions
  def is_premium_tier?(tier), do: tier == @tier_premium
  def is_free_tier?(tier), do: tier == @tier_free
  def is_active_status?(status), do: status == @status_active
  def is_square_active?(square_status), do: square_status == @square_status_active

  @doc """
  Check if a user has active premium based on tier and status.
  """
  def has_active_premium?(tier, status) do
    is_premium_tier?(tier) && is_active_status?(status)
  end

  @doc """
  Convert Square status to application-level internal status.

  ## Examples

      iex> SquareClient.Subscriptions.Constants.square_to_internal_status("ACTIVE")
      "active"

      iex> SquareClient.Subscriptions.Constants.square_to_internal_status("PENDING")
      "active"

      iex> SquareClient.Subscriptions.Constants.square_to_internal_status("CANCELED")
      "canceled"
  """
  def square_to_internal_status(@square_status_active), do: @status_active
  # Treat pending as active
  def square_to_internal_status(@square_status_pending), do: @status_active
  def square_to_internal_status(@square_status_canceled), do: @status_canceled
  def square_to_internal_status(@square_status_paused), do: @status_inactive
  def square_to_internal_status(@square_status_delinquent), do: @status_past_due
  def square_to_internal_status(_), do: @status_inactive
end
