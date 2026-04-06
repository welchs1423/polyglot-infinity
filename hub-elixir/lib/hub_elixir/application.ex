defmodule HubElixir.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Phoenix PubSub — 프로세스 간 메시지 브로드캐스트
      {Phoenix.PubSub, name: HubElixir.PubSub},
      # 주기적으로 Go API를 폴링해서 WebSocket 클라이언트에 브로드캐스트
      HubElixir.Poller,
      # Bandit HTTP + WebSocket 서버
      {Bandit, plug: HubElixir.Router, port: 4000}
    ]

    opts = [strategy: :one_for_one, name: HubElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
