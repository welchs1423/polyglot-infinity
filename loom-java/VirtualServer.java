// loom-java/VirtualServer.java
// Java 21 Virtual Threads (Project Loom) — PostgreSQL-backed order server.
// Port: 8010
//
// All order state is persisted exclusively in PostgreSQL via HikariCP + pure JDBC.
// In-memory order caching is absent; every read and write is a database round-trip.
// Virtual threads (Executors.newVirtualThreadPerTaskExecutor()) park during JDBC
// socket I/O without consuming OS threads, enabling high concurrency with a small
// number of physical connections in the HikariCP pool.
//
// Concurrency:
//   Concurrent PUT /api/java/order transitions on the same order ID are serialized
//   at the database level: applyTransition() issues SELECT ... FOR UPDATE inside
//   an explicit transaction before applying the state-machine check and UPDATE.
//
// Saga Pattern (POST /api/java/order):
//   Phase 1 — local commit: INSERT order with status PENDING.  Committed immediately.
//   Phase 2 — remote call: SagaCoordinator virtual thread sends HTTP GET to the Go
//     gateway, which proxies /api/clojure/transfer to the Clojure STM ledger (:8009).
//   On HTTP 2xx: UPDATE orders SET status = 'COMPLETED'.
//   On timeout or non-2xx: compensating transaction sets status = 'CANCELED'.
//
// Required environment variables:
//   DB_URL       jdbc:postgresql://db-postgres:5432/loom_db
//   DB_USER      dev
//   DB_PASSWORD  polyglot
//
// Optional environment variables:
//   REDIS_HOST   Redis hostname          (default: localhost)
//   REDIS_PORT   Redis port              (default: 6379)
//   GATEWAY_URL  Go hub base URL         (default: http://server-go:8080)
//   APM_URL      APM ingest endpoint     (default: http://localhost:9009/ingest)
//
// Endpoints:
//   GET  /health
//   GET  /api/java/status
//   POST /api/java/order?id=<id>&type=BUY|SELL[&from=ACC-001&to=ACC-002&amount=100.0]
//        Inserts order as PENDING; Saga runs asynchronously; returns 202 Accepted.
//   PUT  /api/java/order?id=<orderId>&event=<evt>     — UPDATE state transition
//   GET  /api/java/order?id=<orderId>                 — SELECT single row
//   GET  /api/java/orders                             — SELECT all rows
//   GET  /api/java/benchmark?n=<N>&mode=virtual|platform|both

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPool;
import redis.clients.jedis.JedisPoolConfig;

import java.io.*;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.sql.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;

public class VirtualServer {

    // ── State machine ─────────────────────────────────────────────────────
    // Transition rules:
    //   PENDING     -> COMPLETED | CANCELED  (Saga coordinator only)
    //   ORDERED     -> PAID | CANCELED
    //   PAID        -> PROCESSING | CANCELED
    //   PROCESSING  -> SHIPPED
    //   SHIPPED     -> DELIVERED
    //   CANCELED    -> REFUNDED
    //   COMPLETED   -> (terminal; no outgoing transitions)
    enum OrderStatus {
        PENDING, ORDERED, PAID, PROCESSING, SHIPPED, DELIVERED, COMPLETED, CANCELED, REFUNDED;

        boolean canTransitionTo(OrderStatus next) {
            return switch (this) {
                case PENDING    -> next == COMPLETED  || next == CANCELED;
                case ORDERED    -> next == PAID       || next == CANCELED;
                case PAID       -> next == PROCESSING || next == CANCELED;
                case PROCESSING -> next == SHIPPED;
                case SHIPPED    -> next == DELIVERED;
                case CANCELED   -> next == REFUNDED;
                default         -> false;
            };
        }
    }

    enum OrderEvent {
        PAY, PROCESS, SHIP, DELIVER, CANCEL, REFUND, COMPLETE;

        OrderStatus targetStatus() {
            return switch (this) {
                case PAY      -> OrderStatus.PAID;
                case PROCESS  -> OrderStatus.PROCESSING;
                case SHIP     -> OrderStatus.SHIPPED;
                case DELIVER  -> OrderStatus.DELIVERED;
                case CANCEL   -> OrderStatus.CANCELED;
                case REFUND   -> OrderStatus.REFUNDED;
                case COMPLETE -> OrderStatus.COMPLETED;
            };
        }
    }

