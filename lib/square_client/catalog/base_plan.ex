defmodule SquareClient.Catalog.BasePlan do
  @moduledoc """
  Struct representing a Square subscription base plan.
  """

  @derive Jason.Encoder
  defstruct [:name, :description]

  @doc """
  Creates a new base plan struct.
  """
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Converts the struct to Square API format.
  """
  def to_square_object(%__MODULE__{} = plan) do
    subscription_plan_data =
      %{name: plan.name}
      |> maybe_add_field(:description, plan.description)

    %{
      type: "SUBSCRIPTION_PLAN",
      id: "##{String.replace(plan.name, " ", "_")}",
      subscription_plan_data: subscription_plan_data
    }
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)
end
