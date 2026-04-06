import Config

config :hub_elixir, HubElixir.Endpoint,
  url: [host: "localhost"],
  http: [port: 4000]

config :logger, level: :info
