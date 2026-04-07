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

import java.io.*;
import java.net.InetSocketAddress;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.concurrent.locks.*;

public class VirtualServer {

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

    // 이벤트 워커: Virtual Thread로 실행되며 큐에서 이벤트를 꺼내 상태 전이를 수행한다.
    // Thread.sleep()이나 I/O 블로킹 없이 큐 대기 중에도 OS Thread를 반환한다.
    static void startEventWorkers(int workerCount) {
        for (int i = 0; i < workerCount; i++) {
            Thread.ofVirtual().name("event-worker-" + i).start(() -> {
                while (!Thread.currentThread().isInterrupted()) {
                    try {
                        EventTask task = eventQueue.take(); // 블로킹 대기, OS Thread 반환
                        Order order = orders.get(task.orderId());
                        if (order == null) {
                            task.result().complete("ORDER_NOT_FOUND");
                        } else {
                            // 실제 I/O 작업 시뮬레이션 (예: DB 저장, 알림 발송)
                            simulateAsyncIo(task.event());
                            String r = order.apply(task.event());
                            task.result().complete(r);
                        }
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    }
                }
            });
        }
    }

    // 외부 시스템 호출 시뮬레이션 (DB write, 결제 API, 알림 등)
    // Virtual Thread에서 sleep은 OS Thread를 차단하지 않는다.
    static void simulateAsyncIo(OrderEvent event) {
        try {
            int delayMs = switch (event) {
                case PAY     -> 5;   // 결제 승인 API 호출
                case SHIP    -> 3;   // 배송사 API 호출
                case CANCEL  -> 2;   // 취소 처리
                case REFUND  -> 8;   // 환불 처리
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

        // 이벤트 워커 16개를 Virtual Thread로 시작
        // 각 워커는 큐 대기 중 OS Thread를 차단하지 않는다.
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
                    respond(ex, 200, toJson(Map.of(
                        "lang",       "java",
                        "version",    System.getProperty("java.version"),
                        "port",       8010,
                        "paradigm",   "virtual-threads",
                        "feature",    "Project Loom — Executors.newVirtualThreadPerTaskExecutor()",
                        "jvm",        System.getProperty("java.vm.name"),
                        "cpu_cores",  Runtime.getRuntime().availableProcessors(),
                        "orders",     orders.size()
                    )));
                    return;
                }

                // POST /api/java/order?id=<orderId>  — 주문 생성
                if (path.equals("/api/java/order") && method.equals("POST")) {
                    String id = params.get("id");
                    if (id == null || id.isEmpty()) {
                        respond(ex, 400, "{\"error\":\"id parameter required\"}");
                        return;
                    }
                    Order existing = orders.putIfAbsent(id, new Order(id));
                    if (existing != null) {
                        respond(ex, 409, "{\"error\":\"order already exists\",\"id\":\"" + id + "\"}");
                        return;
                    }
                    respond(ex, 201, toJson(orders.get(id).toMap()));
                    return;
                }

                // PUT /api/java/order?id=<orderId>&event=<evt>  — 상태 전이
                // 이벤트를 큐에 넣고 Virtual Thread 워커가 비동기로 처리한다.
                // CompletableFuture.get()으로 결과를 기다리는 동안 현재 Virtual Thread는
                // OS Thread를 반환하므로 블로킹이 발생하지 않는다.
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
