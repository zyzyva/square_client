defmodule SquareClient.Controllers.WebhookController do
  @moduledoc """
  Reusable webhook controller behavior for Square webhooks.

  This module provides a complete webhook controller implementation
  that works with SquareClient.WebhookPlug to handle verified events.

  ## Usage

  In your Phoenix app, create a controller that uses this module:

      defmodule MyAppWeb.SquareWebhookController do
        use SquareClient.Controllers.WebhookController
      end

  Then wire it up in your router:

      pipeline :square_webhook do
        plug :accepts, ["json"]
        plug SquareClient.WebhookPlug
      end

      scope "/webhooks", MyAppWeb do
        pipe_through :square_webhook
        post "/square", SquareWebhookController, :handle
      end

  ## Custom Response Handling

  You can override the default response handlers if needed:

      defmodule MyAppWeb.SquareWebhookController do
        use SquareClient.Controllers.WebhookController

        # Override the success response
        def handle_success(conn, event) do
          conn
          |> put_status(:accepted)
          |> json(%{status: "processed", event_id: event.event_id})
        end
      end

  ## Callbacks

  You can implement optional callbacks to customize behavior:

  - `handle_success(conn, event)` - Called when event is successfully processed
  - `handle_invalid_signature(conn)` - Called when signature validation fails
  - `handle_missing_signature(conn)` - Called when signature header is missing
  - `handle_error(conn, reason)` - Called when processing fails
  - `handle_missing_event(conn)` - Called when event is not in assigns
  """

  defmacro __using__(_opts) do
    quote do
      import Plug.Conn
      require Logger

      @doc """
      Main webhook handler endpoint.

      The SquareClient.WebhookPlug should run before this controller
      action, which will verify the webhook and add the result to
      conn.assigns.square_event.
      """
      def handle(conn, _params) do
        handle_webhook_result(conn, conn.assigns[:square_event])
      end

      @doc """
      Handle successful webhook processing.

      Override this function to customize the success response.
      """
      def handle_success(conn, event) do
        Logger.info("Successfully processed Square webhook: #{event.event_type}")

        conn
        |> put_status(:ok)
        |> json(%{received: true, event_id: event.event_id})
      end

      @doc """
      Handle invalid signature error.

      Override this function to customize the invalid signature response.
      """
      def handle_invalid_signature(conn) do
        Logger.warning("Received Square webhook with invalid signature")

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid signature"})
      end

      @doc """
      Handle missing signature error.

      Override this function to customize the missing signature response.
      """
      def handle_missing_signature(conn) do
        Logger.warning("Received Square webhook without signature header")

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Missing signature"})
      end

      @doc """
      Handle generic webhook processing errors.

      Override this function to customize error responses.
      """
      def handle_error(conn, reason) do
        Logger.error("Square webhook processing failed: #{inspect(reason)}")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "Webhook processing failed"})
      end

      @doc """
      Handle missing event in assigns.

      This usually indicates a configuration issue.
      Override this function to customize the response.
      """
      def handle_missing_event(conn) do
        Logger.error("Square webhook event not found in assigns")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
      end

      # Pattern match on the webhook result from WebhookPlug
      defp handle_webhook_result(conn, {:ok, event}), do: handle_success(conn, event)

      defp handle_webhook_result(conn, {:error, :invalid_signature}),
        do: handle_invalid_signature(conn)

      defp handle_webhook_result(conn, {:error, :missing_signature}),
        do: handle_missing_signature(conn)

      defp handle_webhook_result(conn, {:error, reason}), do: handle_error(conn, reason)
      defp handle_webhook_result(conn, nil), do: handle_missing_event(conn)

      # Allow overriding any of the handlers
      defoverridable handle_success: 2,
                     handle_invalid_signature: 1,
                     handle_missing_signature: 1,
                     handle_error: 2,
                     handle_missing_event: 1
    end
  end
end
