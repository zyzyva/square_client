defmodule SquareClient.TaskBoot do
  @moduledoc """
  Boots exactly what the `mix square.*` tasks need to run in a consuming
  app, and nothing more.

  Loads the host application's code and configuration (including runtime
  config) and makes its priv directory resolvable on disk, then starts
  this library's own dependency chain (`req`/`finch`) so the tasks can
  make Square API calls. It never starts the host application's
  supervision tree — no queue workers, no web endpoint, no repo, no
  background jobs. A dev server already running in another terminal is
  unaffected.
  """

  @doc """
  Loads the host app's code/config and starts this library's HTTP
  dependency chain. Does not start the host app's supervision tree.
  """
  @spec ensure_runtime! :: :ok
  def ensure_runtime! do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:square_client)
    :ok
  end
end
