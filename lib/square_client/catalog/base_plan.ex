defmodule SquareClient.Catalog.BasePlan do
  @moduledoc """
  Struct representing a Square subscription base plan.
  """

  @derive JSON.Encoder
  defstruct [:name, :description]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil
        }

  @doc """
  Creates a new base plan struct.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Converts the struct to Square API format.
  """
  @spec to_square_object(t()) :: map()
  def to_square_object(%__MODULE__{} = plan) do
    subscription_plan_data =
      maybe_add_field(%{name: plan.name}, :description, plan.description)

    %{
      type: "SUBSCRIPTION_PLAN",
      id: "##{String.replace(plan.name, " ", "_")}",
      subscription_plan_data: subscription_plan_data
    }
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)
end