    // ── DB Persistence (HikariCP + pure JDBC) ────────────────────────────
    // DbStore is the sole state store. No in-memory caching is performed.
    // Every read and write is a JDBC round-trip to PostgreSQL.
    // HikariCP maintains a bounded pool of physical connections; virtual threads
    // block cheaply when the pool is exhausted (socket park, no OS thread consumed).
    static class DbStore {
        private final HikariDataSource ds;

        DbStore(String jdbcUrl, String user, String password) {
            HikariConfig cfg = new HikariConfig();
            cfg.setJdbcUrl(jdbcUrl);
            cfg.setUsername(user);
            cfg.setPassword(password);
            cfg.setMaximumPoolSize(20);
            cfg.setMinimumIdle(2);
            cfg.setConnectionTimeout(3_000);
            cfg.setIdleTimeout(60_000);
            cfg.setMaxLifetime(1_800_000);
            cfg.setAutoCommit(true);
            ds = new HikariDataSource(cfg);
        }

        // Creates the orders table if it does not exist.
        // Called once at startup; throws SQLException on DDL failure.
        void initSchema() throws SQLException {
            String ddl = """
                CREATE TABLE IF NOT EXISTS orders (
                    id         VARCHAR(255) PRIMARY KEY,
                    type       VARCHAR(8)   NOT NULL DEFAULT 'BUY',
                    status     VARCHAR(32)  NOT NULL,
                    created_at BIGINT       NOT NULL,
                    updated_at BIGINT       NOT NULL
                )
                """;
            try (Connection c = ds.getConnection();
                 PreparedStatement ps = c.prepareStatement(ddl)) {
                ps.executeUpdate();
            }
        }

        // Inserts a new order with status PENDING for Saga orchestration.
        // Returns the inserted row as a Map, or null if the id already exists
        // (ON CONFLICT DO NOTHING returns zero rows via RETURNING).
        Map<String, Object> insertOrderPending(String id, String type, long now) throws SQLException {
            String sql = """
                INSERT INTO orders (id, type, status, created_at, updated_at)
                VALUES (?, ?, 'PENDING', ?, ?)
                ON CONFLICT (id) DO NOTHING
                RETURNING id, type, status, created_at, updated_at
                """;
            try (Connection c = ds.getConnection();
                 PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setString(1, id);
                ps.setString(2, type);
                ps.setLong(3, now);
                ps.setLong(4, now);
                try (ResultSet rs = ps.executeQuery()) {
                    return rs.next() ? rowToMap(rs) : null;
                }
            }
        }

        // Updates the status of an order unconditionally (no state-machine check).
        // Used exclusively by SagaCoordinator: PENDING -> COMPLETED or PENDING -> CANCELED.
        // applyTransition() enforces the state machine for all normal event-driven transitions.
        void updateOrderStatus(String id, String status) throws SQLException {
            try (Connection c = ds.getConnection();
                 PreparedStatement ps = c.prepareStatement(
                     "UPDATE orders SET status = ?, updated_at = ? WHERE id = ?")) {
                ps.setString(1, status);
                ps.setLong(2, System.currentTimeMillis());
                ps.setString(3, id);
                ps.executeUpdate();
            }
        }

        // Inserts a new BUY or SELL order with initial status ORDERED.
        // Returns the inserted row as a Map, or null if the id already exists
        // (ON CONFLICT DO NOTHING returns zero rows via RETURNING).
        Map<String, Object> insertOrder(String id, String type, long now) throws SQLException {
            String sql = """
                INSERT INTO orders (id, type, status, created_at, updated_at)
                VALUES (?, ?, 'ORDERED', ?, ?)
                ON CONFLICT (id) DO NOTHING
                RETURNING id, type, status, created_at, updated_at
                """;
            try (Connection c = ds.getConnection();
                 PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setString(1, id);
                ps.setString(2, type);
                ps.setLong(3, now);
                ps.setLong(4, now);
                try (ResultSet rs = ps.executeQuery()) {
                    return rs.next() ? rowToMap(rs) : null;
                }
            }
        }

