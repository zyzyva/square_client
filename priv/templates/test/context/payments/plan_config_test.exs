defmodule APP_MODULE.Payments.PlanConfigTest do
  use ExUnit.Case, async: true
  alias SquareClient.Plans

  @app :APP_PATH
  @config_path "square_plans.json"

  describe "JSON configuration integration" do
    test "square_plans.json exists and is valid JSON" do
      path = Application.app_dir(@app, Path.join("priv", @config_path))
      assert File.exists?(path)

      # Read and parse JSON
      {:ok, content} = File.read(path)
      {:ok, json} = JSON.decode(content)

      # Verify unified structure
      assert Map.has_key?(json, "plans")
      assert Map.has_key?(json, "one_time_purchases")
    end

    test "development environment has required plans" do
      plans = Plans.get_plans(@app, @config_path)

      assert Map.has_key?(plans, "premium")
      premium = plans["premium"]

      assert premium["name"] == "Premium"
      assert Map.has_key?(premium, "variations")
    end

    test "all variations exist with correct cadence" do
      plans = Plans.get_plans(@app, @config_path)
      variations = plans["premium"]["variations"]

      # At least monthly and yearly should exist
      assert map_size(variations) >= 2

      # Monthly plan
      assert Map.has_key?(variations, "monthly")
      assert variations["monthly"]["cadence"] == "MONTHLY"
      assert variations["monthly"]["currency"] == "USD"
      assert is_integer(variations["monthly"]["amount"])

      # Yearly plan
      assert Map.has_key?(variations, "yearly")
      assert variations["yearly"]["cadence"] == "ANNUAL"
      assert variations["yearly"]["currency"] == "USD"
      assert is_integer(variations["yearly"]["amount"])
    end

    test "pricing increases with plan tier" do
      plans = Plans.get_plans(@app, @config_path)
      variations = plans["premium"]["variations"]

      monthly = variations["monthly"]["amount"]
      yearly = variations["yearly"]["amount"]

      # Premium plans have positive amounts
      assert monthly > 0

      # Yearly should be more than monthly (total cost, not per period)
      assert yearly > monthly
    end

    test "development environment has Square IDs configured" do
      plans = Plans.get_plans(@app, @config_path)
      premium = plans["premium"]

      # Base plan should have ID
      assert premium["base_plan_id"] != nil

      # Monthly and yearly should have variation IDs
      assert premium["variations"]["monthly"]["variation_id"] != nil
      assert premium["variations"]["yearly"]["variation_id"] != nil
    end

    test "production environment has placeholder structure" do
      # Manually load production config
      path = Application.app_dir(@app, Path.join("priv", @config_path))
      {:ok, content} = File.read(path)
      {:ok, json} = JSON.decode(content)

      # With unified structure, check production IDs are null
      premium = json["plans"]["premium"]
      assert Map.has_key?(json["plans"], "premium")

      # Production IDs should be null (not configured yet)
      assert premium["production_base_plan_id"] == nil
      assert premium["variations"]["monthly"]["production_variation_id"] == nil
      assert premium["variations"]["yearly"]["production_variation_id"] == nil
    end
  end

  describe "SquareClient.Plans functions" do
    test "get_plan returns correct plan data" do
      plan = Plans.get_plan(@app, "premium", @config_path)

      assert plan["name"] == "Premium"
      assert plan["description"] == "Premium features for your application"
      assert Map.has_key?(plan, "variations")
    end

    test "get_variation returns correct variation data" do
      monthly = Plans.get_variation(@app, "premium", "monthly", @config_path)
      assert monthly["cadence"] == "MONTHLY"
      assert is_integer(monthly["amount"])

      yearly = Plans.get_variation(@app, "premium", "yearly", @config_path)
      assert yearly["cadence"] == "ANNUAL"
      assert is_integer(yearly["amount"])
    end

    test "get_variation_id returns Square IDs where configured" do
      # Monthly should have ID
      monthly_id = Plans.get_variation_id(@app, "premium", "monthly", @config_path)
      assert monthly_id != nil

      # Yearly should have ID
      yearly_id = Plans.get_variation_id(@app, "premium", "yearly", @config_path)
      assert yearly_id != nil
    end

    test "handles non-existent plans gracefully" do
      plan = Plans.get_plan(@app, "nonexistent", @config_path)
      assert plan == nil

      variation = Plans.get_variation(@app, "nonexistent", "monthly", @config_path)
      assert variation == nil

      variation_id = Plans.get_variation_id(@app, "nonexistent", "monthly", @config_path)
      assert variation_id == nil
    end
  end


  describe "environment handling" do
    test "uses development config in non-prod environments" do
      # The module should use development config in test
      plans = Plans.get_plans(@app, @config_path)

      # Development config has IDs (except weekly)
      assert plans["premium"]["base_plan_id"] != nil
      assert plans["premium"]["variations"]["monthly"]["variation_id"] != nil
      assert plans["premium"]["variations"]["yearly"]["variation_id"] != nil
    end
  end


  describe "error handling" do
    test "handles missing config file gracefully" do
      # Try to load non-existent config
      plans = Plans.get_plans(@app, "nonexistent.json")
      assert plans == %{}
    end

  end

  describe "all plan variations" do
    test "all paid variations exist" do
      plans = Plans.get_plans(@app, @config_path)
      variations = plans["premium"]["variations"]

      # Should have at least 2 variations (monthly and yearly)
      assert map_size(variations) >= 2
      assert Map.has_key?(variations, "monthly")
      assert Map.has_key?(variations, "yearly")

      # Active variations are available
      assert variations["monthly"]["active"] == true
      assert variations["yearly"]["active"] == true
    end

    test "all variations have required fields" do
      plans = Plans.get_plans(@app, @config_path)
      variations = plans["premium"]["variations"]

      for {_key, variation} <- variations do
        assert Map.has_key?(variation, "amount")
        assert Map.has_key?(variation, "currency")
        assert Map.has_key?(variation, "cadence")
        assert Map.has_key?(variation, "name")
        assert Map.has_key?(variation, "variation_id")
      end
    end
  end
end
