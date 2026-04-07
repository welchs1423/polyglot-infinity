defmodule HubElixir.Endpoint do
  use Phoenix.Endpoint, otp_app: :hub_elixir

  # WebSocket 트랜스포트 — /socket/websocket 경로
  socket "/socket", HubElixir.UserSocket,
    websocket: [
      check_origin: false,
      timeout: 45_000
    ],
    longpoll: false

  plug HubElixir.Plugs.CORS
  plug HubElixir.Router
end
