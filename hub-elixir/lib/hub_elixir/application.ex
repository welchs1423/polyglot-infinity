defmodule HubElixir.Application do
  use Application

  require Logger

  # Port for the standalone Cowboy WebSocket server (raw /ws endpoint).
  # The Phoenix HTTP server continues to run on port 4000 via Bandit.
  @ws_port 4001

  @impl true
  def start(_type, _args) do
    children = [
      # ETS-backed Registry tracking all active Cowboy WebSocket client processes.
      HubElixir.WebSocket.Registry,
      # Phoenix PubSub for Phoenix Channel delivery (port 4000 path).
      {Phoenix.PubSub, name: HubElixir.PubSub},
      # Phoenix Endpoint — HTTP(:4000) + Phoenix Channel WebSocket (/socket/websocket).
      HubElixir.Endpoint,
      # Periodic Go API poller — broadcasts snapshots to all WebSocket clients.
      HubElixir.Poller,
      # Redis Pub/Sub subscriber — forwards external events to all WebSocket clients.
      HubElixir.RedisSubscriber
    ]

    opts = [strategy: :one_for_one, name: HubElixir.Supervisor]

    {:ok, sup} = Supervisor.start_link(children, opts)

    # Start the Cowboy WebSocket listener after the supervisor tree is up.
    # The Registry must already be running before Cowboy accepts connections
    # so that websocket_init/1 can call Registry.register/0 without error.
    start_cowboy_ws()

    {:ok, sup}
  end

  # Starts a standalone Cowboy HTTP listener whose sole route upgrades
  # GET /ws to a WebSocket connection handled by HubElixir.WebSocket.Handler.
  # All other paths receive a 404 from the default cowboy_handler.
  defp start_cowboy_ws do
    dispatch = :cowboy_router.compile([
      {:_, [
        {"/ws", HubElixir.WebSocket.Handler, []},
        {:_, :cowboy_handler, :not_found}
      ]}
    ])

    transport_opts = %{socket_opts: [{:port, @ws_port}]}
    protocol_opts  = %{env: %{dispatch: dispatch}}

    case :cowboy.start_clear(:ws_listener, transport_opts, protocol_opts) do
      {:ok, _pid} ->
        Logger.info("[Application] Cowboy WebSocket listener started on port #{@ws_port}")

      {:error, {:already_started, _pid}} ->
        Logger.info("[Application] Cowboy WebSocket listener already running on port #{@ws_port}")

      {:error, reason} ->
        Logger.error("[Application] Cowboy WebSocket listener failed to start: #{inspect(reason)}")
    end
  end
end
