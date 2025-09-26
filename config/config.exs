import Config

# This config is for the square_client library itself
# Apps using this library can override these in their own config files

# Default configuration (sandbox)
config :square_client,
  api_url: System.get_env("SQUARE_API_URL"),
  access_token: System.get_env("SQUARE_ACCESS_TOKEN")

# Import environment specific config
import_config "#{config_env()}.exs"
