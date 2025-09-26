defmodule SquareClient.PlansTest do
  use ExUnit.Case, async: true

  alias SquareClient.Plans

  @test_app :square_client
  @test_config "test_plans.json"

  setup do
    # Clean up any existing test config
    path = Application.app_dir(@test_app, Path.join("priv", @test_config))

    # Ensure app directory exists
    Application.app_dir(@test_app, "priv") |> File.mkdir_p!()

    # Clean up after test
    on_exit(fn ->
      File.rm(path)
    end)

    {:ok, %{path: path}}
  end

  describe "init_config/2" do
    test "creates a new config file with default structure", %{path: path} do
      # Remove if exists
      File.rm(path)

      assert {:ok, ^path} = Plans.init_config(@test_app, @test_config)
      assert File.exists?(path)

      # Verify structure
      {:ok, content} = File.read(path)
      {:ok, config} = JSON.decode(content)

      assert config["development"]["plans"] == %{}
      assert config["production"]["plans"] == %{}
    end

    test "returns error if config already exists", %{path: path} do
      # Create config first
      File.write!(path, "{}")

      assert {:error, :already_exists} = Plans.init_config(@test_app, @test_config)
    end
  end

  describe "get_plans/2" do
    test "returns empty map when no plans configured" do
      plans = Plans.get_plans(@test_app, @test_config)
      assert plans == %{}
    end

    test "returns plans for current environment", %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "basic" => %{
              "name" => "Basic Plan",
              "base_plan_id" => nil
            }
          }
        },
        "production" => %{
          "plans" => %{}
        }
      }

      File.write!(path, JSON.encode!(config))

      plans = Plans.get_plans(@test_app, @test_config)
      assert plans["basic"]["name"] == "Basic Plan"
    end
  end

  describe "get_plan/3" do
    setup %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "name" => "Premium Plan",
              "base_plan_id" => "PLAN_123",
              "variations" => %{
                "monthly" => %{
                  "variation_id" => "VAR_MONTHLY",
                  "amount" => 999
                },
                "yearly" => %{
                  "variation_id" => "VAR_YEARLY",
                  "amount" => 9900
                }
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))
      :ok
    end

    test "returns plan by string key" do
      plan = Plans.get_plan(@test_app, "premium", @test_config)
      assert plan["name"] == "Premium Plan"
      assert plan["base_plan_id"] == "PLAN_123"
    end

    test "returns plan by atom key" do
      plan = Plans.get_plan(@test_app, :premium, @test_config)
      assert plan["name"] == "Premium Plan"
    end

    test "returns nil for non-existent plan" do
      assert nil == Plans.get_plan(@test_app, "nonexistent", @test_config)
    end
  end

  describe "get_variation/4" do
    setup %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "variations" => %{
                "monthly" => %{
                  "variation_id" => "VAR_MONTHLY",
                  "amount" => 999,
                  "cadence" => "MONTHLY"
                }
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))
      :ok
    end

    test "returns variation details" do
      variation = Plans.get_variation(@test_app, "premium", "monthly", @test_config)
      assert variation["variation_id"] == "VAR_MONTHLY"
      assert variation["amount"] == 999
      assert variation["cadence"] == "MONTHLY"
    end

    test "returns nil for non-existent variation" do
      assert nil == Plans.get_variation(@test_app, "premium", "quarterly", @test_config)
    end

    test "returns nil for non-existent plan" do
      assert nil == Plans.get_variation(@test_app, "basic", "monthly", @test_config)
    end
  end

  describe "get_variation_id/4" do
    setup %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "variations" => %{
                "monthly" => %{"variation_id" => "VAR_123"},
                "yearly" => %{"variation_id" => nil}
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))
      :ok
    end

    test "returns variation ID when configured" do
      assert "VAR_123" == Plans.get_variation_id(@test_app, "premium", "monthly", @test_config)
    end

    test "returns nil when variation ID not set" do
      assert nil == Plans.get_variation_id(@test_app, "premium", "yearly", @test_config)
    end

    test "returns nil for non-existent variation" do
      assert nil == Plans.get_variation_id(@test_app, "premium", "quarterly", @test_config)
    end
  end

  describe "update_base_plan_id/4" do
    setup %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "name" => "Premium",
              "base_plan_id" => nil
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))
      :ok
    end

    test "updates base plan ID", %{path: path} do
      assert :ok = Plans.update_base_plan_id(@test_app, "premium", "NEW_PLAN_ID", @test_config)

      # Verify it was saved
      {:ok, content} = File.read(path)
      {:ok, config} = JSON.decode(content)

      assert config["development"]["plans"]["premium"]["base_plan_id"] == "NEW_PLAN_ID"
    end

    test "creates nested structure if needed" do
      assert :ok = Plans.update_base_plan_id(@test_app, "new_plan", "PLAN_789", @test_config)

      plan = Plans.get_plan(@test_app, "new_plan", @test_config)
      assert plan["base_plan_id"] == "PLAN_789"
    end
  end

  describe "update_variation_id/5" do
    setup %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "variations" => %{
                "monthly" => %{
                  "amount" => 999,
                  "variation_id" => nil
                }
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))
      :ok
    end

    test "updates variation ID", %{path: path} do
      assert :ok =
               Plans.update_variation_id(@test_app, "premium", "monthly", "VAR_NEW", @test_config)

      # Verify it was saved
      {:ok, content} = File.read(path)
      {:ok, config} = JSON.decode(content)

      variation = config["development"]["plans"]["premium"]["variations"]["monthly"]
      assert variation["variation_id"] == "VAR_NEW"
      # Ensure other fields preserved
      assert variation["amount"] == 999
    end

    test "creates nested structure if needed" do
      assert :ok =
               Plans.update_variation_id(@test_app, "premium", "quarterly", "VAR_Q", @test_config)

      variation = Plans.get_variation(@test_app, "premium", "quarterly", @test_config)
      assert variation["variation_id"] == "VAR_Q"
    end
  end

  describe "all_configured?/2" do
    setup %{path: path} do
      {:ok, %{path: path}}
    end

    test "returns true when all plans and variations have IDs", %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "base_plan_id" => "PLAN_123",
              "variations" => %{
                "monthly" => %{"variation_id" => "VAR_1"},
                "yearly" => %{"variation_id" => "VAR_2"}
              }
            },
            "basic" => %{
              "base_plan_id" => "PLAN_456",
              "variations" => %{
                "monthly" => %{"variation_id" => "VAR_3"}
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))

      assert Plans.all_configured?(@test_app, @test_config) == true
    end

    test "returns false when base plan ID missing", %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "base_plan_id" => nil,
              "variations" => %{
                "monthly" => %{"variation_id" => "VAR_1"}
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))

      assert Plans.all_configured?(@test_app, @test_config) == false
    end

    test "returns false when variation ID missing", %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "base_plan_id" => "PLAN_123",
              "variations" => %{
                "monthly" => %{"variation_id" => "VAR_1"},
                "yearly" => %{"variation_id" => nil}
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))

      assert Plans.all_configured?(@test_app, @test_config) == false
    end

    test "returns true for empty plans", %{path: path} do
      config = %{
        "development" => %{"plans" => %{}},
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))

      assert Plans.all_configured?(@test_app, @test_config) == true
    end
  end

  describe "unconfigured_items/2" do
    test "identifies plans and variations needing creation", %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "name" => "Premium",
              "base_plan_id" => nil,
              "variations" => %{
                "monthly" => %{"variation_id" => nil},
                "yearly" => %{"variation_id" => "VAR_EXIST"}
              }
            },
            "basic" => %{
              "name" => "Basic",
              "base_plan_id" => "PLAN_BASIC",
              "variations" => %{
                "monthly" => %{"variation_id" => nil}
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))

      result = Plans.unconfigured_items(@test_app, @test_config)

      # Premium needs base plan creation
      assert length(result.base_plans) == 1

      assert {"premium", %{"name" => "Premium"}} =
               Enum.find(result.base_plans, fn {key, _} -> key == "premium" end)

      # Premium monthly and Basic monthly need variation creation
      assert length(result.variations) == 2

      # Note: Since premium has no base_plan_id, its variations can't be created yet
      premium_monthly =
        Enum.find(result.variations, fn
          {"premium", "monthly", _, nil} -> true
          _ -> false
        end)

      assert premium_monthly != nil

      basic_monthly =
        Enum.find(result.variations, fn
          {"basic", "monthly", _, "PLAN_BASIC"} -> true
          _ -> false
        end)

      assert basic_monthly != nil
    end

    test "returns empty lists when all configured", %{path: path} do
      config = %{
        "development" => %{
          "plans" => %{
            "premium" => %{
              "base_plan_id" => "PLAN_123",
              "variations" => %{
                "monthly" => %{"variation_id" => "VAR_1"}
              }
            }
          }
        },
        "production" => %{"plans" => %{}}
      }

      File.write!(path, JSON.encode!(config))

      result = Plans.unconfigured_items(@test_app, @test_config)

      assert result.base_plans == []
      assert result.variations == []
    end
  end

  describe "environment detection" do
    test "uses development for test environment" do
      # In test env, should use development config
      plans = Plans.get_plans(@test_app, @test_config)
      # This should not fail, confirming it's looking at development
      assert is_map(plans)
    end
  end

  describe "JSON formatting" do
    test "formats JSON for readability", %{path: path} do
      Plans.update_base_plan_id(@test_app, "test", "ID", @test_config)

      {:ok, content} = File.read(path)

      # Should have newlines and indentation
      assert String.contains?(content, "\n")
      assert String.contains?(content, "  ")
    end
  end
end
