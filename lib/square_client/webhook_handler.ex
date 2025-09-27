defmodule SquareClient.WebhookHandler do
  @moduledoc """
  Behaviour for handling Square webhook events in your application.

  This module defines the contract that your app must implement to handle
  Square webhook events. It provides a consistent interface across all your
  applications while allowing each app to implement its own business logic.

  ## Implementation Example

      defmodule MyApp.Payments.SquareWebhookHandler do
        @behaviour SquareClient.WebhookHandler

        @impl true
        def handle_event(%{event_type: "subscription.created"} = event) do
          # Update local database
          # Send welcome email
          # etc.
          :ok
        end

        @impl true
        def handle_event(%{event_type: "subscription.updated"} = event) do
          # Update subscription status
          :ok
        end

        # Catch-all for unhandled events
        @impl true
        def handle_event(event) do
          {:error, {:unhandled_event, event.event_type}}
        end
      end

  Then configure your handler in config:

      config :square_client,
        webhook_handler: MyApp.Payments.SquareWebhookHandler,
        webhook_signature_key: System.get_env("SQUARE_WEBHOOK_SIGNATURE_KEY")
  """

  @type event :: %{
          event_type: String.t(),
          data: map(),
          event_id: String.t() | nil,
          created_at: String.t() | nil,
          merchant_id: String.t() | nil
        }

  @type result :: :ok | {:ok, any()} | {:error, any()}

  @doc """
  Handle a Square webhook event.

  Implement this callback with pattern matching on event_type to handle
  different event types. Use function heads for clean pattern matching.
  """
  @callback handle_event(event()) :: result()
end
