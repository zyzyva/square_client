defmodule SquareClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :square_client,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Square API client for Elixir with subscription management focus",
      package: package(),
      docs: [
        main: "SquareClient",
        extras: ["README.md"]
      ],
      igniter: [
        Mix.Tasks.SquareClient.Install
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:plug, "~> 1.16", optional: true},
      {:plug_crypto, "~> 2.0"},
      {:ecto, "~> 3.13", optional: true},
      {:igniter, "~> 0.6", optional: true},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/zyzyva/square_client"},
      maintainers: ["Zyzyva Team"]
    ]
  end
end
