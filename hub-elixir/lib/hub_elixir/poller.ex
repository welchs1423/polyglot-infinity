defmodule HubElixir.Poller do
  use GenServer
  require Logger

  @poll_interval 10_000   # 10 s between Go API polls
  @go_api        "http://localhost:8080/api/status"

  # Public API

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def latest_snapshot, do: GenServer.call(__MODULE__, :latest)

  # GenServer callbacks

  @impl true
  def init(_) do
    schedule_poll()
    {:ok, %{snapshot: %{status: "initializing"}}}
  end

  @impl true
  def handle_info(:poll, state) do
    snapshot = fetch_snapshot()

    # Path 1: Phoenix Channel clients — Phoenix.PubSub delivers raw Erlang messages
    # to each Phoenix.Channel.Server process subscribed to the "system:lobby" topic.
    Phoenix.PubSub.broadcast(
      HubElixir.PubSub,
      "system:lobby",
      {:broadcast, "snapshot", snapshot}
    )

    # Path 2: Cowboy WebSocket clients — Registry.dispatch sends to each handler process.
    HubElixir.WebSocket.Broadcaster.broadcast("snapshot", snapshot)

    schedule_poll()
    {:noreply, %{state | snapshot: snapshot}}
  end

  @impl true
  def handle_call(:latest, _from, state) do
    {:reply, state.snapshot, state}
  end

  # Private helpers

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)

  defp fetch_snapshot do
    case HTTPoison.get(@go_api, [], recv_timeout: 3_000) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            data
            |> Map.put("elixir_hub", "online")
            |> Map.put("polled_at", DateTime.utc_now() |> DateTime.to_iso8601())

          {:error, _reason} ->
            error_snapshot("JSON decode failed")
        end

      {:error, reason} ->
        Logger.warning("[Poller] Go API call failed: #{inspect(reason)}")
        error_snapshot("Go API unreachable")
    end
  end

  defp error_snapshot(msg) do
    %{
      "elixir_hub" => "online",
      "go_status"  => "error",
      "error"      => msg,
      "polled_at"  => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
