defmodule SquareClient.Plans do
  @moduledoc """
  Manages Square subscription plan configurations from JSON file.
  Supports Square's recommended pattern: base plans with variations.

  This module provides plan configuration management for applications
  using the Square Client library.
  """

  @doc """
  Get all one-time purchases for the current environment.

  ## Parameters

    * `app` - The application atom
    * `config_path` - Path to the config file (default: "square_plans.json")

  ## Examples

      SquareClient.Plans.get_one_time_purchases(:my_app)
  """
  @spec get_one_time_purchases(atom(), String.t()) :: map()
  def get_one_time_purchases(app, config_path \\ "square_plans.json") do
    config = load_config(app, config_path)

    case config["one_time_purchases"] do
      nil -> %{}
      purchases -> purchases
    end
  end

  @doc """
  Get a specific one-time purchase by key.

  ## Parameters

    * `app` - The application atom
    * `purchase_key` - The purchase identifier
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  @spec get_one_time_purchase(atom(), String.t() | atom(), String.t()) :: map() | nil
  def get_one_time_purchase(app, purchase_key, config_path \\ "square_plans.json") do
    purchases = get_one_time_purchases(app, config_path)
    purchases[to_string(purchase_key)]
  end

  @doc """
  Get all plan configurations with environment-specific IDs.

  ## Parameters

    * `app` - The application atom (e.g., :my_app)
    * `config_path` - Path to the config file relative to app's priv directory
                      (default: "square_plans.json")

  ## Examples

      SquareClient.Plans.get_plans(:my_app)
      SquareClient.Plans.get_plans(:my_app, "custom_plans.json")
  """
  @spec get_plans(atom(), String.t()) :: map()
  def get_plans(app, config_path \\ "square_plans.json") do
    config = load_config(app, config_path)
    env = environment(app)

    extract_plans(config, env)
  end

  # Extract plans from config
  defp extract_plans(%{"plans" => plans}, env) when is_map(plans) do
    # Transform each plan for the environment
    Map.new(plans, fn {key, plan} ->
      {key, transform_plan_for_environment(plan, env)}
    end)
  end

  defp extract_plans(_, _), do: %{}

  @doc """
  Get a specific plan configuration by plan key.

  ## Parameters

    * `app` - The application atom
    * `plan_key` - The plan identifier (string or atom)
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  @spec get_plan(atom(), String.t() | atom(), String.t()) :: map() | nil
  def get_plan(app, plan_key, config_path \\ "square_plans.json")

  def get_plan(app, plan_key, config_path) when is_binary(plan_key) do
    plans = get_plans(app, config_path)
    plans[plan_key]
  end

  def get_plan(app, plan_key, config_path) when is_atom(plan_key) do
    get_plan(app, Atom.to_string(plan_key), config_path)
  end

  @doc """
  Get a specific variation for a plan.

  ## Parameters

    * `app` - The application atom
    * `plan_key` - The plan identifier
    * `variation_key` - The variation identifier (e.g., "monthly", "yearly")
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  @spec get_variation(atom(), String.t() | atom(), String.t() | atom(), String.t()) ::
          map() | nil
  def get_variation(app, plan_key, variation_key, config_path \\ "square_plans.json") do
    case get_plan(app, plan_key, config_path) do
      %{"variations" => variations} when is_map(variations) ->
        variations[to_string(variation_key)]

      _ ->
        nil
    end
  end

  @doc """
  Get the Square variation ID for a specific plan variation.
  Returns nil if not configured.

  ## Parameters

    * `app` - The application atom
    * `plan_key` - The plan identifier
    * `variation_key` - The variation identifier
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  @spec get_variation_id(atom(), String.t() | atom(), String.t() | atom(), String.t()) ::
          String.t() | nil
  def get_variation_id(app, plan_key, variation_key, config_path \\ "square_plans.json") do
    case get_variation(app, plan_key, variation_key, config_path) do
      %{"variation_id" => id} -> id
      _ -> nil
    end
  end

  @doc """
  Update base plan ID after creation in Square.

  ## Parameters

    * `app` - The application atom
    * `plan_key` - The plan identifier
    * `base_plan_id` - The Square-generated plan ID
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  @spec update_base_plan_id(atom(), String.t(), String.t() | nil, String.t()) :: :ok
  def update_base_plan_id(app, plan_key, base_plan_id, config_path \\ "square_plans.json") do
    updated_config =
      app
      |> load_config(config_path)
      |> put_base_plan_id(environment(app), plan_key, base_plan_id)

    save_config(app, updated_config, config_path)
  end

  defp put_base_plan_id(config, env, plan_key, base_plan_id) do
    config
    |> ensure_plan_exists(plan_key)
    |> put_in(["plans", plan_key, environment_id_field(env, :base)], base_plan_id)
  end

  defp ensure_plan_exists(config, plan_key) do
    config = Map.put_new(config, "plans", %{})

    # Ensure the plan exists with both sandbox and production ID fields
    default_plan = %{
      "sandbox_base_plan_id" => nil,
      "production_base_plan_id" => nil
    }

    existing_plan = config["plans"][plan_key] || default_plan
    put_in(config, ["plans", plan_key], existing_plan)
  end

  defp environment_id_field("production", :base), do: "production_base_plan_id"
  defp environment_id_field(_, :base), do: "sandbox_base_plan_id"
  defp environment_id_field("production", :variation), do: "production_variation_id"
  defp environment_id_field(_, :variation), do: "sandbox_variation_id"

  @doc """
  Update variation ID after creation in Square.

  ## Parameters

    * `app` - The application atom
    * `plan_key` - The plan identifier
    * `variation_key` - The variation identifier
    * `variation_id` - The Square-generated variation ID
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  @spec update_variation_id(atom(), String.t(), String.t(), String.t() | nil, String.t()) :: :ok
  def update_variation_id(
        app,
        plan_key,
        variation_key,
        variation_id,
        config_path \\ "square_plans.json"
      ) do
    updated_config =
      app
      |> load_config(config_path)
      |> put_variation_id(environment(app), plan_key, variation_key, variation_id)

    save_config(app, updated_config, config_path)
  end

  defp put_variation_id(config, env, plan_key, variation_key, variation_id) do
    id_field = environment_id_field(env, :variation)

    config
    |> ensure_variation_exists(plan_key, variation_key)
    |> put_in(["plans", plan_key, "variations", variation_key, id_field], variation_id)
  end

  defp ensure_variation_exists(config, plan_key, variation_key) do
    config
    |> ensure_plan_exists(plan_key)
    |> put_in(
      ["plans", plan_key, "variations"],
      config["plans"][plan_key]["variations"] || %{}
    )
    |> put_in(
      ["plans", plan_key, "variations", variation_key],
      config["plans"][plan_key]["variations"][variation_key] || %{}
    )
  end

  @doc """
  Check if all plans and variations have IDs configured.

  ## Parameters

    * `app` - The application atom
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  @spec all_configured?(atom(), String.t()) :: boolean()
  def all_configured?(app, config_path \\ "square_plans.json") do
    plans = get_plans(app, config_path)

    Enum.all?(plans, fn
      {_key, %{"base_plan_id" => base_id, "variations" => variations}}
      when is_binary(base_id) and is_map(variations) ->
        Enum.all?(variations, fn
          {_vkey, %{"variation_id" => var_id}} when is_binary(var_id) -> true
          _ -> false
        end)

      {_key, %{"type" => "free"}} ->
        # Free plans don't need Square IDs
        true

      _ ->
        false
    end)
  end

  @doc """
  List plans and variations that need to be created in Square.

  ## Parameters

    * `app` - The application atom
    * `config_path` - Path to the config file (default: "square_plans.json")

  ## Returns

  A map with:
    * `:base_plans` - List of base plans that need creation
    * `:variations` - List of variations that need creation
  """
  @spec unconfigured_items(atom(), String.t()) :: %{base_plans: list(), variations: list()}
  def unconfigured_items(app, config_path \\ "square_plans.json") do
    plans = get_plans(app, config_path)

    Enum.reduce(plans, %{base_plans: [], variations: []}, &collect_unconfigured/2)
  end

  # Skip free plans - they don't need Square IDs
  defp collect_unconfigured({_plan_key, %{"type" => "free"}}, acc), do: acc

  # Plan needs a base plan ID, but still track any variations for creation
  defp collect_unconfigured({plan_key, %{"base_plan_id" => nil} = plan}, acc) do
    acc = %{acc | base_plans: [{plan_key, plan} | acc.base_plans]}
    add_unconfigured_variations(acc, plan, plan_key, nil)
  end

  # Plan has a base ID - check its variations for missing IDs
  defp collect_unconfigured(
         {plan_key, %{"base_plan_id" => base_id, "variations" => variations}},
         acc
       )
       when is_map(variations) do
    needed = variations_needing_creation(variations, plan_key, base_id)
    %{acc | variations: needed ++ acc.variations}
  end

  # Plan has ID but no variations - that's ok
  defp collect_unconfigured({_plan_key, %{"base_plan_id" => base_id}}, acc)
       when is_binary(base_id),
       do: acc

  # Skip any other format
  defp collect_unconfigured(_entry, acc), do: acc

  defp add_unconfigured_variations(acc, %{"variations" => variations}, plan_key, base_id)
       when is_map(variations) do
    needed = variations_needing_creation(variations, plan_key, base_id)
    %{acc | variations: needed ++ acc.variations}
  end

  defp add_unconfigured_variations(acc, _plan, _plan_key, _base_id), do: acc

  defp variations_needing_creation(variations, plan_key, base_id) do
    variations
    |> Enum.reject(fn
      {_vkey, %{"variation_id" => id}} when is_binary(id) -> true
      _ -> false
    end)
    |> Enum.map(fn {vkey, variation} -> {plan_key, vkey, variation, base_id} end)
  end

  @doc """
  Initialize a default plan configuration file.

  Creates a new configuration file with example structure if it doesn't exist.

  ## Parameters

    * `app` - The application atom
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  @spec init_config(atom(), String.t()) :: {:ok, String.t()} | {:error, :already_exists}
  def init_config(app, config_path \\ "square_plans.json") do
    path = Application.app_dir(app, Path.join("priv", config_path))

    if File.exists?(path) do
      {:error, :already_exists}
    else
      default = default_config()

      # Ensure directory exists
      path |> Path.dirname() |> File.mkdir_p!()

      content = JSON.encode!(default)
      formatted = format_json(content)
      File.write!(path, formatted)

      {:ok, path}
    end
  end

  # Private functions

  defp load_config(app, config_path) do
    path = Application.app_dir(app, Path.join("priv", config_path))

    case File.read(path) do
      {:ok, content} ->
        case JSON.decode(content) do
          {:ok, config} -> config
          {:error, _} -> default_config()
        end

      {:error, _} ->
        default_config()
    end
  end

  defp save_config(app, config, config_path) do
    path = Application.app_dir(app, Path.join("priv", config_path))

    # Ensure directory exists
    path |> Path.dirname() |> File.mkdir_p!()

    # Native JSON module doesn't support pretty printing, so we'll format it ourselves
    content = JSON.encode!(config)
    formatted = format_json(content)
    File.write!(path, formatted)

    :ok
  end

  # Basic JSON formatting for readability
  defp format_json(json_string) do
    # This is a simple formatter - in production you might want something more robust
    json_string
    |> String.replace(~r/,(?=")/, ",\n    ")
    |> String.replace("{\"", "{\n  \"")
    |> String.replace("\"}", "\"\n}")
    |> String.replace(":{", ": {")
    |> String.replace("},", "},\n")
    |> String.replace("[{", "[\n  {")
    |> String.replace("}]", "}\n]")
  end

  @doc """
  Validate that immutable fields haven't changed on existing plan variations.

  Uses git to compare the current plans JSON with the last committed version, checking if
  variations with Square IDs have had their critical fields (amount, cadence, currency) modified.

  ## Parameters

    * `app` - The application atom
    * `config_path` - Path to the config file (default: "square_plans.json")

  ## Returns

    * `{:ok, []}` - No changes detected
    * `{:warning, changes}` - List of detected changes with details
    * `{:error, reason}` - Could not perform validation (e.g., not in git repo, file not committed)

  ## Example

      iex> SquareClient.Plans.validate_immutable_fields(:my_app)
      {:warning, [
        %{
          plan: "premium",
          variation: "monthly",
          field: "amount",
          old_value: 999,
          new_value: 1299,
          variation_id: "ABC123",
          message: "Price changed from $9.99 to $12.99 on existing variation - consider creating new variation"
        }
      ]}

  ## Notes

  This requires:
  - Git repository
  - The plans JSON file to be committed
  - Git binary available in PATH

  If git is not available or the file is not in a repo, returns `{:error, reason}`.
  """
  @spec validate_immutable_fields(atom(), String.t()) ::
          {:ok, list()} | {:warning, list()} | {:error, term()}
  def validate_immutable_fields(app, config_path \\ "square_plans.json") do
    full_path = Application.app_dir(app, Path.join("priv", config_path))

    with {:ok, old_content} <- get_git_version(full_path),
         {:ok, old_plans} <- parse_json_content(old_content),
         {:ok, current_plans} <- load_config_safe(app, config_path) do
      changes_result(detect_immutable_changes(old_plans, current_plans))
    end
  end

  defp changes_result([]), do: {:ok, []}
  defp changes_result(changes), do: {:warning, changes}

  defp get_git_version(file_path) do
    case System.cmd("git", ["show", "HEAD:#{file_path}"], stderr_to_stdout: true) do
      {content, 0} -> {:ok, content}
      {error, _} -> {:error, "Git error: #{error}"}
    end
  rescue
    _ -> {:error, "Git not available or not in a git repository"}
  end

  defp parse_json_content(content) do
    case Jason.decode(content) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, "Could not parse previous JSON version"}
    end
  end

  defp load_config_safe(app, config_path) do
    try do
      {:ok, load_config(app, config_path)}
    rescue
      _ -> {:error, "Could not load current configuration"}
    end
  end

  defp detect_immutable_changes(old_config, new_config) do
    immutable_fields = ["amount", "cadence", "currency"]
    old_plans = get_in(old_config, ["plans"]) || %{}
    new_plans = get_in(new_config, ["plans"]) || %{}

    Enum.flat_map(old_plans, fn {plan_key, old_plan} ->
      case {old_plan, new_plans[plan_key]} do
        {%{"variations" => old_variations}, %{"variations" => new_variations}}
        when is_map(old_variations) and is_map(new_variations) ->
          detect_variation_changes(plan_key, old_variations, new_variations, immutable_fields)

        _ ->
          []
      end
    end)
  end

  defp detect_variation_changes(plan_key, old_variations, new_variations, immutable_fields) do
    Enum.flat_map(old_variations, fn {var_key, old_var} ->
      detect_single_variation_changes(
        plan_key,
        var_key,
        old_var,
        new_variations[var_key],
        immutable_fields
      )
    end)
  end

  # No Square ID yet, changes are OK
  defp detect_single_variation_changes(
         _plan_key,
         _var_key,
         %{"variation_id" => nil},
         _new,
         _fields
       ),
       do: []

  # Variation was removed but still exists in Square
  defp detect_single_variation_changes(
         plan_key,
         var_key,
         %{"variation_id" => variation_id},
         nil,
         _fields
       )
       when not is_nil(variation_id) do
    [
      %{
        plan: plan_key,
        variation: var_key,
        variation_id: variation_id,
        field: :removed,
        message: "Variation removed from JSON but exists in Square - set active: false instead"
      }
    ]
  end

  # Variation exists in Square - check each immutable field
  defp detect_single_variation_changes(
         plan_key,
         var_key,
         %{"variation_id" => variation_id} = old_var,
         new_var,
         immutable_fields
       )
       when not is_nil(variation_id) do
    Enum.flat_map(immutable_fields, fn field ->
      immutable_field_change(
        plan_key,
        var_key,
        variation_id,
        field,
        old_var[field],
        new_var[field]
      )
    end)
  end

  # No Square ID (variation_id key absent) - changes are OK
  defp detect_single_variation_changes(_plan_key, _var_key, _old_var, _new_var, _fields), do: []

  defp immutable_field_change(_plan_key, _var_key, _variation_id, _field, old_value, new_value)
       when old_value == new_value or is_nil(old_value),
       do: []

  defp immutable_field_change(plan_key, var_key, variation_id, field, old_value, new_value) do
    [
      %{
        plan: plan_key,
        variation: var_key,
        field: field,
        old_value: old_value,
        new_value: new_value,
        variation_id: variation_id,
        message: format_change_message(field, old_value, new_value)
      }
    ]
  end

  defp format_change_message("amount", old, new) do
    old_price = format_price(old)
    new_price = format_price(new)

    "Price changed from #{old_price} to #{new_price} on existing variation - you must create a new variation with the new price instead"
  end

  defp format_change_message("cadence", old, new) do
    "Billing cadence changed from #{old} to #{new} on existing variation - you must create a new variation"
  end

  defp format_change_message("currency", old, new) do
    "Currency changed from #{old} to #{new} on existing variation - you must create a new variation"
  end

  defp format_change_message(field, old, new) do
    "Field '#{field}' changed from #{old} to #{new} on existing variation - this may require creating a new variation"
  end

  defp format_price(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp format_price(other), do: inspect(other)

  @doc """
  Get the current environment for an app (sandbox or production).

  Returns "sandbox" or "production" based on the app's config.

  Auto-detects from api_url if not explicitly configured.

  ## Why not use Mix.env() or config_env()?

  - `Mix.env()` is NOT available in production releases (Mix is a build tool)
  - `config_env()` is a compile-time macro that only works in config files

  Therefore, we detect from the configured `api_url` which works reliably
  in all environments including production releases.
  """
  @spec environment(atom()) :: String.t()
  def environment(app) do
    # Check app-specific environment config first
    # This allows each Phoenix app to configure its environment in config/*.exs files
    env =
      Application.get_env(app, :square_environment) ||
        Application.get_env(:square_client, :environment) ||
        System.get_env("SQUARE_ENVIRONMENT") ||
        detect_environment_from_api_url()

    normalize_environment(env)
  end

  defp normalize_environment(:sandbox), do: "sandbox"
  defp normalize_environment("sandbox"), do: "sandbox"
  defp normalize_environment(:production), do: "production"
  defp normalize_environment("production"), do: "production"
  defp normalize_environment("prod"), do: "production"
  # Default to sandbox for safety
  defp normalize_environment(_), do: "sandbox"

  # Auto-detect environment from configured API URL
  # Note: Mix.env() is NOT available in releases, so we detect from api_url
  defp detect_environment_from_api_url do
    api_url = Application.get_env(:square_client, :api_url)

    cond do
      # Check for sandbox first (contains "sandbox" in URL)
      is_binary(api_url) and String.contains?(api_url, "sandbox") ->
        "sandbox"

      # Production URL is connect.squareup.com without "sandbox"
      is_binary(api_url) and String.contains?(api_url, "connect.squareup.com") ->
        "production"

      # Default to sandbox for safety
      true ->
        "sandbox"
    end
  end

  defp default_config do
    # Return the new unified structure for new configs
    %{
      "plans" => %{},
      "one_time_purchases" => %{}
    }
  end

  # Transform a plan to use the appropriate environment-specific IDs
  defp transform_plan_for_environment(plan, env) do
    plan
    |> maybe_set_base_plan_id(env)
    |> maybe_transform_variations(env)
  end

  # Pattern match on free plans - transform environment-specific IDs
  defp maybe_set_base_plan_id(%{"type" => "free"} = plan, env) do
    cond do
      # Has both sandbox and production IDs
      plan["sandbox_base_plan_id"] && plan["production_base_plan_id"] ->
        base_plan_id =
          if env == "production",
            do: plan["production_base_plan_id"],
            else: plan["sandbox_base_plan_id"]

        plan
        |> Map.put("base_plan_id", base_plan_id)
        |> Map.delete("sandbox_base_plan_id")
        |> Map.delete("production_base_plan_id")

      # Has only sandbox ID
      plan["sandbox_base_plan_id"] && env != "production" ->
        plan
        |> Map.put("base_plan_id", plan["sandbox_base_plan_id"])
        |> Map.delete("sandbox_base_plan_id")

      # Has only production ID
      plan["production_base_plan_id"] && env == "production" ->
        plan
        |> Map.put("base_plan_id", plan["production_base_plan_id"])
        |> Map.delete("production_base_plan_id")

      # No IDs to transform
      true ->
        plan
    end
  end

  # Pattern match when we have sandbox/production fields (transform to base_plan_id)
  defp maybe_set_base_plan_id(
         %{"sandbox_base_plan_id" => sandbox, "production_base_plan_id" => production} = plan,
         env
       ) do
    base_plan_id = if env == "production", do: production, else: sandbox

    plan
    |> Map.put("base_plan_id", base_plan_id)
    |> Map.delete("sandbox_base_plan_id")
    |> Map.delete("production_base_plan_id")
  end

  # No IDs or already has base_plan_id - return as is
  defp maybe_set_base_plan_id(plan, _env), do: plan

  # Pattern match when variations exist
  defp maybe_transform_variations(%{"variations" => variations} = plan, env)
       when is_map(variations) do
    transformed_variations =
      Map.new(variations, fn {key, variation} ->
        {key, transform_variation_for_environment(variation, env)}
      end)

    Map.put(plan, "variations", transformed_variations)
  end

  # No variations - return as is
  defp maybe_transform_variations(plan, _env), do: plan

  defp transform_variation_for_environment(variation, env) do
    id_field = if env == "production", do: "production_variation_id", else: "sandbox_variation_id"
    variation_id = variation[id_field]

    variation
    |> Map.put("variation_id", variation_id)
    |> Map.delete("sandbox_variation_id")
    |> Map.delete("production_variation_id")
  end

  @doc """
  Get features for a specific plan.
  Returns a list of feature atoms or nil if plan doesn't exist.
  """
  @spec get_plan_features(term()) :: list() | nil
  def get_plan_features(plan_id) when is_binary(plan_id) do
    app = Application.get_env(:square_client, :app_name, :square_client)
    plans = get_plans(app)

    case find_plan_by_id(plans, plan_id) do
      nil -> nil
      plan -> Map.get(plan, "features", [])
    end
  end

  def get_plan_features(_), do: nil

  defp find_plan_by_id(plans, plan_id) do
    Enum.find_value(plans, fn
      {_key, %{"id" => ^plan_id} = plan} ->
        plan

      {_key, %{"variations" => variations} = plan} ->
        variation_parent(variations, plan_id, plan)

      _ ->
        nil
    end)
  end

  # If it's a variation ID, return the parent plan
  defp variation_parent(variations, plan_id, plan) do
    if Enum.any?(variations, fn {_vkey, v} -> v["id"] == plan_id end), do: plan
  end
end
