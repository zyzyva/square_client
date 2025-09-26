defmodule SquareClient.Customers do
  @moduledoc """
  Square Customers API client.

  Provides customer management operations including:
  - Creating customers
  - Retrieving customer details
  - Updating customer information
  - Managing customer cards
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
  Create a new Square customer.

  ## Parameters

    * `customer_data` - Map containing customer information:
      * `:email_address` - Customer's email
      * `:reference_id` - Your internal reference ID
      * `:given_name` - Customer's first name
      * `:family_name` - Customer's last name
      * `:phone_number` - Customer's phone number
      * `:note` - Optional note about the customer

  ## Examples

      SquareClient.Customers.create(%{
        email_address: "john@example.com",
        reference_id: "user_123",
        given_name: "John",
        family_name: "Doe"
      })
  """
  def create(customer_data) do
    body =
      %{
        email_address: customer_data[:email_address],
        reference_id: customer_data[:reference_id],
        given_name: customer_data[:given_name],
        family_name: customer_data[:family_name],
        phone_number: customer_data[:phone_number],
        note: customer_data[:note] || "Created via SquareClient"
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    "#{api_url()}/customers"
    |> Req.post(
      Keyword.merge(
        [json: body, headers: request_headers()],
        request_options()
      )
    )
    |> handle_response()
  end

  @doc """
  Get customer details by ID.
  """
  def get(customer_id) do
    "#{api_url()}/customers/#{customer_id}"
    |> Req.get(
      Keyword.merge(
        [headers: request_headers()],
        request_options()
      )
    )
    |> handle_response()
  end

  @doc """
  Create a card on file for a customer.
  """
  def create_card(customer_id, card_nonce) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      source_id: card_nonce,
      card: %{
        customer_id: customer_id
      }
    }

    "#{api_url()}/cards"
    |> Req.post(
      Keyword.merge(
        [json: body, headers: request_headers()],
        request_options()
      )
    )
    |> handle_response()
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

  defp generate_idempotency_key do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
