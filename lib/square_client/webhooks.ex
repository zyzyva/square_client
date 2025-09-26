defmodule SquareClient.Webhooks do
  @moduledoc """
  Square Webhooks handling and signature verification.

  Provides secure webhook processing including:
  - Signature verification using HMAC-SHA256
  - Event parsing and validation
  - Helper functions for common webhook events
  """

  require Logger

  @doc """
  Verify the webhook signature from Square.

  Square signs webhooks using HMAC-SHA256 with your webhook signature key.
  This function verifies that the webhook actually came from Square.

  ## Parameters

    * `payload` - The raw webhook payload (request body as string)
    * `signature` - The signature from the `x-square-hmacsha256-signature` header
    * `signature_key` - Your webhook signature key from Square

  ## Examples

      # In your controller
      def webhook(conn, params) do
        payload = conn.assigns.raw_body
        signature = get_req_header(conn, "x-square-hmacsha256-signature") |> List.first()

        if SquareClient.Webhooks.verify_signature(payload, signature, webhook_key()) do
          # Process webhook
        else
          # Invalid signature - reject
        end
      end
  """
  def verify_signature(payload, signature, signature_key)
      when is_binary(payload) and is_binary(signature) and is_binary(signature_key) do
    expected_signature =
      :crypto.mac(:hmac, :sha256, signature_key, payload)
      |> Base.encode64()

    Plug.Crypto.secure_compare(signature, expected_signature)
  rescue
    _ -> false
  end

  def verify_signature(_, _, _), do: false

  @doc """
  Parse a webhook event from the payload.

  Returns a standardized event structure with:
  - event_type: The type of webhook event
  - data: The event data
  - metadata: Additional event metadata

  ## Examples

      case SquareClient.Webhooks.parse_event(payload) do
        {:ok, %{event_type: "subscription.created", data: data}} ->
          # Handle subscription creation

        {:error, reason} ->
          # Handle parse error
      end
  """
  def parse_event(payload) when is_binary(payload) do
    case JSON.decode(payload) do
      {:ok, %{"type" => event_type, "data" => data} = event} ->
        {:ok,
         %{
           event_type: normalize_event_type(event_type),
           data: data,
           event_id: event["event_id"],
           created_at: event["created_at"],
           merchant_id: event["merchant_id"]
         }}

      {:ok, _} ->
        {:error, :invalid_event_format}

      {:error, _} = error ->
        error
    end
  end

  def parse_event(%{} = event) do
    # Already decoded
    event_type = event["type"] || event[:type]
    data = event["data"] || event[:data]

    if event_type && data do
      {:ok,
       %{
         event_type: normalize_event_type(event_type),
         data: data,
         event_id: event["event_id"] || event[:event_id],
         created_at: event["created_at"] || event[:created_at],
         merchant_id: event["merchant_id"] || event[:merchant_id]
       }}
    else
      {:error, :invalid_event_format}
    end
  end

  @doc """
  Check if an event is a subscription event.
  """
  def subscription_event?(event_type) do
    String.starts_with?(to_string(event_type), "subscription.")
  end

  @doc """
  Check if an event is a payment event.
  """
  def payment_event?(event_type) do
    String.starts_with?(to_string(event_type), "payment.")
  end

  @doc """
  Check if an event is a customer event.
  """
  def customer_event?(event_type) do
    String.starts_with?(to_string(event_type), "customer.")
  end

  @doc """
  Check if an event is an invoice event.
  """
  def invoice_event?(event_type) do
    String.starts_with?(to_string(event_type), "invoice.")
  end

  @doc """
  Extract subscription ID from various event types.
  """
  def get_subscription_id(%{data: %{"object" => %{"subscription" => %{"id" => id}}}}),
    do: {:ok, id}

  def get_subscription_id(%{data: %{"object" => %{"invoice" => %{"subscription_id" => id}}}})
      when not is_nil(id),
      do: {:ok, id}

  def get_subscription_id(%{data: %{"object" => %{"subscription_id" => id}}}) when not is_nil(id),
    do: {:ok, id}

  def get_subscription_id(%{data: %{"id" => id}, event_type: event_type}) do
    if subscription_event?(event_type) do
      {:ok, id}
    else
      {:error, :subscription_id_not_found}
    end
  end

  def get_subscription_id(_), do: {:error, :subscription_id_not_found}

  @doc """
  Extract customer ID from various event types.
  """
  def get_customer_id(%{data: %{"object" => %{"customer" => %{"id" => id}}}}), do: {:ok, id}

  def get_customer_id(%{data: %{"object" => %{"customer_id" => id}}}) when not is_nil(id),
    do: {:ok, id}

  def get_customer_id(%{data: %{"id" => id}, event_type: event_type}) do
    if customer_event?(event_type) do
      {:ok, id}
    else
      {:error, :customer_id_not_found}
    end
  end

  def get_customer_id(_), do: {:error, :customer_id_not_found}

  @doc """
  Extract payment ID from payment events.
  """
  def get_payment_id(%{data: %{"object" => %{"payment" => %{"id" => id}}}}), do: {:ok, id}

  def get_payment_id(%{data: %{"id" => id}, event_type: event_type}) do
    if payment_event?(event_type) do
      {:ok, id}
    else
      {:error, :payment_id_not_found}
    end
  end

  def get_payment_id(_), do: {:error, :payment_id_not_found}

  # Normalize Square event types to a consistent format
  defp normalize_event_type(event_type) when is_binary(event_type) do
    event_type
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, ".")
  end

  defp normalize_event_type(event_type), do: to_string(event_type) |> normalize_event_type()
end
