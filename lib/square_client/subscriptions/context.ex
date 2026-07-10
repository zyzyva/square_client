defmodule SquareClient.Subscriptions.Context do
  @moduledoc """
  Generic CRUD operations for subscription management.

  This module provides reusable functions for managing subscriptions in your
  application, including syncing with Square, checking subscription status, and
  querying subscriptions.

  ## Usage

  Import this module in your application's Payments context:

      defmodule MyApp.Payments do
        import SquareClient.Subscriptions.Context

        # Your app-specific functions...
      end

  Or call functions directly:

      SquareClient.Subscriptions.Context.sync_from_square(subscription, repo)
  """

  alias SquareClient.Subscriptions

  require Logger

  @doc """
  Sync subscription data from Square API and update local database.

  Takes a subscription struct and repo module. Returns `{:ok, updated_subscription}`
  or `{:error, reason}`.

  ## Options

    * `:repo` - The Ecto repo module (required)

  ## Examples

      SquareClient.Subscriptions.Context.sync_from_square(subscription, MyApp.Repo)
  """
  @spec sync_from_square(map(), module(), keyword()) :: {:ok, map()} | {:error, term()}
  def sync_from_square(subscription, repo, opts \\ [])

  def sync_from_square(%{square_subscription_id: nil} = subscription, _repo, _opts) do
    # No Square ID, return as is
    {:ok, subscription}
  end

  def sync_from_square(%{square_subscription_id: square_id} = subscription, repo, _opts) do
    case Subscriptions.get(square_id) do
      {:ok, %{"subscription" => square_data}} ->
        sync_square_data(subscription, square_data, repo)

      {:error, :not_found} ->
        mark_subscription_canceled(subscription, repo)

      {:error, _reason} ->
        # API error, return current subscription unchanged
        {:ok, subscription}
    end
  end

  @doc """
  Check if a subscription should be synced with Square.

  Returns true if:
  - Subscription is missing next_billing_at
  - Subscription is within 3 days of renewal

  ## Examples

      SquareClient.Subscriptions.Context.should_sync?(subscription)
  """
  @spec should_sync?(map()) :: boolean()
  def should_sync?(subscription) do
    cond do
      # Always sync if we don't have the next billing date
      is_nil(subscription.next_billing_at) ->
        true

      # Sync if we're within 3 days of the renewal date (to catch any changes)
      subscription.next_billing_at != nil ->
        days_until_renewal = DateTime.diff(subscription.next_billing_at, DateTime.utc_now(), :day)
        days_until_renewal <= 3

      # Otherwise don't sync
      true ->
        false
    end
  end

  @doc """
  Get a subscription by Square subscription ID.

  ## Examples

      SquareClient.Subscriptions.Context.get_by_square_id("sub_123", MyApp.Subscription, MyApp.Repo)
  """
  @spec get_by_square_id(String.t(), module(), module()) :: map() | nil
  def get_by_square_id(square_id, schema_module, repo) do
    import Ecto.Query

    query = from(s in schema_module, where: s.square_subscription_id == ^square_id)
    repo.one(query)
  end

  @doc """
  Parse a Square date string to a DateTime.

  Square returns dates in ISO8601 format. Returns nil if parsing fails.

  ## Examples

      SquareClient.Subscriptions.Context.parse_square_date("2024-01-15T10:30:00Z")
      #=> ~U[2024-01-15 10:30:00Z]

      SquareClient.Subscriptions.Context.parse_square_date(nil)
      #=> nil
  """
  @spec parse_square_date(String.t() | nil) :: DateTime.t() | nil
  def parse_square_date(nil), do: nil

  def parse_square_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  # Private helper functions

  @monthly_billing_days 30

  defp sync_square_data(subscription, square_data, repo) do
    started_at = parse_square_date(square_data["start_date"])
    next_billing = build_next_billing(square_data, subscription, started_at)

    changeset =
      subscription.__struct__.changeset(subscription, %{
        status: square_data["status"],
        next_billing_at: next_billing,
        started_at: started_at || subscription.started_at,
        canceled_at: parse_square_date(square_data["canceled_date"])
      })

    repo.update(changeset)
  end

  defp build_next_billing(square_data, subscription, started_at) do
    charged_through = parse_square_date(square_data["charged_through_date"])
    calculate_next_billing(charged_through, subscription, started_at)
  end

  # Calculate next billing when Square hasn't provided it yet
  defp calculate_next_billing(nil, %{plan_id: "premium_monthly"}, started_at)
       when not is_nil(started_at) do
    started_at |> DateTime.add(@monthly_billing_days, :day) |> DateTime.truncate(:second)
  end

  defp calculate_next_billing(nil, %{plan_id: "premium_monthly", started_at: started_at}, nil)
       when not is_nil(started_at) do
    started_at |> DateTime.add(@monthly_billing_days, :day) |> DateTime.truncate(:second)
  end

  defp calculate_next_billing(next_billing, _subscription, _started_at), do: next_billing

  defp mark_subscription_canceled(subscription, repo) do
    # Subscription doesn't exist in Square, mark as canceled locally
    changeset =
      subscription.__struct__.changeset(subscription, %{
        status: "CANCELED",
        canceled_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    repo.update(changeset)
  end
end
