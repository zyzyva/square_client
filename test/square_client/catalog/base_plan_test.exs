defmodule SquareClient.Catalog.BasePlanTest do
  use ExUnit.Case, async: true

  alias SquareClient.Catalog.BasePlan

  describe "new/1" do
    test "creates a base plan with name and description" do
      attrs = %{name: "Premium Plan", description: "Premium features"}
      plan = BasePlan.new(attrs)

      assert %BasePlan{name: "Premium Plan", description: "Premium features"} = plan
    end

    test "creates a base plan with only name" do
      attrs = %{name: "Basic Plan"}
      plan = BasePlan.new(attrs)

      assert %BasePlan{name: "Basic Plan", description: nil} = plan
    end

    test "ignores extra fields" do
      attrs = %{name: "Test Plan", extra_field: "ignored"}
      plan = BasePlan.new(attrs)

      assert %BasePlan{name: "Test Plan", description: nil} = plan
      refute Map.has_key?(plan, :extra_field)
    end
  end

  describe "to_square_object/1" do
    test "converts base plan with description to Square format" do
      plan = %BasePlan{name: "Premium Plan", description: "Premium features"}
      result = BasePlan.to_square_object(plan)

      assert result == %{
               type: "SUBSCRIPTION_PLAN",
               id: "#Premium_Plan",
               subscription_plan_data: %{
                 name: "Premium Plan",
                 description: "Premium features"
               }
             }
    end

    test "converts base plan without description to Square format" do
      plan = %BasePlan{name: "Basic Plan", description: nil}
      result = BasePlan.to_square_object(plan)

      assert result == %{
               type: "SUBSCRIPTION_PLAN",
               id: "#Basic_Plan",
               subscription_plan_data: %{
                 name: "Basic Plan"
               }
             }
    end

    test "replaces spaces with underscores in id" do
      plan = %BasePlan{name: "My Test Plan With Spaces"}
      result = BasePlan.to_square_object(plan)

      assert result.id == "#My_Test_Plan_With_Spaces"
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON properly" do
      plan = %BasePlan{name: "Test Plan", description: "Test"}
      json = Jason.encode!(plan)
      decoded = Jason.decode!(json)

      assert decoded == %{
               "name" => "Test Plan",
               "description" => "Test"
             }
    end

    test "excludes nil values from JSON" do
      plan = %BasePlan{name: "Test Plan", description: nil}
      json = Jason.encode!(plan)
      decoded = Jason.decode!(json)

      assert decoded == %{
               "name" => "Test Plan",
               "description" => nil
             }
    end
  end
end
