defmodule HubElixir.WebSocket.Registry do
  @moduledoc """
  ETS-backed Registry for tracking active Cowboy WebSocket handler processes.

  Uses duplicate-key mode so all connected client processes register under the
  single :ws_client key while each retaining its own process identity.
  When a client process terminates (normal or abnormal disconnect), its registry
  entry is automatically removed by the Registry without any explicit cleanup.
  """

  @name __MODULE__

  def child_spec(_opts) do
    Registry.child_spec(keys: :duplicate, name: @name)
  end

  # Registers the calling process as an active WebSocket client.
  # Must be called from websocket_init/1 after the handshake completes.
  def register do
    {:ok, _owner} = Registry.register(@name, :ws_client, nil)
    :ok
  end

  # Sends an already-encoded JSON binary to every registered client process.
  # Registry.dispatch is non-blocking for the caller; each send/2 is async.
  def broadcast(encoded_message) when is_binary(encoded_message) do
    Registry.dispatch(@name, :ws_client, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:ws_broadcast, encoded_message})
      end
    end)
  end
end
