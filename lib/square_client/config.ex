defmodule SquareClient.Config do
  @moduledoc """
  Configuration management for payment service client.
  """

  @defaults %{
    rabbitmq_url: "http://localhost:15672",
    queue_name: "payments",
    exchange: "payments"
  }

  @doc """
  Configure the Square client.
  """
  def configure(opts) do
    config =
      @defaults
      |> Map.merge(Map.new(opts))
      |> validate!()

    :persistent_term.put({__MODULE__, :config}, config)
    :ok
  end

  @doc """
  Get current configuration.
  """
  def get do
    case :persistent_term.get({__MODULE__, :config}, nil) do
      nil -> raise "Square client not configured. Call SquareClient.configure/1 first."
      config -> config
    end
  end

  @doc """
  Get a specific configuration value.
  """
  def get(key) do
    get() |> Map.get(key)
  end

  @doc """
  Get the RabbitMQ management API URL.
  """
  def rabbitmq_url do
    get(:rabbitmq_url)
  end

  @doc """
  Get the base URL (alias for rabbitmq_url for backwards compatibility).
  """
  def base_url do
    rabbitmq_url()
  end

  @doc """
  Get the queue name for payment messages.
  """
  def queue_name do
    get(:queue_name)
  end

  @doc """
  Get the app identifier.
  """
  def app_id do
    get(:app_id)
  end

  defp validate!(config) do
    unless Map.has_key?(config, :rabbitmq_url) do
      raise ArgumentError, "Payment client requires :rabbitmq_url"
    end

    unless Map.has_key?(config, :app_id) do
      raise ArgumentError, "Payment client requires :app_id to identify your application"
    end

    unless Map.has_key?(config, :callback_url) do
      raise ArgumentError, "Payment client requires :callback_url for async responses"
    end

    config
  end
end
