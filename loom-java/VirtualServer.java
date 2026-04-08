// loom-java/VirtualServer.java
// Java 21 Virtual Threads (Project Loom) — Order/Payment State Management Server
// Port: 8010
//
// Virtual Thread 원리:
//   OS Thread 1개당 약 1MB 스택, 생성 비용이 높아 대규모 동시 접속에 불리하다.
//   Virtual Thread는 JVM이 관리하는 경량 스레드로 스택 초기 크기가 수백 바이트이며
//   Thread.sleep()이나 소켓 I/O 등 블로킹 구간에서 OS Thread를 자동으로 반환한다.
//   Executors.newVirtualThreadPerTaskExecutor()를 사용하면 작업마다 Virtual Thread를
//   할당하므로 수만 개의 동시 요청을 OS Thread 수와 무관하게 처리할 수 있다.
//
// DB 영속화:
//   HikariCP 커넥션 풀 + JDBC를 통해 주문 상태를 PostgreSQL 또는 Oracle에 저장한다.
//   autoCommit=true 환경에서 단일 INSERT/MERGE 문만 실행하여 트랜잭션 락 범위를 최소화한다.
//   가상 스레드에서 JDBC 블로킹 호출 시 JVM은 해당 가상 스레드를 언마운트하고
//   OS Thread를 다른 가상 스레드에 재할당한다.
//   DB 접속 실패 시 서버는 인메모리 전용 모드로 폴백하여 계속 동작한다.
//
// 엔드포인트:
//   GET /health
//   GET /api/java/status
//   POST /api/java/order?id=<orderId>              — 주문 생성 (ORDERED)
//   PUT  /api/java/order?id=<orderId>&event=<evt>  — 상태 전이 (PAY, SHIP, CANCEL, REFUND)
//   GET  /api/java/order?id=<orderId>              — 주문 조회
//   GET  /api/java/orders                          — 전체 주문 목록
//   GET  /api/java/benchmark?n=<N>&mode=virtual|platform|both — 벤치마크

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpExchange;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import java.io.*;
import java.net.InetSocketAddress;
import java.sql.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.concurrent.locks.*;
import javax.sql.DataSource;

public class VirtualServer {

    // ── DB 영속화 계층 ──────────────────────────────────────────────────────
    // HikariCP 커넥션 풀을 통해 JDBC 기반으로 주문 상태를 저장한다.
    // dataSource가 null이면 DB 없이 인메모리 전용 모드로 동작한다.
    static final class DbStore {

        private static volatile HikariDataSource dataSource = null;
        private static volatile boolean          isPostgres = true;

        // 환경 변수에서 DB 접속 정보를 읽어 HikariCP 풀을 초기화하고 테이블을 생성한다.
        //   DB_URL      기본값: jdbc:postgresql://localhost:5432/orders
        //   DB_USER     기본값: orders
        //   DB_PASSWORD 기본값: orders
        static void init() {
            String url  = getEnv("DB_URL",      "jdbc:postgresql://localhost:5432/orders");
            String user = getEnv("DB_USER",      "orders");
            String pass = getEnv("DB_PASSWORD",  "orders");

            isPostgres = url.startsWith("jdbc:postgresql:");

            HikariConfig cfg = new HikariConfig();
            cfg.setJdbcUrl(url);
            cfg.setUsername(user);
            cfg.setPassword(pass);
            // 커넥션 풀 크기: 가상 스레드 수가 수천 개여도 DB 서버 부하를 고려해 20으로 제한한다.
            cfg.setMaximumPoolSize(20);
            cfg.setMinimumIdle(5);
            // 3초 이내에 커넥션을 얻지 못하면 SQLException을 발생시켜 대기 스레드를 즉시 해제한다.
            cfg.setConnectionTimeout(3_000);
            cfg.setIdleTimeout(600_000);
            cfg.setMaxLifetime(1_800_000);
            // autoCommit=true: 단일 문 실행마다 즉시 커밋되므로 별도 트랜잭션 관리가 불필요하다.
            cfg.setAutoCommit(true);
            cfg.setPoolName("loom-order-pool");

            try {
                HikariDataSource ds = new HikariDataSource(cfg);
                createTableIfAbsent(ds);
                dataSource = ds;
                System.out.println("[DbStore] connected: " + url);
            } catch (Exception e) {
                // DB 접속 실패 시 서버를 중단하지 않고 인메모리 전용 모드로 폴백한다.
                dataSource = null;
                System.err.println("[DbStore] unavailable, in-memory only: " + e.getMessage());
            }
        }

