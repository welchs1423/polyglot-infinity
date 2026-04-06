defmodule HubElixir.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug, origin: "*"
  end

  scope "/api", HubElixir do
    pipe_through :api
    get "/hub/status", StatusController, :index
  end

  # WebSocket 업그레이드 엔드포인트
  socket "/socket", HubElixir.UserSocket,
    websocket: true,
    longpoll: false
end
