defmodule SquareClient.Plans.ProvisioningValidatorTest do
  use ExUnit.Case, async: true

  alias SquareClient.Plans.ProvisioningValidator, as: Validator

  describe "validate/3 — valid definitions" do
    test "sandbox-style keys: fully valid plan and variations -> :ok" do
      plans = %{
        "premium" => %{
          "name" => "Premium Plan",
          "base_plan_id" => nil,
          "variations" => %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "MONTHLY",
              "amount" => 999,
              "variation_id" => nil,
              "active" => true
            }
          }
        }
      }

      assert Validator.validate(plans, "base_plan_id", "variation_id") == :ok
    end

    test "production-style keys: fully valid plan and variations -> :ok" do
      plans = %{
        "premium" => %{
          "name" => "Premium Plan",
          "production_base_plan_id" => nil,
          "variations" => %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "MONTHLY",
              "amount" => 999,
              "production_variation_id" => nil,
              "active" => true
            }
          }
        }
      }

      assert Validator.validate(plans, "production_base_plan_id", "production_variation_id") ==
               :ok
    end
  end

  describe "validate/3 — skipped rows" do
    test "free plan with garbage fields is skipped entirely" do
      plans = %{
        "free" => %{
          "type" => "free",
          "name" => "",
          "base_plan_id" => nil,
          "variations" => %{
            "only" => %{
              "name" => "",
              "cadence" => "",
              "amount" => -1,
              "variation_id" => nil,
              "active" => true
            }
          }
        }
      }

      assert Validator.validate(plans, "base_plan_id", "variation_id") == :ok
    end

    test "inactive variation missing amount is skipped" do
      plans = %{
        "premium" => %{
          "name" => "Premium Plan",
          "base_plan_id" => "PLAN_1",
          "variations" => %{
            "legacy" => %{
              "name" => "Legacy",
              "cadence" => "MONTHLY",
              "amount" => nil,
              "variation_id" => nil,
              "active" => false
            }
          }
        }
      }

      assert Validator.validate(plans, "base_plan_id", "variation_id") == :ok
    end

    test "variation that already has its id and is missing amount is skipped" do
      plans = %{
        "premium" => %{
          "name" => "Premium Plan",
          "base_plan_id" => "PLAN_1",
          "variations" => %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "MONTHLY",
              "amount" => nil,
              "variation_id" => "VAR_1",
              "active" => true
            }
          }
        }
      }

      assert Validator.validate(plans, "base_plan_id", "variation_id") == :ok
    end

    test "plan with an existing base id and no creatable variations produces no findings" do
      plans = %{
        "premium" => %{
          "name" => "Premium Plan",
          "base_plan_id" => "PLAN_1",
          "variations" => %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "MONTHLY",
              "amount" => 999,
              "variation_id" => "VAR_1",
              "active" => true
            }
          }
        }
      }

      assert Validator.validate(plans, "base_plan_id", "variation_id") == :ok
    end
  end

  describe "validate/3 — plan-level findings" do
    test "nil base id with an empty-string name produces a plan-level finding" do
      plans = %{
        "premium" => %{
          "name" => "",
          "base_plan_id" => nil,
          "variations" => %{}
        }
      }

      assert {:error, [finding]} = Validator.validate(plans, "base_plan_id", "variation_id")
      assert finding.plan == "premium"
      assert finding.variation == nil
      assert finding.field == "name"
      assert finding.problem == "is missing"
    end
  end

  describe "validate/3 — variation-level findings" do
    setup do
      base_plan = %{
        "name" => "Premium Plan",
        "base_plan_id" => "PLAN_1"
      }

      {:ok, base_plan: base_plan}
    end

    test "creatable variation missing amount names the plan, variation, and field", %{
      base_plan: base_plan
    } do
      plans = %{
        "premium" =>
          Map.put(base_plan, "variations", %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "MONTHLY",
              "amount" => nil,
              "variation_id" => nil,
              "active" => true
            }
          })
      }

      assert {:error, [finding]} = Validator.validate(plans, "base_plan_id", "variation_id")

      assert finding == %{
               plan: "premium",
               variation: "monthly",
               field: "amount",
               problem: "is missing"
             }
    end

    test "creatable variation with amount 0 is a finding", %{base_plan: base_plan} do
      plans = %{
        "premium" =>
          Map.put(base_plan, "variations", %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "MONTHLY",
              "amount" => 0,
              "variation_id" => nil,
              "active" => true
            }
          })
      }

      assert {:error, [finding]} = Validator.validate(plans, "base_plan_id", "variation_id")
      assert finding.field == "amount"
      assert finding.problem == "must be a positive integer"
    end

    test "creatable variation with a negative amount is a finding", %{base_plan: base_plan} do
      plans = %{
        "premium" =>
          Map.put(base_plan, "variations", %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "MONTHLY",
              "amount" => -500,
              "variation_id" => nil,
              "active" => true
            }
          })
      }

      assert {:error, [finding]} = Validator.validate(plans, "base_plan_id", "variation_id")
      assert finding.field == "amount"
      assert finding.problem == "must be a positive integer"
    end

    test "creatable variation with a non-integer amount is a finding", %{base_plan: base_plan} do
      plans = %{
        "premium" =>
          Map.put(base_plan, "variations", %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "MONTHLY",
              "amount" => "999",
              "variation_id" => nil,
              "active" => true
            }
          })
      }

      assert {:error, [finding]} = Validator.validate(plans, "base_plan_id", "variation_id")
      assert finding.field == "amount"
      assert finding.problem == "must be a positive integer"
    end

    test "creatable variation with empty cadence is a finding", %{base_plan: base_plan} do
      plans = %{
        "premium" =>
          Map.put(base_plan, "variations", %{
            "monthly" => %{
              "name" => "Monthly",
              "cadence" => "",
              "amount" => 999,
              "variation_id" => nil,
              "active" => true
            }
          })
      }

      assert {:error, [finding]} = Validator.validate(plans, "base_plan_id", "variation_id")
      assert finding.field == "cadence"
      assert finding.problem == "is missing"
    end

    test "creatable variation missing both name and cadence produces two findings", %{
      base_plan: base_plan
    } do
      plans = %{
        "premium" =>
          Map.put(base_plan, "variations", %{
            "monthly" => %{
              "name" => nil,
              "cadence" => nil,
              "amount" => 999,
              "variation_id" => nil,
              "active" => true
            }
          })
      }

      assert {:error, findings} = Validator.validate(plans, "base_plan_id", "variation_id")
      fields = findings |> Enum.map(& &1.field) |> Enum.sort()
      assert fields == ["cadence", "name"]
    end
  end

  describe "format_findings/1" do
    test "includes plan, variation, and field for each finding" do
      findings = [
        %{plan: "premium", variation: nil, field: "name", problem: "is missing"},
        %{plan: "premium", variation: "monthly", field: "amount", problem: "is missing"}
      ]

      output = Validator.format_findings(findings)

      assert output =~ "premium"
      assert output =~ "name"
      assert output =~ "monthly"
      assert output =~ "amount"
      assert length(String.split(output, "\n")) == 2
    end
  end
end