        // orders 테이블이 없으면 생성한다.
        private static void createTableIfAbsent(HikariDataSource ds) throws SQLException {
            try (Connection c = ds.getConnection(); Statement s = c.createStatement()) {
                if (isPostgres) {
                    s.execute(
                        "CREATE TABLE IF NOT EXISTS orders (" +
                        "  id         VARCHAR(255) PRIMARY KEY," +
                        "  status     VARCHAR(32)  NOT NULL," +
                        "  created_at BIGINT       NOT NULL," +
                        "  updated_at BIGINT       NOT NULL" +
                        ")"
                    );
                } else {
                    // Oracle: ORA-00955(name already used) 예외는 테이블이 이미 존재함을 의미한다.
                    try {
                        s.execute(
                            "CREATE TABLE orders (" +
                            "  id         VARCHAR2(255) PRIMARY KEY," +
                            "  status     VARCHAR2(32)  NOT NULL," +
                            "  created_at NUMBER(19)    NOT NULL," +
                            "  updated_at NUMBER(19)    NOT NULL" +
                            ")"
                        );
                    } catch (SQLException ex) {
                        if (ex.getErrorCode() != 955) throw ex;
                    }
                }
            }
        }

        // 주문 상태를 DB에 동기화한다.
        // PostgreSQL: INSERT ON CONFLICT DO UPDATE (단일 문, 행 단위 락)
        // Oracle:     MERGE INTO orders USING DUAL  (단일 문, 행 단위 락)
        // autoCommit=true이므로 문 실행 직후 커밋되어 락 보유 시간이 최소화된다.
        // dataSource가 null이면 즉시 반환한다.
        static void upsertOrder(String id, String status, long createdAt, long updatedAt) {
            if (dataSource == null) return;
            try (Connection c = dataSource.getConnection()) {
                if (isPostgres) {
                    upsertPostgres(c, id, status, createdAt, updatedAt);
                } else {
                    upsertOracle(c, id, status, createdAt, updatedAt);
                }
            } catch (SQLException e) {
                System.err.println("[DbStore] upsertOrder failed id=" + id + ": " + e.getMessage());
            }
        }

        private static void upsertPostgres(Connection c,
                String id, String status, long createdAt, long updatedAt) throws SQLException {
            // INSERT ... ON CONFLICT: 행이 없으면 삽입, 있으면 status와 updated_at만 갱신한다.
            // created_at은 최초 삽입 시 한 번만 기록되며 갱신하지 않는다.
            String sql =
                "INSERT INTO orders(id, status, created_at, updated_at) VALUES (?, ?, ?, ?)" +
                " ON CONFLICT (id) DO UPDATE" +
                "   SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at";
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setString(1, id);
                ps.setString(2, status);
                ps.setLong  (3, createdAt);
                ps.setLong  (4, updatedAt);
                ps.executeUpdate();
            }
        }

