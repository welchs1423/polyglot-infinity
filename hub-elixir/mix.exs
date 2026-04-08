defmodule HubElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :hub_elixir,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {HubElixir.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.2"},
      {:plug_cowboy, "~> 2.7"},
      {:redix, "~> 1.4"}
    ]
  end
end
