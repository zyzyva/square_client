defmodule SquareClient.Subscriptions.Schema do
  @moduledoc """
  Reusable Ecto schema for Square subscriptions.

  This module provides a `__using__` macro that defines a complete subscription schema
  with all necessary fields, changesets, and query helpers. Apps can inject their own
  associations (like `belongs_to :user`) while getting all the Square-specific fields.

  ## Usage

      defmodule MyApp.Payments.Subscription do
        use SquareClient.Subscriptions.Schema,
          repo: MyApp.Repo,
          belongs_to: [
            {:user, MyApp.Accounts.User}
          ]
      end

  ## Options

    * `:repo` - The Ecto repo module for your application (required)
    * `:belongs_to` - List of `{field_name, module}` tuples for associations (optional)
    * `:table_name` - Custom table name (default: "subscriptions")

  ## Fields

  The schema includes all standard Square subscription fields:
    * `square_subscription_id` - Square's subscription ID
    * `plan_id` - Your app's plan identifier
    * `status` - Subscription status (PENDING, ACTIVE, CANCELED, etc.)
    * `card_id` - Associated payment card ID
    * `payment_id` - Associated payment ID (for one-time purchases)
    * `started_at` - When subscription started
    * `canceled_at` - When subscription was canceled
    * `next_billing_at` - Next billing date
    * `trial_ends_at` - Trial period end date
    * `inserted_at` / `updated_at` - Standard timestamps

  ## Query Helpers

  The module provides several query helpers:
    * `active/0` - Query for active subscriptions
    * `for_owner/2` - Query subscriptions for a specific owner
    * `most_recent/1` - Order by most recent first
  """

  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    belongs_to_associations = Keyword.get(opts, :belongs_to, [])
    table_name = Keyword.get(opts, :table_name, "subscriptions")

    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import Ecto.Query, warn: false

      alias unquote(repo), as: Repo
      alias __MODULE__

      @primary_key {:id, :id, autogenerate: true}
      schema unquote(table_name) do
        field(:square_subscription_id, :string)
        field(:plan_id, :string)
        field(:status, :string)
        field(:card_id, :string)
        field(:payment_id, :string)
        field(:started_at, :utc_datetime)
        field(:canceled_at, :utc_datetime)
        field(:next_billing_at, :utc_datetime)
        field(:trial_ends_at, :utc_datetime)

        # Inject belongs_to associations
        unquote_splicing(
          for {field_name, module} <- belongs_to_associations do
            quote do
              belongs_to(unquote(field_name), unquote(module))
            end
          end
        )

        timestamps(type: :utc_datetime)
      end

      @doc """
      Changeset for creating or updating a subscription.
      """
      def changeset(subscription, attrs) do
        # Get owner field name (e.g., :user_id) from belongs_to associations
        owner_field =
          unquote(belongs_to_associations)
          |> List.first()
          |> case do
            {field_name, _module} -> :"#{field_name}_id"
            nil -> nil
          end

        required_fields = [:plan_id, :status] ++ if owner_field, do: [owner_field], else: []

        subscription
        |> cast(attrs, [
          owner_field,
          :square_subscription_id,
          :plan_id,
          :status,
          :card_id,
          :payment_id,
          :started_at,
          :canceled_at,
          :next_billing_at,
          :trial_ends_at
        ])
        |> validate_required(required_fields)
        |> validate_inclusion(:status, [
          "PENDING",
          "ACTIVE",
          "CANCELED",
          "PAUSED",
          "DELINQUENT"
        ])
        |> unique_constraint(:square_subscription_id)
        |> foreign_key_constraint(owner_field)
      end

      @doc """
      Query for active subscriptions (ACTIVE or PENDING status).
      """
      def active do
        from(s in __MODULE__,
          where: s.status in ["ACTIVE", "PENDING"]
        )
      end

      @doc """
      Query subscriptions for a specific owner.

      Accepts either an owner struct with an :id field or an integer ID.
      """
      def for_owner(query \\ __MODULE__, owner)

      def for_owner(query, owner_id) when is_integer(owner_id) do
        owner_field =
          unquote(belongs_to_associations)
          |> List.first()
          |> case do
            {field_name, _module} -> :"#{field_name}_id"
            nil -> raise "No belongs_to association defined"
          end

        from(s in query,
          where: field(s, ^owner_field) == ^owner_id
        )
      end

      def for_owner(query, %{id: owner_id}) do
        for_owner(query, owner_id)
      end

      @doc """
      Get the most recent active subscription for an owner.
      """
      def get_active_for_owner(owner_id) when is_integer(owner_id) do
        owner_field =
          unquote(belongs_to_associations)
          |> List.first()
          |> case do
            {field_name, _module} -> :"#{field_name}_id"
            nil -> raise "No belongs_to association defined"
          end

        active_statuses = ["ACTIVE", "PENDING"]

        from(s in __MODULE__,
          where: field(s, ^owner_field) == ^owner_id,
          where: s.status in ^active_statuses,
          order_by: [
            fragment("CASE WHEN ? = 'ACTIVE' THEN 0 ELSE 1 END", s.status),
            desc: s.inserted_at
          ],
          limit: 1
        )
        |> Repo.one()
      end

      def get_active_for_owner(%{id: owner_id}) do
        get_active_for_owner(owner_id)
      end

      @doc """
      Order subscriptions by most recent first.
      """
      def most_recent(query \\ __MODULE__) do
        from(s in query,
          order_by: [desc: s.inserted_at]
        )
      end

      @doc """
      Generate migration code for creating the subscriptions table.

      Returns a string that can be used in a migration file.
      """
      def migration_code do
        owner_field =
          unquote(belongs_to_associations)
          |> List.first()
          |> case do
            {field_name, module} ->
              table_name =
                module
                |> Module.split()
                |> List.last()
                |> Macro.underscore()
                |> Kernel.<>("s")

              {field_name, table_name}

            nil ->
              nil
          end

        """
        defmodule MyApp.Repo.Migrations.CreateSubscriptions do
          use Ecto.Migration

          def change do
            create table(:#{unquote(table_name)}) do
              #{if owner_field do
          {field, table} = owner_field
          "add :#{field}_id, references(:#{table}, on_delete: :delete_all), null: false"
        end}
              add :square_subscription_id, :string
              add :plan_id, :string, null: false
              add :status, :string, null: false
              add :card_id, :string
              add :payment_id, :string
              add :started_at, :utc_datetime
              add :canceled_at, :utc_datetime
              add :next_billing_at, :utc_datetime
              add :trial_ends_at, :utc_datetime

              timestamps(type: :utc_datetime)
            end

            #{if owner_field do
          {field, _table} = owner_field
          """
          create index(:#{unquote(table_name)}, [:#{field}_id])
          create unique_index(:#{unquote(table_name)}, [:square_subscription_id])
          """
        else
          "create unique_index(:#{unquote(table_name)}, [:square_subscription_id])"
        end}
          end
        end
        """
      end
    end
  end
end
