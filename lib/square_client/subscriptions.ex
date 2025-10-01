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
    * `opts` - Optional parameters:
      * `:start_date` - Future start date in "YYYY-MM-DD" format. Subscription will be PENDING until this date.

  ## Examples

      SquareClient.Subscriptions.create("CUSTOMER_ID", "PLAN_ID", "CARD_ID")
      SquareClient.Subscriptions.create("CUSTOMER_ID", "PLAN_ID", "CARD_ID", start_date: "2025-10-15")
  """
  def create(customer_id, plan_variation_id, card_id, opts \\ []) do
    # If card_id is a nonce (starts with cnon:), save it as a card first
    with {:ok, saved_card_id} <- ensure_card_saved(customer_id, card_id) do
      body = %{
        location_id: location_id(),
        customer_id: customer_id,
        plan_variation_id: plan_variation_id,
        card_id: saved_card_id
      }

      # Add start_date if provided
      body =
        case Keyword.get(opts, :start_date) do
          nil -> body
          start_date -> Map.put(body, :start_date, start_date)
        end

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
    - :start_date - Future start date in "YYYY-MM-DD" format (subscription will be PENDING)

  ## Examples
      iex> create_with_plan_lookup("cust_123", "premium_monthly", "card_456")
      {:ok, %{...subscription...}}

      iex> create_with_plan_lookup("cust_123", "premium_monthly", "card_456", start_date: "2025-10-15")
      {:ok, %{...subscription with PENDING status...}}

      iex> create_with_plan_lookup("cust_123", "invalid_plan", "card_456")
      {:error, {:configuration_error, "Subscription plan not properly configured"}}
  """
  def create_with_plan_lookup(customer_id, plan_variation_key, card_token, opts \\ []) do
    app_name = opts[:app_name] || infer_app_name()

    # Extract start_date if provided
    create_opts = if opts[:start_date], do: [start_date: opts[:start_date]], else: []

    with {:ok, plan_variation_id} <- get_plan_variation_id(app_name, plan_variation_key),
         {:ok, subscription} <- create(customer_id, plan_variation_id, card_token, create_opts) do
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

  For ACTIVE subscriptions, Square cancels at the end of the current billing period.
  For PENDING subscriptions, Square cancels immediately.
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

  @doc """
  Upgrade or change a subscription plan, preserving paid time.

  This function handles the common upgrade/downgrade scenario:
  1. If there's an existing subscription, it cancels it
  2. Calculates when the new subscription should start (day after current access ends)
  3. Creates the new subscription with the deferred start date

  ## Parameters
  - `customer_id` - Square customer ID
  - `new_plan_variation_key` - The plan to upgrade/downgrade to
  - `card_token` - Card ID or nonce for payment
  - `opts` - Options:
    - `:current_access_ends_at` - When current paid access ends (DateTime, Date, or date string)
    - `:subscription_to_cancel` - Square subscription ID to cancel before creating new one
    - `:app_name` - App name for plan lookup

  ## Returns
  - `{:ok, new_subscription}` - New subscription created
  - `{:error, reason}` - Failed to create subscription

  ## Examples
      # Upgrade from 7-day pass to monthly
      SquareClient.Subscriptions.upgrade_subscription(
        "customer_123",
        "premium_monthly",
        "card_456",
        current_access_ends_at: ~U[2025-10-07 00:00:00Z]
      )

      # Upgrade from monthly to yearly
      SquareClient.Subscriptions.upgrade_subscription(
        "customer_123",
        "premium_yearly",
        "card_456",
        current_access_ends_at: ~U[2025-11-15 00:00:00Z],
        subscription_to_cancel: "sub_monthly_123"
      )
  """
  def upgrade_subscription(customer_id, new_plan_variation_key, card_token, opts \\ []) do
    subscription_to_cancel = opts[:subscription_to_cancel]
    current_access_ends_at = opts[:current_access_ends_at]
    app_name = opts[:app_name]

    # Cancel existing subscription if present
    if subscription_to_cancel do
      Logger.info("Canceling existing subscription #{subscription_to_cancel} for upgrade")

      case cancel(subscription_to_cancel) do
        {:ok, _} ->
          Logger.info("Canceled subscription #{subscription_to_cancel}")

        {:error, reason} ->
          Logger.warning("Failed to cancel subscription, continuing anyway: #{inspect(reason)}")
      end
    end

    # Calculate start date for new subscription
    start_date = calculate_deferred_start_date(current_access_ends_at)

    # Create new subscription
    create_opts = [app_name: app_name]

    create_opts =
      if start_date, do: Keyword.put(create_opts, :start_date, start_date), else: create_opts

    create_with_plan_lookup(customer_id, new_plan_variation_key, card_token, create_opts)
  end

  @doc """
  Calculate when a new subscription should start based on when current access ends.

  Returns the start date as a string in "YYYY-MM-DD" format, or nil if subscription
  should start immediately.

  ## Parameters
  - `current_access_ends_at` - When the user's current paid access ends
    - Can be DateTime, Date, or date string ("YYYY-MM-DD")
    - If nil or in the past, returns nil (start immediately)
    - If in the future, returns day after as "YYYY-MM-DD"

  ## Examples
      iex> calculate_deferred_start_date(~U[2025-10-07 23:59:59Z])
      "2025-10-08"

      iex> calculate_deferred_start_date(nil)
      nil

      iex> calculate_deferred_start_date(~U[2020-01-01 00:00:00Z])
      nil
  """
  def calculate_deferred_start_date(nil), do: nil

  def calculate_deferred_start_date(access_ends_at) do
    now = DateTime.utc_now()
    ends_at_datetime = to_datetime(access_ends_at)

    if DateTime.compare(ends_at_datetime, now) == :gt do
      # Access ends in the future - start day after
      ends_at_datetime
      |> DateTime.add(1, :day)
      |> DateTime.to_date()
      |> Date.to_string()
    else
      # Access already ended or ending now - start immediately
      nil
    end
  end

  # Convert various date/datetime types to DateTime
  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%Date{} = d), do: DateTime.new!(d, ~T[00:00:00], "Etc/UTC")

  defp to_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} ->
        dt

      _ ->
        case Date.from_iso8601(string) do
          {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          _ -> DateTime.utc_now()
        end
    end
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
