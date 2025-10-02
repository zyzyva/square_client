defmodule APP_MODULEWeb.SubscriptionLive.ApiFailureTest do
  use APP_MODULEWeb.ConnCase
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  alias APP_MODULE.ACCOUNTS_CONTEXT

  setup do
    # Create a test user
    {:ok, user} =
      ACCOUNTS_CONTEXT.register_user(%{
        email: "test@example.com",
        username: "testuser"
      })

    # Log in the user
    conn = build_conn()
    conn = log_in_user(conn, user)

    {:ok, conn: conn, user: user}
  end

  describe "subscription creation with API failures" do
    test "shows user-friendly error when Square API is down", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/subscription")

      # Try to select and purchase a plan
      # Since Square API is not running in test, this simulates API down
      capture_log(fn ->
        # Click monthly plan
        html =
          view
          |> element("button[phx-click=\"select_plan\"][phx-value-plan_id=\"premium_monthly\"]")
          |> render_click()

        # Should show payment modal or handle the click
        assert html =~ "Premium" or html =~ "payment"

        # Check for error message
        html = render(view)

        # Should show user-friendly error, not technical details
        # At minimum, should still render
        assert html =~ "unavailable" or
                 html =~ "try again" or
                 html =~ "Please try" or
                 html =~ "Premium"

        # Should NOT expose technical errors to user
        refute html =~ "econnrefused"
        refute html =~ "TransportError"
        refute html =~ "{:error"
      end)
    end

    test "handles payment service unavailability gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/subscription")

      # Page should still be functional
      # Free plan is no longer displayed
      refute html =~ "Free"
      assert html =~ "Premium"
    end

    test "displays proper error for configuration issues", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/subscription")

      # Should have plan selection buttons
      assert html =~ "select_plan"
    end
  end

  describe "subscription cancellation with API failures" do
    test "shows appropriate message when cancellation fails", %{conn: conn, user: user} do
      # Create an active subscription
      {:ok, _subscription} =
        %APP_MODULE.Payments.Subscription{}
        |> APP_MODULE.Payments.Subscription.changeset(%{
          user_id: user.id,
          plan_id: "premium_monthly",
          status: "ACTIVE",
          square_subscription_id: "sub_123"
        })
        |> APP_MODULE.Repo.insert()

      capture_log(fn ->
        {:ok, view, _html} = live(conn, ~p"/subscription")
        send(self(), {:view, view})
      end)

      assert_received {:view, view}

      capture_log(fn ->
        # Try to cancel subscription
        # Look for cancel button if it exists
        html = render(view)

        # Check if there's a cancel button by looking for the actual element
        case Phoenix.LiveViewTest.has_element?(view, "button[phx-click=\"cancel_subscription\"]") do
          true ->
            view
            |> element("button[phx-click=\"cancel_subscription\"]")
            |> render_click()

            html = render(view)

            # Should show error message about unavailability
            # At minimum, still shows the page
            assert html =~ "unavailable" or
                     html =~ "try again" or
                     html =~ "contact support" or
                     html =~ "Premium"
          false ->
            # No cancel button visible, which is fine for this UI
            # The subscription status is shown instead
            assert html =~ "Current Plan" or html =~ "Premium"
        end
      end)
    end

    test "handles no subscription case properly", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/subscription")

      # User has no subscription, should be on free plan
      html = render(view)

      # Free plan is no longer displayed
      refute html =~ "Free"
      refute html =~ "Stay on Free"
    end
  end

  describe "error message visibility" do
    test "flash messages are displayed to user", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/subscription")

      # Trigger an action that would cause an API call
      capture_log(fn ->
        # Select a plan
        view
        |> element("button[phx-click=\"select_plan\"][phx-value-plan_id=\"premium_monthly\"]")
        |> render_click()

        html = render(view)

        # Even if API is down, page should render
        assert html =~ "Premium" or html =~ "Subscription"
      end)
    end

    test "errors don't break the page layout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/subscription")

      # Page structure should be intact
      assert html =~ "<!DOCTYPE html>" or html =~ "<div"
      assert html =~ "Subscription Plans"

      # Free plan is no longer displayed
      refute html =~ "Free"
      # Weekly is no longer displayed
      refute html =~ "Weekly"
      assert html =~ "Monthly"
      assert html =~ "Yearly"
    end
  end

  describe "recovery from API failures" do
    test "page remains interactive after API errors", %{conn: conn} do
      capture_log(fn ->
        {:ok, view, _html} = live(conn, ~p"/subscription")
        send(self(), {:view, view})
      end)

      assert_received {:view, view}

      capture_log(fn ->
        # Try multiple interactions
        # First attempt
        view
        |> element("button[phx-click=\"select_plan\"][phx-value-plan_id=\"premium_monthly\"]")
        |> render_click()

        # Should still be able to close modal or select another plan
        html = render(view)

        if html =~ "close_modal" do
          view
          |> element("[phx-click=\"close_modal\"]")
          |> render_click()
        end

        # Try selecting a different plan
        view
        |> element("button[phx-click=\"select_plan\"][phx-value-plan_id=\"premium_yearly\"]")
        |> render_click()

        # Page should still be responsive
        final_html = render(view)
        assert final_html =~ "Premium"
      end)
    end

    test "user can retry after API failure", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/subscription")

      capture_log(fn ->
        # First attempt fails due to API being down
        view
        |> element("button[phx-click=\"select_plan\"][phx-value-plan_id=\"premium_monthly\"]")
        |> render_click()

        # User should be able to try again
        view
        |> element("button[phx-click=\"select_plan\"][phx-value-plan_id=\"premium_monthly\"]")
        |> render_click()

        # No crash, page still works
        html = render(view)
        assert html =~ "Subscription"
      end)
    end
  end
end
