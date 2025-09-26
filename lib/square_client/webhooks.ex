defmodule SquareClient.Webhooks do
  @moduledoc """
  Handle payment service webhook verification and processing.
  """

  require Logger

  @doc """
  Verify a webhook signature from the payment service.

  ## Parameters

    * `body` - Raw request body string
    * `signature` - X-Webhook-Signature header value
    * `url` - Full webhook URL (optional for payment service)

  ## Returns

    * `{:ok, payload}` - If signature is valid
    * `{:error, :invalid_signature}` - If signature is invalid

  ## Examples

      case SquareClient.Webhooks.verify_signature(body, signature, url) do
        {:ok, payload} -> process_webhook(payload)
        {:error, :invalid_signature} -> {:error, "Invalid webhook signature"}
      end
  """
  def verify_signature(body, signature, _url \\ nil) do
    webhook_secret = SquareClient.Config.get(:webhook_secret)

    if webhook_secret do
      computed = compute_signature(body, webhook_secret)

      if secure_compare(computed, signature) do
        {:ok, Jason.decode!(body)}
      else
        Logger.warning("Invalid webhook signature")
        {:error, :invalid_signature}
      end
    else
      Logger.warning("Webhook secret not configured, skipping verification")
      {:ok, Jason.decode!(body)}
    end
  end

  @doc """
  Parse a webhook event and return structured data.

  ## Parameters

    * `payload` - Decoded webhook payload

  ## Returns

    * `{:ok, event}` - Parsed event with type and data
    * `{:error, reason}` - If parsing fails

  ## Examples

      {:ok, event} = SquareClient.Webhooks.parse_event(payload)
      case event.type do
        "subscription.created" -> handle_subscription_created(event.data)
        "subscription.updated" -> handle_subscription_updated(event.data)
        _ -> :ok
      end
  """
  def parse_event(%{"type" => type, "data" => data} = payload) do
    event = %{
      id: payload["event_id"] || payload["id"],
      type: type,
      data: data,
      created_at: payload["created_at"],
      app_id: payload["app_id"],
      metadata: payload["metadata"]
    }

    {:ok, event}
  end

  def parse_event(_), do: {:error, :invalid_payload}

  @doc """
  List of subscription-related webhook event types.
  """
  def subscription_event_types do
    [
      "subscription.created",
      "subscription.updated",
      "subscription.canceled",
      "subscription.paused",
      "subscription.resumed",
      "subscription.action.executed"
    ]
  end

  @doc """
  List of payment-related webhook event types.
  """
  def payment_event_types do
    [
      "payment.created",
      "payment.updated",
      "payment.deleted",
      "refund.created",
      "refund.updated"
    ]
  end

  @doc """
  List of customer-related webhook event types.
  """
  def customer_event_types do
    [
      "customer.created",
      "customer.updated",
      "customer.deleted",
      "card.created",
      "card.updated",
      "card.deleted"
    ]
  end

  defp compute_signature(body, webhook_secret) do
    :crypto.mac(:hmac, :sha256, webhook_secret, body)
    |> Base.encode16(case: :lower)
  end

  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    a_bytes = :binary.bin_to_list(a)
    b_bytes = :binary.bin_to_list(b)

    result =
      Enum.zip(a_bytes, b_bytes)
      |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)

    result == 0
  end

  defp secure_compare(_, _), do: false
end
