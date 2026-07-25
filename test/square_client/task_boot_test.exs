defmodule SquareClient.TaskBootTest do
  use ExUnit.Case, async: false

  alias SquareClient.TaskBoot

  test "ensure_runtime!/0 returns :ok" do
    assert TaskBoot.ensure_runtime!() == :ok
  end

  test "ensure_runtime!/0 is idempotent — calling it twice returns :ok both times" do
    assert TaskBoot.ensure_runtime!() == :ok
    assert TaskBoot.ensure_runtime!() == :ok
  end

  test "after calling it, :square_client and :req are started applications" do
    TaskBoot.ensure_runtime!()

    started = Enum.map(Application.started_applications(), &elem(&1, 0))

    assert :square_client in started
    assert :req in started
  end
end
