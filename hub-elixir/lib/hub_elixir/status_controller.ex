defmodule HubElixir.StatusController do
  use Phoenix.Controller, formats: [:json]

  @moduledoc """
  GET /api/hub/status
  Poller가 보유한 최신 시스템 스냅숏(Go + 다운스트림 집계)을 반환한다.
  스냅숏이 아직 없으면 초기화 중임을 알리는 응답을 즉시 반환한다.
  """

  def index(conn, _params) do
    snapshot = HubElixir.Poller.latest_snapshot()

    status_code =
      case Map.get(snapshot, "elixir_hub") do
        "online" -> 200
        _        -> 503
      end

    conn
    |> put_status(status_code)
    |> json(Map.put(snapshot, "served_by", "HubElixir.StatusController"))
  end
end
