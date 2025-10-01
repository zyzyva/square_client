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
  def update_base_plan_id(app, plan_key, base_plan_id, config_path \\ "square_plans.json") do
    config = load_config(app, config_path)
    env = environment(app)

    id_field = environment_id_field(env, :base)

    updated_config =
      config
      |> ensure_plan_exists(plan_key)
      |> put_in(["plans", plan_key, id_field], base_plan_id)

    save_config(app, updated_config, config_path)
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
  def update_variation_id(
        app,
        plan_key,
        variation_key,
        variation_id,
        config_path \\ "square_plans.json"
      ) do
    config = load_config(app, config_path)
    env = environment(app)

    id_field = environment_id_field(env, :variation)

    updated_config =
      config
      |> ensure_variation_exists(plan_key, variation_key)
      |> put_in(["plans", plan_key, "variations", variation_key, id_field], variation_id)

    save_config(app, updated_config, config_path)
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
  def unconfigured_items(app, config_path \\ "square_plans.json") do
    plans = get_plans(app, config_path)

    unconfigured = %{
      base_plans: [],
      variations: []
    }

    Enum.reduce(plans, unconfigured, fn
      {_plan_key, %{"type" => "free"}}, acc ->
        # Skip free plans - they don't need Square IDs
        acc

      {plan_key, %{"base_plan_id" => nil} = plan}, acc ->
        # Plan needs base plan ID, but still check variations for tracking
        acc = %{acc | base_plans: [{plan_key, plan} | acc.base_plans]}

        # Still check variations in case we want to track them
        case plan do
          %{"variations" => variations} when is_map(variations) ->
            variations_needing_creation =
              variations
              |> Enum.reject(fn
                {_vkey, %{"variation_id" => id}} when is_binary(id) -> true
                _ -> false
              end)
              |> Enum.map(fn {vkey, variation} ->
                # base_plan_id is nil
                {plan_key, vkey, variation, nil}
              end)

            %{acc | variations: variations_needing_creation ++ acc.variations}

          _ ->
            acc
        end

      {plan_key, %{"base_plan_id" => base_id, "variations" => variations}}, acc
      when is_map(variations) ->
        # Check variations for missing IDs
        variations_needing_creation =
          variations
          |> Enum.reject(fn
            {_vkey, %{"variation_id" => id}} when is_binary(id) -> true
            _ -> false
          end)
          |> Enum.map(fn {vkey, variation} ->
            {plan_key, vkey, variation, base_id}
          end)

        %{acc | variations: variations_needing_creation ++ acc.variations}

      {_plan_key, %{"base_plan_id" => base_id}}, acc when is_binary(base_id) ->
        # Plan has ID but no variations - that's ok
        acc

      _, acc ->
        # Skip any other format
        acc
    end)
  end

  @doc """
  Initialize a default plan configuration file.

  Creates a new configuration file with example structure if it doesn't exist.

  ## Parameters

    * `app` - The application atom
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  def init_config(app, config_path \\ "square_plans.json") do
    path = Application.app_dir(app, Path.join("priv", config_path))

    if File.exists?(path) do
      {:error, :already_exists}
    else
      default = default_config()

      # Ensure directory exists
      Path.dirname(path) |> File.mkdir_p!()

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
    Path.dirname(path) |> File.mkdir_p!()

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

  defp environment(app) do
    # Check app-specific environment config first
    # This allows each Phoenix app to configure its environment in config/*.exs files
    # DO NOT use Mix.env() as it's not available in releases!
    env =
      Application.get_env(app, :square_environment) ||
        Application.get_env(:square_client, :environment) ||
        System.get_env("SQUARE_ENVIRONMENT") ||
        "sandbox"

    case env do
      :sandbox -> "sandbox"
      "sandbox" -> "sandbox"
      :production -> "production"
      "production" -> "production"
      "prod" -> "production"
      # Default to sandbox for safety
      _ -> "sandbox"
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

  # Pattern match on free plans - no transformation needed
  defp maybe_set_base_plan_id(%{"type" => "free"} = plan, _env), do: plan

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
end
