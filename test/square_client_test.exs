defmodule SquareClientTest do
  use ExUnit.Case
  doctest SquareClient

  describe "version/0" do
    test "returns the current version" do
      assert SquareClient.version() == "0.1.0"
    end
  end
end