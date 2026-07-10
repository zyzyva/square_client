defmodule Mix.Tasks.Square.SetupPlans do
  @moduledoc """
  Set up Square subscription plans in the SANDBOX environment.

  Uses Square's recommended pattern:
  - Base plans (what you're selling)
  - Variations (how it's sold - monthly, yearly, etc.)

  Usage:
      mix square.setup_plans
      mix square.setup_plans --app my_app
      mix square.setup_plans --config custom_plans.json
      mix square.setup_plans --dry-run

  Options:
    --app       Optional. The application atom (defaults to current app)
    --config    Optional. Path to config file (default: square_plans.json)
    --dry-run   Preview changes without creating anything

  This will create the subscription plans and variations in your Square SANDBOX account
  and update the configuration file with the sandbox IDs.

  For production setup, use: mix square.setup_production
  """
  use Mix.Task

  alias SquareClient.{Plans, Catalog}

  @shortdoc "Create subscription plans in Square SANDBOX environment"

  @switches [
    app: :string,
    config: :string,
    dry_run: :boolean
  ]

  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_options(args)

    Mix.Task.run("app.start")

    IO.puts("Setting up Square SANDBOX subscription plans...")
    IO.puts("Using Square's recommended pattern: base plans with variations\n")

    maybe_announce_dry_run(opts.dry_run)

    plan_configs = Plans.get_plans(opts.app, opts.config_path)

    ensure_plans_configured!(plan_configs, opts)

    process_plans(opts.dry_run, plan_configs, opts)

    print_next_steps(opts.app)
  end

  defp parse_options(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    %{
      app: get_app(opts[:app]),
      config_path: opts[:config] || "square_plans.json",
      dry_run: opts[:dry_run] || false
    }
  end

  defp maybe_announce_dry_run(true = _dry_run) do
    IO.puts("🔍 DRY RUN MODE - No changes will be made\n")
  end

  defp maybe_announce_dry_run(false = _dry_run), do: :ok

  defp ensure_plans_configured!(plan_configs, opts) when map_size(plan_configs) == 0 do
    IO.puts("❌ No plans configured in #{opts.config_path}")
    IO.puts("   Please configure your plans first.")
    IO.puts("\nYou can initialize a config file with:")
    IO.puts("   mix square.init_plans --app #{opts.app}")
    exit(:normal)
  end

  defp ensure_plans_configured!(_plan_configs, _opts), do: :ok

  defp process_plans(false = _dry_run, plan_configs, opts) do
    Enum.each(plan_configs, fn {plan_key, plan_config} ->
      process_plan(plan_key, plan_config, opts)
    end)

    IO.puts("\n✅ Sandbox setup complete!")
  end

  defp process_plans(true = _dry_run, plan_configs, _opts) do
    IO.puts("📋 Plans that would be processed:")

    Enum.each(plan_configs, fn {_plan_key, plan_config} ->
      preview_plan(plan_config)
    end)

    IO.puts("\n📋 Dry run complete. Run without --dry-run to apply changes.")
  end

  defp process_plan(plan_key, plan_config, opts) do
    IO.puts("📦 Processing plan: #{plan_config["name"]}")

    # Step 1: Create or update base plan
    base_plan_id = ensure_base_plan(opts.app, plan_key, plan_config, opts.config_path)

    # Step 2: Create or update variations
    maybe_create_variations(base_plan_id, plan_key, plan_config, opts)

    IO.puts("")
  end

  defp maybe_create_variations(base_plan_id, plan_key, plan_config, opts) do
    if base_plan_id do
      create_variations(opts, plan_key, plan_config, base_plan_id)
    end
  end

  defp preview_plan(plan_config) do
    IO.puts("  - #{plan_config["name"]}")
    preview_variations(plan_config["variations"])
  end

  defp preview_variations(nil), do: :ok

  defp preview_variations(variations) do
    Enum.each(variations, fn {_var_key, var} ->
      preview_variation(var)
    end)
  end

  defp preview_variation(var) do
    if var["active"] != false do
      IO.puts("    • #{var["name"]} (#{variation_status(var)})")
    else
      IO.puts("    • #{var["name"]} (inactive - skipped)")
    end
  end

  defp variation_status(var) do
    if var["variation_id"] || var["sandbox_variation_id"] do
      "exists"
    else
      "would be created"
    end
  end

  defp print_next_steps(app) do
    IO.puts("\nNext steps:")
    IO.puts("1. Verify plans: mix square.list_plans --app #{app}")
    IO.puts("2. Test thoroughly in sandbox")
    IO.puts("3. When ready for production: mix square.setup_production --app #{app}")
    IO.puts("4. Commit the updated configuration to version control")
  end

  defp get_app(nil) do
    # Infer from the current Mix project
    Mix.Project.config()[:app] ||
      raise "Could not determine application. Please specify --app explicitly."
  end

  defp get_app(app_string) when is_binary(app_string) do
    String.to_atom(app_string)
  end

  defp ensure_base_plan(app, plan_key, plan_config, config_path) do
    # Check for sandbox ID (after environment transformation)
    if plan_config["base_plan_id"] do
      IO.puts("   ✓ Sandbox base plan already exists: #{plan_config["base_plan_id"]}")
      plan_config["base_plan_id"]
    else
      IO.puts("   📝 Creating base plan...")

      # Add app prefix to plan name for clarity in Square Dashboard
      prefixed_name = get_prefixed_plan_name(app, plan_config["name"])

      case Catalog.create_base_subscription_plan(%{
             name: prefixed_name,
             description: plan_config["description"]
           }) do
        {:ok, result} ->
          IO.puts("   ✅ Created sandbox base plan: #{result.plan_id}")

          # Save to config
          Plans.update_base_plan_id(app, plan_key, result.plan_id, config_path)

          result.plan_id

        {:error, reason} ->
          IO.puts("   ❌ Failed to create base plan: #{inspect(reason)}")
          nil
      end
    end
  end

  defp create_variations(opts, plan_key, plan_config, base_plan_id) do
    ctx = %{
      app: opts.app,
      config_path: opts.config_path,
      plan_key: plan_key,
      base_plan_id: base_plan_id
    }

    Enum.each(plan_config["variations"] || %{}, fn {variation_key, variation_config} ->
      process_variation(ctx, variation_key, variation_config)
    end)
  end

  defp process_variation(ctx, variation_key, variation_config) do
    variation_id = variation_config["variation_id"] || variation_config["sandbox_variation_id"]

    dispatch_variation(
      variation_id,
      variation_config["active"] != false,
      ctx,
      variation_key,
      variation_config
    )
  end

  # Has ID and is active - ensure it's active in Square
  defp dispatch_variation(variation_id, true, _ctx, _variation_key, variation_config)
       when not is_nil(variation_id) do
    ensure_variation_active(variation_id, variation_config["name"])
  end

  # Has ID but inactive - ensure it's deactivated in Square
  defp dispatch_variation(variation_id, false, _ctx, _variation_key, variation_config)
       when not is_nil(variation_id) do
    ensure_variation_inactive(variation_id, variation_config["name"])
  end

  # No ID but active - create it
  defp dispatch_variation(nil, true, ctx, variation_key, variation_config) do
    IO.puts("   📝 Creating variation: #{variation_config["name"]}")
    create_sandbox_variation(ctx, variation_key, variation_config)
  end

  # No ID and inactive - skip
  defp dispatch_variation(nil, false, _ctx, _variation_key, variation_config) do
    IO.puts("   ⏭️  Skipping inactive variation: #{variation_config["name"]}")
  end

  defp create_sandbox_variation(ctx, variation_key, variation_config) do
    case Catalog.create_plan_variation(%{
           base_plan_id: ctx.base_plan_id,
           name: variation_config["name"],
           cadence: variation_config["cadence"],
           amount: variation_config["amount"],
           currency: variation_config["currency"]
         }) do
      {:ok, result} ->
        IO.puts("   ✅ Created sandbox variation: #{result.variation_id}")

        # Save to config
        Plans.update_variation_id(
          ctx.app,
          ctx.plan_key,
          variation_key,
          result.variation_id,
          ctx.config_path
        )

      {:error, reason} ->
        IO.puts("   ❌ Failed to create variation: #{inspect(reason)}")
    end
  end

  defp ensure_variation_active(variation_id, name) do
    case get_catalog_status(variation_id) do
      {:ok, :active} ->
        IO.puts("   ✓ Sandbox variation '#{name}' is active: #{variation_id}")

      {:ok, :deleted} ->
        IO.puts("   🔄 Reactivating variation '#{name}': #{variation_id}")
        update_catalog_status(variation_id, false)

      {:error, :not_found} ->
        IO.puts("   ⚠️  Variation '#{name}' not found in Square: #{variation_id}")

      _ ->
        IO.puts("   ✓ Sandbox variation '#{name}' exists: #{variation_id}")
    end
  end

  defp ensure_variation_inactive(variation_id, name) do
    case get_catalog_status(variation_id) do
      {:ok, :active} ->
        IO.puts("   🔄 Deactivating variation '#{name}': #{variation_id}")
        update_catalog_status(variation_id, true)

      {:ok, :deleted} ->
        IO.puts("   ✓ Variation '#{name}' is already deactivated: #{variation_id}")

      {:error, :not_found} ->
        IO.puts("   ⏭️  Variation '#{name}' doesn't exist (inactive): #{variation_id}")

      _ ->
        IO.puts("   ⏭️  Skipping inactive variation '#{name}': #{variation_id}")
    end
  end

  defp get_catalog_status(object_id) do
    case Catalog.get(object_id) do
      {:ok, %{"present_at_all_locations" => false}} -> {:ok, :deleted}
      {:ok, _} -> {:ok, :active}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :unknown}
    end
  end

  defp update_catalog_status(object_id, should_deactivate) do
    case Catalog.get(object_id) do
      {:ok, current_object} ->
        # Set present_at_all_locations to false to deactivate, true to activate
        updated_object = Map.put(current_object, "present_at_all_locations", !should_deactivate)
        post_catalog_update(updated_object, should_deactivate)

      {:error, reason} ->
        IO.puts("     ❌ Failed to get current object: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp post_catalog_update(updated_object, should_deactivate) do
    body = %{
      idempotency_key: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      object: updated_object
    }

    api_url = SquareClient.Config.api_url!()
    access_token = SquareClient.Config.access_token!()

    response =
      Req.post(
        "#{api_url}/catalog/object",
        json: body,
        headers: [
          {"Authorization", "Bearer #{access_token}"},
          {"Square-Version", "2025-01-23"}
        ]
      )

    handle_catalog_update_response(response, should_deactivate)
  end

  defp handle_catalog_update_response({:ok, %{status: status}}, should_deactivate)
       when status in 200..299 do
    action = if should_deactivate, do: "Deactivated", else: "Reactivated"
    IO.puts("     ✅ #{action} successfully")
    :ok
  end

  defp handle_catalog_update_response({:ok, %{status: status, body: body}}, _should_deactivate) do
    error_msg = extract_error_message(body)
    IO.puts("     ❌ Failed to update status: #{error_msg}")
    {:error, status}
  end

  defp handle_catalog_update_response({:error, reason}, _should_deactivate) do
    IO.puts("     ❌ Failed to update: #{inspect(reason)}")
    {:error, reason}
  end

  defp extract_error_message(%{"errors" => [%{"detail" => detail} | _]}), do: detail
  defp extract_error_message(%{"errors" => errors}) when is_list(errors), do: "#{inspect(errors)}"
  defp extract_error_message(body), do: "HTTP error: #{inspect(body)}"

  defp get_prefixed_plan_name(app, plan_name) do
    # Check if custom prefix is configured
    prefix =
      Application.get_env(:square_client, :plan_name_prefix) ||
        Application.get_env(app, :square_plan_prefix) ||
        format_app_name(app)

    # Don't double-prefix if it already starts with the prefix
    if String.starts_with?(plan_name, prefix) do
      plan_name
    else
      "#{prefix} #{plan_name}"
    end
  end

  defp format_app_name(app) do
    app
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end
end
