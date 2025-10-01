defmodule Mix.Tasks.SquareClient.Install do
  @moduledoc """
  Installs SquareClient into a Phoenix application.

  This task generates all the necessary files and configuration for Square
  subscription management, including:

  - Square client configuration
  - Subscription schema and migration
  - Webhook handler implementation
  - Webhook controller
  - Router configuration

  ## Usage

      # Auto-detect everything (recommended for Phoenix gen.auth apps)
      mix igniter.install square_client

      # Or run the task directly
      mix square_client.install

  ## Auto-Detection

  The installer automatically detects:

    * **App module prefix** - From your application name (e.g., `Contacts4us`)
    * **Owner module** - Defaults to `AppName.Accounts.User` (Phoenix gen.auth convention)
    * **Owner key** - Defaults to `:user_id`

  ## Options

  All options are optional and only needed for non-standard setups:

    * `--owner-module` - Override the owner module
      Default: `YourApp.Accounts.User`

    * `--owner-key` - Override the foreign key name
      Default: Derived from owner module (`:user_id` for User)

  ## Examples

      # Standard Phoenix gen.auth app (auto-detects everything)
      mix igniter.install square_client

      # Custom owner module
      mix square_client.install --owner-module MyApp.Organizations.Account
  """
  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _source) do
    %Igniter.Mix.Task.Info{
      group: :square_client,
      adds_deps: [
        {:square_client, github: "zyzyva/square_client"}
      ],
      installs: [],
      example: "mix square_client.install --owner-module MyApp.Accounts.User"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    module_prefix = get_module_prefix(igniter)

    # Auto-detect owner module (Phoenix gen.auth default)
    owner_module = get_option(igniter, :owner_module) ||
                   Module.concat([module_prefix, "Accounts", "User"])

    owner_key = get_option(igniter, :owner_key) || derive_owner_key(owner_module)

    igniter
    |> Igniter.Project.Config.configure(
      "config.exs",
      :square_client,
      [:api_url],
      "https://connect.squareupsandbox.com/v2"
    )
    |> Igniter.Project.Config.configure(
      "config.exs",
      :square_client,
      [:access_token],
      quote do
        System.get_env("SQUARE_ACCESS_TOKEN")
      end
    )
    |> Igniter.Project.Config.configure(
      "config.exs",
      :square_client,
      [:location_id],
      quote do
        System.get_env("SQUARE_LOCATION_ID")
      end
    )
    |> Igniter.Project.Config.configure(
      "config.exs",
      :square_client,
      [:webhook_handler],
      Module.concat([module_prefix, "Payments", "SquareWebhookHandler"])
    )
    |> Igniter.Project.Config.configure(
      "prod.exs",
      :square_client,
      [:api_url],
      "https://connect.squareup.com/v2"
    )
    |> generate_subscription_schema(module_prefix, owner_module, owner_key)
    |> generate_webhook_handler(module_prefix)
    |> generate_webhook_controller(module_prefix)
    |> add_runtime_validation(module_prefix)
    |> add_router_configuration(module_prefix)
    |> generate_migration(owner_key)
  end

  defp get_option(igniter, key) do
    Igniter.Util.Options.get_option(igniter.args.options, key, fn val ->
      {:ok, String.to_atom(val)}
    end)
  end

  defp get_module_prefix(igniter) do
    # Try to detect the application module prefix
    app_name = Igniter.Project.Application.app_name(igniter)

    app_name
    |> Atom.to_string()
    |> Macro.camelize()
    |> String.to_atom()
  end

  defp derive_owner_key(owner_module) when is_atom(owner_module) do
    owner_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> then(&"#{&1}_id")
    |> String.to_atom()
  end

  defp derive_owner_key(_), do: :user_id

  defp generate_subscription_schema(igniter, module_prefix, owner_module, owner_key) do
    schema_module = Module.concat([module_prefix, "Payments", "Subscription"])
    repo_module = Module.concat([module_prefix, "Repo"])
    owner_module = owner_module || Module.concat([module_prefix, "Accounts", "User"])

    schema_contents = """
    defmodule #{inspect(schema_module)} do
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

    Igniter.Code.Module.create_module(
      igniter,
      schema_module,
      schema_contents
    )
  end

  defp generate_webhook_handler(igniter, module_prefix) do
    handler_module = Module.concat([module_prefix, "Payments", "SquareWebhookHandler"])
    subscription_module = Module.concat([module_prefix, "Payments", "Subscription"])
    repo_module = Module.concat([module_prefix, "Repo"])

    handler_contents = """
    defmodule #{inspect(handler_module)} do
      @moduledoc \"\"\"
      Handles Square webhook events.

      This module implements the SquareClient.WebhookHandler behaviour to process
      webhook events from Square, such as subscription updates and payment events.
      \"\"\"

      @behaviour SquareClient.WebhookHandler

      alias #{inspect(subscription_module)}
      alias #{inspect(repo_module)}

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

    Igniter.Code.Module.create_module(
      igniter,
      handler_module,
      handler_contents
    )
  end

  defp generate_webhook_controller(igniter, module_prefix) do
    controller_module = Module.concat([module_prefix <> "Web", "SquareWebhookController"])

    controller_contents = """
    defmodule #{inspect(controller_module)} do
      @moduledoc \"\"\"
      Controller for handling Square webhook events.

      This controller uses the SquareClient.Controllers.WebhookController
      behavior which provides standard webhook response handling.
      \"\"\"

      use #{inspect(Module.concat([module_prefix <> "Web", :controller]))}
      use SquareClient.Controllers.WebhookController
    end
    """

    Igniter.Code.Module.create_module(
      igniter,
      controller_module,
      controller_contents
    )
  end

  defp add_runtime_validation(igniter, module_prefix) do
    app_module = Module.concat([module_prefix, "Application"])

    Igniter.Code.Module.find_and_update_module!(igniter, app_module, fn zipper ->
      # Add the validation call at the start of the start/2 function
      Igniter.Code.Function.move_to_function_call_in_current_scope(
        zipper,
        :start,
        2
      )
      |> case do
        {:ok, zipper} ->
          # Insert validation at the beginning of the function
          validation_code = """
          # Validate Square configuration at runtime
          # This catches missing config and env vars before the app starts
          # Provides clear error messages with examples
          SquareClient.Config.validate_runtime!()
          """

          {:ok, Igniter.Code.Common.add_code(zipper, validation_code)}

        _ ->
          {:ok, zipper}
      end
    end)
  end

  defp add_router_configuration(igniter, module_prefix) do
    router_module = Module.concat([module_prefix <> "Web", "Router"])

    # Add the webhook pipeline and route
    pipeline_code = """
    pipeline :square_webhook do
      plug :accepts, ["json"]
      plug SquareClient.WebhookPlug
    end
    """

    route_code = """
    scope "/webhooks", #{inspect(module_prefix)}Web do
      pipe_through :square_webhook
      post "/square", SquareWebhookController, :handle
    end
    """

    igniter
    |> Igniter.Code.Module.find_and_update_module!(router_module, fn zipper ->
      zipper
      |> Igniter.Code.Common.add_code(pipeline_code)
      |> Igniter.Code.Common.add_code(route_code)
      |> then(&{:ok, &1})
    end)
  end

  defp generate_migration(igniter, owner_key) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    migration_name = "create_subscriptions"

    migration_contents = """
    defmodule #{inspect(Module.concat([Igniter.Project.Application.app_name(igniter), "Repo", "Migrations", "CreateSubscriptions"]))} do
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
          add #{inspect(owner_key)}, references(:#{pluralize_owner_key(owner_key)}, on_delete: :delete_all), null: false

          timestamps(type: :utc_datetime)
        end

        create unique_index(:subscriptions, [:square_subscription_id])
        create index(:subscriptions, [#{inspect(owner_key)}])
        create index(:subscriptions, [:status])
      end
    end
    """

    Igniter.Code.Module.create_module(
      igniter,
      Module.concat([
        Igniter.Project.Application.app_name(igniter),
        "Repo",
        "Migrations",
        "#{timestamp}_#{migration_name}"
      ]),
      migration_contents
    )
  end

  defp pluralize_owner_key(owner_key) do
    owner_key
    |> Atom.to_string()
    |> String.replace_suffix("_id", "s")
  end
end
