defmodule HubElixir.Poller do
  use GenServer
  require Logger

  @poll_interval 10_000   # 10초마다 Go API 폴링
  @go_api        "http://localhost:8080/api/status"

  # ── 공개 API ───────────────────────────────────────────────
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def latest_snapshot, do: GenServer.call(__MODULE__, :latest)

  # ── GenServer 콜백 ─────────────────────────────────────────
  @impl true
  def init(_) do
    schedule_poll()
    {:ok, %{snapshot: %{status: "initializing"}}}
  end

  @impl true
  def handle_info(:poll, state) do
    snapshot = fetch_snapshot()
    # PubSub으로 전체 채널에 브로드캐스트
    Phoenix.PubSub.broadcast(HubElixir.PubSub, "system:lobby", {:broadcast, "snapshot", snapshot})
    schedule_poll()
    {:noreply, %{state | snapshot: snapshot}}
  end

  @impl true
  def handle_call(:latest, _from, state) do
    {:reply, state.snapshot, state}
  end

  # ── 내부 헬퍼 ──────────────────────────────────────────────
  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)

  defp fetch_snapshot do
    case HTTPoison.get(@go_api, [], recv_timeout: 3_000) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            data
            |> Map.put("elixir_hub", "online")
            |> Map.put("polled_at", DateTime.utc_now() |> DateTime.to_iso8601())
          _ -> error_snapshot("JSON decode failed")
        end
      {:error, reason} ->
        Logger.warning("[Elixir Poller] Go API 호출 실패: #{inspect(reason)}")
        error_snapshot("Go API unreachable")
    end
  end

  defp error_snapshot(msg), do: %{
    "elixir_hub" => "online",
    "go_status"  => "error",
    "error"      => msg,
    "polled_at"  => DateTime.utc_now() |> DateTime.to_iso8601()
  }
end
