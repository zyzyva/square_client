defmodule SquareClient.Customers do
  @moduledoc """
  Handle customer operations through the payment service.
  """

  alias SquareClient.HTTP

  @doc """
  Create a new customer.

  ## Parameters

    * `attrs` - Customer attributes:
      * `:email_address` - Customer's email (required for subscriptions)
      * `:given_name` - First name
      * `:family_name` - Last name
      * `:phone_number` - Phone number
      * `:reference_id` - Your internal customer ID

  ## Examples

      SquareClient.Customers.create(%{
        email_address: "customer@example.com",
        given_name: "John",
        family_name: "Doe"
      })
  """
  def create(attrs) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      customer: attrs
    }

    HTTP.post("/api/customers", body)
  end

  @doc """
  Retrieve a customer by ID.
  """
  def get(customer_id) do
    HTTP.get("/api/customers/#{customer_id}")
  end

  @doc """
  Search for customers.

  ## Parameters

    * `filters` - Search filters
    * `opts` - Additional options like :limit, :cursor

  ## Examples

      SquareClient.Customers.search(%{
        email_address: %{exact: "customer@example.com"}
      })
  """
  def search(filters, opts \\ []) do
    body = %{
      filter: filters
    }

    body =
      opts
      |> Keyword.take([:limit, :cursor])
      |> Enum.reduce(body, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)

    HTTP.post("/api/customers/search", body)
  end

  @doc """
  Update a customer.

  ## Parameters

    * `customer_id` - The customer ID to update
    * `updates` - Map of updates to apply

  ## Examples

      SquareClient.Customers.update("CUSTOMER_ID", %{
        given_name: "Jane"
      })
  """
  def update(customer_id, updates) do
    body = %{
      customer: updates
    }

    HTTP.put("/api/customers/#{customer_id}", body)
  end

  @doc """
  Delete a customer.
  """
  def delete(customer_id) do
    HTTP.delete("/api/customers/#{customer_id}")
  end

  @doc """
  List a customer's cards on file.
  """
  def list_cards(customer_id) do
    HTTP.get("/api/customers/#{customer_id}/cards")
  end

  @doc """
  Create a card on file for a customer.

  ## Parameters

    * `customer_id` - The customer ID
    * `source_id` - Payment source ID from Square Web Payments SDK

  ## Examples

      SquareClient.Customers.create_card("CUSTOMER_ID", "SOURCE_ID")
  """
  def create_card(customer_id, source_id) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      source_id: source_id,
      card: %{
        customer_id: customer_id
      }
    }

    HTTP.post("/api/customers/#{customer_id}/cards", body)
  end

  defp generate_idempotency_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end