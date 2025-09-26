defmodule SquareClient.Catalog.PlanVariationTest do
  use ExUnit.Case, async: true

  alias SquareClient.Catalog.PlanVariation

  describe "new/1" do
    test "creates a plan variation with all fields" do
      attrs = %{
        base_plan_id: "PLAN123",
        name: "Monthly",
        cadence: "MONTHLY",
        amount: 999,
        currency: "USD"
      }

      variation = PlanVariation.new(attrs)

      assert %PlanVariation{
               base_plan_id: "PLAN123",
               name: "Monthly",
               cadence: "MONTHLY",
               amount: 999,
               currency: "USD"
             } = variation
    end

    test "defaults currency to USD when not provided" do
      attrs = %{
        base_plan_id: "PLAN123",
        name: "Monthly",
        cadence: "MONTHLY",
        amount: 999
      }

      variation = PlanVariation.new(attrs)

      assert variation.currency == "USD"
    end

    test "uses provided currency when specified" do
      attrs = %{
        base_plan_id: "PLAN123",
        name: "Monthly",
        cadence: "MONTHLY",
        amount: 999,
        currency: "EUR"
      }

      variation = PlanVariation.new(attrs)

      assert variation.currency == "EUR"
    end
  end

  describe "to_square_object/1" do
    test "converts variation to Square API format" do
      variation = %PlanVariation{
        base_plan_id: "PLAN123",
        name: "Monthly",
        cadence: "MONTHLY",
        amount: 999,
        currency: "USD"
      }

      result = PlanVariation.to_square_object(variation)

      assert result == %{
               type: "SUBSCRIPTION_PLAN_VARIATION",
               id: "#PLAN123_Monthly",
               subscription_plan_variation_data: %{
                 name: "Monthly",
                 phases: [
                   %{
                     cadence: "MONTHLY",
                     pricing: %{
                       type: "STATIC",
                       price_money: %{
                         amount: 999,
                         currency: "USD"
                       }
                     }
                   }
                 ],
                 subscription_plan_id: "PLAN123"
               }
             }
    end

    test "handles annual cadence" do
      variation = %PlanVariation{
        base_plan_id: "PLAN456",
        name: "Annual",
        cadence: "ANNUAL",
        amount: 9900,
        currency: "USD"
      }

      result = PlanVariation.to_square_object(variation)

      assert result.subscription_plan_variation_data.phases == [
               %{
                 cadence: "ANNUAL",
                 pricing: %{
                   type: "STATIC",
                   price_money: %{
                     amount: 9900,
                     currency: "USD"
                   }
                 }
               }
             ]
    end

    test "creates correct ID format" do
      variation = %PlanVariation{
        base_plan_id: "BASE_PLAN_ID",
        name: "Custom Name",
        cadence: "MONTHLY",
        amount: 100,
        currency: "USD"
      }

      result = PlanVariation.to_square_object(variation)

      assert result.id == "#BASE_PLAN_ID_Custom Name"
    end
  end

  describe "JSON.Encoder" do
    test "encodes to JSON properly" do
      variation = %PlanVariation{
        base_plan_id: "PLAN123",
        name: "Monthly",
        cadence: "MONTHLY",
        amount: 999,
        currency: "USD"
      }

      json = JSON.encode!(variation)
      decoded = JSON.decode!(json)

      assert decoded == %{
               "base_plan_id" => "PLAN123",
               "name" => "Monthly",
               "cadence" => "MONTHLY",
               "amount" => 999,
               "currency" => "USD"
             }
    end
  end
end
