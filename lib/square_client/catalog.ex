defmodule SquareClient.Catalog do
  @moduledoc """
  Handle catalog operations for subscription plans through the payment service.
  """

  alias SquareClient.HTTP

  @doc """
  Create a subscription plan in the catalog.

  ## Parameters

    * `plan` - Plan details:
      * `:name` - Plan name
      * `:phases` - List of subscription phases with pricing

  ## Examples

      SquareClient.Catalog.create_subscription_plan(%{
        name: "Premium Monthly",
        phases: [
          %{
            cadence: "MONTHLY",
            recurring_price_money: %{
              amount: 999,
              currency: "USD"
            }
          }
        ]
      })
  """
  def create_subscription_plan(plan) do
    object = %{
      type: "SUBSCRIPTION_PLAN",
      id: "#plan",
      subscription_plan_data: plan
    }

    body = %{
      idempotency_key: generate_idempotency_key(),
      object: object
    }

    HTTP.post("/api/catalog/plans", body)
  end

  @doc """
  List subscription plans.

  ## Options

    * `:cursor` - Pagination cursor
    * `:limit` - Number of results

  ## Examples

      {:ok, plans} = SquareClient.Catalog.list_subscription_plans()
  """
  def list_subscription_plans(opts \\ []) do
    query = build_query_params([types: "SUBSCRIPTION_PLAN"] ++ opts)
    HTTP.get("/api/catalog/plans#{query}")
  end

  @doc """
  Get a specific catalog object by ID.
  """
  def get(object_id) do
    HTTP.get("/api/catalog/plans/#{object_id}")
  end

  @doc """
  Update a catalog object.

  ## Parameters

    * `object_id` - The catalog object ID
    * `updates` - Map of updates

  ## Examples

      SquareClient.Catalog.update("PLAN_ID", %{
        subscription_plan_data: %{
          name: "Premium Monthly (Updated)"
        }
      })
  """
  def update(object_id, updates) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      object: Map.put(updates, :id, object_id)
    }

    HTTP.post("/api/catalog/plans", body)
  end

  @doc """
  Delete a catalog object.
  """
  def delete(object_id) do
    HTTP.delete("/api/catalog/plans/#{object_id}")
  end

  @doc """
  Search the catalog with filters.

  ## Parameters

    * `query` - Search query map
    * `opts` - Additional options

  ## Examples

      SquareClient.Catalog.search(%{
        filter: %{
          type_filter: %{types: ["SUBSCRIPTION_PLAN"]},
          enabled_location_ids: ["LOCATION_ID"]
        }
      })
  """
  def search(query, opts \\ []) do
    body = Map.merge(query, Map.new(opts))
    HTTP.post("/api/catalog/search", body)
  end

  defp generate_idempotency_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp build_query_params([]), do: ""

  defp build_query_params(opts) do
    params =
      opts
      |> Enum.map(fn {key, value} ->
        case value do
          v when is_list(v) ->
            "#{key}=#{Enum.join(v, ",")}"

          v ->
            "#{key}=#{URI.encode(to_string(v))}"
        end
      end)
      |> Enum.join("&")

    "?#{params}"
  end
end