        // Applies an order event within a serializable transaction.
        // SELECT ... FOR UPDATE serializes concurrent transitions on the same row.
        // Returns one of:
        //   "OK:<prevStatus>:<newStatus>"     — transition applied
        //   "ORDER_NOT_FOUND"                 — no row with given id
        //   "INVALID_TRANSITION:<from>:<to>"  — state machine rejected the event
        String applyTransition(String id, OrderEvent event) throws SQLException {
            try (Connection c = ds.getConnection()) {
                c.setAutoCommit(false);
                try {
                    OrderStatus current;
                    try (PreparedStatement sel = c.prepareStatement(
                            "SELECT status FROM orders WHERE id = ? FOR UPDATE")) {
                        sel.setString(1, id);
                        try (ResultSet rs = sel.executeQuery()) {
                            if (!rs.next()) {
                                c.rollback();
                                return "ORDER_NOT_FOUND";
                            }
                            current = OrderStatus.valueOf(rs.getString("status"));
                        }
                    }
                    OrderStatus next = event.targetStatus();
                    if (!current.canTransitionTo(next)) {
                        c.rollback();
                        return "INVALID_TRANSITION:" + current + "->" + next;
                    }
                    try (PreparedStatement upd = c.prepareStatement(
                            "UPDATE orders SET status = ?, updated_at = ? WHERE id = ?")) {
                        upd.setString(1, next.name());
                        upd.setLong(2, System.currentTimeMillis());
                        upd.setString(3, id);
                        upd.executeUpdate();
                    }
                    c.commit();
                    return "OK:" + current.name() + ":" + next.name();
                } catch (SQLException e) {
                    c.rollback();
                    throw e;
                } finally {
                    c.setAutoCommit(true);
                }
            }
        }

        // Returns a single order row as a Map, or null if not found.
        Map<String, Object> findOrder(String id) throws SQLException {
            try (Connection c = ds.getConnection();
                 PreparedStatement ps = c.prepareStatement(
                     "SELECT id, type, status, created_at, updated_at FROM orders WHERE id = ?")) {
                ps.setString(1, id);
                try (ResultSet rs = ps.executeQuery()) {
                    return rs.next() ? rowToMap(rs) : null;
                }
            }
        }

        // Returns all orders sorted by creation time descending.
        List<Map<String, Object>> findAllOrders() throws SQLException {
            String sql = "SELECT id, type, status, created_at, updated_at " +
                         "FROM orders ORDER BY created_at DESC";
            List<Map<String, Object>> list = new ArrayList<>();
            try (Connection c = ds.getConnection();
                 PreparedStatement ps = c.prepareStatement(sql);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rowToMap(rs));
            }
            return list;
        }

        // Returns the total number of rows in the orders table.
        int countOrders() throws SQLException {
            try (Connection c = ds.getConnection();
                 PreparedStatement ps = c.prepareStatement("SELECT COUNT(*) FROM orders");
                 ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt(1) : 0;
            }
        }

        // Deletes benchmark rows whose id starts with the given prefix.
        // Used by the benchmark endpoint to clean up after each run.
        void deleteBenchmarkOrders(String prefix) throws SQLException {
            try (Connection c = ds.getConnection();
                 PreparedStatement ps = c.prepareStatement(
                     "DELETE FROM orders WHERE id LIKE ?")) {
                ps.setString(1, prefix + "%");
                ps.executeUpdate();
            }
        }

        private Map<String, Object> rowToMap(ResultSet rs) throws SQLException {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id",         rs.getString("id"));
            m.put("type",       rs.getString("type"));
            m.put("status",     rs.getString("status"));
            m.put("created_at", rs.getLong("created_at"));
            m.put("updated_at", rs.getLong("updated_at"));
            return m;
        }

        boolean isRunning() {
            return ds != null && !ds.isClosed();
        }

