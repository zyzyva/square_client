defmodule SquareClient.Plans.FormatterTest do
  use ExUnit.Case, async: true

  alias SquareClient.Plans.Formatter

  describe "build_variation_plans/5 tier_type handling" do
    test "variations without tier_type are emitted with tier_type: \"personal\"" do
      plan_data = %{
        "name" => "Premium",
        "variations" => %{
          "monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY",
            "features" => ["a", "b"]
          }
        }
      }

      [variation] = Formatter.build_variation_plans("premium", plan_data, nil, false, :all)

      assert variation.tier_type == "personal"
      assert variation.id == :premium_monthly
    end

    test "variations with explicit tier_type are passed through unchanged" do
      plan_data = %{
        "name" => "Premium",
        "variations" => %{
          "team_monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY",
            "tier_type" => "team",
            "features" => ["a", "b"]
          }
        }
      }

      [variation] = Formatter.build_variation_plans("premium", plan_data, nil, false, :all)

      assert variation.tier_type == "team"
      assert variation.id == :premium_team_monthly
    end

    test "tier_types: [\"personal\"] filters out team variations" do
      plan_data = %{
        "name" => "Premium",
        "variations" => %{
          "monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY"
          },
          "team_monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY",
            "tier_type" => "team"
          }
        }
      }

      result = Formatter.build_variation_plans("premium", plan_data, nil, false, ["personal"])

      ids = Enum.map(result, & &1.id)
      assert :premium_monthly in ids
      refute :premium_team_monthly in ids
    end

    test "tier_types: [\"team\"] returns only team variations and excludes implicit-personal ones" do
      plan_data = %{
        "name" => "Premium",
        "variations" => %{
          "monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY"
          },
          "team_monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY",
            "tier_type" => "team"
          }
        }
      }

      result = Formatter.build_variation_plans("premium", plan_data, nil, false, ["team"])

      ids = Enum.map(result, & &1.id)
      assert :premium_team_monthly in ids
      refute :premium_monthly in ids
    end

    test "tier_types: :all returns every variation regardless of tier_type" do
      plan_data = %{
        "name" => "Premium",
        "variations" => %{
          "monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY"
          },
          "team_monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY",
            "tier_type" => "team"
          }
        }
      }

      result = Formatter.build_variation_plans("premium", plan_data, nil, false, :all)

      ids = Enum.map(result, & &1.id)
      assert :premium_monthly in ids
      assert :premium_team_monthly in ids
    end

    test "default tier_types arg (when omitted) is :all" do
      # build_variation_plans/4 default-clauses tier_types to :all, so callers
      # that only pass 4 args (the pre-tier_type signature) get every variation.
      plan_data = %{
        "name" => "Premium",
        "variations" => %{
          "monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY"
          },
          "team_monthly" => %{
            "active" => true,
            "amount" => 500,
            "price_cents" => 500,
            "cadence" => "MONTHLY",
            "tier_type" => "team"
          }
        }
      }

      result = Formatter.build_variation_plans("premium", plan_data, nil, false)
      ids = Enum.map(result, & &1.id)
      assert :premium_monthly in ids
      assert :premium_team_monthly in ids
    end
  end
end
