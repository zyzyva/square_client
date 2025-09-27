defmodule SquareClient.WebhookPlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureLog

  alias SquareClient.WebhookPlug

  # Mock handler for testing
  defmodule MockHandler do
    @behaviour SquareClient.WebhookHandler

    @impl true
    def handle_event(%{event_type: "payment.created"} = _event) do
      send(self(), :payment_created_handled)
      :ok
    end

    @impl true
    def handle_event(%{event_type: "error.test"} = _event) do
      {:error, :test_error}
    end

    @impl true
    def handle_event(_event) do
      :ok
    end
  end

  setup do
    # Store original config
    original_handler = Application.get_env(:square_client, :webhook_handler)
    original_key = Application.get_env(:square_client, :webhook_signature_key)

    # Set test config
    Application.put_env(:square_client, :webhook_handler, MockHandler)
    Application.put_env(:square_client, :webhook_signature_key, "test_signature_key")

    on_exit(fn ->
      # Restore original config
      if original_handler do
        Application.put_env(:square_client, :webhook_handler, original_handler)
      else
        Application.delete_env(:square_client, :webhook_handler)
      end

      if original_key do
        Application.put_env(:square_client, :webhook_signature_key, original_key)
      else
        Application.delete_env(:square_client, :webhook_signature_key)
      end
    end)

    :ok
  end

  describe "init/1" do
    test "passes through options" do
      opts = [foo: :bar]
      assert WebhookPlug.init(opts) == opts
    end
  end

  describe "call/2 with valid signature" do
    test "processes valid webhook with correct signature" do
      body = ~s({"type": "payment.created", "data": {"id": "123"}})
      signature = generate_signature(body, "test_signature_key")

      conn =
        conn(:post, "/webhook", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-square-hmacsha256-signature", signature)
        |> WebhookPlug.call([])

      assert {:ok, event} = conn.assigns.square_event
      assert event.event_type == "payment.created"
      assert event.data == %{"id" => "123"}
      assert_received :payment_created_handled
    end

    test "handles webhook that returns error from handler" do
      body = ~s({"type": "error.test", "data": {}})
      signature = generate_signature(body, "test_signature_key")

      capture_log(fn ->
        conn =
          conn(:post, "/webhook", body)
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-square-hmacsha256-signature", signature)
          |> WebhookPlug.call([])

        assert {:ok, event} = conn.assigns.square_event
        assert event.event_type == "error.test"
      end)
    end
  end

  describe "call/2 with invalid signature" do
    test "rejects webhook with invalid signature" do
      body = ~s({"type": "payment.created", "data": {"id": "123"}})

      capture_log(fn ->
        conn =
          conn(:post, "/webhook", body)
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-square-hmacsha256-signature", "invalid_signature")
          |> WebhookPlug.call([])

        assert {:error, :invalid_signature} = conn.assigns.square_event
      end)
    end

    test "rejects webhook with missing signature" do
      body = ~s({"type": "payment.created", "data": {"id": "123"}})

      capture_log(fn ->
        conn =
          conn(:post, "/webhook", body)
          |> put_req_header("content-type", "application/json")
          |> WebhookPlug.call([])

        assert {:error, :missing_signature} = conn.assigns.square_event
      end)
    end
  end

  describe "call/2 with invalid payload" do
    test "handles malformed JSON" do
      body = "not valid json"
      signature = generate_signature(body, "test_signature_key")

      capture_log(fn ->
        conn =
          conn(:post, "/webhook", body)
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-square-hmacsha256-signature", signature)
          |> WebhookPlug.call([])

        assert {:error, _} = conn.assigns.square_event
      end)
    end

    test "handles invalid event format" do
      body = ~s({"invalid": "format"})
      signature = generate_signature(body, "test_signature_key")

      capture_log(fn ->
        conn =
          conn(:post, "/webhook", body)
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-square-hmacsha256-signature", signature)
          |> WebhookPlug.call([])

        assert {:error, :invalid_event_format} = conn.assigns.square_event
      end)
    end
  end

  describe "configuration" do
    test "handles missing signature key configuration" do
      Application.delete_env(:square_client, :webhook_signature_key)
      System.delete_env("SQUARE_WEBHOOK_SIGNATURE_KEY")

      body = ~s({"type": "payment.created", "data": {"id": "123"}})

      capture_log(fn ->
        conn =
          conn(:post, "/webhook", body)
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-square-hmacsha256-signature", "any_signature")
          |> WebhookPlug.call([])

        assert {:error, :signature_key_not_configured} = conn.assigns.square_event
      end)

      # Restore for other tests
      Application.put_env(:square_client, :webhook_signature_key, "test_signature_key")
    end

    test "handles missing handler configuration" do
      Application.delete_env(:square_client, :webhook_handler)

      body = ~s({"type": "payment.created", "data": {"id": "123"}})
      signature = generate_signature(body, "test_signature_key")

      capture_log(fn ->
        conn =
          conn(:post, "/webhook", body)
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-square-hmacsha256-signature", signature)
          |> WebhookPlug.call([])

        # Should still parse and verify, just not handle
        assert {:ok, event} = conn.assigns.square_event
        assert event.event_type == "payment.created"
      end)

      # Restore for other tests
      Application.put_env(:square_client, :webhook_handler, MockHandler)
    end
  end

  # Helper function to generate valid signatures
  defp generate_signature(payload, key) do
    :crypto.mac(:hmac, :sha256, key, payload)
    |> Base.encode64()
  end
end
