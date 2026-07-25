defmodule SquareClient.CheckoutTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias SquareClient.Checkout

  @test_app :square_client
  @test_config "checkout_test_plans.json"

  setup do
    bypass = Bypass.open()

    original_config = Application.get_all_env(:square_client)

    Application.put_env(:square_client, :api_url, "http://localhost:#{bypass.port}/v2")
    Application.put_env(:square_client, :access_token, "test_token")
    Application.put_env(:square_client, :disable_retries, true)

    path = Application.app_dir(@test_app, Path.join("priv", @test_config))
    File.mkdir_p!(Application.app_dir(@test_app, "priv"))

    config = %{
      "plans" => %{
        "premium" => %{
          "name" => "Premium Plan",
          "sandbox_base_plan_id" => "PLAN_SANDBOX_123",
          "production_base_plan_id" => nil,
          "variations" => %{
            "monthly" => %{
              "name" => "Monthly",
              "amount" => 999,
              "currency" => "USD",
              "cadence" => "MONTHLY",
              "sandbox_variation_id" => "VAR_SANDBOX_123",
              "production_variation_id" => nil,
              "active" => true
            },
            "legacy" => %{
              "name" => "Monthly",
              "amount" => 999,
              "currency" => "USD",
              "cadence" => "MONTHLY",
              "sandbox_variation_id" => "VAR_OLD",
              "production_variation_id" => nil,
              "active" => false
            },
            "yearly" => %{
              "name" => "Annual",
              "amount" => 9900,
              "cadence" => "ANNUAL",
              "sandbox_variation_id" => nil,
              "production_variation_id" => nil,
              "active" => true
            }
          }
        }
      }
    }

    File.write!(path, JSON.encode!(config))

    on_exit(fn ->
      File.rm(path)

      Enum.each(original_config, fn {key, value} ->
        Application.put_env(:square_client, key, value)
      end)
    end)

    {:ok, bypass: bypass}
  end

  describe "create_subscription_link/4 happy path" do
    test "sends catalog-sourced price, currency, and name with the caller's location",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/online-checkout/payment-links", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["quick_pay"]["name"] == "Premium Plan Monthly"
        assert request["quick_pay"]["price_money"]["amount"] == 999
        assert request["quick_pay"]["price_money"]["currency"] == "USD"
        assert request["quick_pay"]["location_id"] == "LOC_TEST"
        assert request["checkout_options"]["subscription_plan_id"] == "VAR_SANDBOX_123"
        refute Map.has_key?(request["checkout_options"], "redirect_url")

        response = %{
          "payment_link" => %{
            "id" => "PLINK_1",
            "url" => "https://square.link/u/abc"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "monthly",
              location_id: "LOC_TEST",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}

      assert result ==
               {:ok, %{payment_link_id: "PLINK_1", checkout_url: "https://square.link/u/abc"}}
    end

    test "passes redirect_url through when provided", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/online-checkout/payment-links", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = JSON.decode!(body)

        assert request["checkout_options"]["redirect_url"] == "https://myapp.com/done"

        response = %{
          "payment_link" => %{
            "id" => "PLINK_2",
            "url" => "https://square.link/u/def"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, JSON.encode!(response))
      end)

      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "monthly",
              location_id: "LOC_TEST",
              redirect_url: "https://myapp.com/done",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert {:ok, %{payment_link_id: "PLINK_2"}} = result
    end
  end

  describe "create_subscription_link/4 pre-flight failures" do
    test "missing location_id returns error without any HTTP request" do
      log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "monthly",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result == {:error, :location_id_required}
      assert log =~ "location_id is required"
    end

    test "empty string location_id returns error without any HTTP request" do
      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "monthly",
              location_id: "",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result == {:error, :location_id_required}
    end

    test "unknown plan key returns error without any HTTP request" do
      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "nonexistent", "monthly",
              location_id: "LOC_TEST",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result == {:error, :unknown_plan}
    end

    test "unknown variation key returns error without any HTTP request" do
      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "nonexistent",
              location_id: "LOC_TEST",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result == {:error, :unknown_variation}
    end

    test "inactive variation returns error without any HTTP request" do
      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "legacy",
              location_id: "LOC_TEST",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result == {:error, :variation_inactive}
    end

    test "unprovisioned variation returns error without any HTTP request" do
      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "yearly",
              location_id: "LOC_TEST",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result == {:error, :variation_not_provisioned}
    end
  end

  describe "create_subscription_link/4 API error handling" do
    test "surfaces Square's error detail on a non-success response", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/online-checkout/payment-links", fn conn ->
        error_response = %{
          "errors" => [
            %{
              "category" => "INVALID_REQUEST_ERROR",
              "code" => "BAD_REQUEST",
              "detail" => "INVALID_LOCATION"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, JSON.encode!(error_response))
      end)

      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "monthly",
              location_id: "LOC_TEST",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result == {:error, "INVALID_LOCATION"}
    end

    test "returns :api_unavailable when Square is unreachable", %{bypass: bypass} do
      Bypass.down(bypass)

      _log =
        capture_log(fn ->
          result =
            Checkout.create_subscription_link(@test_app, "premium", "monthly",
              location_id: "LOC_TEST",
              config_path: @test_config
            )

          send(self(), {:result, result})
        end)

      assert_received {:result, result}
      assert result == {:error, :api_unavailable}
    end
  end
end
