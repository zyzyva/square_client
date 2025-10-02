defmodule SquareClient.Plans.Formatter do
  @moduledoc """
  Formats plan data from JSON for display in LiveViews and UI components.

  This module transforms raw JSON plan data into structured, UI-ready formats
  that can be directly consumed by LiveViews, APIs, or other presentation layers.
  """

  @doc """
  Get all subscription plans formatted for UI display.

  Returns a list of plan maps with id, name, price, features, etc.

  ## Parameters
    * `app` - The application atom
    * `config_path` - Path to config file (default: "square_plans.json")
    * `opts` - Options including:
      * `:include_inactive` - Include inactive plans (default: false)
      * `:plan_types` - Module with plan type definitions (optional)

  ## Examples

      SquareClient.Plans.Formatter.get_subscription_plans(:my_app)

      SquareClient.Plans.Formatter.get_subscription_plans(:my_app, "plans.json",
        plan_types: MyApp.PlanTypes
      )
  """
  def get_subscription_plans(app, config_path \\ "square_plans.json", opts \\ []) do
    plans = SquareClient.Plans.get_plans(app, config_path)
    plan_types = Keyword.get(opts, :plan_types)
    include_inactive = Keyword.get(opts, :include_inactive, false)

    # Build the free plan if it exists
    free_plan = build_free_plan(plans["free"], plan_types)

    # Build premium/paid plans with variations
    premium_plans =
      plans
      |> Enum.reject(fn {key, _} -> key == "free" end)
      |> Enum.flat_map(fn {plan_key, plan_data} ->
        build_variation_plans(plan_key, plan_data, plan_types, include_inactive)
      end)

    # Combine and filter nils
    [free_plan | premium_plans]
    |> Enum.filter(& &1)
    |> Enum.sort_by(& &1.price_cents)
  end

  @doc """
  Get all one-time purchases formatted for UI display.

  ## Parameters
    * `app` - The application atom
    * `config_path` - Path to config file (default: "square_plans.json")
    * `opts` - Options including:
      * `:include_inactive` - Include inactive purchases (default: false)
  """
  def get_one_time_purchases(app, config_path \\ "square_plans.json", opts \\ []) do
    include_inactive = Keyword.get(opts, :include_inactive, false)
    config = load_full_config(app, config_path)

    case config["one_time_purchases"] do
      nil ->
        []

      purchases ->
        purchases
        |> maybe_filter_active(include_inactive)
        |> Enum.map(fn {key, purchase} ->
          %{
            id: String.to_atom(key),
            name: purchase["name"],
            description: purchase["description"],
            price: purchase["price"],
            price_cents: purchase["price_cents"],
            duration_days: purchase["duration_days"],
            auto_renews: purchase["auto_renews"] || false,
            billing_notice: purchase["billing_notice"],
            features: purchase["features"] || [],
            type: :one_time,
            active: purchase["active"] != false
          }
        end)
        |> Enum.sort_by(& &1.price_cents)
    end
  end

  @doc """
  Get all plans (subscriptions and one-time purchases).

  ## Parameters
    * `app` - The application atom
    * `config_path` - Path to config file (default: "square_plans.json")
    * `opts` - Options (see get_subscription_plans/3)
  """
  def get_all_plans(app, config_path \\ "square_plans.json", opts \\ []) do
    subscription_plans = get_subscription_plans(app, config_path, opts)
    one_time_purchases = get_one_time_purchases(app, config_path, opts)
    subscription_plans ++ one_time_purchases
  end

  @doc """
  Get a specific plan by its ID.

  ## Parameters
    * `app` - The application atom
    * `plan_id` - The plan identifier (atom or string)
    * `config_path` - Path to config file (default: "square_plans.json")
    * `opts` - Options (see get_subscription_plans/3)
  """
  def get_plan_by_id(app, plan_id, config_path \\ "square_plans.json", opts \\ []) do
    all_plans = get_all_plans(app, config_path, opts)

    plan_atom = if is_binary(plan_id), do: String.to_atom(plan_id), else: plan_id
    Enum.find(all_plans, &(&1.id == plan_atom))
  end

  @doc """
  Mark plans with recommended status based on current plan.

  This is useful for highlighting upgrade paths in the UI.

  ## Parameters
    * `plans` - List of plan maps
    * `current_plan_id` - The user's current plan ID
    * `opts` - Options including:
      * `:plan_types` - Module with recommendation logic (must implement `is_recommended?/2`)

  ## Examples

      plans = get_all_plans(:my_app)
      marked = mark_recommended_plans(plans, :free, plan_types: MyApp.PlanTypes)
  """
  def mark_recommended_plans(plans, current_plan_id, opts \\ []) do
    plan_types = Keyword.get(opts, :plan_types)

    if plan_types && function_exported?(plan_types, :is_recommended?, 2) do
      Enum.map(plans, fn plan ->
        Map.put(plan, :recommended, plan_types.is_recommended?(plan.id, current_plan_id))
      end)
    else
      # Default recommendation logic
      Enum.map(plans, fn plan ->
        recommended = default_recommendation(plan.id, current_plan_id)
        Map.put(plan, :recommended, recommended)
      end)
    end
  end

  @doc """
  Format a price for display based on amount and cadence.

  ## Parameters
    * `amount` - Price in cents
    * `cadence` - Billing cadence (WEEKLY, MONTHLY, ANNUAL, etc.)
    * `opts` - Options including:
      * `:currency` - Currency code (default: "USD")
      * `:format` - :short or :long (default: :short)
  """
  def format_price(amount, cadence, opts \\ []) do
    currency = Keyword.get(opts, :currency, "USD")
    format = Keyword.get(opts, :format, :short)

    dollars = amount / 100

    price_str =
      case currency do
        "USD" -> "$#{format_amount(dollars)}"
        "EUR" -> "€#{format_amount(dollars)}"
        "GBP" -> "£#{format_amount(dollars)}"
        _ -> "#{currency} #{format_amount(dollars)}"
      end

    cadence_str =
      case {cadence, format} do
        {"WEEKLY", :short} -> "/week"
        {"WEEKLY", :long} -> " per week"
        {"MONTHLY", :short} -> "/mo"
        {"MONTHLY", :long} -> " per month"
        {"ANNUAL", :short} -> "/yr"
        {"ANNUAL", :long} -> " per year"
        {"DAILY", :short} -> "/day"
        {"DAILY", :long} -> " per day"
        {nil, _} -> ""
        _ -> ""
      end

    price_str <> cadence_str
  end

  # Private functions

  defp build_free_plan(nil, _plan_types), do: build_free_plan(%{}, nil)

  defp build_free_plan(free_config, plan_types) do
    %{
      id: get_plan_atom(plan_types, :free, "free"),
      name: free_config["name"] || "Free",
      price: free_config["price"] || "$0",
      price_cents: free_config["price_cents"] || 0,
      features: free_config["features"] || default_free_features(),
      type: :subscription,
      auto_renews: false,
      billing_notice: free_config["billing_notice"] || "Free forever",
      active: free_config["active"] != false
    }
  end

  defp build_variation_plans(plan_key, plan_data, plan_types, include_inactive) do
    variations = plan_data["variations"] || %{}

    variations
    |> maybe_filter_active(include_inactive)
    |> Enum.map(fn {var_key, variation} ->
      plan_atom = build_plan_atom(plan_key, var_key, plan_types)

      %{
        id: plan_atom,
        name: build_plan_name(plan_data["name"], variation["name"], var_key),
        price: variation["price"] || format_price(variation["amount"], variation["cadence"]),
        price_cents: variation["price_cents"] || variation["amount"],
        features: variation["features"] || plan_data["features"] || default_premium_features(),
        type: :subscription,
        auto_renews: variation["auto_renews"] != false,
        billing_notice:
          variation["billing_notice"] || default_billing_notice(variation["cadence"]),
        cadence: variation["cadence"],
        variation_id: variation["variation_id"],
        base_plan_id: plan_data["base_plan_id"],
        active: variation["active"] != false
      }
    end)
  end

  defp maybe_filter_active(items, true), do: items

  defp maybe_filter_active(items, false) do
    Enum.filter(items, fn {_key, item} -> item["active"] != false end)
  end

  defp build_plan_atom(base, variation, plan_types) do
    # Build the compound atom like :premium_monthly
    atom = String.to_atom("#{base}_#{variation}")

    # If plan_types module is provided, check if it has a function for this specific plan
    if plan_types do
      # Try the compound name first (e.g., premium_monthly)
      compound_name = String.to_atom("#{base}_#{variation}")

      if function_exported?(plan_types, compound_name, 0) do
        apply(plan_types, compound_name, [])
      else
        atom
      end
    else
      atom
    end
  end

  defp get_plan_atom(nil, _default, string_key), do: String.to_atom(string_key)

  defp get_plan_atom(plan_types, default, _string_key) do
    if function_exported?(plan_types, default, 0) do
      apply(plan_types, default, [])
    else
      default
    end
  end

  defp build_plan_name(base_name, nil, "weekly"), do: "#{base_name || "Premium"} Weekly"
  defp build_plan_name(base_name, nil, "monthly"), do: "#{base_name || "Premium"} Monthly"
  defp build_plan_name(base_name, nil, "yearly"), do: "#{base_name || "Premium"} Yearly"

  defp build_plan_name(base_name, variation_name, _key),
    do: "#{base_name || "Premium"} #{variation_name}"

  defp format_amount(dollars) when dollars == trunc(dollars) do
    "#{trunc(dollars)}"
  end

  defp format_amount(dollars) do
    :erlang.float_to_binary(dollars, decimals: 2)
  end

  defp default_free_features do
    [
      "Basic features",
      "Limited usage",
      "Community support"
    ]
  end

  defp default_premium_features do
    [
      "All features",
      "Unlimited usage",
      "Priority support"
    ]
  end

  defp default_billing_notice("WEEKLY"), do: "Billed weekly, auto-renews until cancelled"
  defp default_billing_notice("MONTHLY"), do: "Billed monthly, auto-renews until cancelled"
  defp default_billing_notice("ANNUAL"), do: "Billed annually, auto-renews until cancelled"
  defp default_billing_notice(_), do: "Auto-renews until cancelled"

  defp default_recommendation(:free, _current), do: false

  defp default_recommendation(plan_id, :free) when plan_id != :free do
    # For free users, only recommend monthly plans
    plan_str = Atom.to_string(plan_id)
    String.ends_with?(plan_str, "_monthly")
  end

  defp default_recommendation(plan_id, current_id)
       when is_atom(plan_id) and is_atom(current_id) do
    # Extract cadence from plan atoms like :premium_monthly
    plan_str = Atom.to_string(plan_id)
    current_str = Atom.to_string(current_id)

    cond do
      # Already on this plan
      plan_id == current_id -> false
      # Recommend yearly to monthly users
      String.ends_with?(plan_str, "_yearly") && String.ends_with?(current_str, "_monthly") -> true
      # Recommend monthly to weekly users
      String.ends_with?(plan_str, "_monthly") && String.ends_with?(current_str, "_weekly") -> true
      # Otherwise not recommended
      true -> false
    end
  end

  defp default_recommendation(_, _), do: false

  defp load_full_config(app, config_path) do
    path = Application.app_dir(app, Path.join("priv", config_path))

    case File.read(path) do
      {:ok, content} ->
        case JSON.decode(content) do
          {:ok, json} -> json
          _ -> %{}
        end

      _ ->
        %{}
    end
  end
end
