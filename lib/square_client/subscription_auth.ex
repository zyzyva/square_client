defmodule SquareClient.SubscriptionAuth do
  @moduledoc """
  Plug and helpers for subscription-based access control.

  Provides plugs and LiveView hooks for enforcing subscription requirements
  on routes and LiveView pages.

  ## Usage in Router

      import SquareClient.SubscriptionAuth

      # Require any premium subscription
      pipe_through [:browser, :require_authenticated_user, :require_premium_subscription]

      # Require specific plan
      plug :require_specific_plan, plan: "premium_yearly"

      # Require specific feature
      plug :require_feature, feature: :api_access

  ## Usage in LiveView

      live_session :premium_features,
        on_mount: [
          {MyAppWeb.UserAuth, :ensure_authenticated},
          {SquareClient.SubscriptionAuth, :require_premium}
        ] do
        live "/analytics", AnalyticsLive, :index
      end
  """

  import Plug.Conn

  # Compile-time check for Phoenix availability

  @doc """
  Plug that requires user to have an active premium subscription.

  Options:
    * `:payments_module` - The payments context module (required)
    * `:redirect_to` - Path to redirect to if not subscribed (default: "/subscription")
    * `:message` - Flash message to show (optional)
  """
  def require_premium_subscription(conn, opts) do
    payments_module = Keyword.fetch!(opts, :payments_module)
    redirect_path = Keyword.get(opts, :redirect_to, "/subscription")
    message = Keyword.get(opts, :message, "This feature requires a premium subscription")

    user = conn.assigns[:current_user] || get_in(conn.assigns, [:current_scope, :user])

    if user && payments_module.has_premium?(user) do
      conn
    else
      conn
      |> put_flash_if_available(:error, message)
      |> redirect_if_available(to: redirect_path)
      |> halt()
    end
  end

  @doc """
  Plug that requires user to have a specific subscription plan.

  Options:
    * `:payments_module` - The payments context module (required)
    * `:plan` - The required plan ID (required)
    * `:redirect_to` - Path to redirect to if not subscribed (default: "/subscription")
    * `:message` - Flash message to show (optional)
  """
  def require_specific_plan(conn, opts) do
    payments_module = Keyword.fetch!(opts, :payments_module)
    required_plan = Keyword.fetch!(opts, :plan)
    redirect_path = Keyword.get(opts, :redirect_to, "/subscription")
    message = Keyword.get(opts, :message, "This feature requires the #{required_plan} plan")

    user = conn.assigns[:current_user] || get_in(conn.assigns, [:current_scope, :user])

    if user && payments_module.has_plan?(user, required_plan) do
      conn
    else
      conn
      |> put_flash_if_available(:error, message)
      |> redirect_if_available(to: redirect_path)
      |> halt()
    end
  end

  @doc """
  Plug that requires user to have a specific feature enabled.

  Features are determined by the subscription plan configuration.

  Options:
    * `:payments_module` - The payments context module (required)
    * `:feature` - The required feature atom (required)
    * `:redirect_to` - Path to redirect to if not subscribed (default: "/subscription")
    * `:message` - Flash message to show (optional)
  """
  def require_feature(conn, opts) do
    payments_module = Keyword.fetch!(opts, :payments_module)
    required_feature = Keyword.fetch!(opts, :feature)
    redirect_path = Keyword.get(opts, :redirect_to, "/subscription")
    message = Keyword.get(opts, :message, "This feature requires an upgraded subscription")

    user = conn.assigns[:current_user] || get_in(conn.assigns, [:current_scope, :user])

    if user && payments_module.has_feature?(user, required_feature) do
      conn
    else
      conn
      |> put_flash_if_available(:error, message)
      |> redirect_if_available(to: redirect_path)
      |> halt()
    end
  end

  @doc """
  API plug that returns 402 Payment Required for subscription-gated endpoints.

  Options:
    * `:payments_module` - The payments context module (required)
    * `:message` - Error message to return (optional)
  """
  def require_api_access(conn, opts) do
    payments_module = Keyword.fetch!(opts, :payments_module)
    message = Keyword.get(opts, :message, "API access requires premium subscription")

    user = conn.assigns[:current_user] || conn.assigns[:api_user]

    if user && payments_module.has_premium?(user) do
      conn
    else
      conn
      |> put_status(:payment_required)
      |> json_if_available(%{
        error: message,
        upgrade_url: "/subscription"
      })
      |> halt()
    end
  end

  @doc """
  Assigns subscription status to conn for use in templates.

  Adds the following assigns:
    * `:has_premium?` - Boolean indicating premium status
    * `:current_plan` - Current subscription plan ID or "free"
    * `:subscription` - The active subscription record (if any)

  Options:
    * `:payments_module` - The payments context module (required)
  """
  def assign_subscription_status(conn, opts) do
    payments_module = Keyword.fetch!(opts, :payments_module)
    user = conn.assigns[:current_user] || get_in(conn.assigns, [:current_scope, :user])

    if user do
      subscription = payments_module.get_active_subscription(user)

      conn
      |> assign(:has_premium?, payments_module.has_premium?(user))
      |> assign(:current_plan, payments_module.get_current_plan(user))
      |> assign(:subscription, subscription)
    else
      conn
      |> assign(:has_premium?, false)
      |> assign(:current_plan, "free")
      |> assign(:subscription, nil)
    end
  end

  @doc """
  Helper to check subscription status in controllers.

  Returns `{:ok, subscription}` or `{:error, :subscription_required}`
  """
  def check_subscription(user, payments_module, required_plan \\ nil) do
    cond do
      is_nil(user) ->
        {:error, :not_authenticated}

      required_plan && !payments_module.has_plan?(user, required_plan) ->
        {:error, :wrong_plan}

      !payments_module.has_premium?(user) ->
        {:error, :subscription_required}

      true ->
        {:ok, payments_module.get_active_subscription(user)}
    end
  end

  # Helper functions to handle Phoenix.Controller availability
  if Code.ensure_loaded?(Phoenix.Controller) do
    defp put_flash_if_available(conn, type, message) do
      Phoenix.Controller.put_flash(conn, type, message)
    end

    defp redirect_if_available(conn, opts) do
      Phoenix.Controller.redirect(conn, opts)
    end

    defp json_if_available(conn, data) do
      Phoenix.Controller.json(conn, data)
    end
  else
    defp put_flash_if_available(conn, _type, _message) do
      # When Phoenix isn't available, just pass through the connection
      conn
    end

    defp redirect_if_available(conn, opts) do
      # Basic redirect without Phoenix
      path = Keyword.get(opts, :to, "/")

      conn
      |> put_resp_header("location", path)
      |> send_resp(302, "")
    end

    defp json_if_available(conn, data) do
      # Basic JSON response without Phoenix
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(conn.status || 200, JSON.encode!(data))
    end
  end
end
