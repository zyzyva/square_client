defmodule Mix.Tasks.SquareClient.Install do
  @moduledoc """
  Generates Square subscription management files for a Phoenix application.

  ## Usage

      mix square_client.install

  This task auto-detects your application structure (assumes Phoenix gen.auth)
  and generates:

  - Subscription schema using library macro
  - Webhook handler implementation
  - Webhook controller
  - Database migration
  - Configuration files

  ## What It Generates

  Files created:
  - `lib/your_app/payments/subscription.ex` - Subscription schema
  - `lib/your_app/payments/square_webhook_handler.ex` - Webhook event handler
  - `lib/your_app_web/controllers/square_webhook_controller.ex` - Webhook endpoint
  - `priv/repo/migrations/TIMESTAMP_create_subscriptions.exs` - Database migration
  - Updates `config/config.exs` with Square configuration
  - Updates `config/prod.exs` with production URL

  ## Manual Steps After Running

  1. Add runtime validation to `lib/your_app/application.ex`:
     ```
     def start(_type, _args) do
       SquareClient.Config.validate_runtime!()
       # ... rest of your children
     end
     ```

  2. Add webhook route to `lib/your_app_web/router.ex`:
     ```
     pipeline :square_webhook do
       plug :accepts, ["json"]
       plug SquareClient.WebhookPlug
     end

     scope "/webhooks", YourAppWeb do
       pipe_through :square_webhook
       post "/square", SquareWebhookController, :handle
     end
     ```

  3. Run the migration:
     ```
     mix ecto.migrate
     ```

  4. Set environment variables:
     ```
     export SQUARE_ACCESS_TOKEN="your_token"
     export SQUARE_LOCATION_ID="your_location_id"
     ```

  ## Options

    * `--tests` - Generate comprehensive test files (default: true)
    * `--no-tests` - Skip test generation

  Assumptions:
  - App follows Phoenix gen.auth conventions
  - Owner module is `YourApp.Accounts.User`
  - Foreign key is `:user_id`
  - Repo module is `YourApp.Repo`
  """

  use Mix.Task

  @shortdoc "Generates Square subscription management files"

  def run(args) do
    # Parse options
    {opts, _, _} = OptionParser.parse(args, strict: [tests: :boolean])
    generate_tests = Keyword.get(opts, :tests, true)

    # Get app information
    app_name = Mix.Project.config()[:app]
    module_prefix = app_name |> Atom.to_string() |> Macro.camelize()
    owner_module = Module.concat([module_prefix, "Accounts", "User"])
    owner_association = :user
    owner_key = :user_id
    repo_module = Module.concat([module_prefix, "Repo"])

    Mix.shell().info("Installing SquareClient for #{module_prefix}...")

    # Create directories
    payments_dir = "lib/#{Macro.underscore(module_prefix)}/payments"
    File.mkdir_p!(payments_dir)

    controllers_dir = "lib/#{Macro.underscore(module_prefix)}_web/controllers"
    File.mkdir_p!(controllers_dir)

    # Generate files
    create_subscription_schema(
      module_prefix,
      owner_module,
      owner_association,
      repo_module,
      payments_dir
    )

    create_webhook_handler(module_prefix, payments_dir)
    create_webhook_controller(module_prefix, controllers_dir)
    create_migration(module_prefix, owner_key)
    create_user_migration(owner_key)
    create_square_plans_json(app_name)
    create_payments_context(module_prefix, repo_module, owner_module, payments_dir, app_name)
    create_subscription_liveviews(module_prefix, app_name)
    create_square_payment_hook()
    update_config(module_prefix)

    # Generate auth helpers using the separate task
    Mix.shell().info("\n📔 Generating subscription auth helpers...")
    Mix.Task.run("square_client.gen.auth", [])

    # Automate setup
    update_application(module_prefix)
    update_router(module_prefix)
    update_app_js()
    update_user_schema(module_prefix, owner_module)
    run_migration()

    # Generate tests if requested
    if generate_tests do
      Mix.shell().info("\n📝 Generating comprehensive test files...")
      Mix.Task.run("square_client.gen.tests", [])
    else
      Mix.shell().info("\n⏭️  Skipping test generation (use --tests to generate)")
    end

    # Print remaining manual steps
    print_manual_steps(module_prefix)

    Mix.shell().info("\n✅ Square Client installation complete!")
  end

  defp create_subscription_schema(
         module_prefix,
         owner_module,
         owner_association,
         repo_module,
         dir
       ) do
    path = Path.join(dir, "subscription.ex")

    content = """
    defmodule #{module_prefix}.Payments.Subscription do
      @moduledoc \"\"\"
      Schema for tracking Square subscriptions.

      This module uses the SquareClient.Subscriptions.Schema macro to provide
      standard subscription functionality with Square integration.
      \"\"\"

      use SquareClient.Subscriptions.Schema,
        repo: #{inspect(repo_module)},
        belongs_to: [
          {#{inspect(owner_association)}, #{inspect(owner_module)}}
        ]

      # Convenience aliases for app-specific terminology
      defdelegate get_active_for_user(user_or_id), to: __MODULE__, as: :get_active_for_owner

      def for_user(query \\\\ __MODULE__, user_or_id) do
        for_owner(query, user_or_id)
      end
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp create_webhook_handler(module_prefix, dir) do
    path = Path.join(dir, "square_webhook_handler.ex")

    content = """
    defmodule #{module_prefix}.Payments.SquareWebhookHandler do
      @moduledoc \"\"\"
      Handles Square webhook events.

      This module implements the SquareClient.WebhookHandler behaviour to process
      webhook events from Square, such as subscription updates and payment events.
      \"\"\"

      @behaviour SquareClient.WebhookHandler

      alias #{module_prefix}.Payments.Subscription
      alias #{module_prefix}.Repo

      require Logger

      @impl true
      def handle_event(%{event_type: "subscription.created", data: data}) do
        sync_subscription(data)
      end

      @impl true
      def handle_event(%{event_type: "subscription.updated", data: data}) do
        sync_subscription(data)
      end

      @impl true
      def handle_event(%{event_type: "subscription.canceled", data: data}) do
        sync_subscription(data)
      end

      @impl true
      def handle_event(%{event_type: "invoice.payment_made", data: _data}) do
        # Handle successful subscription payments
        Logger.info("Subscription payment successful")
        :ok
      end

      @impl true
      def handle_event(%{event_type: "invoice.payment_failed", data: _data}) do
        # Handle failed subscription payments
        Logger.warning("Subscription payment failed")
        :ok
      end

      @impl true
      def handle_event(%{event_type: event_type}) do
        Logger.debug("Unhandled webhook event: \#{event_type}")
        :ok
      end

      defp sync_subscription(%{"object" => %{"subscription" => square_sub}}) do
        # Convert Square webhook format to expected format (Square uses "id", we expect "square_subscription_id")
        # Note: Gradient type checker will warn here - this is expected for dynamic webhook data
        subscription_data = Map.put(square_sub, "square_subscription_id", square_sub["id"])

        SquareClient.Subscriptions.Context.sync_from_square(
          Subscription,
          Repo,
          subscription_data
        )

        :ok
      rescue
        error ->
          Logger.error("Failed to sync subscription: \#{inspect(error)}")
          {:error, error}
      end

      defp sync_subscription(_data) do
        Logger.warning("Received subscription webhook without subscription data")
        :ok
      end
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp create_webhook_controller(module_prefix, dir) do
    path = Path.join(dir, "square_webhook_controller.ex")

    content = """
    defmodule #{module_prefix}Web.SquareWebhookController do
      @moduledoc \"\"\"
      Controller for handling Square webhook events.

      This controller uses the SquareClient.Controllers.WebhookController
      behavior which provides standard webhook response handling.
      \"\"\"

      use #{module_prefix}Web, :controller
      use SquareClient.Controllers.WebhookController
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp create_migration(module_prefix, owner_key) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    migrations_dir = "priv/repo/migrations"
    File.mkdir_p!(migrations_dir)

    path = Path.join(migrations_dir, "#{timestamp}_create_subscriptions.exs")
    owner_table = owner_key |> Atom.to_string() |> String.replace_suffix("_id", "s")

    content = """
    defmodule #{module_prefix}.Repo.Migrations.CreateSubscriptions do
      use Ecto.Migration

      def change do
        create table(:subscriptions) do
          add :square_subscription_id, :string
          add :plan_id, :string
          add :status, :string
          add :card_id, :string
          add :payment_id, :string
          add :started_at, :utc_datetime
          add :canceled_at, :utc_datetime
          add :next_billing_at, :utc_datetime
          add :trial_ends_at, :utc_datetime
          add #{inspect(owner_key)}, references(:#{owner_table}, on_delete: :delete_all), null: false

          timestamps(type: :utc_datetime)
        end

        create unique_index(:subscriptions, [:square_subscription_id])
        create index(:subscriptions, [#{inspect(owner_key)}])
        create index(:subscriptions, [:status])
      end
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp create_user_migration(owner_key) do
    # Add 1 second to timestamp to avoid duplicate migration version
    timestamp =
      DateTime.utc_now()
      |> DateTime.add(1, :second)
      |> Calendar.strftime("%Y%m%d%H%M%S")

    # Convert :user_id to "users" by removing _id suffix and pluralizing
    table_name =
      owner_key
      |> Atom.to_string()
      |> String.replace_suffix("_id", "")
      |> then(&"#{&1}s")

    migration_name = "add_square_fields_to_#{table_name}"
    path = "priv/repo/migrations/#{timestamp}_#{migration_name}.exs"
    module_name = Macro.camelize(migration_name)

    content = """
    defmodule #{Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()}.Repo.Migrations.#{module_name} do
      use Ecto.Migration

      def change do
        alter table(:#{table_name}) do
          add :square_customer_id, :string
        end

        create unique_index(:#{table_name}, [:square_customer_id])
      end
    end
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp update_config(module_prefix) do
    webhook_handler = "#{module_prefix}.Payments.SquareWebhookHandler"

    # Update config.exs
    config_path = "config/config.exs"

    config_addition = """

    # Square client configuration
    config :square_client,
      api_url: "https://connect.squareupsandbox.com/v2",
      access_token: System.get_env("SQUARE_ACCESS_TOKEN"),
      location_id: System.get_env("SQUARE_LOCATION_ID"),
      webhook_handler: #{webhook_handler}
    """

    if File.exists?(config_path) do
      existing = File.read!(config_path)

      if String.contains?(existing, ":square_client") do
        Mix.shell().info("  * Config already contains :square_client - skipping config.exs")
      else
        File.write!(config_path, existing <> config_addition)
        Mix.shell().info("  * Updated #{config_path}")
      end
    end

    # Update prod.exs
    prod_path = "config/prod.exs"

    prod_addition = """

    # Square client production configuration
    config :square_client,
      api_url: "https://connect.squareup.com/v2"
    """

    if File.exists?(prod_path) do
      existing = File.read!(prod_path)

      if String.contains?(existing, "square_client") && String.contains?(existing, "squareup.com") do
        Mix.shell().info(
          "  * Config already contains production :square_client - skipping prod.exs"
        )
      else
        File.write!(prod_path, existing <> prod_addition)
        Mix.shell().info("  * Updated #{prod_path}")
      end
    end
  end

  defp create_square_plans_json(_app_name) do
    priv_dir = "priv"
    File.mkdir_p!(priv_dir)
    path = Path.join(priv_dir, "square_plans.json")

    # Production-ready JSON configuration template
    content = ~S"""
    {
      "plans": {
        "free": {
          "id": "free",
          "name": "Free",
          "description": "Basic features for casual users",
          "type": "free",
          "active": true,
          "price": "$0",
          "price_cents": 0,
          "features": [
            "Basic functionality",
            "Community support",
            "Limited usage"
          ]
        },
        "premium": {
          "name": "Premium",
          "description": "Premium features for your application",
          "type": "subscription",
          "sandbox_base_plan_id": null,
          "production_base_plan_id": null,
          "variations": {
            "monthly": {
              "id": "premium_monthly",
              "name": "Monthly",
              "amount": 999,
              "cadence": "MONTHLY",
              "currency": "USD",
              "sandbox_variation_id": null,
              "production_variation_id": null,
              "active": true,
              "price": "$9.99/mo",
              "price_cents": 999,
              "auto_renews": true,
              "billing_notice": "Billed monthly, auto-renews until cancelled",
              "features": [
                "All premium features",
                "Priority support",
                "Advanced functionality"
              ]
            },
            "yearly": {
              "id": "premium_yearly",
              "name": "Yearly",
              "amount": 9900,
              "cadence": "ANNUAL",
              "currency": "USD",
              "sandbox_variation_id": null,
              "production_variation_id": null,
              "active": true,
              "price": "$99/yr",
              "price_cents": 9900,
              "auto_renews": true,
              "billing_notice": "Billed annually, auto-renews until cancelled",
              "features": [
                "Everything in Premium Monthly",
                "Save $20/year",
                "Early access to new features"
              ]
            }
          }
        }
      },
      "one_time_purchases": {
        "week_pass": {
          "id": "week_pass",
          "active": true,
          "name": "7-Day Pass",
          "type": "one_time",
          "description": "Try premium features for a week",
          "price": "$4.99",
          "price_cents": 499,
          "duration_days": 7,
          "auto_renews": false,
          "billing_notice": "One-time payment, NO auto-renewal",
          "features": [
            "7 days unlimited access",
            "All premium features",
            "No recurring charges",
            "Perfect for short-term needs"
          ]
        }
      }
    }
    """

    File.write!(path, content)
    Mix.shell().info("  * Created #{path}")
  end

  defp create_payments_context(module_prefix, _repo_module, _owner_module, dir, app_name) do
    path = Path.join(dir, "payments.ex")

    assigns = [module_prefix: module_prefix, app_name: app_name]
    generate_from_template("payments.ex.eex", path, assigns)
  end

  defp create_subscription_liveviews(module_prefix, app_name) do
    live_dir = "lib/#{Macro.underscore(module_prefix)}_web/live/subscription_live"
    File.mkdir_p!(live_dir)

    assigns = [module_prefix: module_prefix, app_name: app_name]

    generate_from_template(
      "subscription_live_index.ex.eex",
      Path.join(live_dir, "index.ex"),
      assigns
    )

    generate_from_template(
      "subscription_live_manage.ex.eex",
      Path.join(live_dir, "manage.ex"),
      assigns
    )
  end

  defp create_square_payment_hook do
    hooks_dir = "assets/js/hooks"
    File.mkdir_p!(hooks_dir)

    generate_from_template("square_payment.js.eex", Path.join(hooks_dir, "square_payment.js"), [])
  end

  defp generate_from_template(template_name, output_path, assigns) do
    template = read_template(template_name)

    # Use simple string replacement instead of EEx to avoid conflicts with HEEx
    content =
      template
      |> String.replace("{{MODULE}}", assigns[:module_prefix] || "")
      |> String.replace(":{{APP}}", ":#{assigns[:app_name] || ""}")

    File.write!(output_path, content)
    Mix.shell().info("  * Created #{output_path}")
  end

  defp read_template(name) do
    template_path = Application.app_dir(:square_client, ["priv", "templates", name])
    File.read!(template_path)
  end

  defp update_application(module_prefix) do
    app_path = "lib/#{Macro.underscore(module_prefix)}/application.ex"

    if File.exists?(app_path) do
      content = File.read!(app_path)

      unless String.contains?(content, "SquareClient.Config.validate_runtime!") do
        # Add validation after 'def start' line
        updated =
          String.replace(
            content,
            ~r/(def start\(_type, _args\) do\n)/,
            "\\1    SquareClient.Config.validate_runtime!()\n\n"
          )

        File.write!(app_path, updated)
        Mix.shell().info("  * Updated #{app_path} with Square config validation")
      end
    end
  end

  defp update_router(module_prefix) do
    router_path = "lib/#{Macro.underscore(module_prefix)}_web/router.ex"

    if File.exists?(router_path) do
      content = File.read!(router_path)
      updates = []

      # Add webhook pipeline if not present
      {content, updates} =
        if String.contains?(content, "pipeline :square_webhook") do
          {content, updates}
        else
          webhook_pipeline = """

            pipeline :square_webhook do
              plug :accepts, ["json"]
              plug SquareClient.WebhookPlug
            end
          """

          updated_content =
            String.replace(
              content,
              ~r/(pipeline :api do.*?end)/s,
              "\\1#{webhook_pipeline}"
            )

          {updated_content, ["webhook pipeline" | updates]}
        end

      # Add webhook route if not present
      {content, updates} =
        if String.contains?(content, "SquareWebhookController") do
          {content, updates}
        else
          webhook_route = """

            scope "/webhooks", #{module_prefix}Web do
              pipe_through :square_webhook
              post "/square", SquareWebhookController, :handle
            end
          """

          # Add webhook route before the final 'end' of the router module
          updated_content =
            String.replace(
              content,
              ~r/\nend\s*$/,
              "\n#{webhook_route}end\n"
            )

          {updated_content, ["webhook route" | updates]}
        end

      # Add LiveView routes if not present
      {content, updates} =
        if String.contains?(content, "SubscriptionLive.Index") do
          {content, updates}
        else
          liveview_routes = """

              live "/subscription", SubscriptionLive.Index, :index
              live "/subscription/manage", SubscriptionLive.Manage, :manage
          """

          # Try to find existing authenticated live_session
          updated_content =
            String.replace(
              content,
              ~r/(live_session :require_authenticated_user.*?do)/s,
              "\\1#{liveview_routes}"
            )

          {updated_content, ["subscription routes" | updates]}
        end

      if updates != [] do
        File.write!(router_path, content)
        Mix.shell().info("  * Updated #{router_path} with #{Enum.join(updates, ", ")}")
      end
    end
  end

  defp update_app_js do
    app_js_path = "assets/js/app.js"

    if File.exists?(app_js_path) do
      content = File.read!(app_js_path)

      unless String.contains?(content, "square_payment") do
        # Add import at top
        import_line = "import SquarePayment from \"./hooks/square_payment\"\n"
        content = String.replace(content, ~r/(import.*\n)/, "\\1#{import_line}", global: false)

        # Add to hooks object
        content =
          String.replace(
            content,
            ~r/(hooks:\s*\{)/,
            "\\1SquarePayment, "
          )

        File.write!(app_js_path, content)
        Mix.shell().info("  * Updated #{app_js_path} with Square payment hook")
      end
    end
  end

  defp update_user_schema(module_prefix, _owner_module) do
    user_path = "lib/#{Macro.underscore(module_prefix)}/accounts/user.ex"

    unless File.exists?(user_path) do
      Mix.shell().error("  ⚠️  Could not find User schema at #{user_path}")

      Mix.shell().error(
        "     You'll need to manually add square_customer_id field and subscriptions association"
      )

      :ok
    else
      do_update_user_schema(user_path, module_prefix)
    end
  end

  defp do_update_user_schema(user_path, module_prefix) do
    content = File.read!(user_path)

    # Check if already has square_customer_id
    if content =~ ~r/field\s+:square_customer_id/ do
      Mix.shell().info("  * User schema already has square_customer_id field")
    else
      # Find the schema block and add the field before belongs_to or timestamps
      content =
        cond do
          # Try to add before belongs_to
          content =~ ~r/\n(\s+)belongs_to / ->
            String.replace(
              content,
              ~r/\n(\s+)belongs_to /,
              "\n    field :square_customer_id, :string\n\n\\1belongs_to ",
              global: false
            )

          # Try to add before has_many
          content =~ ~r/\n(\s+)has_many / ->
            String.replace(
              content,
              ~r/\n(\s+)has_many /,
              "\n    field :square_customer_id, :string\n\n\\1has_many ",
              global: false
            )

          # Try to add before timestamps
          content =~ ~r/\n(\s+)timestamps\(/ ->
            String.replace(
              content,
              ~r/\n(\s+)timestamps\(/,
              "\n    field :square_customer_id, :string\n\n\\1timestamps(",
              global: false
            )

          # Default: couldn't find insertion point
          true ->
            Mix.shell().error(
              "  ⚠️  Could not automatically add square_customer_id to User schema"
            )

            Mix.shell().error("     Please add manually: field :square_customer_id, :string")
            content
        end

      if content != File.read!(user_path) do
        File.write!(user_path, content)
        Mix.shell().info("  * Updated #{user_path} with square_customer_id field")
      end
    end

    # Check if already has subscriptions association
    if content =~ ~r/has_many\s+:subscriptions/ do
      Mix.shell().info("  * User schema already has subscriptions association")
    else
      # Add has_many :subscriptions after the square_customer_id or other associations
      content = File.read!(user_path)

      content =
        cond do
          # Try to add after other has_many
          content =~ ~r/\n(\s+)has_many .+\n/ ->
            String.replace(
              content,
              ~r/(\n\s+has_many .+\n)/,
              "\\1    has_many :subscriptions, #{module_prefix}.Payments.Subscription\n",
              global: false
            )

          # Try to add after belongs_to
          content =~ ~r/\n(\s+)belongs_to .+\n/ ->
            String.replace(
              content,
              ~r/(\n\s+belongs_to .+\n)/,
              "\\1    has_many :subscriptions, #{module_prefix}.Payments.Subscription\n",
              global: false
            )

          # Try to add before timestamps
          content =~ ~r/\n(\s+)timestamps\(/ ->
            String.replace(
              content,
              ~r/\n(\s+)timestamps\(/,
              "\n    has_many :subscriptions, #{module_prefix}.Payments.Subscription\n\n\\1timestamps(",
              global: false
            )

          # Default: couldn't find insertion point
          true ->
            Mix.shell().error(
              "  ⚠️  Could not automatically add subscriptions association to User schema"
            )

            Mix.shell().error(
              "     Please add manually: has_many :subscriptions, #{module_prefix}.Payments.Subscription"
            )

            content
        end

      if content != File.read!(user_path) do
        File.write!(user_path, content)
        Mix.shell().info("  * Updated #{user_path} with subscriptions association")
      end
    end

    :ok
  end

  defp run_migration do
    Mix.shell().info("\n  Running migration...")
    Mix.Task.run("ecto.migrate")
  end

  defp print_manual_steps(module_prefix) do
    Mix.shell().info("""

    📋 Remaining Manual Steps:

    1. Add Square SDK script to your root layout:

       In lib/#{Macro.underscore(module_prefix)}_web/components/layouts/root.html.heex, add before </head>:

         <script type="text/javascript" src="https://sandbox.web.squarecdn.com/v1/square.js"></script>

       For production, use:

         <script type="text/javascript" src="https://web.squarecdn.com/v1/square.js"></script>

    2. Set environment variables:

       export SQUARE_ACCESS_TOKEN="your_sandbox_token"
       export SQUARE_LOCATION_ID="your_location_id"
       export SQUARE_APPLICATION_ID="your_square_application_id"

       Get your credentials from: https://developer.squareup.com/apps

    3. Customize priv/square_plans.json:
       - Update pricing to match your plans
       - Add your Square plan/variation IDs from Square Dashboard
       - Customize features and descriptions for your app

    That's it! Your subscription system is ready to use. 🎉
    Visit /subscription to see it in action.
    """)
  end
end
