defmodule SquareClient do
  @moduledoc """
  Direct Square API client library for Elixir applications.

  ## Overview

  SquareClient provides direct integration with Square's REST API for:
  - Payment processing
  - Subscription management
  - Customer management
  - Catalog operations

  ## Architecture

      Your App → SquareClient → Square API

  ## Key Features

  - **Direct API integration** - No proxy service or message queue required
  - **Synchronous operations** - Immediate feedback for payment processing
  - **Environment-aware** - Use provided helper functions in your config
  - **Minimal configuration** - Only requires access token and location ID
  - **Comprehensive catalog management** - Base plans with pricing variations

  ## Configuration

  Configure in your app's config files. Use the URLs defined in this module:

      # config/dev.exs and config/test.exs
      config :square_client,
        api_url: "https://connect.squareupsandbox.com/v2",
        access_token: System.get_env("SQUARE_ACCESS_TOKEN"),
        location_id: System.get_env("SQUARE_LOCATION_ID")

      # config/prod.exs
      config :square_client,
        api_url: "https://connect.squareup.com/v2",
        access_token: System.get_env("SQUARE_ACCESS_TOKEN"),
        location_id: System.get_env("SQUARE_LOCATION_ID")

  The `sandbox_api_url/0` and `production_api_url/0` functions are provided
  for reference and runtime use, but cannot be used directly in config files.
  """

  @doc """
  Returns the current library version.
  """
  def version do
    "0.1.0"
  end

  @doc """
  Returns the Square sandbox API URL for development and testing.

  This function is provided for reference and runtime use. In config files,
  use the string directly: `"https://connect.squareupsandbox.com/v2"`
  """
  def sandbox_api_url, do: "https://connect.squareupsandbox.com/v2"

  @doc """
  Returns the Square production API URL.

  This function is provided for reference and runtime use. In config files,
  use the string directly: `"https://connect.squareup.com/v2"`
  """
  def production_api_url, do: "https://connect.squareup.com/v2"
end
