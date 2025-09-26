import Config

# Test configuration - disable retries for faster tests
# IMPORTANT: Tests must set api_url via Application.put_env in their setup blocks
config :square_client,
  disable_retries: true,
  # Set to a non-routable address to ensure tests fail if they don't configure Bypass
  api_url: "http://192.0.2.1:9999/v2",
  access_token: "test_token_only",
  location_id: "TEST_LOCATION"
