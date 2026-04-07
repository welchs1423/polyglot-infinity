defmodule HubElixir.Plugs.CORS do
  @moduledoc "CORS 헤더를 추가하는 경량 Plug (외부 의존성 없음)"
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization")
    |> send_resp(204, "")
    |> halt()
  end

  def call(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization")
  end
end

defmodule HubElixir.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
    plug HubElixir.Plugs.CORS
  end

  scope "/api", HubElixir do
    pipe_through :api
    get "/hub/status", StatusController, :index
  end
end
