defmodule SquareClient.HTTP do
  @moduledoc """
  HTTP client for payment service requests.
  """

  alias SquareClient.Config

  @doc """
  Make a GET request to Square API.
  """
  def get(path, opts \\ []) do
    request(:get, path, nil, opts)
  end

  @doc """
  Make a POST request to Square API.
  """
  def post(path, body, opts \\ []) do
    request(:post, path, body, opts)
  end

  @doc """
  Make a PUT request to Square API.
  """
  def put(path, body, opts \\ []) do
    request(:put, path, body, opts)
  end

  @doc """
  Make a DELETE request to Square API.
  """
  def delete(path, opts \\ []) do
    request(:delete, path, nil, opts)
  end

  defp request(method, path, body, opts) do
    url = build_url(path)
    headers = build_headers()

    # Add app_id to all requests
    body = add_app_metadata(body)

    req_opts = [
      method: method,
      url: url,
      headers: headers
    ]

    req_opts =
      if body do
        Keyword.put(req_opts, :json, body)
      else
        req_opts
      end

    req_opts = Keyword.merge(req_opts, opts)

    case Req.request(req_opts) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, %{status: status, body: response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_url(path) do
    base = Config.base_url()
    "#{base}#{path}"
  end

  defp build_headers do
    headers = [
      {"Content-Type", "application/json"},
      {"X-App-ID", Config.app_id()}
    ]

    # Add API key if configured
    case Config.get(:api_key) do
      nil -> headers
      key -> [{"Authorization", "Bearer #{key}"} | headers]
    end
  end

  defp add_app_metadata(nil), do: nil

  defp add_app_metadata(body) when is_map(body) do
    body
    |> Map.put(:app_id, Config.app_id())
    |> Map.put(:app_metadata, %{
      app: Config.app_id(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp add_app_metadata(body), do: body
end
