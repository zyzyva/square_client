defmodule SquareClient.Catalog.PlanVariation do
  @moduledoc """
  Struct representing a Square subscription plan variation.
  """

  @derive JSON.Encoder
  defstruct [:base_plan_id, :name, :cadence, :amount, :currency]

  @type t :: %__MODULE__{
          base_plan_id: String.t() | nil,
          name: String.t() | nil,
          cadence: String.t() | nil,
          amount: integer() | nil,
          currency: String.t() | nil
        }

  @doc """
  Creates a new plan variation struct.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(:currency, "USD")
    |> normalize_currency()
    |> then(&struct(__MODULE__, &1))
  end

  defp normalize_currency(%{currency: nil} = attrs), do: %{attrs | currency: "USD"}
  defp normalize_currency(%{currency: ""} = attrs), do: %{attrs | currency: "USD"}
  defp normalize_currency(attrs), do: attrs

  @doc """
  Converts the struct to Square API format.
  """
  @spec to_square_object(t()) :: map()
  def to_square_object(%__MODULE__{} = variation) do
    %{
      type: "SUBSCRIPTION_PLAN_VARIATION",
      id: "##{variation.base_plan_id}_#{variation.name}",
      subscription_plan_variation_data: %{
        name: variation.name,
        phases: [
          %{
            cadence: variation.cadence,
            pricing: %{
              type: "STATIC",
              price_money: %{
                amount: variation.amount,
                currency: variation.currency
              }
            }
          }
        ],
        subscription_plan_id: variation.base_plan_id
      }
    }
  end
end
