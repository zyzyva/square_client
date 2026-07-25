defmodule SquareClient.Plans.ProvisioningValidator do
  @moduledoc """
  Validates a full plan definition before a provisioning task creates
  anything in Square. Shared by both the sandbox (`mix square.setup_plans`)
  and production (`mix square.setup_production`) tasks, which read
  different config key names for the Square-assigned base plan and
  variation IDs — the caller passes those key names in, so the validity
  rule cannot drift between the two paths.
  """

  @doc """
  Validates every plan and active variation that a provisioning run would
  create, against the env-appropriate `base_id_key` / `variation_id_key`
  (e.g. `"base_plan_id"` / `"variation_id"` for sandbox,
  `"production_base_plan_id"` / `"production_variation_id"` for
  production).

  Returns `:ok`, or `{:error, findings}` where each finding is a map with
  `:plan`, `:variation` (`nil` for a plan-level finding), `:field`, and
  `:problem`.
  """
  @spec validate(map(), String.t(), String.t()) :: :ok | {:error, [map()]}
  def validate(plans, base_id_key, variation_id_key) do
    findings =
      plans
      |> Enum.reject(fn {_plan_key, plan} -> plan["type"] == "free" end)
      |> Enum.flat_map(fn {plan_key, plan} ->
        validate_plan_name(plan_key, plan[base_id_key], plan["name"]) ++
          validate_variations(plan_key, plan["variations"], variation_id_key)
      end)

    result(findings)
  end

  defp result([]), do: :ok
  defp result(findings), do: {:error, findings}

  # Base plan already exists — not being created, name is not re-validated.
  defp validate_plan_name(_plan_key, base_id, _name) when not is_nil(base_id), do: []

  defp validate_plan_name(plan_key, nil, name) do
    to_findings(valid_string?(name), plan_key, nil, "name", name_problem(name))
  end

  defp validate_variations(_plan_key, nil, _variation_id_key), do: []

  defp validate_variations(plan_key, variations, variation_id_key) do
    Enum.flat_map(variations, fn {variation_key, variation} ->
      validate_variation(plan_key, variation_key, variation, variation_id_key)
    end)
  end

  defp validate_variation(plan_key, variation_key, variation, variation_id_key) do
    creating? = variation["active"] != false and is_nil(variation[variation_id_key])
    validate_creatable_variation(creating?, plan_key, variation_key, variation)
  end

  # Inactive, or already provisioned — not being created, not validated.
  defp validate_creatable_variation(false, _plan_key, _variation_key, _variation), do: []

  defp validate_creatable_variation(true, plan_key, variation_key, variation) do
    to_findings(
      valid_string?(variation["name"]),
      plan_key,
      variation_key,
      "name",
      name_problem(variation["name"])
    ) ++
      to_findings(
        valid_string?(variation["cadence"]),
        plan_key,
        variation_key,
        "cadence",
        cadence_problem(variation["cadence"])
      ) ++
      to_findings(
        valid_amount?(variation["amount"]),
        plan_key,
        variation_key,
        "amount",
        amount_problem(variation["amount"])
      )
  end

  defp to_findings(true, _plan_key, _variation_key, _field, _problem), do: []

  defp to_findings(false, plan_key, variation_key, field, problem) do
    [%{plan: plan_key, variation: variation_key, field: field, problem: problem}]
  end

  defp valid_string?(value) when is_binary(value) and value != "", do: true
  defp valid_string?(_value), do: false

  defp valid_amount?(value) when is_integer(value) and value > 0, do: true
  defp valid_amount?(_value), do: false

  defp name_problem(nil), do: "is missing"
  defp name_problem(""), do: "is missing"
  defp name_problem(_other), do: "must be a non-empty string"

  defp cadence_problem(nil), do: "is missing"
  defp cadence_problem(""), do: "is missing"
  defp cadence_problem(_other), do: "must be a non-empty string"

  defp amount_problem(nil), do: "is missing"
  defp amount_problem(_other), do: "must be a positive integer"

  @doc """
  Formats validation findings as a single printable string, one line per
  finding, for the provisioning tasks to print identically.
  """
  @spec format_findings([map()]) :: String.t()
  def format_findings(findings) do
    findings
    |> Enum.map(&format_finding/1)
    |> Enum.join("\n")
  end

  defp format_finding(%{plan: plan_key, variation: nil, field: field, problem: problem}) do
    "  - plan #{plan_key}: #{field} #{problem}"
  end

  defp format_finding(%{plan: plan_key, variation: variation_key, field: field, problem: problem}) do
    "  - plan #{plan_key}, variation #{variation_key}: #{field} #{problem}"
  end
end
