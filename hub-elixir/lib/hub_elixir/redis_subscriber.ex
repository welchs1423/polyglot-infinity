defmodule HubElixir.RedisSubscriber do
  @moduledoc """
  Redis Pub/Sub subscriber for the `polyglot:events` channel.

  Maintains a dedicated Redix.PubSub connection (separate from any command
  connection) and forwards received events to all WebSocket clients through
  two parallel paths:
    1. Phoenix.PubSub -> Phoenix Channel clients (port 4000)
    2. HubElixir.WebSocket.Broadcaster -> Cowboy WebSocket clients (port 4001)

  On Redis connection failure the process schedules a retry after 5 s and
  doubles the retry interval on each consecutive failure up to 30 s.
  """
  use GenServer
  require Logger

  @channel        "polyglot:events"
  @redis_url      "redis://localhost:6379"
  @retry_base_ms  5_000
  @retry_max_ms   30_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_) do
    state = connect(%{pubsub: nil, retry_ms: @retry_base_ms})
    {:ok, state}
  end

  # Successful subscription confirmation from Redix.PubSub.
  @impl true
  def handle_info(
        {:redix_pubsub, _conn, _ref, :subscribed, %{channel: ch}},
        state
      ) do
    Logger.info("[RedisSubscriber] subscription confirmed: #{ch}")
    {:noreply, %{state | retry_ms: @retry_base_ms}}
  end

  # Incoming message on the subscribed channel.
  @impl true
  def handle_info(
        {:redix_pubsub, _conn, _ref, :message, %{channel: @channel, payload: payload}},
        state
      ) do
    case Jason.decode(payload) do
      {:ok, event} ->
        Logger.info("[RedisSubscriber] event received: #{inspect(event["event"])}")

        # Path 1: Phoenix Channel clients via Phoenix.PubSub.
        Phoenix.PubSub.broadcast(
          HubElixir.PubSub,
          "system:lobby",
          {:broadcast, "redis_event", event}
        )

        # Path 2: Cowboy WebSocket clients via Registry broadcast.
        HubElixir.WebSocket.Broadcaster.broadcast("redis_event", event)

      {:error, _reason} ->
        Logger.warning("[RedisSubscriber] JSON parse failure for payload: #{payload}")
    end

    {:noreply, state}
  end

  # Redix.PubSub reports that the connection was closed (network drop, etc.).
  @impl true
  def handle_info(
        {:redix_pubsub, _conn, _ref, :disconnected, %{error: error}},
        state
      ) do
    Logger.warning("[RedisSubscriber] Redis connection lost: #{inspect(error)}")
    Process.send_after(self(), :retry_connect, state.retry_ms)
    {:noreply, %{state | pubsub: nil}}
  end

  # Scheduled reconnection attempt after a previous failure.
  @impl true
  def handle_info(:retry_connect, state) do
    new_state = connect(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Starts a Redix.PubSub connection and subscribes to @channel.
  # Returns updated state with :pubsub and :retry_ms fields.
  defp connect(state) do
    case Redix.PubSub.start_link(@redis_url, name: :redix_pubsub) do
      {:ok, pubsub} ->
        {:ok, _ref} = Redix.PubSub.subscribe(pubsub, @channel, self())
        Logger.info("[RedisSubscriber] connected, subscribing to #{@channel}")
        %{state | pubsub: pubsub, retry_ms: @retry_base_ms}

      {:error, {:already_started, pubsub}} ->
        # Process already named :redix_pubsub — reuse and resubscribe.
        {:ok, _ref} = Redix.PubSub.subscribe(pubsub, @channel, self())
        Logger.info("[RedisSubscriber] reusing existing connection, resubscribed to #{@channel}")
        %{state | pubsub: pubsub, retry_ms: @retry_base_ms}

      {:error, reason} ->
        next_ms = min(state.retry_ms * 2, @retry_max_ms)
        Logger.warning("[RedisSubscriber] connection failed: #{inspect(reason)}, retry in #{state.retry_ms} ms")
        Process.send_after(self(), :retry_connect, state.retry_ms)
        %{state | pubsub: nil, retry_ms: next_ms}
    end
  end
end
