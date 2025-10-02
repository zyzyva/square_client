defmodule SquareClient.Config do
  @moduledoc """
  Configuration validation for SquareClient.

  This module validates that required configuration is present at compile time
  when possible, and provides helpful error messages.

  ## Required Configuration

  Add to your config files:

      # config/dev.exs
      config :square_client,
        api_url: "https://connect.squareupsandbox.com/v2",
        access_token: System.get_env("SQUARE_ACCESS_TOKEN"),
        location_id: System.get_env("SQUARE_LOCATION_ID")

      # config/prod.exs
      config :square_client,
        api_url: "https://connect.squareup.com/v2",
        access_token: System.get_env("SQUARE_ACCESS_TOKEN"),
        location_id: System.get_env("SQUARE_LOCATION_ID")

  ## Validation

  To validate configuration at compile time in your application, add to your
  application.ex or a module that gets compiled early:

      defmodule MyApp.Application do
        use Application

        # Validate Square config at compile time
        SquareClient.Config.validate!()

        def start(_type, _args) do
          # Validate again at runtime to catch missing env vars
          SquareClient.Config.validate_runtime!()
          # ...
        end
      end
  """

  @doc """
  Validate configuration at compile time.

  Checks that api_url is configured. Cannot check runtime env vars.
  Raises CompileError if configuration is invalid.
  """
  defmacro validate! do
    quote do
      case Application.compile_env(:square_client, :api_url) do
        nil ->
          raise CompileError,
            description: """
            SquareClient API URL is not configured.

            Add this to your config/dev.exs:
              config :square_client,
                api_url: "https://connect.squareupsandbox.com/v2"

            Add this to your config/prod.exs:
              config :square_client,
                api_url: "https://connect.squareup.com/v2"

            See SquareClient.Config for more details.
            """

        url when is_binary(url) ->
          :ok

        other ->
          raise CompileError,
            description: """
            SquareClient API URL must be a string, got: #{inspect(other)}

            Valid values:
              - "https://connect.squareupsandbox.com/v2" (for sandbox)
              - "https://connect.squareup.com/v2" (for production)
            """
      end
    end
  end

  @doc """
  Validate configuration at runtime.

  Checks that all required configuration is present, including environment
  variables that may not be available at compile time.

  Returns :ok or raises RuntimeError with helpful message.
  """
  def validate_runtime! do
    errors =
      []
      |> validate_api_url()
      |> validate_access_token()
      |> validate_location_id()
      |> validate_webhook_handler()

    case errors do
      [] ->
        :ok

      errors ->
        raise """
        SquareClient configuration is invalid:

        #{Enum.map_join(errors, "\n", fn err -> "  • #{err}" end)}

        Required configuration:

          config :square_client,
            api_url: "https://connect.squareupsandbox.com/v2",  # or production URL
            access_token: System.get_env("SQUARE_ACCESS_TOKEN"),
            location_id: System.get_env("SQUARE_LOCATION_ID"),
            webhook_handler: MyApp.Payments.SquareWebhookHandler  # if using webhooks

        Environment variables:
          SQUARE_ACCESS_TOKEN - Your Square API access token (required)
          SQUARE_LOCATION_ID - Your Square location ID (required)

        Get these from: https://developer.squareup.com/apps
        """
    end
  end

  @doc """
  Get the configured API URL.

  Returns the URL or raises with a helpful error message.
  """
  def api_url! do
    Application.get_env(:square_client, :api_url) ||
      raise """
      Square API URL is not configured.

      Add to config/dev.exs:
        config :square_client, api_url: "https://connect.squareupsandbox.com/v2"

      Add to config/prod.exs:
        config :square_client, api_url: "https://connect.squareup.com/v2"
      """
  end

  @doc """
  Get the configured access token.

  Returns the token or raises with a helpful error message.
  """
  def access_token! do
    Application.get_env(:square_client, :access_token) ||
      System.get_env("SQUARE_ACCESS_TOKEN") ||
      raise """
      Square access token is not configured.

      Set the SQUARE_ACCESS_TOKEN environment variable or add to your config:
        config :square_client, access_token: System.get_env("SQUARE_ACCESS_TOKEN")

      Get your access token from: https://developer.squareup.com/apps
      """
  end

  @doc """
  Get the configured location ID.

  Returns the location ID or raises with a helpful error message.
  """
  def location_id! do
    Application.get_env(:square_client, :location_id) ||
      System.get_env("SQUARE_LOCATION_ID") ||
      raise """
      Square location ID is not configured.

      Set the SQUARE_LOCATION_ID environment variable or add to your config:
        config :square_client, location_id: System.get_env("SQUARE_LOCATION_ID")

      Get your location ID from: https://developer.squareup.com/apps
      """
  end

  @doc """
  Check if configuration is valid without raising.

  Returns {:ok, config} or {:error, reasons}.
  """
  def check do
    with {:ok, api_url} <- check_api_url(),
         {:ok, access_token} <- check_access_token(),
         {:ok, location_id} <- check_location_id() do
      {:ok, %{api_url: api_url, access_token: access_token, location_id: location_id}}
    else
      {:error, reasons} when is_list(reasons) -> {:error, reasons}
      {:error, reason} -> {:error, [reason]}
    end
  end

  defp check_api_url do
    case Application.get_env(:square_client, :api_url) do
      nil -> {:error, "API URL not configured"}
      url when is_binary(url) -> {:ok, url}
      _ -> {:error, "API URL must be a string"}
    end
  end

  defp check_access_token do
    case Application.get_env(:square_client, :access_token) ||
           System.get_env("SQUARE_ACCESS_TOKEN") do
      nil -> {:error, "Access token not configured"}
      token when is_binary(token) and byte_size(token) > 0 -> {:ok, token}
      _ -> {:error, "Access token must be a non-empty string"}
    end
  end

  defp check_location_id do
    case Application.get_env(:square_client, :location_id) ||
           System.get_env("SQUARE_LOCATION_ID") do
      nil -> {:error, "Location ID not configured"}
      id when is_binary(id) and byte_size(id) > 0 -> {:ok, id}
      _ -> {:error, "Location ID must be a non-empty string"}
    end
  end

  defp validate_api_url(errors) do
    case Application.get_env(:square_client, :api_url) do
      nil -> ["API URL is not configured. Add :api_url to your config :square_client" | errors]
      url when is_binary(url) -> errors
      _ -> ["API URL must be a string" | errors]
    end
  end

  defp validate_access_token(errors) do
    case Application.get_env(:square_client, :access_token) || System.get_env("SQUARE_ACCESS_TOKEN") do
      nil ->
        ["Access token is not configured. Set SQUARE_ACCESS_TOKEN environment variable or configure :access_token" | errors]

      token when is_binary(token) and byte_size(token) > 0 ->
        errors

      _ ->
        ["Access token must be a non-empty string" | errors]
    end
  end

  defp validate_location_id(errors) do
    case Application.get_env(:square_client, :location_id) || System.get_env("SQUARE_LOCATION_ID") do
      nil ->
        ["Location ID is not configured. Set SQUARE_LOCATION_ID environment variable or configure :location_id" | errors]

      location_id when is_binary(location_id) and byte_size(location_id) > 0 ->
        errors

      _ ->
        ["Location ID must be a non-empty string" | errors]
    end
  end

  defp validate_webhook_handler(errors) do
    case Application.get_env(:square_client, :webhook_handler) do
      nil ->
        ["Webhook handler is not configured. Add :webhook_handler to your config :square_client if you use webhooks" | errors]

      handler when is_atom(handler) ->
        validate_webhook_module(handler, errors)

      _ ->
        ["Webhook handler must be a module name (atom)" | errors]
    end
  end

  defp validate_webhook_module(handler, errors) do
    cond do
      not Code.ensure_loaded?(handler) ->
        ["Webhook handler module #{inspect(handler)} does not exist or is not loaded" | errors]

      not function_exported?(handler, :handle_event, 1) ->
        ["Webhook handler #{inspect(handler)} must implement handle_event/1" | errors]

      true ->
        errors
    end
  end
end
