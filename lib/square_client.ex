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
  - **Environment-aware** - Automatic sandbox/production switching
  - **Flexible configuration** - Application config, environment variables, or defaults
  - **Comprehensive catalog management** - Base plans with pricing variations

  ## Configuration

  Configure in your app's config files:

      config :square_client,
        api_url: "https://connect.squareupsandbox.com/v2",
        access_token: System.get_env("SQUARE_ACCESS_TOKEN")

  Or use environment variables:
  - `SQUARE_ACCESS_TOKEN` - Your Square API access token
  - `SQUARE_ENVIRONMENT` - "production" or "sandbox" (default)
  - `SQUARE_LOCATION_ID` - Your Square location ID
  """

  @doc """
  Returns the current library version.
  """
  def version do
    "0.1.0"
  end
end