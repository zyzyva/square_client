defmodule SquareClient.PaymentQueue do
  @moduledoc """
  Queue payment operations through RabbitMQ for async processing.
  """

  alias SquareClient.RabbitMQPublisher

  @doc """
  Queue a payment operation for async processing.

  Returns {:ok, correlation_id} which can be used to match the callback response.
  """
  def queue_operation(operation, params) do
    RabbitMQPublisher.publish(operation, params)
  end

  @doc """
  Queue a subscription creation.
  """
  def create_subscription(customer_id, plan_id, opts \\ []) do
    params = %{
      customer_id: customer_id,
      plan_id: plan_id,
      card_id: opts[:card_id],
      start_date: opts[:start_date],
      metadata: opts[:metadata]
    }

    queue_operation("subscription.create", params)
  end

  @doc """
  Queue a subscription cancellation.
  """
  def cancel_subscription(subscription_id) do
    queue_operation("subscription.cancel", %{subscription_id: subscription_id})
  end

  @doc """
  Queue a payment.
  """
  def create_payment(source_id, amount, currency, opts \\ []) do
    params = %{
      source_id: source_id,
      amount: amount,
      currency: currency,
      customer_id: opts[:customer_id],
      reference_id: opts[:reference_id],
      note: opts[:note]
    }

    queue_operation("payment.create", params)
  end

  @doc """
  Queue a customer creation.
  """
  def create_customer(attrs) do
    queue_operation("customer.create", attrs)
  end

  @doc """
  Queue a refund.
  """
  def create_refund(payment_id, amount, currency, opts \\ []) do
    params = %{
      payment_id: payment_id,
      amount: amount,
      currency: currency,
      reason: opts[:reason]
    }

    queue_operation("refund.create", params)
  end
end
