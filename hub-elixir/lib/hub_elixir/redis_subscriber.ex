defmodule HubElixir.RedisSubscriber do
  @moduledoc """
  Redis Pub/Sub 구독자 — `polyglot:events` 채널을 구독하고
  수신된 이벤트를 Phoenix PubSub으로 브로드캐스트한다.

  Go가 워크플로 완료 시 Redis PUBLISH로 이벤트를 발행하면
  이 GenServer가 수신해 Phoenix Channel 클라이언트에게 실시간 전달한다.
  """
  use GenServer
  require Logger

  @channel "polyglot:events"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_) do
    case Redix.start_link("redis://localhost:6379", name: :redix_pubsub) do
      {:ok, conn} ->
        # 비동기 구독
        Redix.PubSub.subscribe(:redix_pubsub, @channel, self())
        Logger.info("[RedisSubscriber] 구독 시작: #{@channel}")
        {:ok, %{conn: conn}}
      {:error, reason} ->
        Logger.warning("[RedisSubscriber] Redis 연결 실패: #{inspect(reason)} — 재시도 예약")
        Process.send_after(self(), :retry_connect, 5_000)
        {:ok, %{conn: nil}}
    end
  end

  @impl true
  def handle_info({:redix_pubsub, _conn, _ref, :subscribed, %{channel: ch}}, state) do
    Logger.info("[RedisSubscriber] 구독 확인: #{ch}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:redix_pubsub, _conn, _ref, :message, %{channel: @channel, payload: payload}}, state) do
    case Jason.decode(payload) do
      {:ok, event} ->
        Logger.info("[RedisSubscriber] 이벤트 수신: #{inspect(event["event"])}")
        # Phoenix PubSub으로 브로드캐스트 → WebSocket 클라이언트에 실시간 전달
        Phoenix.PubSub.broadcast(HubElixir.PubSub, "system:lobby", {:broadcast, "redis_event", event})
      {:error, _} ->
        Logger.warning("[RedisSubscriber] JSON 파싱 실패: #{payload}")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(:retry_connect, _state) do
    case Redix.start_link("redis://localhost:6379", name: :redix_pubsub) do
      {:ok, conn} ->
        Redix.PubSub.subscribe(:redix_pubsub, @channel, self())
        Logger.info("[RedisSubscriber] 재연결 성공")
        {:noreply, %{conn: conn}}
      {:error, _} ->
        Process.send_after(self(), :retry_connect, 10_000)
        {:noreply, %{conn: nil}}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
