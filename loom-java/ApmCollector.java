// loom-java/ApmCollector.java
// Asynchronous APM transaction metric collector for the Java Loom service.
//
// Design constraints:
//   - Producer path (record()) must never block a virtual thread executing
//     business logic.  ConcurrentLinkedQueue provides O(1) CAS-based offer().
//   - A single background virtual thread drains the queue and forwards batches
//     to the central APM server via HTTP POST so that I/O never touches the
//     request-serving virtual threads.
//   - If the queue exceeds MAX_QUEUE_SIZE, new events are silently discarded.
//     This is an explicit back-pressure policy: APM observability data is
//     lower-priority than order-processing throughput.
//   - APM server unavailability is fully non-fatal.  Every exception in the
//     drain loop is caught and swallowed; the business service remains healthy.
//
// Lifecycle:
//   Call ApmCollector.init(apmUrl) once at startup (idempotent).
//   Call ApmCollector.record(metric) on every transaction; the call returns
//   immediately without any synchronization overhead visible to the caller.

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicBoolean;

public class ApmCollector {

    // TransactionMetric captures the observable dimensions of a single request.
    //   correlationId : trace identifier injected or generated at the gateway
    //   service       : name of the originating service ("java-loom")
    //   endpoint      : request URI path ("/api/java/order")
    //   responseMs    : wall-clock time from first byte received to response sent
    //   queryMs       : time spent in JDBC operations during this request
    //   timestamp     : epoch milliseconds when the request completed
    public record TransactionMetric(
        String correlationId,
        String service,
        String endpoint,
        long   responseMs,
        long   queryMs,
        long   timestamp
    ) {}

    // Maximum number of metrics buffered before new events are dropped.
    // At 1200 TPS with 500 ms flush interval the maximum burst is ~600 events;
    // 10 000 provides ~16x headroom before loss begins.
    private static final int  MAX_QUEUE_SIZE    = 10_000;
    private static final int  BATCH_SIZE        = 200;
    private static final long DRAIN_INTERVAL_MS = 500L;

    // ConcurrentLinkedQueue uses the Michael-Scott non-blocking algorithm.
    // offer() is wait-free for producers.  poll() is lock-free for the single
    // consumer virtual thread.  No OS-level lock or condition variable is used.
    private static final ConcurrentLinkedQueue<TransactionMetric> queue =
        new ConcurrentLinkedQueue<>();

    // Guards against calling init() multiple times concurrently at startup.
    private static final AtomicBoolean started = new AtomicBoolean(false);

    // Resolved once in init(); subsequently read concurrently without locks
    // because String references are safely published via volatile semantics.
    private static volatile String apmUrl = "http://localhost:9009/ingest";

    // Dedicated HttpClient for the drain thread only.
    // connectTimeout is intentionally short: if the APM server is not
    // reachable within 2 s the batch is discarded and the drain loop
    // continues without delay.
    private static final HttpClient httpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(2))
        .build();

    // Initializes the collector.  Must be called before the first record().
    // Subsequent calls are ignored thanks to the AtomicBoolean gate.
    //   url — APM ingest endpoint, e.g. "http://apm-server:9009/ingest".
    //         Pass null or empty to keep the default (localhost).
    public static void init(String url) {
        if (url != null && !url.isEmpty()) {
            apmUrl = url;
        }
        if (started.compareAndSet(false, true)) {
            Thread.ofVirtual()
                  .name("apm-drain")
                  .start(ApmCollector::drainLoop);
        }
    }

    // Enqueues a metric for asynchronous forwarding.
    // Returns immediately; the caller is never blocked or parked.
    // Silently drops the metric when the queue is at capacity.
    public static void record(TransactionMetric m) {
        if (queue.size() >= MAX_QUEUE_SIZE) {
            return;
        }
        queue.offer(m);
    }

    // ── Background drain loop ─────────────────────────────────────────────
    // Runs in a single virtual thread created by init().
    // Sleeps DRAIN_INTERVAL_MS between flushes; wakes up early on interrupt
    // to perform a final flush before the thread exits.
    private static void drainLoop() {
        while (true) {
            try {
                Thread.sleep(DRAIN_INTERVAL_MS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                flush();   // Final drain before shutdown.
                return;
            }
            flush();
        }
    }

    // Drains up to BATCH_SIZE metrics from the queue and POSTs them to
    // the APM server.  Any remaining items are left for the next flush cycle.
    // All I/O exceptions are caught; the batch is discarded on failure.
    private static void flush() {
        if (queue.isEmpty()) {
            return;
        }
        List<TransactionMetric> batch = new ArrayList<>(BATCH_SIZE);
        TransactionMetric m;
        while (batch.size() < BATCH_SIZE && (m = queue.poll()) != null) {
            batch.add(m);
        }
        if (batch.isEmpty()) {
            return;
        }
        try {
            String body = toJsonArray(batch);
            HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(apmUrl))
                .timeout(Duration.ofSeconds(2))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();
            // send() is called on the background virtual thread; blocking here
            // is acceptable and does not consume any OS thread during socket I/O.
            httpClient.send(req, HttpResponse.BodyHandlers.discarding());
        } catch (Exception e) {
            // APM server unreachable or timeout: discard batch silently.
        }
    }

    // ── JSON serialization ────────────────────────────────────────────────
    // Hand-rolled to avoid adding a Jackson/Gson dependency.
    // Produces a JSON array: [{"correlationId":"...","service":"..."},...].
    private static String toJsonArray(List<TransactionMetric> batch) {
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < batch.size(); i++) {
            if (i > 0) sb.append(",");
            TransactionMetric t = batch.get(i);
            sb.append("{")
              .append("\"correlationId\":\"").append(esc(t.correlationId())).append("\",")
              .append("\"service\":\"").append(esc(t.service())).append("\",")
              .append("\"endpoint\":\"").append(esc(t.endpoint())).append("\",")
              .append("\"responseMs\":").append(t.responseMs()).append(",")
              .append("\"queryMs\":").append(t.queryMs()).append(",")
              .append("\"timestamp\":").append(t.timestamp())
              .append("}");
        }
        return sb.append("]").toString();
    }

    private static String esc(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
