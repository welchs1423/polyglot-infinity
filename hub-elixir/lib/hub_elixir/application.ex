defmodule HubElixir.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Phoenix PubSub — 프로세스 간 메시지 브로드캐스트
      {Phoenix.PubSub, name: HubElixir.PubSub},
      # Phoenix Endpoint — HTTP(:4000) + WebSocket(/socket/websocket)
      HubElixir.Endpoint,
      # 주기적으로 Go API를 폴링해서 WebSocket 클라이언트에 브로드캐스트
      HubElixir.Poller,
      # Redis Pub/Sub 구독자 — Go 워크플로 완료 이벤트 수신 → Phoenix Channel 브로드캐스트
      HubElixir.RedisSubscriber
    ]

    opts = [strategy: :one_for_one, name: HubElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
