defmodule HubElixir.UserSocket do
  use Phoenix.Socket

  # "system" 토픽으로 연결 → SystemChannel로 디스패치
  channel "system:*", HubElixir.SystemChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
