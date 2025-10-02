import Config

# Production configuration
# Should use real Square production API
# URL will be determined by SQUARE_ENVIRONMENT env var

# Square client production configuration
config :square_client,
  api_url: "https://connect.squareup.com/v2"
