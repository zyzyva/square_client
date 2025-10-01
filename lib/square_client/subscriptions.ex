defmodule SquareClient.Subscriptions do
  @moduledoc """
  Square Subscriptions API client.

  Provides subscription management operations including:
  - Creating subscriptions
  - Retrieving subscription details
  - Canceling subscriptions
  - Managing subscription updates
  """

  require Logger

  defp api_url, do: SquareClient.Config.api_url!()
  defp access_token, do: SquareClient.Config.access_token!()

  defp location_id, do: SquareClient.Config.location_id!()

  defp request_headers do
    [
      {"Authorization", "Bearer #{access_token()}"},
      {"Square-Version", "2025-01-23"},
      {"Content-Type", "application/json"}
    ]
  end

  defp request_options do
    if Application.get_env(:square_client, :disable_retries, false) ||
         System.get_env("SQUARE_ENVIRONMENT") == "test" do
      [retry: false]
    else
      [
        retry: :transient,
        retry_delay: fn attempt -> attempt * 100 end,
        max_retries: 3,
        receive_timeout: 30_000,
        connect_options: [timeout: 10_000]
      ]
    end
  end

  @doc """
  Create a subscription.

  ## Parameters

    * `customer_id` - Square customer ID
    * `plan_variation_id` - Square plan variation ID
    * `card_id` - Square card ID (saved card on file)

  ## Examples

      SquareClient.Subscriptions.create("CUSTOMER_ID", "PLAN_ID", "CARD_ID")
  """
  def create(customer_id, plan_variation_id, card_id) do
    # If card_id is a nonce (starts with cnon:), save it as a card first
    with {:ok, saved_card_id} <- ensure_card_saved(customer_id, card_id) do
      body = %{
        location_id: location_id(),
        customer_id: customer_id,
        plan_variation_id: plan_variation_id,
        card_id: saved_card_id
      }

      "#{api_url()}/subscriptions"
      |> Req.post(
        Keyword.merge(
          [json: body, headers: request_headers()],
          request_options()
        )
      )
      |> handle_subscription_response()
    end
  end

  @doc """
  Create a subscription with plan lookup by key.

  This is a higher-level function that:
  1. Looks up the Square plan variation ID from the app's configuration
  2. Creates the subscription with proper error handling

  ## Parameters
  - customer_id: Square customer ID
  - plan_variation_key: Plan key like "premium_monthly" or "premium_yearly"
  - card_token: Card ID or nonce for payment
  - opts: Options including:
    - :app_name - Override app name for plan lookup (defaults to current app)

  ## Examples
      iex> create_with_plan_lookup("cust_123", "premium_monthly", "card_456")
      {:ok, %{...subscription...}}

      iex> create_with_plan_lookup("cust_123", "invalid_plan", "card_456")
      {:error, {:configuration_error, "Subscription plan not properly configured"}}
  """
  def create_with_plan_lookup(customer_id, plan_variation_key, card_token, opts \\ []) do
    app_name = opts[:app_name] || infer_app_name()

    with {:ok, plan_variation_id} <- get_plan_variation_id(app_name, plan_variation_key),
         {:ok, subscription} <- create(customer_id, plan_variation_id, card_token) do
      {:ok, subscription}
    else
      {:error, :plan_not_found} ->
        Logger.error("Square plan ID not configured for plan: #{plan_variation_key}")
        {:error, {:configuration_error, "Subscription plan not properly configured"}}

      {:error, {:card_declined, message}} ->
        Logger.error("Card declined: #{message}")
        {:error, {:card_declined, message}}

      {:error, {:card_save_failed, reason}} ->
        Logger.error("Failed to save card: #{inspect(reason)}")
        {:error, {:card_save_failed, reason}}

      {:error, message} when is_binary(message) ->
        # API error with detail message from Square
        Logger.error("Square API error: #{message}")
        {:error, message}

      {:error, reason} ->
        Logger.error("Failed to create subscription: #{inspect(reason)}")
        {:error, :subscription_failed}
    end
  end

  @doc """
  Get Square plan variation ID for a given plan key.

  Parses the plan key to extract plan and variation components,
  then looks up the Square ID from the app's configuration.
  """
  def get_plan_variation_id(app_name, plan_variation_key) do
    {plan_key, variation_key} = parse_plan_variation_key(plan_variation_key)

    case SquareClient.Plans.get_variation_id(app_name, plan_key, variation_key) do
      nil -> {:error, :plan_not_found}
      id -> {:ok, id}
    end
  end

  @doc """
  Parse a plan variation key into plan and variation components.

  ## Examples
      iex> parse_plan_variation_key("premium_monthly")
      {"premium", "monthly"}

      iex> parse_plan_variation_key(:premium_yearly)
      {"premium", "yearly"}

      iex> parse_plan_variation_key("basic")
      {"basic", "default"}
  """
  def parse_plan_variation_key(key) do
    key_str = to_string(key)

    case String.split(key_str, "_", parts: 2) do
      [plan, variation] -> {plan, variation}
      [plan] -> {plan, "default"}
    end
  end

  # Infer the app name from configuration or application environment
  defp infer_app_name do
    # Try multiple sources in order of preference
    cond do
      # Explicit configuration
      app_name = Application.get_env(:square_client, :app_name) ->
        app_name

      # OTP app configuration
      otp_app = Application.get_env(:square_client, :otp_app) ->
        otp_app

      # Mix project (works in dev/test)
      Code.ensure_loaded?(Mix.Project) && Mix.Project.config()[:app] ->
        Mix.Project.config()[:app]

      # No fallback - require explicit configuration
      true ->
        raise "Cannot infer app name. Please set :app_name in square_client config"
    end
  end

  @doc """
  Get subscription details.
  """
  def get(subscription_id) do
    "#{api_url()}/subscriptions/#{subscription_id}"
    |> Req.get(
      Keyword.merge(
        [headers: request_headers()],
        request_options()
      )
    )
    |> handle_response()
  end

  @doc """
  Cancel a subscription.
  """
  def cancel(subscription_id) do
    "#{api_url()}/subscriptions/#{subscription_id}/cancel"
    |> Req.post(
      Keyword.merge(
        [json: %{}, headers: request_headers()],
        request_options()
      )
    )
    |> handle_response()
  end

  defp ensure_card_saved(customer_id, card_id_or_nonce) do
    if String.starts_with?(card_id_or_nonce, "cnon:") do
      # It's a nonce, save it as a card
      case SquareClient.Customers.create_card(customer_id, card_id_or_nonce) do
        {:ok, %{"card" => card}} ->
          Logger.info("Saved card on file: #{card["id"]}")
          {:ok, card["id"]}

        {:error, reason} ->
          Logger.error("Failed to save card: #{inspect(reason)}")
          {:error, {:card_save_failed, reason}}
      end
    else
      # It's already a saved card ID
      {:ok, card_id_or_nonce}
    end
  end

  defp handle_subscription_response(result) do
    case result do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body["subscription"]}

      {:ok, %{status: 402, body: body}} ->
        # Payment required - card was declined
        Logger.error("Square API error (402): #{inspect(body)}")
        error_msg = parse_error(body)
        {:error, {:card_declined, error_msg}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Square API error (#{status}): #{inspect(body)}")
        {:error, parse_error(body)}

      {:error, reason} ->
        Logger.error("Square API request failed: #{inspect(reason)}")
        {:error, :api_unavailable}
    end
  end

  defp handle_response(result) do
    case result do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 404, body: _body}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Square API error (#{status}): #{inspect(body)}")
        {:error, parse_error(body)}

      {:error, reason} ->
        Logger.error("Square API request failed: #{inspect(reason)}")
        {:error, :api_unavailable}
    end
  end

  defp parse_error(body) when is_map(body) do
    case body["errors"] do
      [%{"detail" => detail} | _] -> detail
      _ -> "Square API error"
    end
  end

  defp parse_error(_), do: "Unknown error"
end
