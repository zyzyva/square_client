defmodule SquareClient do
  @moduledoc """
  Async payment processing client using RabbitMQ message queuing.

  ## Overview

  SquareClient provides async payment processing through a centralized payment service.
  Instead of direct Square API calls, this library:

  1. Publishes payment requests to RabbitMQ via HTTP
  2. Payment service processes with Square API
  3. Returns results via webhook callbacks

  ## Architecture

      Your App → RabbitMQ → Payment Service → Square API
          ↑                         ↓
          ←── Webhook Callback ─────┘

  ## Key Features

  - **Async operations** - All operations return immediately with correlation IDs
  - **No Square credentials needed** - Centralized in payment service
  - **Automatic retry** - Payment service handles failures
  - **Multi-app support** - Each app tracked by app_id
  - **Simple integration** - No AMQP/Broadway dependencies
  """

  alias SquareClient.Config

  @doc """
  Configure the payment service client.

  ## Options

    * `:rabbitmq_url` - RabbitMQ management API URL (required)
    * `:app_id` - Your application identifier (required, e.g., "contacts4us")
    * `:callback_url` - URL where payment service sends responses (required)
    * `:queue_name` - RabbitMQ queue name (defaults to "payments")
    * `:exchange` - RabbitMQ exchange (defaults to "payments")
    * `:rabbitmq_username` - RabbitMQ username (defaults to "guest")
    * `:rabbitmq_password` - RabbitMQ password (defaults to "guest")

  ## Examples

      SquareClient.configure(
        rabbitmq_url: "http://localhost:15672",
        app_id: "contacts4us",
        callback_url: "https://contacts4us.com/webhooks/payments",
        rabbitmq_username: System.get_env("RABBITMQ_USERNAME"),
        rabbitmq_password: System.get_env("RABBITMQ_PASSWORD")
      )
  """
  def configure(opts) do
    Config.configure(opts)
  end

  @doc """
  Get current configuration.
  """
  def config do
    Config.get()
  end
end
