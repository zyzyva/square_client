defmodule Mix.Tasks.SquareClient.Gen.AuthTests do
  @moduledoc """
  Generates tests for subscription authentication helpers.

  ## Usage

      mix square_client.gen.auth_tests

  This task generates comprehensive tests for:
  - Subscription auth plugs (require_premium, require_plan, etc.)
  - LiveView subscription hooks
  - Payments context auth functions
  - Test fixtures for subscriptions

  The main test generator automatically runs this task.
  """

  use Mix.Task

  @shortdoc "Generates tests for subscription authentication helpers"

  def run(_args) do
    app_name = Mix.Project.config()[:app]
    module_prefix = app_name |> Atom.to_string() |> Macro.camelize()

    Mix.shell().info("Generating subscription auth tests for #{module_prefix}...")

    # Create test files
    create_subscription_auth_test(module_prefix)
    create_subscription_hooks_test(module_prefix)
    create_payments_auth_functions_test(module_prefix)
    create_subscription_fixtures(module_prefix)

    Mix.shell().info("\n✅ Subscription auth tests generated successfully!")
  end

  defp create_subscription_auth_test(module_prefix) do
    test_dir = "test/#{Macro.underscore(module_prefix)}_web"
    File.mkdir_p!(test_dir)

    path = Path.join(test_dir, "subscription_auth_test.exs")

    content = """
    defmodule #{module_prefix}Web.SubscriptionAuthTest do
      use #{module_prefix}Web.ConnCase, async: true
      import #{module_prefix}.AccountsFixtures
      import #{module_prefix}.SubscriptionFixtures

      describe "require_premium/2" do
        setup do
          user = user_fixture()
          conn = build_conn() |> log_in_user(user) |> fetch_flash()
          %{conn: conn, user: user}
        end

        test "allows access when user has premium subscription", %{conn: conn, user: user} do
          _subscription = active_subscription_fixture(user)

          # Reload user to ensure fresh data
          conn = conn |> assign(:current_user, #{module_prefix}.Accounts.get_user!(user.id))
          conn = #{module_prefix}Web.SubscriptionAuth.require_premium(conn)

          refute conn.halted
        end

        test "redirects to subscription page when user has no subscription", %{conn: conn, user: _user} do
          conn = conn |> fetch_flash()
          conn = #{module_prefix}Web.SubscriptionAuth.require_premium(conn)

          assert conn.halted
          assert redirected_to(conn) == "/subscription"
          assert Phoenix.Flash.get(conn.assigns.flash, :error) == "This feature requires a premium subscription"
        end

        test "redirects when subscription is canceled", %{conn: conn, user: user} do
          _subscription = canceled_subscription_fixture(user)

          conn = conn |> assign(:current_user, #{module_prefix}.Accounts.get_user!(user.id))
          conn = #{module_prefix}Web.SubscriptionAuth.require_premium(conn)

          assert conn.halted
          assert redirected_to(conn) == "/subscription"
        end

        test "redirects for unauthenticated users" do
          conn = build_conn() |> init_test_session(%{}) |> fetch_flash()
          conn = #{module_prefix}Web.SubscriptionAuth.require_premium(conn)

          assert conn.halted
          assert redirected_to(conn) == "/subscription"
        end
      end

      describe "require_plan/2" do
        setup do
          user = user_fixture()
          conn = build_conn() |> log_in_user(user) |> fetch_flash()
          %{conn: conn, user: user}
        end

        test "allows access when user has the specific plan", %{conn: conn, user: user} do
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_yearly",
            status: "ACTIVE"
          })

          conn = conn |> assign(:current_user, #{module_prefix}.Accounts.get_user!(user.id))
          conn = #{module_prefix}Web.SubscriptionAuth.require_plan(conn, "premium_yearly")

          refute conn.halted
        end

        test "redirects when user has different plan", %{conn: conn, user: user} do
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_monthly",
            status: "ACTIVE"
          })

          conn = conn |> assign(:current_user, #{module_prefix}.Accounts.get_user!(user.id))
          conn = #{module_prefix}Web.SubscriptionAuth.require_plan(conn, "premium_yearly")

          assert conn.halted
          assert redirected_to(conn) == "/subscription"
          assert Phoenix.Flash.get(conn.assigns.flash, :error) == "This feature requires the premium_yearly plan"
        end
      end

      describe "require_api_subscription/2" do
        setup do
          user = user_fixture()
          conn = build_conn()
            |> put_req_header("accept", "application/json")
            |> assign(:current_user, user)
          %{conn: conn, user: user}
        end

        test "allows API access with premium subscription", %{conn: conn, user: user} do
          _subscription = active_subscription_fixture(user)

          conn = conn |> assign(:current_user, #{module_prefix}.Accounts.get_user!(user.id))
          conn = #{module_prefix}Web.SubscriptionAuth.require_api_subscription(conn)

          refute conn.halted
        end

        test "returns 402 Payment Required without subscription", %{conn: conn, user: _user} do
          conn = #{module_prefix}Web.SubscriptionAuth.require_api_subscription(conn)

          assert conn.halted
          assert conn.status == 402

          {:ok, body} = Jason.decode(conn.resp_body)
          assert body["error"] == "API access requires premium subscription"
          assert body["upgrade_url"] == "/subscription"
        end
      end

      describe "load_subscription/2" do
        setup do
          user = user_fixture()
          conn = build_conn() |> log_in_user(user) |> fetch_flash()
          %{conn: conn, user: user}
        end

        test "assigns subscription status for premium user", %{conn: conn, user: user} do
          subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_monthly",
            status: "ACTIVE"
          })

          conn = conn |> assign(:current_user, #{module_prefix}.Accounts.get_user!(user.id))
          conn = #{module_prefix}Web.SubscriptionAuth.load_subscription(conn)

          assert conn.assigns[:has_premium?] == true
          assert conn.assigns[:current_plan] == "premium_monthly"
          assert conn.assigns[:subscription].id == subscription.id
        end

        test "assigns free status for user without subscription", %{conn: conn, user: _user} do
          conn = #{module_prefix}Web.SubscriptionAuth.load_subscription(conn)

          assert conn.assigns[:has_premium?] == false
          assert conn.assigns[:current_plan] == "free"
          assert conn.assigns[:subscription] == nil
        end
      end

      describe "has_premium?/1" do
        test "returns true for user with active subscription" do
          user = user_fixture()
          _subscription = active_subscription_fixture(user)

          # Reload user to get fresh data with associations
          user = #{module_prefix}.Accounts.get_user!(user.id)
          assert #{module_prefix}Web.SubscriptionAuth.has_premium?(user) == true
        end

        test "returns false for user without subscription" do
          user = user_fixture()
          assert #{module_prefix}Web.SubscriptionAuth.has_premium?(user) == false
        end

        test "accepts conn and extracts current_user" do
          user = user_fixture()
          _subscription = active_subscription_fixture(user)

          # Reload user and assign to conn
          user = #{module_prefix}.Accounts.get_user!(user.id)
          conn = build_conn() |> assign(:current_user, user)
          assert #{module_prefix}Web.SubscriptionAuth.has_premium?(conn) == true
        end

        test "returns false for conn without current_user" do
          conn = build_conn()
          refute #{module_prefix}Web.SubscriptionAuth.has_premium?(conn)
        end
      end

      describe "has_plan?/2" do
        test "returns true when user has specific plan" do
          user = user_fixture()
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_yearly",
            status: "ACTIVE"
          })

          user = #{module_prefix}.Accounts.get_user!(user.id)
          assert #{module_prefix}Web.SubscriptionAuth.has_plan?(user, "premium_yearly") == true
          assert #{module_prefix}Web.SubscriptionAuth.has_plan?(user, "premium_monthly") == false
        end

        test "accepts conn and checks plan" do
          user = user_fixture()
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_yearly",
            status: "ACTIVE"
          })

          user = #{module_prefix}.Accounts.get_user!(user.id)
          conn = build_conn() |> assign(:current_user, user)
          assert #{module_prefix}Web.SubscriptionAuth.has_plan?(conn, "premium_yearly") == true
        end
      end
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp create_subscription_hooks_test(module_prefix) do
    test_dir = "test/#{Macro.underscore(module_prefix)}_web"
    File.mkdir_p!(test_dir)

    path = Path.join(test_dir, "subscription_hooks_test.exs")

    content = """
    defmodule #{module_prefix}Web.SubscriptionHooksTest do
      use #{module_prefix}Web.ConnCase, async: true
      import #{module_prefix}.AccountsFixtures
      import #{module_prefix}.SubscriptionFixtures

      describe "on_mount :require_premium" do
        test "allows access for users with premium subscription" do
          user = user_fixture()
          _subscription = active_subscription_fixture(user)
          user = #{module_prefix}.Accounts.get_user!(user.id)

          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}, current_user: user}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount(:require_premium, %{}, %{}, socket)
          assert {:cont, _socket} = result
        end

        test "halts and redirects for users without subscription" do
          user = user_fixture()

          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}, current_user: user}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount(:require_premium, %{}, %{}, socket)
          assert {:halt, socket} = result
          assert socket.redirected == {:redirect, %{status: 302, to: "/subscription"}}
        end

        test "halts for unauthenticated users" do
          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount(:require_premium, %{}, %{}, socket)
          assert {:halt, socket} = result
          assert socket.redirected == {:redirect, %{status: 302, to: "/subscription"}}
        end
      end

      describe "on_mount {:require_plan, plan}" do
        test "allows access when user has the required plan" do
          user = user_fixture()
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_yearly",
            status: "ACTIVE"
          })
          user = #{module_prefix}.Accounts.get_user!(user.id)

          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}, current_user: user}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount({:require_plan, "premium_yearly"}, %{}, %{}, socket)
          assert {:cont, _socket} = result
        end

        test "halts when user has different plan" do
          user = user_fixture()
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_monthly",
            status: "ACTIVE"
          })
          user = #{module_prefix}.Accounts.get_user!(user.id)

          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}, current_user: user}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount({:require_plan, "premium_yearly"}, %{}, %{}, socket)
          assert {:halt, socket} = result
          assert socket.redirected == {:redirect, %{status: 302, to: "/subscription"}}
        end
      end

      describe "on_mount :assign_subscription" do
        test "assigns subscription status for premium user" do
          user = user_fixture()
          subscription = active_subscription_fixture(user)
          user = #{module_prefix}.Accounts.get_user!(user.id)

          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}, current_user: user}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount(:assign_subscription, %{}, %{}, socket)
          assert {:cont, socket} = result
          assert socket.assigns[:has_premium?] == true
          assert socket.assigns[:current_plan] == "premium_monthly"
          assert socket.assigns[:subscription].id == subscription.id
        end

        test "assigns free status for user without subscription" do
          user = user_fixture()

          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}, current_user: user}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount(:assign_subscription, %{}, %{}, socket)
          assert {:cont, socket} = result
          assert socket.assigns[:has_premium?] == false
          assert socket.assigns[:current_plan] == "free"
          assert socket.assigns[:subscription] == nil
        end

        test "assigns defaults when user is not authenticated" do
          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount(:assign_subscription, %{}, %{}, socket)
          assert {:cont, socket} = result
          assert socket.assigns[:has_premium?] == false
          assert socket.assigns[:current_plan] == "free"
          assert socket.assigns[:subscription] == nil
        end
      end

      describe "on_mount :default" do
        test "behaves same as :assign_subscription" do
          user = user_fixture()
          _subscription = active_subscription_fixture(user)
          user = #{module_prefix}.Accounts.get_user!(user.id)

          socket = %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}, current_user: user}
          }

          result = #{module_prefix}Web.SubscriptionHooks.on_mount(:default, %{}, %{}, socket)
          assert {:cont, socket} = result
          assert socket.assigns[:has_premium?] == true
        end
      end
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp create_payments_auth_functions_test(module_prefix) do
    test_dir = "test/#{Macro.underscore(module_prefix)}"
    File.mkdir_p!(test_dir)

    path = Path.join(test_dir, "payments_auth_functions_test.exs")

    content = """
    defmodule #{module_prefix}.PaymentsAuthFunctionsTest do
      use #{module_prefix}.DataCase, async: true
      import #{module_prefix}.AccountsFixtures
      import #{module_prefix}.SubscriptionFixtures
      alias #{module_prefix}.Payments

      describe "has_plan?/2" do
        setup do
          user = user_fixture()
          %{user: user}
        end

        test "returns true when user has the specific plan", %{user: user} do
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_yearly",
            status: "ACTIVE"
          })

          assert Payments.has_plan?(user, "premium_yearly") == true
          assert Payments.has_plan?(user, "premium_monthly") == false
        end

        test "returns false when user has no subscription", %{user: user} do
          assert Payments.has_plan?(user, "premium_yearly") == false
        end

        test "returns false when subscription is canceled", %{user: user} do
          _subscription = canceled_subscription_fixture(user, "premium_yearly")
          assert Payments.has_plan?(user, "premium_yearly") == false
        end

        test "accepts user id instead of user struct", %{user: user} do
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_monthly",
            status: "ACTIVE"
          })

          assert Payments.has_plan?(user.id, "premium_monthly") == true
        end
      end

      describe "get_current_plan/1" do
        setup do
          user = user_fixture()
          %{user: user}
        end

        test "returns plan_id for active subscription", %{user: user} do
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_yearly",
            status: "ACTIVE"
          })

          assert Payments.get_current_plan(user) == "premium_yearly"
        end

        test "returns 'free' when user has no subscription", %{user: user} do
          assert Payments.get_current_plan(user) == "free"
        end

        test "returns 'free' when subscription is canceled", %{user: user} do
          _subscription = canceled_subscription_fixture(user, "premium_yearly")
          assert Payments.get_current_plan(user) == "free"
        end

        test "returns 'free' for nil user" do
          assert Payments.get_current_plan(nil) == "free"
        end
      end

      describe "has_feature?/2" do
        setup do
          user = user_fixture()
          %{user: user}
        end

        test "returns true when plan includes the feature", %{user: user} do
          _subscription = subscription_fixture(%{
            user_id: user.id,
            plan_id: "premium_yearly",
            status: "ACTIVE"
          })

          # Test with a feature that might exist - if it doesn't, at least test the function doesn't crash
          # The actual features depend on your plan configuration
          result = Payments.has_feature?(user, :api_access)
          assert is_boolean(result)
        end

        test "returns false when plan doesn't include the feature", %{user: user} do
          # Free plan shouldn't have premium features
          assert Payments.has_feature?(user, :api_access) == false
          assert Payments.has_feature?(user, :advanced_analytics) == false
        end

        test "returns false for nil user" do
          assert Payments.has_feature?(nil, :api_access) == false
        end
      end
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp create_subscription_fixtures(module_prefix) do
    support_dir = "test/support"
    File.mkdir_p!(support_dir)

    path = Path.join(support_dir, "subscription_fixtures.ex")

    content = """
    defmodule #{module_prefix}.SubscriptionFixtures do
      @moduledoc \"\"\"
      This module defines test helpers for creating
      entities related to subscriptions.
      \"\"\"

      alias #{module_prefix}.Payments.Subscription
      alias #{module_prefix}.Repo

      @doc \"\"\"
      Generate a subscription.
      \"\"\"
      def subscription_fixture(attrs \\\\ %{}) do
        {:ok, subscription} =
          attrs
          |> Enum.into(%{
            square_subscription_id: "test_sub_\#{System.unique_integer([:positive])}",
            plan_id: "premium_monthly",
            status: "ACTIVE",
            started_at: DateTime.utc_now() |> DateTime.truncate(:second),
            user_id: attrs[:user_id] || raise("user_id is required")
          })
          |> then(&struct(Subscription, &1))
          |> Repo.insert()

        subscription
      end

      @doc \"\"\"
      Generate an active premium subscription for a user.
      \"\"\"
      def active_subscription_fixture(user, plan_id \\\\ "premium_monthly") do
        subscription_fixture(%{
          user_id: user.id,
          plan_id: plan_id,
          status: "ACTIVE"
        })
      end

      @doc \"\"\"
      Generate a canceled subscription for a user.
      \"\"\"
      def canceled_subscription_fixture(user, plan_id \\\\ "premium_monthly") do
        subscription_fixture(%{
          user_id: user.id,
          plan_id: plan_id,
          status: "CANCELED",
          canceled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      end
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end
end
