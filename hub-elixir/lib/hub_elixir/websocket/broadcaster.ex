defmodule HubElixir.WebSocket.Broadcaster do
  @moduledoc """
  Utility module for encoding event payloads to JSON and dispatching
  broadcast messages to all registered Cowboy WebSocket clients via
  HubElixir.WebSocket.Registry.

  Called by both HubElixir.Poller (periodic snapshot) and
  HubElixir.RedisSubscriber (event-driven Redis Pub/Sub messages).
  """

  require Logger

  # Encodes event and payload as a JSON object and broadcasts to all clients.
  # event   - string event name visible to WebSocket clients
  # payload - any Jason-encodable term used as the message body
  def broadcast(event, payload) when is_binary(event) do
    case Jason.encode(%{"event" => event, "payload" => payload}) do
      {:ok, encoded} ->
        HubElixir.WebSocket.Registry.broadcast(encoded)

      {:error, reason} ->
        Logger.warning("[Broadcaster] JSON encode error for event=#{event}: #{inspect(reason)}")
    end
  end
end