        private static void upsertOracle(Connection c,
                String id, String status, long createdAt, long updatedAt) throws SQLException {
            // MERGE INTO USING DUAL: DUAL은 Oracle 단일 행 더미 테이블이다.
            // ON 조건에서 일치하는 행이 있으면 UPDATE, 없으면 INSERT한다.
            // 파라미터 순서: (1)ON조건id (2)UPDATE status (3)UPDATE updated_at
            //               (4)INSERT id (5)INSERT status (6)INSERT created_at (7)INSERT updated_at
            String sql =
                "MERGE INTO orders USING DUAL ON (id = ?)" +
                " WHEN MATCHED    THEN UPDATE SET status = ?, updated_at = ?" +
                " WHEN NOT MATCHED THEN INSERT (id, status, created_at, updated_at)" +
                "   VALUES (?, ?, ?, ?)";
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setString(1, id);
                ps.setString(2, status);
                ps.setLong  (3, updatedAt);
                ps.setString(4, id);
                ps.setString(5, status);
                ps.setLong  (6, createdAt);
                ps.setLong  (7, updatedAt);
                ps.executeUpdate();
            }
        }

        static boolean isConnected() { return dataSource != null; }

        private static String getEnv(String key, String defaultVal) {
            String v = System.getenv(key);
            return (v != null && !v.isEmpty()) ? v : defaultVal;
        }
    }

    // ── 주문 상태 열거형 ────────────────────────────────────────────────────
    // 상태 전이 규칙:
    //   ORDERED -> PAID -> PROCESSING -> SHIPPED -> DELIVERED
    //   ORDERED -> CANCELED
    //   PAID    -> CANCELED -> REFUNDED
    enum OrderStatus {
        ORDERED, PAID, PROCESSING, SHIPPED, DELIVERED, CANCELED, REFUNDED;

        boolean canTransitionTo(OrderStatus next) {
            return switch (this) {
                case ORDERED    -> next == PAID    || next == CANCELED;
                case PAID       -> next == PROCESSING || next == CANCELED;
                case PROCESSING -> next == SHIPPED;
                case SHIPPED    -> next == DELIVERED;
                case CANCELED   -> next == REFUNDED;
                default         -> false;
            };
        }
    }

    // ── 이벤트 열거형 ──────────────────────────────────────────────────────
    enum OrderEvent {
        PAY, SHIP, PROCESS, DELIVER, CANCEL, REFUND;

        OrderStatus targetStatus() {
            return switch (this) {
                case PAY     -> OrderStatus.PAID;
                case PROCESS -> OrderStatus.PROCESSING;
                case SHIP    -> OrderStatus.SHIPPED;
                case DELIVER -> OrderStatus.DELIVERED;
                case CANCEL  -> OrderStatus.CANCELED;
                case REFUND  -> OrderStatus.REFUNDED;
            };
        }
    }

    // ── 주문 도메인 객체 ────────────────────────────────────────────────────
    static class Order {
        final String id;
        // 상태 변경은 ReentrantLock으로 동시성을 보호한다.
        // synchronized 대신 Lock을 사용하면 virtual thread의 pinning 문제를 피할 수 있다.
        private final ReentrantLock lock = new ReentrantLock();
        private OrderStatus status;
        private final List<String> history = new ArrayList<>();
        private final long createdAt;
        private long updatedAt;

        Order(String id) {
            this.id        = id;
            this.status    = OrderStatus.ORDERED;
            this.createdAt = System.currentTimeMillis();
            this.updatedAt = createdAt;
            history.add(ts() + " CREATED -> ORDERED");
        }

        // 상태 전이: 허용된 전이만 수행하고 이벤트 히스토리를 기록한다.
        String apply(OrderEvent event) {
            lock.lock();
            try {
                OrderStatus next = event.targetStatus();
                if (!status.canTransitionTo(next)) {
                    return "INVALID_TRANSITION:" + status + "->" + next;
                }
                String prev = status.name();
                status    = next;
                updatedAt = System.currentTimeMillis();
                history.add(ts() + " " + prev + " -> " + status.name() + " [" + event.name() + "]");
                return "OK";
            } finally {
                lock.unlock();
            }
        }

        OrderStatus status() {
            lock.lock();
            try { return status; } finally { lock.unlock(); }
        }

        Map<String, Object> toMap() {
            lock.lock();
            try {
                return Map.of(
                    "id",         id,
                    "status",     status.name(),
                    "history",    new ArrayList<>(history),
                    "created_at", createdAt,
                    "updated_at", updatedAt
                );
            } finally {
                lock.unlock();
            }
        }

        private String ts() {
            return "[" + System.currentTimeMillis() + "]";
        }
    }

    // ── 주문 저장소 ────────────────────────────────────────────────────────
    // ConcurrentHashMap으로 스레드 안전 조회를 보장한다.
    static final ConcurrentHashMap<String, Order> orders = new ConcurrentHashMap<>();

    // ── 비동기 이벤트 큐 ────────────────────────────────────────────────────
    // 상태 전이 이벤트를 큐에 쌓고, 별도의 Virtual Thread 워커가 처리한다.
    // 이 패턴은 HTTP 요청 스레드와 이벤트 처리를 분리하여 응답 속도를 높인다.
    record EventTask(String orderId, OrderEvent event, CompletableFuture<String> result) {}

    static final LinkedBlockingQueue<EventTask> eventQueue = new LinkedBlockingQueue<>();

    // 이벤트 워커: Virtual Thread로 실행되며 큐에서 이벤트를 꺼내 처리한다.
    // 처리 순서:
    //   1. simulateAsyncIo  — 외부 API 호출 시뮬레이션 (OS Thread 반환)
    //   2. order.apply      — 인메모리 상태 전이 (ReentrantLock, pinning 없음)
    //   3. DbStore.upsert   — DB 영속화 (JDBC 블로킹, OS Thread 반환)
    //   4. future.complete  — HTTP 응답 신호
    // DB 쓰기는 Lock 해제 후 수행되므로 Lock 보유 시간에 포함되지 않는다.
    static void startEventWorkers(int workerCount) {
        for (int i = 0; i < workerCount; i++) {
            Thread.ofVirtual().name("event-worker-" + i).start(() -> {
                while (!Thread.currentThread().isInterrupted()) {
                    try {
                        EventTask task  = eventQueue.take(); // 블로킹 대기, OS Thread 반환
                        Order     order = orders.get(task.orderId());
                        if (order == null) {
                            task.result().complete("ORDER_NOT_FOUND");
                        } else {
                            simulateAsyncIo(task.event());
                            String r = order.apply(task.event());
                            if ("OK".equals(r)) {
                                // Lock 해제 후 스냅샷을 읽어 DB에 반영한다.
                                // DB 쓰기가 완료된 후 future를 완성하여 응답 일관성을 보장한다.
                                Map<String, Object> snap = order.toMap();
                                DbStore.upsertOrder(
                                    (String) snap.get("id"),
                                    (String) snap.get("status"),
                                    (long)   snap.get("created_at"),
                                    (long)   snap.get("updated_at")
                                );
                            }
                            task.result().complete(r);
                        }
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    }
                }
            });
        }
    }

    // 외부 시스템 호출 시뮬레이션 (결제 API, 배송사 API, 알림 등)
    // Virtual Thread에서 sleep은 OS Thread를 차단하지 않는다.
    static void simulateAsyncIo(OrderEvent event) {
        try {
            int delayMs = switch (event) {
                case PAY     -> 5;
                case SHIP    -> 3;
                case CANCEL  -> 2;
                case REFUND  -> 8;
                default      -> 1;
            };
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // ── 벤치마크: Virtual Thread vs Platform Thread ──────────────────────
    // 동일한 작업(주문 상태 전이 + I/O 시뮬레이션)을 두 방식으로 실행하고 비교한다.
    // Platform Thread(OS Thread)는 풀 크기 상한에 묶이지만,
    // Virtual Thread는 작업 수와 무관하게 모두 동시에 실행된다.
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
            "Each task: create order + state transition (PAY) + " +
            "simulated I/O (5ms). " +
            "Platform threads block OS thread during I/O. " +
            "Virtual threads yield OS thread during I/O.");
        return result;
    }

    static long runBenchmarkWith(int n, boolean virtual) throws Exception {
        // 벤치마크용 임시 주문 ID 목록 생성
        List<String> ids = new ArrayList<>(n);
        for (int i = 0; i < n; i++) {
            String id = (virtual ? "vt" : "pt") + "-bench-" + i + "-" + System.nanoTime();
            orders.put(id, new Order(id));
            ids.add(id);
        }

        CountDownLatch latch = new CountDownLatch(n);
        long t0 = System.nanoTime();

        ExecutorService exec = virtual
            ? Executors.newVirtualThreadPerTaskExecutor()
            : Executors.newFixedThreadPool(200); // OS Thread 상한 200개

        try {
            for (String id : ids) {
                exec.submit(() -> {
                    try {
                        simulateAsyncIo(OrderEvent.PAY); // I/O 시뮬레이션
                        Order o = orders.get(id);
                        if (o != null) o.apply(OrderEvent.PAY);
                    } finally {
                        latch.countDown();
                    }
                });
            }
            latch.await(60, TimeUnit.SECONDS);
        } finally {
            exec.shutdown();
            // 벤치마크용 임시 주문 제거
            for (String id : ids) orders.remove(id);
        }

        return (System.nanoTime() - t0) / 1_000_000;
    }

    // ── JSON 직렬화 ────────────────────────────────────────────────────────
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

    // ── HTTP 유틸리티 ──────────────────────────────────────────────────────
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

    // ── 메인 ────────────────────────────────────────────────────────────────
    public static void main(String[] args) throws Exception {
        int port = 8010;

        // DB 커넥션 풀을 초기화한다. 실패해도 서버는 인메모리 모드로 계속 기동한다.
        DbStore.init();

        // 이벤트 워커 16개를 Virtual Thread로 시작
        startEventWorkers(16);

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 256);

        // HTTP 서버 자체도 Virtual Thread로 요청을 처리한다.
        // 요청마다 새 Virtual Thread를 할당하므로 수만 개의 동시 접속이 가능하다.
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());

        server.createContext("/", ex -> {
            String method = ex.getRequestMethod();
            String path   = ex.getRequestURI().getPath();
            Map<String, String> params = parseQuery(ex.getRequestURI().getQuery());

            try {
                // GET /health
                if (path.equals("/health")) {
                    respond(ex, 200, "{\"status\":\"ok\",\"lang\":\"java\",\"port\":8010}");
                    return;
                }

                // GET /api/java/status
                if (path.equals("/api/java/status")) {
                    Map<String, Object> statusMap = new LinkedHashMap<>();
                    statusMap.put("lang",        "java");
                    statusMap.put("version",      System.getProperty("java.version"));
                    statusMap.put("port",          8010);
                    statusMap.put("paradigm",      "virtual-threads");
                    statusMap.put("feature",      "Project Loom — Executors.newVirtualThreadPerTaskExecutor()");
                    statusMap.put("jvm",           System.getProperty("java.vm.name"));
                    statusMap.put("cpu_cores",     Runtime.getRuntime().availableProcessors());
                    statusMap.put("orders",        orders.size());
                    statusMap.put("db_connected",  DbStore.isConnected());
                    String dbUrl = System.getenv("DB_URL");
                    statusMap.put("db_url", dbUrl != null && !dbUrl.isEmpty() ? dbUrl : "jdbc:postgresql://localhost:5432/orders");
                    respond(ex, 200, toJson(statusMap));
                    return;
                }

                // POST /api/java/order?id=<orderId>  — 주문 생성
                if (path.equals("/api/java/order") && method.equals("POST")) {
                    String id = params.get("id");
                    if (id == null || id.isEmpty()) {
                        respond(ex, 400, "{\"error\":\"id parameter required\"}");
                        return;
                    }
                    Order created  = new Order(id);
                    Order existing = orders.putIfAbsent(id, created);
                    if (existing != null) {
                        respond(ex, 409, "{\"error\":\"order already exists\",\"id\":\"" + id + "\"}");
                        return;
                    }
                    // 신규 주문을 DB에 INSERT한다.
                    // Virtual Thread에서 JDBC 블로킹이 발생하지만 OS Thread를 점유하지 않는다.
                    Map<String, Object> snap = created.toMap();
                    DbStore.upsertOrder(
                        (String) snap.get("id"),
                        (String) snap.get("status"),
                        (long)   snap.get("created_at"),
                        (long)   snap.get("updated_at")
                    );
                    respond(ex, 201, toJson(snap));
                    return;
                }

                // PUT /api/java/order?id=<orderId>&event=<evt>  — 상태 전이
                // 이벤트를 큐에 넣고 Virtual Thread 워커가 비동기로 처리한다.
                // CompletableFuture.get() 대기 중 현재 Virtual Thread는 OS Thread를 반환한다.
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
                    CompletableFuture<String> future = new CompletableFuture<>();
                    eventQueue.put(new EventTask(id, event, future));
                    // Virtual Thread가 여기서 대기하는 동안 OS Thread는 다른 작업을 처리한다.
                    String r = future.get(10, TimeUnit.SECONDS);
                    if (r.startsWith("INVALID") || r.equals("ORDER_NOT_FOUND")) {
                        respond(ex, 400, "{\"error\":\"" + r + "\"}");
                    } else {
                        respond(ex, 200, toJson(orders.get(id).toMap()));
                    }
                    return;
                }

                // GET /api/java/order?id=<orderId>  — 주문 조회
                if (path.equals("/api/java/order") && method.equals("GET")) {
                    String id = params.get("id");
                    if (id == null) {
                        respond(ex, 400, "{\"error\":\"id parameter required\"}");
                        return;
                    }
                    Order o = orders.get(id);
                    if (o == null) {
                        respond(ex, 404, "{\"error\":\"order not found\",\"id\":\"" + id + "\"}");
                        return;
                    }
                    respond(ex, 200, toJson(o.toMap()));
                    return;
                }

                // GET /api/java/orders  — 전체 주문 목록
                if (path.equals("/api/java/orders")) {
                    List<Map<String, Object>> list = new ArrayList<>();
                    orders.values().forEach(o -> list.add(o.toMap()));
                    respond(ex, 200, toJson(Map.of("count", list.size(), "orders", list)));
                    return;
                }

                // GET /api/java/benchmark?n=<N>&mode=virtual|platform|both
                // Virtual Thread와 Platform Thread의 처리 성능을 비교한다.
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
            }
        });

        server.start();
        System.out.println("[Java 21 Loom] Virtual Thread Order Server on :" + port);
        System.out.println("  DB connected : " + DbStore.isConnected());
        System.out.println("  POST /api/java/order?id=order-1");
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
