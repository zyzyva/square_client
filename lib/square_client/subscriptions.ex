defmodule SquareClient.Subscriptions do
  @moduledoc """
  Handle subscription operations through the payment service.
  """

  alias SquareClient.HTTP

  @doc """
  Create a new subscription for a customer.

  ## Parameters

    * `customer_id` - The customer ID (can be app-specific)
    * `plan_id` - The subscription plan ID
    * `opts` - Additional options:
      * `:card_id` - Payment card ID for the subscription
      * `:start_date` - When to start the subscription (defaults to now)
      * `:metadata` - Additional metadata for tracking

  ## Examples

      SquareClient.Subscriptions.create(
        "CUSTOMER_ID",
        "PLAN_ID",
        card_id: "CARD_ID"
      )
  """
  def create(customer_id, plan_id, opts \\ []) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      plan_id: plan_id,
      customer_id: customer_id
    }

    body =
      if card_id = opts[:card_id] do
        Map.put(body, :card_id, card_id)
      else
        body
      end

    body =
      if start_date = opts[:start_date] do
        Map.put(body, :start_date, start_date)
      else
        body
      end

    HTTP.post("/api/subscriptions", body)
  end

  @doc """
  Retrieve a subscription by ID.
  """
  def get(subscription_id) do
    HTTP.get("/api/subscriptions/#{subscription_id}")
  end

  @doc """
  List subscriptions with optional filters.

  ## Options

    * `:customer_id` - Filter by customer
    * `:location_id` - Filter by location
    * `:status` - Filter by status (ACTIVE, CANCELED, etc.)
    * `:limit` - Number of results to return
    * `:cursor` - Pagination cursor

  ## Examples

      SquareClient.Subscriptions.list(customer_id: "CUSTOMER_ID", status: "ACTIVE")
  """
  def list(opts \\ []) do
    query_params = build_query_params(opts)
    HTTP.get("/api/subscriptions#{query_params}")
  end

  @doc """
  Update a subscription.

  ## Parameters

    * `subscription_id` - The subscription ID to update
    * `updates` - Map of updates to apply

  ## Examples

      SquareClient.Subscriptions.update("SUB_ID", %{
        plan_id: "NEW_PLAN_ID"
      })
  """
  def update(subscription_id, updates) do
    body = %{
      subscription: updates
    }

    HTTP.put("/api/subscriptions/#{subscription_id}", body)
  end

  @doc """
  Cancel a subscription.

  ## Examples

      SquareClient.Subscriptions.cancel("SUB_ID")
  """
  def cancel(subscription_id) do
    HTTP.post("/api/subscriptions/#{subscription_id}/cancel", %{})
  end

  @doc """
  Pause a subscription.

  ## Options

    * `:pause_effective_date` - When to pause (defaults to immediate)
    * `:resume_effective_date` - When to automatically resume

  ## Examples

      SquareClient.Subscriptions.pause("SUB_ID",
        resume_effective_date: "2024-03-01"
      )
  """
  def pause(subscription_id, opts \\ []) do
    body =
      opts
      |> Keyword.take([:pause_effective_date, :resume_effective_date])
      |> Map.new()

    HTTP.post("/api/subscriptions/#{subscription_id}/pause", body)
  end

  @doc """
  Resume a paused subscription.

  ## Options

    * `:resume_effective_date` - When to resume (defaults to immediate)

  ## Examples

      SquareClient.Subscriptions.resume("SUB_ID")
  """
  def resume(subscription_id, opts \\ []) do
    body =
      opts
      |> Keyword.take([:resume_effective_date])
      |> Map.new()

    HTTP.post("/api/subscriptions/#{subscription_id}/resume", body)
  end

  defp generate_idempotency_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp build_query_params([]), do: ""

  defp build_query_params(opts) do
    params =
      opts
      |> Enum.map(fn {key, value} -> "#{key}=#{URI.encode(to_string(value))}" end)
      |> Enum.join("&")

    "?#{params}"
  end
end