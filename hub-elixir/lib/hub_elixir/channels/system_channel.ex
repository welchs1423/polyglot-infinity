defmodule HubElixir.SystemChannel do
  use Phoenix.Channel

  @moduledoc """
  WebSocket 채널: 클라이언트가 "system:lobby"에 조인하면
  Poller가 10초마다 브로드캐스트하는 시스템 스냅숏을 실시간으로 수신한다.
  """

  def join("system:lobby", _payload, socket) do
    # 조인 즉시 최신 스냅숏을 전송
    send(self(), :after_join)
    {:ok, socket}
  end

  def handle_info(:after_join, socket) do
    snapshot = HubElixir.Poller.latest_snapshot()
    push(socket, "snapshot", snapshot)
    {:noreply, socket}
  end

  # Poller가 PubSub으로 브로드캐스트한 이벤트를 채널 클라이언트에 전달
  def handle_info({:broadcast, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end
end
