defmodule SquareClient.Payments do
  @moduledoc """
  Handle payment operations through the payment service.
  """

  alias SquareClient.HTTP

  @doc """
  Create a payment.

  ## Parameters

    * `source_id` - Payment source (card nonce, card on file ID, etc.)
    * `amount` - Amount in cents
    * `currency` - Currency code (e.g., "USD")
    * `opts` - Additional options:
      * `:location_id` - Location ID (uses default if not provided)
      * `:reference_id` - Your internal reference ID
      * `:note` - Payment note
      * `:customer_id` - Square customer ID
      * `:autocomplete` - Whether to auto-complete (defaults to true)

  ## Examples

      SquareClient.Payments.create("SOURCE_ID", 1000, "USD",
        customer_id: "CUSTOMER_ID",
        note: "Premium subscription payment"
      )
  """
  def create(source_id, amount, currency, opts \\ []) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      source_id: source_id,
      amount_money: %{
        amount: amount,
        currency: currency
      },
      autocomplete: Keyword.get(opts, :autocomplete, true)
    }

    # Add optional fields
    body =
      opts
      |> Keyword.take([:reference_id, :note, :customer_id])
      |> Enum.reduce(body, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)

    HTTP.post("/api/payments", body)
  end

  @doc """
  Get a payment by ID.
  """
  def get(payment_id) do
    HTTP.get("/api/payments/#{payment_id}")
  end

  @doc """
  Complete a payment that was created with autocomplete: false.

  ## Examples

      SquareClient.Payments.complete("PAYMENT_ID")
  """
  def complete(payment_id) do
    HTTP.post("/api/payments/#{payment_id}/complete", %{})
  end

  @doc """
  Cancel a payment.

  ## Examples

      SquareClient.Payments.cancel("PAYMENT_ID")
  """
  def cancel(payment_id) do
    HTTP.post("/api/payments/#{payment_id}/cancel", %{})
  end

  @doc """
  Create a refund for a payment.

  ## Parameters

    * `payment_id` - The payment ID to refund
    * `amount` - Amount to refund in cents
    * `currency` - Currency code
    * `opts` - Additional options:
      * `:reason` - Reason for refund

  ## Examples

      SquareClient.Payments.refund("PAYMENT_ID", 500, "USD",
        reason: "Customer requested partial refund"
      )
  """
  def refund(payment_id, amount, currency, opts \\ []) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      payment_id: payment_id,
      amount_money: %{
        amount: amount,
        currency: currency
      }
    }

    body =
      if reason = opts[:reason] do
        Map.put(body, :reason, reason)
      else
        body
      end

    HTTP.post("/api/refunds", body)
  end

  @doc """
  List payments with optional filters.

  ## Options

    * `:location_id` - Filter by location
    * `:customer_id` - Filter by customer
    * `:begin_time` - Start of time range
    * `:end_time` - End of time range
    * `:limit` - Number of results
    * `:cursor` - Pagination cursor

  ## Examples

      SquareClient.Payments.list(
        customer_id: "CUSTOMER_ID",
        begin_time: "2024-01-01T00:00:00Z"
      )
  """
  def list(opts \\ []) do
    query_params = build_query_params(opts)
    HTTP.get("/api/payments#{query_params}")
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