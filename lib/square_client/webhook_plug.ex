defmodule SquareClient.WebhookPlug do
  @moduledoc """
  Standard webhook plug for Square webhook endpoints.

  This plug handles the common tasks for Square webhooks:
  - Extracting and verifying signatures
  - Parsing events
  - Routing to your handler
  - Standardized responses

  ## Usage in your Phoenix app

  In your router:

      pipeline :square_webhook do
        plug :accepts, ["json"]
        plug SquareClient.WebhookPlug
      end

      scope "/webhooks", MyAppWeb do
        pipe_through :square_webhook
        post "/square", SquareWebhookController, :handle
      end

  Then create a minimal controller:

      defmodule MyAppWeb.SquareWebhookController do
        use MyAppWeb, :controller

        def handle(conn, _params) do
          # Event is already verified and parsed in conn.assigns.square_event
          case conn.assigns.square_event do
            {:ok, event} ->
              # Event has been handled by your configured handler
              json(conn, %{received: true})

            {:error, :invalid_signature} ->
              conn
              |> put_status(:unauthorized)
              |> json(%{error: "Invalid signature"})

            {:error, reason} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid webhook"})
          end
        end
      end
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, body} <- read_request_body(conn),
         {:ok, signature} <- get_signature(conn),
         :ok <- verify_signature(body, signature),
         {:ok, event} <- parse_event(body) do
      # Always handle the event but don't fail if the handler returns an error
      handle_event(event)
      assign(conn, :square_event, {:ok, event})
    else
      {:error, :missing_signature} = error ->
        Logger.warning("Square webhook missing signature")
        assign(conn, :square_event, error)

      {:error, :invalid_signature} = error ->
        Logger.warning("Square webhook invalid signature")
        assign(conn, :square_event, error)

      {:error, reason} = error ->
        Logger.error("Square webhook error: #{inspect(reason)}")
        assign(conn, :square_event, error)
    end
  end

  defp get_signature(conn) do
    get_req_header(conn, "x-square-hmacsha256-signature")
    |> handle_signature_header()
  end

  defp handle_signature_header([signature]) when is_binary(signature), do: {:ok, signature}
  defp handle_signature_header([]), do: {:error, :missing_signature}
  defp handle_signature_header(_), do: {:error, :invalid_signature}

  defp read_request_body(conn) do
    {:ok, body, _conn} = read_body(conn)
    {:ok, body}
  rescue
    _ -> {:error, :body_read_error}
  end

  defp verify_signature(body, signature) do
    signature_key = get_signature_key()

    cond do
      is_nil(signature_key) ->
        Logger.error("Square webhook signature key not configured")
        {:error, :signature_key_not_configured}

      SquareClient.Webhooks.verify_signature(body, signature, signature_key) ->
        :ok

      true ->
        {:error, :invalid_signature}
    end
  end

  defp parse_event(body) do
    SquareClient.Webhooks.parse_event(body)
  end

  defp handle_event(event) do
    handler = get_webhook_handler()

    cond do
      is_nil(handler) ->
        Logger.warning("No Square webhook handler configured, skipping event processing")
        :ok

      not is_atom(handler) ->
        Logger.error("Invalid webhook handler configuration: #{inspect(handler)}")
        {:error, :invalid_handler}

      true ->
        apply(handler, :handle_event, [event])
    end
  rescue
    error ->
      Logger.error("Webhook handler error: #{inspect(error)}")
      {:error, :handler_error}
  end

  defp get_signature_key do
    Application.get_env(:square_client, :webhook_signature_key) ||
      System.get_env("SQUARE_WEBHOOK_SIGNATURE_KEY")
  end

  defp get_webhook_handler do
    Application.get_env(:square_client, :webhook_handler)
  end
end
