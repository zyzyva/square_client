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

  This task has no options - it auto-detects everything from your Phoenix app.

  Assumptions:
  - App follows Phoenix gen.auth conventions
  - Owner module is `YourApp.Accounts.User`
  - Foreign key is `:user_id`
  - Repo module is `YourApp.Repo`
  """

  use Mix.Task

  @shortdoc "Generates Square subscription management files"

  def run(_args) do
    # Get app information
    app_name = Mix.Project.config()[:app]
    module_prefix = app_name |> Atom.to_string() |> Macro.camelize()
    owner_module = Module.concat([module_prefix, "Accounts", "User"])
    owner_key = :user_id
    repo_module = Module.concat([module_prefix, "Repo"])

    Mix.shell().info("Installing SquareClient for #{module_prefix}...")

    # Create directories
    payments_dir = "lib/#{Macro.underscore(module_prefix)}/payments"
    File.mkdir_p!(payments_dir)

    controllers_dir = "lib/#{Macro.underscore(module_prefix)}_web/controllers"
    File.mkdir_p!(controllers_dir)

    # Generate files
    create_subscription_schema(module_prefix, owner_module, owner_key, repo_module, payments_dir)
    create_webhook_handler(module_prefix, payments_dir)
    create_webhook_controller(module_prefix, controllers_dir)
    create_migration(module_prefix, owner_key)
    update_config(module_prefix)

    # Print manual steps
    print_manual_steps(module_prefix)

    Mix.shell().info("\n✅ Square Client installation complete!")
  end

  defp create_subscription_schema(module_prefix, owner_module, owner_key, repo_module, dir) do
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
          {#{inspect(owner_key)}, #{inspect(owner_module)}}
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
        SquareClient.Subscriptions.Context.sync_from_square(
          Subscription,
          Repo,
          square_sub
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
          add :square_subscription_id, :string, null: false
          add :square_customer_id, :string
          add :status, :string, null: false
          add :tier, :string, null: false
          add :charged_through_date, :date
          add :canceled_date, :date
          add :start_date, :date
          add :next_billing_date, :date
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
        Mix.shell().info("  * Config already contains production :square_client - skipping prod.exs")
      else
        File.write!(prod_path, existing <> prod_addition)
        Mix.shell().info("  * Updated #{prod_path}")
      end
    end
  end

  defp print_manual_steps(module_prefix) do
    Mix.shell().info("""

    📋 Manual Steps Required:

    1. Add runtime validation to lib/#{Macro.underscore(module_prefix)}/application.ex:

       def start(_type, _args) do
         SquareClient.Config.validate_runtime!()
         # ... rest of your code
       end

    2. Add webhook route to lib/#{Macro.underscore(module_prefix)}_web/router.ex:

       pipeline :square_webhook do
         plug :accepts, ["json"]
         plug SquareClient.WebhookPlug
       end

       scope "/webhooks", #{module_prefix}Web do
         pipe_through :square_webhook
         post "/square", SquareWebhookController, :handle
       end

    3. Run the migration:

       mix ecto.migrate

    4. Set environment variables:

       export SQUARE_ACCESS_TOKEN="your_sandbox_token"
       export SQUARE_LOCATION_ID="your_location_id"

    Get your credentials from: https://developer.squareup.com/apps
    """)
  end
end
