defmodule SquareClient.Catalog do
  @moduledoc """
  Direct Square Catalog API integration for managing subscription plans and variations.
  Follows Square's recommended pattern: base plans with separate variations.

  Each app can use this to create and manage their own subscription plans.
  """

  require Logger

  alias SquareClient.Catalog.{BasePlan, PlanVariation}

  # Custom guard for successful HTTP status codes
  defguardp is_success(status) when status in 200..299

  # Common request headers
  defp request_headers do
    [
      {"Authorization", "Bearer #{access_token()}"},
      {"Square-Version", "2025-01-23"}
    ]
  end

  # Get API URL from config or environment
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
    # First check Application config, then fall back to env vars
    Application.get_env(:square_client, :access_token) ||
      System.get_env("SQUARE_ACCESS_TOKEN")
  end

  # Configure request options based on environment
  defp request_options do
    # Check if we're in test mode via config or env var
    if Application.get_env(:square_client, :disable_retries, false) ||
         System.get_env("SQUARE_ENVIRONMENT") == "test" do
      # Disable retries in test environment
      [retry: false]
    else
      # Default Req retry behavior
      []
    end
  end

  @doc """
  Create a base subscription plan without variations.
  This creates the container for your subscription product.

  ## Examples

      SquareClient.Catalog.create_base_subscription_plan(%{
        name: "Contacts4us Premium",
        description: "Premium features for Contacts4us"
      })

      # Or using the struct directly
      plan = SquareClient.Catalog.BasePlan.new(%{
        name: "Premium Plan",
        description: "Premium features"
      })
      SquareClient.Catalog.create_base_subscription_plan(plan)
  """
  def create_base_subscription_plan(%BasePlan{} = plan) do
    object = BasePlan.to_square_object(plan)
    do_create_base_plan(object)
  end

  def create_base_subscription_plan(attrs) when is_map(attrs) do
    attrs
    |> BasePlan.new()
    |> create_base_subscription_plan()
  end

  defp do_create_base_plan(object) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      object: object
    }

    "#{api_url()}/catalog/object"
    |> Req.post(
      Keyword.merge(
        [
          json: body,
          headers: request_headers()
        ],
        request_options()
      )
    )
    |> handle_create_base_plan_response()
  end

  @doc """
  Create a subscription plan variation for a base plan.
  This defines how the plan is sold (frequency, price, etc).

  ## Examples

      SquareClient.Catalog.create_plan_variation(%{
        base_plan_id: "ABCD1234",
        name: "Monthly",
        cadence: "MONTHLY",
        amount: 999,
        currency: "USD"
      })

      # Or using the struct directly
      variation = SquareClient.Catalog.PlanVariation.new(%{
        base_plan_id: "ABCD1234",
        name: "Monthly",
        cadence: "MONTHLY",
        amount: 999
      })
      SquareClient.Catalog.create_plan_variation(variation)
  """
  def create_plan_variation(%PlanVariation{} = variation) do
    object = PlanVariation.to_square_object(variation)
    do_create_plan_variation(object)
  end

  def create_plan_variation(attrs) when is_map(attrs) do
    attrs
    |> PlanVariation.new()
    |> create_plan_variation()
  end

  defp do_create_plan_variation(object) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      object: object
    }

    "#{api_url()}/catalog/object"
    |> Req.post(
      Keyword.merge(
        [
          json: body,
          headers: request_headers()
        ],
        request_options()
      )
    )
    |> handle_create_variation_response()
  end

  @doc """
  List all subscription plans in the catalog.
  """
  def list_subscription_plans do
    "#{api_url()}/catalog/list"
    |> Req.get(
      Keyword.merge(
        [
          params: [types: "SUBSCRIPTION_PLAN"],
          headers: request_headers()
        ],
        request_options()
      )
    )
    |> handle_list_plans_response()
  end

  @doc """
  List all subscription plan variations in the catalog.
  """
  def list_plan_variations do
    "#{api_url()}/catalog/list"
    |> Req.get(
      Keyword.merge(
        [
          params: [types: "SUBSCRIPTION_PLAN_VARIATION"],
          headers: request_headers()
        ],
        request_options()
      )
    )
    |> handle_list_variations_response()
  end

  @doc """
  Get a specific catalog object by ID.
  """
  def get(object_id) do
    "#{api_url()}/catalog/object/#{object_id}"
    |> Req.get(
      Keyword.merge(
        [
          headers: request_headers()
        ],
        request_options()
      )
    )
    |> handle_get_response()
  end

  @doc """
  Delete a catalog object.
  """
  def delete(object_id) do
    "#{api_url()}/catalog/object/#{object_id}"
    |> Req.delete(
      Keyword.merge(
        [
          headers: request_headers()
        ],
        request_options()
      )
    )
    |> handle_delete_response(object_id)
  end

  # Alias for consistency with Square API naming
  def delete_catalog_object(object_id), do: delete(object_id)

  defp generate_idempotency_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp parse_error(body) when is_map(body) do
    case body["errors"] do
      [%{"detail" => detail} | _] -> detail
      _ -> "Square API error"
    end
  end

  defp parse_error(_), do: "Unknown error"

  # Handle create variation response with pattern matching
  defp handle_create_variation_response(
         {:ok,
          %{
            status: status,
            body: %{
              "catalog_object" => %{
                "id" => variation_id,
                "subscription_plan_variation_data" => %{
                  "subscription_plan_id" => base_plan_id,
                  "name" => name,
                  "phases" => phases
                }
              }
            }
          }}
       )
       when is_success(status) do
    Logger.info("Created plan variation: #{variation_id}")

    {:ok,
     %{
       variation_id: variation_id,
       base_plan_id: base_plan_id,
       name: name,
       phases: phases
     }}
  end

  defp handle_create_variation_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to create variation (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_create_variation_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  # Handle create base plan response with pattern matching
  defp handle_create_base_plan_response(
         {:ok,
          %{
            status: status,
            body: %{
              "catalog_object" => %{
                "id" => plan_id,
                "subscription_plan_data" => %{"name" => name}
              }
            }
          }}
       )
       when is_success(status) do
    Logger.info("Created base subscription plan: #{plan_id}")

    {:ok,
     %{
       plan_id: plan_id,
       name: name,
       type: "base_plan"
     }}
  end

  defp handle_create_base_plan_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to create base plan (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_create_base_plan_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  # Handle list plans response with pattern matching
  defp handle_list_plans_response({:ok, %{status: status, body: body}})
       when is_success(status) do
    plans = body["objects"] || []

    formatted_plans =
      Enum.map(plans, fn %{
                           "id" => id,
                           "subscription_plan_data" => plan_data
                         } ->
        %{
          id: id,
          name: plan_data["name"],
          description: plan_data["description"]
        }
      end)

    {:ok, formatted_plans}
  end

  defp handle_list_plans_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to list plans (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_list_plans_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  # Handle list variations response with pattern matching
  defp handle_list_variations_response({:ok, %{status: status, body: body}})
       when is_success(status) do
    variations = body["objects"] || []

    formatted_variations =
      Enum.map(variations, fn %{
                                "id" => variation_id,
                                "subscription_plan_variation_data" => %{
                                  "subscription_plan_id" => base_plan_id,
                                  "name" => name,
                                  "phases" => phases
                                }
                              } ->
        %{
          variation_id: variation_id,
          base_plan_id: base_plan_id,
          name: name,
          phases: phases
        }
      end)

    {:ok, formatted_variations}
  end

  defp handle_list_variations_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to list variations (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_list_variations_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  # Handle get response with pattern matching
  defp handle_get_response({:ok, %{status: status, body: body}})
       when is_success(status) do
    {:ok, body["object"]}
  end

  defp handle_get_response({:ok, %{status: 404}}) do
    {:error, :not_found}
  end

  defp handle_get_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to get object (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_get_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end

  # Handle delete response with pattern matching
  defp handle_delete_response({:ok, %{status: status}}, object_id)
       when is_success(status) do
    Logger.info("Deleted catalog object: #{object_id}")
    {:ok, :deleted}
  end

  defp handle_delete_response({:ok, %{status: 404}}, _object_id) do
    {:error, :not_found}
  end

  defp handle_delete_response({:ok, %{status: status, body: body}}, _object_id) do
    Logger.error("Failed to delete object (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_delete_response({:error, reason}, _object_id) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end
end
