defmodule Mix.Tasks.SquareClient.Gen.Auth do
  @moduledoc """
  Generates subscription authentication helpers for a Phoenix application.

  ## Usage

      mix square_client.gen.auth

  This task generates:
  - `lib/your_app_web/subscription_auth.ex` - Plug-based authentication helpers
  - `lib/your_app_web/subscription_hooks.ex` - LiveView on_mount hooks

  These files provide subscription-based access control for:
  - Regular HTTP routes (via plugs)
  - LiveView routes (via on_mount hooks)
  - API endpoints (with 402 Payment Required responses)
  - Template helpers for conditional rendering

  The main installer automatically runs this task, but you can run it
  separately if you need to regenerate just the auth helpers.
  """

  use Mix.Task

  @shortdoc "Generates subscription authentication helpers"

  def run(_args) do
    # Get app information
    app_name = Mix.Project.config()[:app]
    module_prefix = app_name |> Atom.to_string() |> Macro.camelize()

    Mix.shell().info("Generating subscription auth helpers for #{module_prefix}...")

    # Generate the auth helper files
    create_subscription_auth_helpers(module_prefix, app_name)

    Mix.shell().info("\n✅ Subscription auth helpers generated successfully!")

    Mix.shell().info("""

    ## Usage Examples

    ### In Router (Plugs)

        import #{module_prefix}Web.SubscriptionAuth

        pipeline :require_premium do
          plug :require_premium
        end

        scope "/premium", #{module_prefix}Web do
          pipe_through [:browser, :require_authenticated_user, :require_premium]
          # Premium routes here
        end

    ### In LiveView (Hooks)

        live_session :premium_features,
          on_mount: [
            {#{module_prefix}Web.UserAuth, :ensure_authenticated},
            {#{module_prefix}Web.SubscriptionHooks, :require_premium}
          ] do
          live "/analytics", AnalyticsLive, :index
        end

    ### In Templates

        <%= if #{module_prefix}Web.SubscriptionAuth.has_premium?(@conn) do %>
          <.link navigate="/premium-feature">Premium Feature</.link>
        <% else %>
          <.link navigate="/subscription">Upgrade to Premium</.link>
        <% end %>
    """)
  end

  defp create_subscription_auth_helpers(module_prefix, app_name) do
    web_dir = "lib/#{Macro.underscore(module_prefix)}_web"
    File.mkdir_p!(web_dir)

    assigns = [
      web_module: "#{module_prefix}Web",
      app_module: module_prefix,
      app_name: app_name
    ]

    # Generate subscription auth module
    auth_path = Path.join(web_dir, "subscription_auth.ex")
    auth_template = read_template("subscription_auth.ex.eex")
    auth_output = EEx.eval_string(auth_template, assigns)
    File.write!(auth_path, auth_output)
    Mix.shell().info("  * Created #{auth_path}")

    # Generate subscription hooks module
    hooks_path = Path.join(web_dir, "subscription_hooks.ex")
    hooks_template = read_template("subscription_hooks.ex.eex")
    hooks_output = EEx.eval_string(hooks_template, assigns)
    File.write!(hooks_path, hooks_output)
    Mix.shell().info("  * Created #{hooks_path}")
  end

  defp read_template(name) do
    # First try to find in deps
    deps_path = Path.join(["deps", "square_client", "priv", "templates", name])

    # Then try in parent directory (for development)
    dev_path = Path.join(["..", "square_client", "priv", "templates", name])

    # Finally try application resource
    app_path = Application.app_dir(:square_client, ["priv", "templates", name])

    Mix.shell().info("  Looking for template:")
    Mix.shell().info("    deps_path: #{deps_path} - exists: #{File.exists?(deps_path)}")
    Mix.shell().info("    dev_path: #{dev_path} - exists: #{File.exists?(dev_path)}")
    Mix.shell().info("    app_path: #{app_path} - exists: #{File.exists?(app_path)}")

    cond do
      File.exists?(deps_path) ->
        Mix.shell().info("    Using deps_path")
        File.read!(deps_path)

      File.exists?(dev_path) ->
        Mix.shell().info("    Using dev_path")
        File.read!(dev_path)

      File.exists?(app_path) ->
        Mix.shell().info("    Using app_path")
        File.read!(app_path)

      true ->
        raise "Template not found: #{name}"
    end
  end
end
