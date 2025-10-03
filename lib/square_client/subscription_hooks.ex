defmodule SquareClient.SubscriptionHooks do
  @moduledoc """
  LiveView on_mount hooks for subscription-based access control.

  ## Usage

  Configure in your router:

      defmodule MyAppWeb.Router do
        live_session :premium_features,
          on_mount: [
            {MyAppWeb.UserAuth, :ensure_authenticated},
            {MyAppWeb.SubscriptionHooks, :require_premium}
          ] do
          live "/analytics", AnalyticsLive, :index
        end
      end

  Then create your app-specific hooks module:

      defmodule MyAppWeb.SubscriptionHooks do
        use SquareClient.SubscriptionHooks,
          payments_module: MyApp.Payments
      end
  """

  @doc false
  defmacro __using__(opts) do
    payments_module = Keyword.fetch!(opts, :payments_module)

    quote do
      import Phoenix.Component
      import Phoenix.LiveView
      alias unquote(payments_module), as: Payments

      @doc """
      Requires premium subscription to access the LiveView.
      Redirects to subscription page if not subscribed.
      """
      def on_mount(:require_premium, _params, _session, socket) do
        if socket.assigns[:current_user] && Payments.has_premium?(socket.assigns.current_user) do
          {:cont, socket}
        else
          {:halt,
           socket
           |> Phoenix.LiveView.put_flash(:error, "Premium subscription required")
           |> Phoenix.LiveView.redirect(to: "/subscription")}
        end
      end

      @doc """
      Requires specific plan to access the LiveView.
      """
      def on_mount({:require_plan, plan}, _params, _session, socket) do
        user = socket.assigns[:current_user]

        if user && Payments.has_plan?(user, plan) do
          {:cont, socket}
        else
          {:halt,
           socket
           |> Phoenix.LiveView.put_flash(:error, "This feature requires the #{plan} plan")
           |> Phoenix.LiveView.redirect(to: "/subscription")}
        end
      end

      @doc """
      Assigns subscription status without enforcing requirements.
      Useful for pages with mixed free/premium features.
      """
      def on_mount(:assign_subscription, _params, _session, socket) do
        {:cont, assign_subscription_status(socket)}
      end

      @doc """
      Default mount that assigns subscription status.
      """
      def on_mount(:default, _params, _session, socket) do
        {:cont, assign_subscription_status(socket)}
      end

      defp assign_subscription_status(socket) do
        if user = socket.assigns[:current_user] do
          subscription = Payments.get_active_subscription(user)

          socket
          |> assign(:has_premium?, Payments.has_premium?(user))
          |> assign(:current_plan, Payments.get_current_plan(user))
          |> assign(:subscription, subscription)
          |> assign(:plan_features, get_plan_features(user))
        else
          socket
          |> assign(:has_premium?, false)
          |> assign(:current_plan, "free")
          |> assign(:subscription, nil)
          |> assign(:plan_features, [])
        end
      end

      defp get_plan_features(user) do
        plan = Payments.get_current_plan(user)

        case SquareClient.Plans.get_plan_features(plan) do
          nil -> []
          features -> features
        end
      end

      defoverridable on_mount: 4
    end
  end
end
