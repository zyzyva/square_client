defmodule APP_MODULEWeb.SquareWebhookControllerTest do
  use APP_MODULEWeb.ConnCase, async: true
  import ExUnit.CaptureLog

  describe "handle/2" do
    test "returns success for valid webhook event", %{conn: conn} do
      # Directly call the controller action instead of going through the router
      conn =
        conn
        |> assign(:square_event, {:ok, %{event_type: "payment.created", event_id: "evt_123"}})

      conn = APP_MODULEWeb.SquareWebhookController.handle(conn, %{})

      assert json_response(conn, 200) == %{
               "received" => true,
               "event_id" => "evt_123"
             }
    end

    test "returns unauthorized for invalid signature", %{conn: conn} do
      log =
        capture_log(fn ->
          conn =
            conn
            |> assign(:square_event, {:error, :invalid_signature})

          conn = APP_MODULEWeb.SquareWebhookController.handle(conn, %{})

          assert json_response(conn, 401) == %{"error" => "Invalid signature"}
        end)

      assert log =~ "Received Square webhook with invalid signature"
    end

    test "returns unauthorized for missing signature", %{conn: conn} do
      log =
        capture_log(fn ->
          conn =
            conn
            |> assign(:square_event, {:error, :missing_signature})

          conn = APP_MODULEWeb.SquareWebhookController.handle(conn, %{})

          assert json_response(conn, 401) == %{"error" => "Missing signature"}
        end)

      assert log =~ "Received Square webhook without signature header"
    end

    test "returns bad request for other errors", %{conn: conn} do
      log =
        capture_log(fn ->
          conn =
            conn
            |> assign(:square_event, {:error, :invalid_format})

          conn = APP_MODULEWeb.SquareWebhookController.handle(conn, %{})

          assert json_response(conn, 400) == %{"error" => "Webhook processing failed"}
        end)

      assert log =~ "Square webhook processing failed"
    end

    test "returns internal server error when square_event is not set", %{conn: conn} do
      log =
        capture_log(fn ->
          conn = APP_MODULEWeb.SquareWebhookController.handle(conn, %{})
          assert json_response(conn, 500) == %{"error" => "Internal server error"}
        end)

      assert log =~ "Square webhook event not found in assigns"
    end
  end
end
