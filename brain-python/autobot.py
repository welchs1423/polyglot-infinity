# autobot.py
#
# Autonomous trading bot for the polyglot-infinity system.
#
# Operation:
#   1. Connects to the Go gateway WebSocket at ws://localhost:8080/ws.
#   2. Parses incoming JSON frames; extracts the "price" field from each.
#   3. Maintains a rolling window of the last SMA_WINDOW prices.
#   4. Computes the simple moving average (SMA) over that window.
#   5. Detects SMA crossover:
#        price crosses above SMA -> BUY signal
#        price crosses below SMA -> SELL signal
#   6. On a signal, POSTs an order to the Go gateway at /api/java/order,
#      which reverse-proxies the request to the Java Loom server (port 8010).
#
# Order endpoint:
#   POST http://localhost:8080/api/java/order?id=<uuid4>&type=BUY|SELL
#   The Java server inserts the order with initial status ORDERED.
#
# Reconnect policy:
#   Exponential back-off starting at RECONNECT_BASE_S, capped at
#   RECONNECT_CAP_S, resets to base on each successful connection.
#
# Duplicate-signal suppression:
#   ORDER_COOLDOWN_S enforces a minimum interval between consecutive orders
#   to avoid flooding when price oscillates around the SMA.

import asyncio
import json
import logging
import uuid
from collections import deque
from typing import Deque, Optional

import httpx
import websockets
import websockets.exceptions

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

GATEWAY_WS_URL   = "ws://localhost:8080/ws"
GATEWAY_HTTP_URL = "http://localhost:8080"
ORDER_PATH       = "/api/java/order"

# Number of price samples used for the SMA calculation.
SMA_WINDOW = 10

# Minimum elapsed seconds between consecutive order submissions.
# Prevents duplicate orders when price straddles the SMA across several ticks.
ORDER_COOLDOWN_S = 2.0

# WebSocket reconnect back-off parameters (seconds).
RECONNECT_BASE_S = 1.0
RECONNECT_CAP_S  = 30.0

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [autobot] %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# SMA utility
# ---------------------------------------------------------------------------

def compute_sma(prices: Deque[float]) -> Optional[float]:
    # Returns the arithmetic mean of all values in the deque.
    # Returns None when the deque contains fewer than SMA_WINDOW entries
    # because an incomplete window does not produce a reliable signal.
    if len(prices) < SMA_WINDOW:
        return None
    return sum(prices) / len(prices)

# ---------------------------------------------------------------------------
# Order placement
# ---------------------------------------------------------------------------

async def place_order(client: httpx.AsyncClient, side: str, price: float) -> None:
    # Submits a single market order to /api/java/order via the Go gateway.
    # side must be "BUY" or "SELL" (Java enum value).
    # A fresh UUID4 is used as the order ID on every call.
    order_id = str(uuid.uuid4())
    params = {"id": order_id, "type": side}
    try:
        resp = await client.post(
            f"{GATEWAY_HTTP_URL}{ORDER_PATH}",
            params=params,
            timeout=5.0,
        )
        resp.raise_for_status()
        log.info(
            "Order accepted: side=%s order_id=%s price=%.4f http=%d",
            side, order_id, price, resp.status_code,
        )
    except httpx.HTTPStatusError as exc:
        log.warning(
            "Order rejected by server: side=%s order_id=%s http=%d body=%s",
            side,
            order_id,
            exc.response.status_code,
            exc.response.text[:200],
        )
    except httpx.RequestError as exc:
        log.error(
            "Order request failed (network): side=%s order_id=%s error=%s",
            side, order_id, exc,
        )

# ---------------------------------------------------------------------------
# Main bot loop
# ---------------------------------------------------------------------------

async def run_bot() -> None:
    # prices: rolling window, deque enforces maxlen so the oldest sample is
    # discarded automatically when a new one is appended after the window is full.
    prices: Deque[float] = deque(maxlen=SMA_WINDOW)

    # prev_above tracks whether the price was above the SMA on the previous tick.
    # None means no prior comparable tick exists yet (first valid SMA reading).
    prev_above: Optional[bool] = None

    # Monotonic timestamp of the most recently submitted order (loop clock seconds).
    last_order_time: float = 0.0

    backoff = RECONNECT_BASE_S

    async with httpx.AsyncClient() as http_client:
        while True:
            try:
                async with websockets.connect(GATEWAY_WS_URL) as ws:
                    log.info("Connected to WebSocket: %s", GATEWAY_WS_URL)
                    backoff = RECONNECT_BASE_S  # reset back-off on successful connect

                    async for raw_frame in ws:
                        # Parse JSON frame.
                        try:
                            msg = json.loads(raw_frame)
                        except json.JSONDecodeError:
                            log.debug("Received non-JSON frame, skipping")
                            continue

                        # Extract price from the "price" field.
                        # The Go gateway broadcasts Redis "order-events" payloads
                        # published by the Java Loom server; trade-tick events
                        # carry a numeric "price" field representing the executed
                        # price of the matched order.
                        raw_price = msg.get("price")
                        if raw_price is None:
                            log.debug(
                                "Frame has no 'price' field, skipping. keys=%s",
                                list(msg.keys()),
                            )
                            continue

                        try:
                            price = float(raw_price)
                        except (TypeError, ValueError):
                            log.warning("Non-numeric price value: %r", raw_price)
                            continue

                        # Append to rolling window and attempt SMA computation.
                        prices.append(price)
                        sma = compute_sma(prices)

                        if sma is None:
                            # Window not yet full; accumulate without signalling.
                            log.debug(
                                "Window filling: %d/%d price=%.4f",
                                len(prices), SMA_WINDOW, price,
                            )
                            continue

                        log.debug("price=%.4f sma=%.4f", price, sma)

                        current_above = price > sma

                        # A crossover is detected when the current position
                        # relative to the SMA differs from the previous tick.
                        if prev_above is not None and current_above != prev_above:
                            now = asyncio.get_event_loop().time()
                            if now - last_order_time >= ORDER_COOLDOWN_S:
                                side = "BUY" if current_above else "SELL"
                                log.info(
                                    "Crossover signal: %s | price=%.4f sma=%.4f",
                                    side, price, sma,
                                )
                                await place_order(http_client, side, price)
                                last_order_time = now
                            else:
                                log.debug(
                                    "Signal suppressed by cooldown (%.2fs remaining)",
                                    ORDER_COOLDOWN_S - (asyncio.get_event_loop().time() - last_order_time),
                                )

                        prev_above = current_above

            except (
                websockets.exceptions.ConnectionClosedError,
                websockets.exceptions.ConnectionClosedOK,
                OSError,
            ) as exc:
                log.warning(
                    "WebSocket disconnected: %s – reconnecting in %.1fs",
                    exc, backoff,
                )
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2.0, RECONNECT_CAP_S)

            except Exception as exc:
                log.exception("Unexpected error in bot loop: %s", exc)
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2.0, RECONNECT_CAP_S)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    log.info(
        "Autobot starting: strategy=SMA-%d ws=%s order_cooldown=%.1fs",
        SMA_WINDOW, GATEWAY_WS_URL, ORDER_COOLDOWN_S,
    )
    asyncio.run(run_bot())


if __name__ == "__main__":
    main()
