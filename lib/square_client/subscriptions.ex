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

  defp api_url do
    case Application.get_env(:square_client, :api_url) do
      nil ->
        # Only fall back to environment variables if not explicitly set to nil
        # This prevents tests from accidentally using real APIs
        case System.get_env("SQUARE_ENVIRONMENT") do
          "test" -> raise "Square API URL must be configured in test environment"
          "production" -> "https://connect.squareup.com/v2"
          _ -> "https://connect.squareupsandbox.com/v2"
        end

      url ->
        url
    end
  end

  defp access_token do
    Application.get_env(:square_client, :access_token) ||
      System.get_env("SQUARE_ACCESS_TOKEN")
  end

  defp location_id do
    Application.get_env(:square_client, :location_id) ||
      System.get_env("SQUARE_LOCATION_ID")
  end

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
