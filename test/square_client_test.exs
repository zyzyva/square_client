defmodule SquareClientTest do
  use ExUnit.Case
  doctest SquareClient

  test "greets the world" do
    assert SquareClient.hello() == :world
  end
end
