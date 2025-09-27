defmodule SquareClient.WebhookHandlerTest do
  use ExUnit.Case, async: true

  # Test module that implements the behaviour
  defmodule TestHandler do
    @behaviour SquareClient.WebhookHandler

    @impl true
    def handle_event(%{event_type: "test.success"} = _event) do
      :ok
    end

    @impl true
    def handle_event(%{event_type: "test.error"} = _event) do
      {:error, :test_error}
    end

    @impl true
    def handle_event(%{event_type: "test.with_data"} = event) do
      {:ok, event.data}
    end

    @impl true
    def handle_event(_event) do
      {:error, :unhandled}
    end
  end

  describe "behaviour implementation" do
    test "enforces handle_event/1 callback" do
      # This test verifies the behaviour is properly defined
      callbacks = SquareClient.WebhookHandler.behaviour_info(:callbacks)
      assert {:handle_event, 1} in callbacks
    end
  end

  describe "test handler" do
    test "handles success event" do
      event = %{event_type: "test.success", data: %{}}
      assert TestHandler.handle_event(event) == :ok
    end

    test "handles error event" do
      event = %{event_type: "test.error", data: %{}}
      assert TestHandler.handle_event(event) == {:error, :test_error}
    end

    test "handles event with data" do
      data = %{"amount" => 100}
      event = %{event_type: "test.with_data", data: data}
      assert TestHandler.handle_event(event) == {:ok, data}
    end

    test "handles unknown event" do
      event = %{event_type: "unknown.event", data: %{}}
      assert TestHandler.handle_event(event) == {:error, :unhandled}
    end
  end
end
