defmodule SquareClient.Payments do
  @moduledoc """
  Handle payment operations directly with Square API.
  """

  require Logger

  # Get API configuration
  defp api_url do
    Application.get_env(:square_client, :api_url) ||
      case System.get_env("SQUARE_ENVIRONMENT", "sandbox") do
        "production" -> "https://connect.squareup.com/v2"
        "test" -> System.get_env("SQUARE_API_TEST_URL", "http://localhost:4001/v2")
        _ -> "https://connect.squareupsandbox.com/v2"
      end
  end

  defp access_token do
    Application.get_env(:square_client, :access_token) ||
      System.get_env("SQUARE_ACCESS_TOKEN")
  end

  defp location_id do
    Application.get_env(:square_client, :location_id) ||
      System.get_env("SQUARE_LOCATION_ID")
  end

  defp request_headers do
    [
      {"Authorization", "Bearer #{access_token()}"},
      {"Square-Version", "2025-01-23"},
      {"Content-Type", "application/json"}
    ]
  end

  defp request_options do
    if Application.get_env(:square_client, :disable_retries, false) ||
         System.get_env("SQUARE_ENVIRONMENT") == "test" do
      [retry: false]
    else
      []
    end
  end

  @doc """
  Create a payment.

  ## Parameters

    * `source_id` - The payment source ID (e.g., card nonce or customer card on file)
    * `amount` - The amount to charge in cents
    * `currency` - The currency code (e.g., "USD")
    * `opts` - Optional parameters including:
      * `:customer_id` - The Square customer ID
      * `:reference_id` - Your internal reference ID
      * `:note` - A note for the payment
      * `:autocomplete` - Whether to immediately capture the payment (default true)

  ## Examples

      SquareClient.Payments.create("cnon:card-nonce", 1000, "USD",
        customer_id: "CUSTOMER_ID",
        reference_id: "order-123"
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
      location_id: opts[:location_id] || location_id()
    }

    # Add optional fields
    body =
      body
      |> maybe_add_field(:customer_id, opts[:customer_id])
      |> maybe_add_field(:reference_id, opts[:reference_id])
      |> maybe_add_field(:note, opts[:note])
      |> maybe_add_field(:autocomplete, opts[:autocomplete])

    "#{api_url()}/payments"
    |> Req.post(
      Keyword.merge(
        [json: body, headers: request_headers()],
        request_options()
      )
    )
    |> handle_payment_response()
  end

  @doc """
  Get payment details.
  """
  def get(payment_id) do
    "#{api_url()}/payments/#{payment_id}"
    |> Req.get(
      Keyword.merge(
        [headers: request_headers()],
        request_options()
      )
    )
    |> handle_get_response()
  end

  @doc """
  Complete a payment that was created with autocomplete: false.
  """
  def complete(payment_id) do
    "#{api_url()}/payments/#{payment_id}/complete"
    |> Req.post(
      Keyword.merge(
        [json: %{}, headers: request_headers()],
        request_options()
      )
    )
    |> handle_complete_response()
  end

  @doc """
  Cancel a payment.
  """
  def cancel(payment_id) do
    "#{api_url()}/payments/#{payment_id}/cancel"
    |> Req.post(
      Keyword.merge(
        [json: %{}, headers: request_headers()],
        request_options()
      )
    )
    |> handle_cancel_response()
  end

  @doc """
  Refund a payment.
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

    body = maybe_add_field(body, :reason, opts[:reason])

    "#{api_url()}/refunds"
    |> Req.post(
      Keyword.merge(
        [json: body, headers: request_headers()],
        request_options()
      )
    )
    |> handle_refund_response()
  end

  @doc """
  List payments with optional filters.
  """
  def list(opts \\ []) do
    params =
      []
      |> maybe_add_param(:begin_time, opts[:begin_time])
      |> maybe_add_param(:end_time, opts[:end_time])
      |> maybe_add_param(:sort_order, opts[:sort_order])
      |> maybe_add_param(:cursor, opts[:cursor])
      |> maybe_add_param(:location_id, opts[:location_id] || location_id())
      |> maybe_add_param(:limit, opts[:limit])

    "#{api_url()}/payments"
    |> Req.get(
      Keyword.merge(
        [params: params, headers: request_headers()],
        request_options()
      )
    )
    |> handle_list_response()
  end

  # Response handlers
  defguardp is_success(status) when status in 200..299

  defp handle_payment_response({:ok, %{status: status, body: body}})
       when is_success(status) do
    payment = body["payment"]
    Logger.info("Payment created: #{payment["id"]}")

    {:ok, %{
      payment_id: payment["id"],
      status: payment["status"],
      amount: payment["amount_money"]["amount"],
      currency: payment["amount_money"]["currency"],
      created_at: payment["created_at"]
    }}
  end

  defp handle_payment_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to create payment (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_payment_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  defp handle_get_response({:ok, %{status: status, body: body}})
       when is_success(status) do
    {:ok, body["payment"]}
  end

  defp handle_get_response({:ok, %{status: 404}}) do
    {:error, :not_found}
  end

  defp handle_get_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to get payment (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_get_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  defp handle_complete_response({:ok, %{status: status, body: body}})
       when is_success(status) do
    payment = body["payment"]
    Logger.info("Payment completed: #{payment["id"]}")
    {:ok, payment}
  end

  defp handle_complete_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to complete payment (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_complete_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  defp handle_cancel_response({:ok, %{status: status}})
       when is_success(status) do
    Logger.info("Payment canceled successfully")
    :ok
  end

  defp handle_cancel_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to cancel payment (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_cancel_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  defp handle_refund_response({:ok, %{status: status, body: body}})
       when is_success(status) do
    refund = body["refund"]
    Logger.info("Refund created: #{refund["id"]}")

    {:ok, %{
      refund_id: refund["id"],
      payment_id: refund["payment_id"],
      amount: refund["amount_money"]["amount"],
      status: refund["status"]
    }}
  end

  defp handle_refund_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to create refund (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_refund_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  defp handle_list_response({:ok, %{status: status, body: body}})
       when is_success(status) do
    {:ok, %{
      payments: body["payments"] || [],
      cursor: body["cursor"]
    }}
  end

  defp handle_list_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to list payments (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_list_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  # Helper functions
  defp generate_idempotency_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp parse_error(body) when is_map(body) do
    case body["errors"] do
      [%{"detail" => detail} | _] -> detail
      _ -> "Square API error"
    end
  end

  defp parse_error(_), do: "Unknown error"

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_param(list, _key, nil), do: list
  defp maybe_add_param(list, key, value), do: [{key, value} | list]
end