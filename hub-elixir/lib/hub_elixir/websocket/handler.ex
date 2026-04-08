defmodule HubElixir.WebSocket.Handler do
  @moduledoc """
  Cowboy WebSocket handler implementing the :cowboy_websocket behaviour.

  Each connected client spawns an independent BEAM process for this handler,
  giving natural per-connection isolation with no shared mutable state.

  Lifecycle
    init/2           - validates the HTTP upgrade request and stores peer info
    websocket_init/1 - registers in Registry, pushes the initial snapshot frame
    websocket_handle/2 - decodes frames received from the client
    websocket_info/2 - forwards {:ws_broadcast, encoded} frames to the client
    terminate/3      - logs the disconnection reason

  Bidirectional protocol (JSON over text frames):
    Client sends  {"event": "ping"}
    Server replies {"event": "pong", "ts": <unix_ms>}

    Server pushes {"event": "snapshot", "payload": {...}} on connect and
                  on every Poller tick (every 10 s) or Redis event.
  """

  @behaviour :cowboy_websocket

  require Logger

  @idle_timeout_ms 60_000

  # Called by Cowboy when an HTTP request arrives on the /ws path.
  # Signals Cowboy to upgrade the connection to WebSocket and stores
  # the peer address in state for diagnostic logging.
  def init(req, _opts) do
    peer  = :cowboy_req.peer(req)
    state = %{peer: peer}
    Logger.info("[WS] client connecting from #{inspect(peer)}")
    {:cowboy_websocket, req, state, %{idle_timeout: @idle_timeout_ms}}
  end

  # Called by Cowboy after the WebSocket handshake completes.
  # Registers this process in the client Registry so Broadcaster can reach it,
  # then immediately pushes the latest cached snapshot as the first frame.
  def websocket_init(state) do
    :ok       = HubElixir.WebSocket.Registry.register()
    snapshot  = HubElixir.Poller.latest_snapshot()

    case Jason.encode(%{"event" => "snapshot", "payload" => snapshot}) do
      {:ok, frame} ->
        {:reply, {:text, frame}, state}

      {:error, reason} ->
        Logger.warning("[WS] failed to encode initial snapshot: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Handles a text frame received from the client.
  # The frame must be a UTF-8 JSON object with an "event" key.
  def websocket_handle({:text, data}, state) do
    case Jason.decode(data) do
      {:ok, %{"event" => "ping"}} ->
        ts           = System.system_time(:millisecond)
        {:ok, frame} = Jason.encode(%{"event" => "pong", "ts" => ts})
        {:reply, {:text, frame}, state}

      {:ok, %{"event" => event}} ->
        Logger.debug("[WS] received event=#{event} peer=#{inspect(state.peer)}")
        {:ok, state}

      {:error, _reason} ->
        Logger.warning("[WS] non-JSON text frame from peer=#{inspect(state.peer)}")
        {:ok, state}
    end
  end

  # Binary frames and control frames (ping, pong) are acknowledged silently.
  def websocket_handle(_frame, state), do: {:ok, state}

  # Forwards a pre-encoded broadcast message to the connected client.
  # The message originates from HubElixir.WebSocket.Broadcaster which is called
  # by both Poller (periodic) and RedisSubscriber (event-driven).
  def websocket_info({:ws_broadcast, encoded}, state) when is_binary(encoded) do
    {:reply, {:text, encoded}, state}
  end

  # Ignores any other Erlang messages that arrive in the process mailbox.
  def websocket_info(_msg, state), do: {:ok, state}

  # Called by Cowboy when the connection is closed for any reason.
  # Registry deregistration is automatic because the process terminates.
  def terminate(reason, _req, state) do
    Logger.info("[WS] client disconnected peer=#{inspect(state.peer)} reason=#{inspect(reason)}")
    :ok
  end
end
