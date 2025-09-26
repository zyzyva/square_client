defmodule SquareClient.RabbitMQPublisher do
  @moduledoc """
  Publishes payment messages to RabbitMQ via HTTP API.
  Similar to how swoosh_rabbitmq publishes email messages.
  """

  alias SquareClient.Config
  require Logger

  @doc """
  Publish a payment message to RabbitMQ.

  The message includes:
  - The payment operation details
  - The app_id for tracking
  - A callback URL for the response
  - A correlation_id for matching responses
  """
  def publish(operation, params) do
    message = build_message(operation, params)

    case send_to_rabbitmq(message) do
      {:ok, _} ->
        {:ok, %{correlation_id: message.correlation_id, status: "queued"}}

      {:error, reason} ->
        Logger.error("Failed to publish payment message: #{inspect(reason)}")
        {:error, :queue_publish_failed}
    end
  end

  defp build_message(operation, params) do
    %{
      operation: operation,
      params: params,
      app_id: Config.app_id(),
      callback_url: Config.get(:callback_url),
      correlation_id: generate_correlation_id(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp send_to_rabbitmq(message) do
    url = build_rabbitmq_url()
    headers = build_headers()

    body = %{
      properties: %{
        app_id: message.app_id,
        correlation_id: message.correlation_id,
        reply_to: message.callback_url,
        content_type: "application/json"
      },
      routing_key: Config.queue_name(),
      payload: Jason.encode!(message),
      payload_encoding: "string"
    }

    Req.post(url, json: body, headers: headers)
  end

  defp build_rabbitmq_url do
    base = Config.rabbitmq_url()
    exchange = Config.get(:exchange)

    # RabbitMQ Management API endpoint for publishing
    "#{base}/api/exchanges/%2F/#{exchange}/publish"
  end

  defp build_headers do
    username = Config.get(:rabbitmq_username) || "guest"
    password = Config.get(:rabbitmq_password) || "guest"

    auth = Base.encode64("#{username}:#{password}")

    [
      {"Authorization", "Basic #{auth}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
