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
    env = environment(app)
    config = load_config(app, config_path)

    case config[env]["one_time_purchases"] do
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
  Get all plan configurations for the current environment.

  ## Parameters

    * `app` - The application atom (e.g., :my_app)
    * `config_path` - Path to the config file relative to app's priv directory
                      (default: "square_plans.json")

  ## Examples

      SquareClient.Plans.get_plans(:my_app)
      SquareClient.Plans.get_plans(:my_app, "custom_plans.json")
  """
  def get_plans(app, config_path \\ "square_plans.json") do
    env = environment(app)
    config = load_config(app, config_path)

    case config[env]["plans"] do
      nil -> %{}
      plans -> plans
    end
  end

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
      nil -> nil
      plan -> plan["variations"][to_string(variation_key)]
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
      nil -> nil
      variation -> variation["variation_id"]
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

    # Ensure nested structure exists
    config_with_env = Map.put_new(config, env, %{"plans" => %{}})

    config_with_plans =
      put_in(config_with_env, [env, "plans"], config_with_env[env]["plans"] || %{})

    config_with_plan =
      put_in(
        config_with_plans,
        [env, "plans", plan_key],
        config_with_plans[env]["plans"][plan_key] || %{}
      )

    updated_config =
      put_in(config_with_plan, [env, "plans", plan_key, "base_plan_id"], base_plan_id)

    save_config(app, updated_config, config_path)
  end

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

    # Ensure nested structure exists
    config_with_env = Map.put_new(config, env, %{"plans" => %{}})

    config_with_plans =
      put_in(config_with_env, [env, "plans"], config_with_env[env]["plans"] || %{})

    config_with_plan =
      put_in(
        config_with_plans,
        [env, "plans", plan_key],
        config_with_plans[env]["plans"][plan_key] || %{}
      )

    config_with_variations =
      put_in(
        config_with_plan,
        [env, "plans", plan_key, "variations"],
        config_with_plan[env]["plans"][plan_key]["variations"] || %{}
      )

    config_with_variation =
      put_in(
        config_with_variations,
        [env, "plans", plan_key, "variations", variation_key],
        config_with_variations[env]["plans"][plan_key]["variations"][variation_key] || %{}
      )

    updated_config =
      put_in(
        config_with_variation,
        [env, "plans", plan_key, "variations", variation_key, "variation_id"],
        variation_id
      )

    save_config(app, updated_config, config_path)
  end

  @doc """
  Check if all plans and variations have IDs configured.

  ## Parameters

    * `app` - The application atom
    * `config_path` - Path to the config file (default: "square_plans.json")
  """
  def all_configured?(app, config_path \\ "square_plans.json") do
    plans = get_plans(app, config_path)

    Enum.all?(plans, fn {_key, plan} ->
      has_base_plan = plan["base_plan_id"] != nil

      has_all_variations =
        Enum.all?(plan["variations"] || %{}, fn {_vkey, variation} ->
          variation["variation_id"] != nil
        end)

      has_base_plan && has_all_variations
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

    Enum.reduce(plans, unconfigured, fn {plan_key, plan}, acc ->
      acc =
        if plan["base_plan_id"] == nil do
          %{acc | base_plans: [{plan_key, plan} | acc.base_plans]}
        else
          acc
        end

      variations_needing_creation =
        Enum.filter(plan["variations"] || %{}, fn {_vkey, variation} ->
          variation["variation_id"] == nil
        end)
        |> Enum.map(fn {vkey, variation} ->
          {plan_key, vkey, variation, plan["base_plan_id"]}
        end)

      %{acc | variations: variations_needing_creation ++ acc.variations}
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
    # First check app-specific environment config
    env =
      Application.get_env(app, :environment) ||
        Application.get_env(app, :env) ||
        Mix.env()

    case env do
      :dev -> "development"
      :prod -> "production"
      :production -> "production"
      # Use dev config for tests
      :test -> "development"
      _ -> "development"
    end
  end

  defp default_config do
    %{
      "development" => %{"plans" => %{}},
      "production" => %{"plans" => %{}}
    }
  end
end