        void close() {
            if (ds != null) ds.close();
        }
    }

    static volatile DbStore dbStore;

    // ── Saga Pattern ──────────────────────────────────────────────────────
    // SagaCoordinator implements a two-phase compensating transaction.
    //
    // Pre-condition: the order row exists in DB with status PENDING.
    //   Phase 1 is committed by the HTTP handler before executeSaga() is called.
    //
    // Phase 2 — remote call:
    //   HTTP GET to Go gateway -> /api/clojure/transfer?from=...&to=...&amount=...
    //   The Go gateway proxies /api/clojure/* to the Clojure STM ledger (:8009).
    //   Per-request timeout: 10 seconds.  HttpClient connect timeout: 5 seconds.
    //
    // On HTTP 2xx:
    //   UPDATE orders SET status = 'COMPLETED', updated_at = <now> WHERE id = <orderId>
    //   Publish SAGA_COMPLETE event to Redis.
    //
    // On timeout or non-2xx:
    //   Compensating transaction:
    //   UPDATE orders SET status = 'CANCELED', updated_at = <now> WHERE id = <orderId>
    //   Publish SAGA_COMPENSATE event to Redis.
    //
    // If the compensating UPDATE itself fails (e.g. DB unreachable), the error is
    // written to stderr and the order remains in PENDING state for external reconciliation.
    static class SagaCoordinator {

        // Single shared HttpClient instance.  HttpClient is thread-safe; internally
        // reuses connections so that each saga virtual thread does not incur a full
        // TCP + TLS handshake for every call.
        private static final HttpClient HTTP_CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

        // Resolved once at class-loading time.  The Go gateway proxies
        // /api/clojure/* to the Clojure STM ledger (:8009).
        private static final String GATEWAY_URL =
            System.getenv().getOrDefault("GATEWAY_URL", "http://server-go:8080");

        // Spawns a background virtual thread to execute the saga.
        // Returns immediately; the calling HTTP handler is not blocked.
        static void executeSaga(String orderId, String orderType,
                                String fromAccount, String toAccount, double amount,
                                String correlationId) {
            Thread.ofVirtual()
                  .name("saga-" + orderId)
                  .start(() -> runSaga(orderId, orderType, fromAccount, toAccount,
                                       amount, correlationId));
        }

        private static void runSaga(String orderId, String orderType,
                                    String fromAccount, String toAccount, double amount,
                                    String correlationId) {
            boolean success = false;
            try {
                // The Clojure STM ledger transfer endpoint accepts query parameters.
                // The Go gateway proxies /api/clojure/ to ledger-clojure:8009.
                String url = GATEWAY_URL
                    + "/api/clojure/transfer"
                    + "?from="   + fromAccount
                    + "&to="     + toAccount
                    + "&amount=" + amount;

                HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(10))
                    .header("X-Correlation-Id", correlationId)
                    .header("X-Order-Id",       orderId)
                    .GET()
                    .build();

                HttpResponse<String> resp =
                    HTTP_CLIENT.send(req, HttpResponse.BodyHandlers.ofString());
                int sc = resp.statusCode();

                if (sc >= 200 && sc < 300) {
                    success = true;
                } else {
                    System.err.println("[Saga] Remote ledger returned HTTP " + sc
                        + " for order " + orderId + ". Compensating.");
                }
            } catch (java.net.http.HttpTimeoutException e) {
                System.err.println("[Saga] Payment request timed out for order "
                    + orderId + ". Compensating.");
            } catch (Exception e) {
                System.err.println("[Saga] Payment request failed for order "
                    + orderId + ": " + e.getMessage() + ". Compensating.");
            }

            // Apply the terminal status update regardless of which branch was taken.
            String finalStatus = success ? "COMPLETED" : "CANCELED";
            String sagaEvent   = success ? "SAGA_COMPLETE" : "SAGA_COMPENSATE";
            try {
                dbStore.updateOrderStatus(orderId, finalStatus);
                publishOrderEvent(orderId, orderType, "PENDING", finalStatus, sagaEvent);
            } catch (SQLException e) {
                System.err.println("[Saga] DB update to " + finalStatus
                    + " failed for order " + orderId + ": " + e.getMessage());
            }
        }
    }

    // ── Redis Pub/Sub ────────────────────────────────────────────────────
    // JedisPool is thread-safe. getResource() borrows a Jedis instance; the
    // try-with-resources block returns it to the pool after publish().
    // Redis unavailability is non-fatal: errors are written to stderr only.
    static volatile JedisPool jedisPool;
    static final String REDIS_CHANNEL = "order-events";

    static void publishOrderEvent(String orderId, String type,
                                   String prevStatus, String newStatus, String eventName) {
        JedisPool pool = jedisPool;
        if (pool == null || pool.isClosed()) return;
        String payload = "{" +
            "\"order_id\":\"" + orderId      + "\"," +
            "\"type\":\""     + type         + "\"," +
            "\"event\":\""    + eventName    + "\"," +
            "\"prev_status\":\"" + prevStatus + "\"," +
            "\"new_status\":\"" + newStatus   + "\"," +
            "\"channel\":\""  + REDIS_CHANNEL + "\"," +
            "\"timestamp\":"  + System.currentTimeMillis() +
        "}";
        try (Jedis jedis = pool.getResource()) {
            jedis.publish(REDIS_CHANNEL, payload);
        } catch (Exception e) {
            System.err.println("[Redis publish error] " + e.getMessage());
        }
    }

    // ── Benchmark ───────────────────────────────────────────────────────
    // Measures INSERT + PAY transition throughput for virtual vs platform threads.
    // All operations are real JDBC round-trips; benchmark rows are deleted after
    // each run to avoid polluting the orders table.
    static Map<String, Object> benchmark(int n, String mode) throws Exception {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("tasks", n);
        result.put("mode",  mode);
        if (mode.equals("platform") || mode.equals("both")) {
            result.put("platform_ms", runBenchmarkWith(n, false));
        }
        if (mode.equals("virtual") || mode.equals("both")) {
            result.put("virtual_ms", runBenchmarkWith(n, true));
        }
        if (mode.equals("both")) {
            long p = (long) result.get("platform_ms");
            long v = (long) result.get("virtual_ms");
            result.put("speedup", String.format("%.2fx", (double) p / Math.max(v, 1)));
            result.put("winner", v <= p ? "virtual_thread" : "platform_thread");
        }
        result.put("platform_pool_capped_at", 200);
        result.put("virtual_pool_unbounded",  true);
        result.put("note",
            "Each task: INSERT BUY order + PAY transition via JDBC PreparedStatement. " +
            "Virtual threads yield the OS thread during JDBC socket I/O. " +
            "Platform threads block the OS thread for the same duration.");
        return result;
    }

    static long runBenchmarkWith(int n, boolean virtual) throws Exception {
        String prefix = (virtual ? "vt" : "pt") + "-bench-" + System.nanoTime() + "-";
        List<String> ids = new ArrayList<>(n);
        for (int i = 0; i < n; i++) ids.add(prefix + i);

        CountDownLatch latch = new CountDownLatch(n);
        long t0 = System.nanoTime();

        ExecutorService exec = virtual
            ? Executors.newVirtualThreadPerTaskExecutor()
            : Executors.newFixedThreadPool(200);

        try {
            for (String id : ids) {
                exec.submit(() -> {
                    try {
                        dbStore.insertOrder(id, "BUY", System.currentTimeMillis());
                        dbStore.applyTransition(id, OrderEvent.PAY);
                    } catch (Exception e) {
                        System.err.println("[bench error] " + e.getMessage());
                    } finally {
                        latch.countDown();
                    }
                });
            }
            latch.await(120, TimeUnit.SECONDS);
        } finally {
            exec.shutdown();
            dbStore.deleteBenchmarkOrders(prefix);
        }

        return (System.nanoTime() - t0) / 1_000_000;
    }

    // ── JSON serialization ───────────────────────────────────────────────
    // Hand-rolled serializer avoids a dependency on Jackson or Gson.
    // Handles Map, List, String, Boolean, null, and numbers (via toString()).
    @SuppressWarnings("unchecked")
    static String toJson(Object v) {
        if (v instanceof Map<?,?> m) {
            var sb = new StringBuilder("{");
            boolean first = true;
            for (var e : ((Map<String, Object>) m).entrySet()) {
                if (!first) sb.append(",");
                sb.append("\"").append(e.getKey()).append("\":").append(toJson(e.getValue()));
                first = false;
            }
            return sb.append("}").toString();
        }
        if (v instanceof List<?> list) {
            var sb = new StringBuilder("[");
            for (int i = 0; i < list.size(); i++) {
                if (i > 0) sb.append(",");
                sb.append(toJson(list.get(i)));
            }
            return sb.append("]").toString();
        }
        if (v instanceof String s)  return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
        if (v instanceof Boolean b) return b.toString();
        if (v == null)              return "null";
        return v.toString();
    }

    // ── HTTP utilities ───────────────────────────────────────────────────
    static void respond(HttpExchange ex, int status, String body) throws IOException {
        byte[] bytes = body.getBytes("UTF-8");
        ex.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        ex.getResponseHeaders().set("Access-Control-Allow-Origin", "*");
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = ex.getResponseBody()) { os.write(bytes); }
    }

    static Map<String, String> parseQuery(String qs) {
        Map<String, String> m = new HashMap<>();
        if (qs == null || qs.isEmpty()) return m;
        for (String pair : qs.split("&")) {
            String[] kv = pair.split("=", 2);
            if (kv.length == 2) m.put(kv[0], kv[1]);
        }
        return m;
    }

    // ── main ─────────────────────────────────────────────────────────────
    public static void main(String[] args) throws Exception {
        int port = 8010;

        // DB_URL is required. The server exits immediately if it is absent,
        // because there is no in-memory fallback for order persistence.
        String dbUrl  = System.getenv("DB_URL");
        String dbUser = System.getenv().getOrDefault("DB_USER", "dev");
        String dbPass = System.getenv().getOrDefault("DB_PASSWORD", "polyglot");
        if (dbUrl == null || dbUrl.isEmpty()) {
            System.err.println("[FATAL] DB_URL is not set. PostgreSQL is required.");
            System.exit(1);
        }
        dbStore = new DbStore(dbUrl, dbUser, dbPass);
        dbStore.initSchema();
        System.out.println("[DB] HikariCP pool initialized -> " + dbUrl);

        // Redis pub/sub is optional. Failure to connect disables event publishing
        // but does not affect order processing.
        String redisHost = System.getenv().getOrDefault("REDIS_HOST", "localhost");
        int    redisPort = Integer.parseInt(
            System.getenv().getOrDefault("REDIS_PORT", "6379"));
        try {
            JedisPoolConfig poolCfg = new JedisPoolConfig();
            poolCfg.setMaxTotal(16);
            poolCfg.setMaxIdle(4);
            poolCfg.setMinIdle(1);
            poolCfg.setTestOnBorrow(false);
            jedisPool = new JedisPool(poolCfg, redisHost, redisPort, 2_000);
            System.out.println("[Redis] JedisPool connected -> " + redisHost + ":" + redisPort);
        } catch (Exception e) {
            System.err.println("[Redis] JedisPool init failed (pub/sub disabled): " + e.getMessage());
        }

        // APM collector: resolves APM_URL from environment, falls back to localhost.
        // init() is idempotent; the background drain virtual thread is started once.
        ApmCollector.init(System.getenv("APM_URL"));
        System.out.println("[APM] ApmCollector initialized");

        Runtime.getRuntime().addShutdownHook(Thread.ofVirtual().unstarted(() -> {
            if (dbStore != null) dbStore.close();
        }));

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 256);

        // Each HTTP request is dispatched to a new virtual thread.
        // JDBC calls inside handlers block the virtual thread at the socket level;
        // the underlying OS thread is released and reused for other virtual threads.
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());

        server.createContext("/", ex -> {
            // APM: record wall-clock start time and resolve/generate correlation ID.
            // correlationId is propagated from the upstream gateway (Go Hub) via the
            // X-Correlation-Id header; if absent, a new UUID v4 is generated so that
            // requests entering the service directly are also traceable.
            long   t0 = System.currentTimeMillis();
            String incomingCid = ex.getRequestHeaders().getFirst("X-Correlation-Id");
            final String correlationId = (incomingCid != null && !incomingCid.isEmpty())
                ? incomingCid
                : UUID.randomUUID().toString();
            ex.getResponseHeaders().set("X-Correlation-Id", correlationId);

            String method = ex.getRequestMethod();
            String path   = ex.getRequestURI().getPath();
            Map<String, String> params = parseQuery(ex.getRequestURI().getQuery());

            // queryMs captures the JDBC execution time for the primary DB operation
            // in this request.  Updated in-place by each DB-calling branch.
            // long[] is used because lambdas require effectively-final references.
            long[] queryMs = {0L};

            try {
                // GET /health
                if (path.equals("/health")) {
                    respond(ex, 200, "{\"status\":\"ok\",\"lang\":\"java\",\"port\":8010}");
                    return;
                }

                // GET /api/java/status
                if (path.equals("/api/java/status")) {
                    int orderCount = dbStore.countOrders();
                    Map<String, Object> status = new LinkedHashMap<>();
                    status.put("lang",      "java");
                    status.put("version",   System.getProperty("java.version"));
                    status.put("port",      8010);
                    status.put("paradigm",  "virtual-threads");
                    status.put("feature",   "Project Loom — Executors.newVirtualThreadPerTaskExecutor()");
                    status.put("jvm",       System.getProperty("java.vm.name"));
                    status.put("cpu_cores", Runtime.getRuntime().availableProcessors());
                    status.put("orders",    orderCount);
                    status.put("db_url",    System.getenv().getOrDefault("DB_URL", "not configured"));
                    respond(ex, 200, toJson(status));
                    return;
                }

                // POST /api/java/order?id=<id>&type=BUY|SELL[&from=ACC-001&to=ACC-002&amount=100.0]
                // Saga Phase 1: INSERT order with status PENDING (committed immediately).
                // Saga Phase 2: SagaCoordinator virtual thread calls Go gateway ->
                //   Clojure STM ledger.  On 2xx: COMPLETED.  On timeout/non-2xx: CANCELED.
                // Returns 202 Accepted with the PENDING row; final status is set asynchronously.
                if (path.equals("/api/java/order") && method.equals("POST")) {
                    String id   = params.get("id");
                    String type = params.getOrDefault("type", "BUY").toUpperCase();
                    if (id == null || id.isEmpty()) {
                        respond(ex, 400, "{\"error\":\"id parameter required\"}");
                        return;
                    }
                    if (!type.equals("BUY") && !type.equals("SELL")) {
                        respond(ex, 400, "{\"error\":\"type must be BUY or SELL\"}");
                        return;
                    }
                    String fromAcct = params.getOrDefault("from", "ACC-001");
                    String toAcct   = params.getOrDefault("to",   "ACC-002");
                    double amount;
                    try {
                        amount = Double.parseDouble(params.getOrDefault("amount", "100.0"));
                        if (amount <= 0) throw new NumberFormatException("non-positive");
                    } catch (NumberFormatException e) {
                        respond(ex, 400, "{\"error\":\"amount must be a positive number\"}");
                        return;
                    }
                    long dbStart = System.currentTimeMillis();
                    Map<String, Object> row =
                        dbStore.insertOrderPending(id, type, System.currentTimeMillis());
                    queryMs[0] = System.currentTimeMillis() - dbStart;
                    if (row == null) {
                        respond(ex, 409, "{\"error\":\"order already exists\",\"id\":\"" + id + "\"}");
                        return;
                    }
                    // 202 Accepted: PENDING row is durable in DB.
                    // SagaCoordinator will update the row to COMPLETED or CANCELED
                    // asynchronously once the remote ledger call resolves.
                    respond(ex, 202, toJson(row));
                    final String fId = id, fType = type, fFrom = fromAcct,
                                 fTo = toAcct, fCid = correlationId;
                    final double fAmount = amount;
                    Thread.ofVirtual().start(() ->
                        publishOrderEvent(fId, fType, "", "PENDING", "INSERT"));
                    SagaCoordinator.executeSaga(fId, fType, fFrom, fTo, fAmount, fCid);
                    return;
                }

                // PUT /api/java/order?id=<orderId>&event=<evt>
                // Applies a state transition inside a DB transaction (SELECT FOR UPDATE).
                // On success, publishes the event to Redis asynchronously.
                if (path.equals("/api/java/order") && method.equals("PUT")) {
                    String id  = params.get("id");
                    String evt = params.get("event");
                    if (id == null || evt == null) {
                        respond(ex, 400, "{\"error\":\"id and event parameters required\"}");
                        return;
                    }
                    OrderEvent event;
                    try {
                        event = OrderEvent.valueOf(evt.toUpperCase());
                    } catch (IllegalArgumentException e) {
                        respond(ex, 400, "{\"error\":\"unknown event: " + evt + "\"}");
                        return;
                    }
                    long dbStart = System.currentTimeMillis();
                    String r = dbStore.applyTransition(id, event);
                    queryMs[0] = System.currentTimeMillis() - dbStart;
                    if (r.startsWith("OK:")) {
                        String[] parts      = r.split(":", 3);
                        String   prevStatus = parts[1];
                        String   newStatus  = parts[2];
                        Map<String, Object> updated = dbStore.findOrder(id);
                        respond(ex, 200, toJson(updated));
                        // Publish to Redis after the HTTP response is committed.
                        // Fire-and-forget in a new virtual thread to avoid blocking the caller.
                        if (updated != null) {
                            final String orderType = (String) updated.get("type");
                            Thread.ofVirtual().start(() ->
                                publishOrderEvent(id, orderType, prevStatus, newStatus, evt));
                        }
                    } else if (r.equals("ORDER_NOT_FOUND")) {
                        respond(ex, 404, "{\"error\":\"ORDER_NOT_FOUND\",\"id\":\"" + id + "\"}");
                    } else {
                        respond(ex, 400, "{\"error\":\"" + r + "\"}");
                    }
                    return;
                }

                // GET /api/java/order?id=<orderId>
                if (path.equals("/api/java/order") && method.equals("GET")) {
                    String id = params.get("id");
                    if (id == null) {
                        respond(ex, 400, "{\"error\":\"id parameter required\"}");
                        return;
                    }
                    long dbStart = System.currentTimeMillis();
                    Map<String, Object> row = dbStore.findOrder(id);
                    queryMs[0] = System.currentTimeMillis() - dbStart;
                    if (row == null) {
                        respond(ex, 404, "{\"error\":\"order not found\",\"id\":\"" + id + "\"}");
                        return;
                    }
                    respond(ex, 200, toJson(row));
                    return;
                }

                // GET /api/java/orders
                if (path.equals("/api/java/orders")) {
                    long dbStart = System.currentTimeMillis();
                    List<Map<String, Object>> list = dbStore.findAllOrders();
                    queryMs[0] = System.currentTimeMillis() - dbStart;
                    respond(ex, 200, toJson(Map.of("count", list.size(), "orders", list)));
                    return;
                }

                // GET /api/java/benchmark?n=<N>&mode=virtual|platform|both
                if (path.equals("/api/java/benchmark")) {
                    int n = Math.max(10, Math.min(
                        Integer.parseInt(params.getOrDefault("n", "1000")), 5000));
                    String mode = params.getOrDefault("mode", "both");
                    if (!Set.of("virtual", "platform", "both").contains(mode)) {
                        respond(ex, 400, "{\"error\":\"mode must be virtual, platform, or both\"}");
                        return;
                    }
                    respond(ex, 200, toJson(benchmark(n, mode)));
                    return;
                }

                respond(ex, 404, "{\"error\":\"not found\",\"path\":\"" + path + "\"}");

            } catch (Exception e) {
                try {
                    respond(ex, 500, "{\"error\":\"" + e.getClass().getSimpleName()
                        + ": " + e.getMessage() + "\"}");
                } catch (IOException ignored) {}
            } finally {
                // Enqueue APM metric after the response has been written.
                // Thread.ofVirtual().start() is used so that the ApmCollector.record()
                // call (which is itself non-blocking) does not execute on the
                // request-serving virtual thread after it has returned from ServeHTTP.
                // In practice record() returns in nanoseconds, but the separation
                // makes the non-blocking contract explicit.
                final long   responseMs     = System.currentTimeMillis() - t0;
                final long   capturedQueryMs = queryMs[0];
                final String capturedPath   = path;
                Thread.ofVirtual().start(() ->
                    ApmCollector.record(new ApmCollector.TransactionMetric(
                        correlationId, "java-loom", capturedPath,
                        responseMs, capturedQueryMs, System.currentTimeMillis()
                    ))
                );
            }
        });

        server.start();
        System.out.println("[Java 21 Loom] PostgreSQL-backed Virtual Thread Order Server on :" + port);
        System.out.println("  POST /api/java/order?id=order-1&type=BUY&from=ACC-001&to=ACC-002&amount=500");
        System.out.println("  POST /api/java/order?id=order-2&type=SELL");
        System.out.println("  PUT  /api/java/order?id=order-1&event=PAY");
        System.out.println("  PUT  /api/java/order?id=order-1&event=PROCESS");
        System.out.println("  PUT  /api/java/order?id=order-1&event=SHIP");
        System.out.println("  PUT  /api/java/order?id=order-1&event=DELIVER");
        System.out.println("  PUT  /api/java/order?id=order-1&event=CANCEL");
        System.out.println("  GET  /api/java/order?id=order-1");
        System.out.println("  GET  /api/java/orders");
        System.out.println("  GET  /api/java/benchmark?n=1000&mode=both");

        Thread.currentThread().join();
    }
}
