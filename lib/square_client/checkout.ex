defmodule SquareClient.Checkout do
  @moduledoc """
  Square-hosted online checkout links for subscription plan variations.

  Price, currency, and product name always come from the JSON plan catalog
  (via `SquareClient.Plans`) — there is no way for a caller to supply them.
  The Square location identifier is always required from the caller, because
  it determines the merchant name Square renders as the heading of the
  hosted checkout page; this library never lists locations and picks one.
  """

  require Logger

  alias SquareClient.Plans

  # Custom guard for successful HTTP status codes
  defguardp is_success(status) when status in 200..299

  # Common request headers
  defp request_headers do
    [
      {"Authorization", "Bearer #{access_token()}"},
      {"Square-Version", "2025-01-23"}
    ]
  end

  defp api_url, do: SquareClient.Config.api_url!()

  defp access_token, do: SquareClient.Config.access_token!()

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
  Create a Square-hosted subscription checkout link for a catalog plan variation.

  ## Parameters

    * `app` - The application atom
    * `plan_key` - The plan identifier in the JSON catalog
    * `variation_key` - The variation identifier in the JSON catalog
    * `opts` - Keyword list:
      * `:location_id` - required. The Square location whose name is
        rendered as the checkout page heading.
      * `:redirect_url` - optional. Where Square sends the buyer after payment.
      * `:config_path` - optional, default `"square_plans.json"`.

  ## Examples

      SquareClient.Checkout.create_subscription_link(:my_app, "premium", "monthly",
        location_id: "LOC_ABC123",
        redirect_url: "https://myapp.com/checkout/complete"
      )
  """
  @spec create_subscription_link(atom(), String.t() | atom(), String.t() | atom(), keyword()) ::
          {:ok, %{payment_link_id: String.t(), checkout_url: String.t()}} | {:error, term()}
  def create_subscription_link(app, plan_key, variation_key, opts \\ []) do
    location_id = Keyword.get(opts, :location_id)

    with :ok <- validate_location_id(location_id),
         {:ok, resolved} <- resolve(app, plan_key, variation_key, opts) do
      do_create_subscription_link(resolved, location_id, Keyword.get(opts, :redirect_url))
    end
  end

  # Resolves the plan, variation, and Square variation ID for the current
  # environment. Returns a {plan, variation, variation_id} tuple kept opaque
  # here (not destructured) to stay within the scope-binding limit.
  defp resolve(app, plan_key, variation_key, opts) do
    with {:ok, resolved} <-
           resolve_plan_and_variation(
             app,
             plan_key,
             variation_key,
             Keyword.get(opts, :config_path, "square_plans.json")
           ),
         {:ok, variation_id} <-
           fetch_variation_id(app, plan_key, variation_key, elem(resolved, 1)) do
      {:ok, Tuple.insert_at(resolved, 2, variation_id)}
    end
  end

  defp resolve_plan_and_variation(app, plan_key, variation_key, config_path) do
    with {:ok, plan} <- fetch_plan(app, plan_key, config_path),
         {:ok, variation} <- fetch_variation(app, plan_key, variation_key, config_path),
         :ok <- validate_active(variation) do
      {:ok, {plan, variation}}
    end
  end

  defp validate_location_id(location_id) when location_id in [nil, ""] do
    Logger.error(
      "SquareClient.Checkout: location_id is required — the location determines the " <>
        "merchant name Square renders as the heading of the hosted checkout page, so it " <>
        "must be chosen deliberately. This library never guesses a location."
    )

    {:error, :location_id_required}
  end

  defp validate_location_id(_location_id), do: :ok

  defp fetch_plan(app, plan_key, config_path) do
    case Plans.get_plan(app, plan_key, config_path) do
      nil ->
        Logger.error("SquareClient.Checkout: unknown plan key #{inspect(plan_key)}")
        {:error, :unknown_plan}

      plan ->
        {:ok, plan}
    end
  end

  defp fetch_variation(app, plan_key, variation_key, config_path) do
    case Plans.get_variation(app, plan_key, variation_key, config_path) do
      nil ->
        Logger.error("SquareClient.Checkout: unknown variation key #{inspect(variation_key)}")
        {:error, :unknown_variation}

      variation ->
        {:ok, variation}
    end
  end

  defp validate_active(%{"active" => false}) do
    Logger.error("SquareClient.Checkout: variation is inactive and not for sale")
    {:error, :variation_inactive}
  end

  defp validate_active(_variation), do: :ok

  defp fetch_variation_id(_app, _plan_key, _variation_key, %{"variation_id" => variation_id})
       when is_binary(variation_id) do
    {:ok, variation_id}
  end

  defp fetch_variation_id(app, plan_key, variation_key, _variation) do
    Logger.error(
      "SquareClient.Checkout: plan #{inspect(plan_key)} variation #{inspect(variation_key)} " <>
        "has no Square variation ID for the #{Plans.environment(app)} environment — run " <>
        "mix square.setup_plans (sandbox) or mix square.setup_production (production) first"
    )

    {:error, :variation_not_provisioned}
  end

  defp do_create_subscription_link({plan, variation, variation_id}, location_id, redirect_url) do
    body = %{
      idempotency_key: generate_idempotency_key(),
      quick_pay: quick_pay(plan, variation, location_id),
      checkout_options: checkout_options(variation_id, redirect_url)
    }

    "#{api_url()}/online-checkout/payment-links"
    |> Req.post(
      Keyword.merge(
        [
          json: body,
          headers: request_headers()
        ],
        request_options()
      )
    )
    |> handle_create_payment_link_response()
  end

  defp quick_pay(plan, variation, location_id) do
    %{
      name: "#{plan["name"]} #{variation["name"]}",
      price_money: %{
        amount: variation["amount"],
        currency: variation["currency"] || "USD"
      },
      location_id: location_id
    }
  end

  defp checkout_options(variation_id, nil) do
    %{subscription_plan_id: variation_id}
  end

  defp checkout_options(variation_id, redirect_url) do
    %{subscription_plan_id: variation_id, redirect_url: redirect_url}
  end

  defp generate_idempotency_key do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp parse_error(body) when is_map(body) do
    case body["errors"] do
      [%{"detail" => detail} | _] -> detail
      _ -> "Square API error"
    end
  end

  defp parse_error(_), do: "Unknown error"

  defp handle_create_payment_link_response(
         {:ok,
          %{
            status: status,
            body: %{"payment_link" => %{"id" => payment_link_id, "url" => checkout_url}}
          }}
       )
       when is_success(status) do
    Logger.info("Created checkout payment link: #{payment_link_id}")
    {:ok, %{payment_link_id: payment_link_id, checkout_url: checkout_url}}
  end

  defp handle_create_payment_link_response({:ok, %{status: status, body: body}}) do
    Logger.error("Failed to create payment link (#{status}): #{inspect(body)}")
    {:error, parse_error(body)}
  end

  defp handle_create_payment_link_response({:error, reason}) do
    Logger.error("Failed to call Square API: #{inspect(reason)}")
    {:error, :api_unavailable}
  end
end
