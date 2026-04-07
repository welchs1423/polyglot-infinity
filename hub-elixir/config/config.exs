import Config

config :hub_elixir, HubElixir.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [port: 4000],
  secret_key_base: String.duplicate("polyglot_infinity_hub_elixir_secret_", 2),
  pubsub_server: HubElixir.PubSub,
  live_view: [signing_salt: "hub_elixir"]

config :logger, level: :info
