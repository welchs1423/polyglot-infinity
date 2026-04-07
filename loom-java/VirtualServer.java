// loom-java/VirtualServer.java
// Polyglot Infinity — Java 21 Virtual Threads (Project Loom) (:8010)
//
// 핵심 강점: Thread.ofVirtual() — OS 스레드가 아닌 JVM 관리 경량 스레드.
// OS 스레드 1개 ≈ 1MB 스택. Virtual Thread ≈ 수백 바이트.
// 10만 개 virtual thread를 동시에 띄워도 메모리·컨텍스트스위치 비용이 극히 낮습니다.
//
// Kotlin coroutine/Scala future도 경량 비동기이지만, virtual thread는
// 기존 blocking API(JDBC, socket, sleep)를 그대로 쓰면서도 OS 스레드를 차단하지 않음.
// → 레거시 코드 수정 없이 대규모 동시성 확보.
//
// GET /health
// GET /api/java/status
// GET /api/java/vthreads?n=50000      — N개 virtual thread 스폰, 처리량·메모리 측정
// GET /api/java/compare?n=200         — virtual vs platform thread 생성 시간 비교
// GET /api/java/pipeline?n=1000&delay=10 — Blocking I/O 시뮬레이션: Thread.sleep() 포함 작업
//   virtual thread: sleep 중 OS thread 해제 → N개 동시 sleep → ~delay ms 완료
//   platform thread: pool 상한(200)에 묶임 → ceil(N/200)*delay ms 소요

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpExchange;

import java.io.*;
import java.net.InetSocketAddress;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.*;
import java.lang.management.ManagementFactory;

public class VirtualServer {

    // ── Black-Scholes (순수 계산 — I/O 없음) ────────────────────────
    // 각 virtual thread가 이 계산을 수행합니다.
    // virtual thread는 블로킹 없이 계산만 하는 경우에도 효율적입니다.
    static double normCdf(double x) {
        double t = 1.0 / (1.0 + 0.2316419 * Math.abs(x));
        double d = Math.exp(-0.5 * x * x) / Math.sqrt(2 * Math.PI);
        double p = t * (0.319381530 + t * (-0.356563782
                + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
        double cdf = 1.0 - d * p;
        return x < 0 ? 1.0 - cdf : cdf;
    }

    record BSResult(double call, double put, double delta) {}

    static BSResult blackScholes(double s, double k, double r, double sigma, double t) {
        double d1 = (Math.log(s / k) + (r + 0.5 * sigma * sigma) * t) / (sigma * Math.sqrt(t));
        double d2 = d1 - sigma * Math.sqrt(t);
        double call  = s * normCdf(d1) - k * Math.exp(-r * t) * normCdf(d2);
        double put   = k * Math.exp(-r * t) * normCdf(-d2) - s * normCdf(-d1);
        double delta = normCdf(d1);
        return new BSResult(call, put, delta);
    }

    // ── Virtual Thread 배치 실행 ─────────────────────────────────────
    // Thread.ofVirtual().start() — OS 스레드가 아닌 JVM 경량 스레드 생성.
    // Executors.newVirtualThreadPerTaskExecutor() — 작업마다 virtual thread 할당.
    // OS 스레드 풀 크기와 무관하게 수십만 개 동시 실행 가능.
    static Map<String, Object> runVirtualThreads(int n) throws Exception {
        long memBefore = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory();
        long t0 = System.nanoTime();

        AtomicLong totalCall   = new AtomicLong(Double.doubleToRawLongBits(0.0));
        AtomicInteger finished = new AtomicInteger(0);
        CountDownLatch latch   = new CountDownLatch(n);

        // newVirtualThreadPerTaskExecutor: 작업마다 새 virtual thread 생성.
        // newFixedThreadPool(n)과 달리 OS 스레드를 N개 점유하지 않습니다.
        try (var exec = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < n; i++) {
                final int idx = i;
                exec.submit(() -> {
                    try {
                        // 각 virtual thread: 서로 다른 파라미터로 BS 계산
                        double s     = 80.0 + (idx % 120);
                        double sigma = 0.10 + (idx % 40) * 0.01;
                        BSResult r   = blackScholes(s, 100.0, 0.05, sigma, 1.0);

                        // AtomicLong에 call 값 누적 (double bit trick)
                        long cur, updated;
                        do {
                            cur     = totalCall.get();
                            updated = Double.doubleToRawLongBits(
                                          Double.longBitsToDouble(cur) + r.call());
                        } while (!totalCall.compareAndSet(cur, updated));

                        finished.incrementAndGet();
                    } finally {
                        latch.countDown();
                    }
                });
            }
            latch.await(30, TimeUnit.SECONDS);
        }

        long elapsedMs  = (System.nanoTime() - t0) / 1_000_000;
        long memAfter   = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory();
        long memDeltaKb = (memAfter - memBefore) / 1024;
        double avgCall  = Double.longBitsToDouble(totalCall.get()) / Math.max(finished.get(), 1);
        int cpuCores    = Runtime.getRuntime().availableProcessors();

        return Map.ofEntries(
            Map.entry("lang",             "java"),
            Map.entry("version",          System.getProperty("java.version")),
            Map.entry("paradigm",         "virtual-threads"),
            Map.entry("virtual_threads",  n),
            Map.entry("finished",         finished.get()),
            Map.entry("elapsed_ms",       elapsedMs),
            Map.entry("throughput_per_s", n * 1000L / Math.max(elapsedMs, 1)),
            Map.entry("mem_delta_kb",     memDeltaKb),
            Map.entry("cpu_cores",        cpuCores),
            Map.entry("avg_call_price",   String.format("%.4f", avgCall)),
            Map.entry("note", "Thread.ofVirtual — OS threads used ≈ " + cpuCores
                    + ", virtual threads spawned = " + n)
        );
    }

    // ── Blocking I/O 시뮬레이션 ──────────────────────────────────────
    // Virtual Thread의 핵심 강점: Thread.sleep()이 포함된 blocking 코드를
    // 그대로 써도 OS 스레드를 차단하지 않습니다.
    // - Platform thread pool(200개): N개 작업 중 200개만 동시 sleep 가능
    //   → 총 소요 = ceil(N/200) * delayMs
    // - Virtual thread: N개 모두 동시에 sleep (JVM이 OS thread를 재활용)
    //   → 총 소요 ≈ delayMs (N에 무관!)
    static Map<String, Object> runPipeline(int n, int delayMs) throws Exception {
        final int PLATFORM_POOL = 200;

        // Platform thread 측정
        long t0p = System.nanoTime();
        CountDownLatch lp = new CountDownLatch(n);
        AtomicLong sumPlatform = new AtomicLong(0);
        try (var exec = Executors.newFixedThreadPool(PLATFORM_POOL)) {
            for (int i = 0; i < n; i++) {
                final int idx = i;
                exec.submit(() -> {
                    try {
                        Thread.sleep(delayMs); // blocking I/O 시뮬레이션
                        BSResult r = blackScholes(90 + idx % 40, 100, 0.05, 0.2, 1.0);
                        long cur, upd;
                        do {
                            cur = sumPlatform.get();
                            upd = Double.doubleToRawLongBits(
                                Double.longBitsToDouble(cur) + r.call());
                        } while (!sumPlatform.compareAndSet(cur, upd));
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    } finally {
                        lp.countDown();
                    }
                });
            }
            lp.await(120, TimeUnit.SECONDS);
        }
        long platformMs = (System.nanoTime() - t0p) / 1_000_000;

        // Virtual thread 측정
        long t0v = System.nanoTime();
        CountDownLatch lv = new CountDownLatch(n);
        AtomicLong sumVirtual = new AtomicLong(0);
        try (var exec = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < n; i++) {
                final int idx = i;
                exec.submit(() -> {
                    try {
                        Thread.sleep(delayMs); // virtual thread는 sleep 중 OS thread 반환
                        BSResult r = blackScholes(90 + idx % 40, 100, 0.05, 0.2, 1.0);
                        long cur, upd;
                        do {
                            cur = sumVirtual.get();
                            upd = Double.doubleToRawLongBits(
                                Double.longBitsToDouble(cur) + r.call());
                        } while (!sumVirtual.compareAndSet(cur, upd));
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    } finally {
                        lv.countDown();
                    }
                });
            }
            lv.await(120, TimeUnit.SECONDS);
        }
        long virtualMs = (System.nanoTime() - t0v) / 1_000_000;

        int theoreticalPlatformMs = (int)(Math.ceil((double) n / PLATFORM_POOL) * delayMs);

        return Map.ofEntries(
            Map.entry("lang",                    "java"),
            Map.entry("tasks",                   n),
            Map.entry("delay_ms_per_task",        delayMs),
            Map.entry("platform_pool_size",       PLATFORM_POOL),
            Map.entry("platform_total_ms",        platformMs),
            Map.entry("virtual_total_ms",          virtualMs),
            Map.entry("theoretical_platform_ms",  theoreticalPlatformMs),
            Map.entry("speedup",                  String.format("%.1fx", (double) platformMs / Math.max(virtualMs, 1))),
            Map.entry("virtual_concurrency",       n + " tasks all sleeping simultaneously"),
            Map.entry("note", "Virtual threads release OS thread during sleep — " +
                n + " tasks × " + delayMs + "ms blocking completed in ~" + virtualMs + "ms")
        );
    }

    // ── Virtual vs Platform Thread 비교 ─────────────────────────────
    // Platform thread = OS thread (생성 비용 높음, 스택 1MB)
    // Virtual thread  = JVM thread (생성 비용 낮음, 스택 수백 바이트, 동적 확장)
    static Map<String, Object> compareThreads(int n) throws Exception {
        // Platform threads
        long t0p = System.nanoTime();
        CountDownLatch lp = new CountDownLatch(n);
        try (var exec = Executors.newFixedThreadPool(Math.min(n, 200))) {
            for (int i = 0; i < n; i++) {
                final int idx = i;
                exec.submit(() -> {
                    blackScholes(100.0 + idx % 50, 100.0, 0.05, 0.2, 1.0);
                    lp.countDown();
                });
            }
            lp.await(30, TimeUnit.SECONDS);
        }
        long platformMs = (System.nanoTime() - t0p) / 1_000_000;

        // Virtual threads
        long t0v = System.nanoTime();
        CountDownLatch lv = new CountDownLatch(n);
        try (var exec = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < n; i++) {
                final int idx = i;
                exec.submit(() -> {
                    blackScholes(100.0 + idx % 50, 100.0, 0.05, 0.2, 1.0);
                    lv.countDown();
                });
            }
            lv.await(30, TimeUnit.SECONDS);
        }
        long virtualMs = (System.nanoTime() - t0v) / 1_000_000;

        return Map.of(
            "lang",                 "java",
            "tasks",                n,
            "platform_thread_ms",   platformMs,
            "virtual_thread_ms",    virtualMs,
            "speedup",              String.format("%.2fx", (double) platformMs / Math.max(virtualMs, 1)),
            "platform_pool_size",   Math.min(n, 200),
            "virtual_pool_size",    "unbounded (one-per-task)",
            "winner",               virtualMs <= platformMs ? "virtual_thread" : "platform_thread",
            "note", "platform threads capped at 200 (OS limits); virtual threads uncapped"
        );
    }

    // ── JSON 직렬화 ───────────────────────────────────────────────
    @SuppressWarnings("unchecked")
    static String toJson(Object v) {
        if (v instanceof Map<?,?> m) {
            StringBuilder sb = new StringBuilder("{");
            boolean first = true;
            for (var entry : ((Map<String,Object>) m).entrySet()) {
                if (!first) sb.append(",");
                sb.append("\"").append(entry.getKey()).append("\":");
                sb.append(toJson(entry.getValue()));
                first = false;
            }
            return sb.append("}").toString();
        }
        if (v instanceof List<?> list) {
            StringBuilder sb = new StringBuilder("[");
            for (int i = 0; i < list.size(); i++) {
                if (i > 0) sb.append(",");
                sb.append(toJson(list.get(i)));
            }
            return sb.append("]").toString();
        }
        if (v instanceof String s)  return "\"" + s.replace("\"", "\\\"") + "\"";
        if (v instanceof Boolean b) return b.toString();
        if (v == null)              return "null";
        return v.toString();
    }

    // ── HTTP 핸들러 ───────────────────────────────────────────────
    static void respond(HttpExchange ex, String body) throws IOException {
        byte[] bytes = body.getBytes("UTF-8");
        ex.getResponseHeaders().set("Content-Type", "application/json");
        ex.getResponseHeaders().set("Access-Control-Allow-Origin", "*");
        ex.sendResponseHeaders(200, bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
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

    public static void main(String[] args) throws Exception {
        int port = 8010;
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 128);

        // 요청마다 virtual thread 사용 — 서버 자체도 virtual thread 기반
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());

        server.createContext("/", ex -> {
            String path = ex.getRequestURI().getPath();
            Map<String, String> params = parseQuery(ex.getRequestURI().getQuery());

            try {
                String body = switch (path) {
                    case "/health" -> "{\"status\":\"ok\",\"lang\":\"java\",\"port\":8010}";

                    case "/api/java/status" -> toJson(Map.of(
                        "lang",        "java",
                        "version",     System.getProperty("java.version"),
                        "port",        8010,
                        "paradigm",    "virtual-threads",
                        "feature",     "Project Loom — Thread.ofVirtual()",
                        "jvm",         System.getProperty("java.vm.name"),
                        "cpu_cores",   Runtime.getRuntime().availableProcessors()
                    ));

                    case "/api/java/vthreads" -> {
                        int n = Math.max(1, Math.min(
                            Integer.parseInt(params.getOrDefault("n", "50000")), 100000));
                        yield toJson(runVirtualThreads(n));
                    }

                    case "/api/java/compare" -> {
                        int n = Math.max(10, Math.min(
                            Integer.parseInt(params.getOrDefault("n", "500")), 2000));
                        yield toJson(compareThreads(n));
                    }

                    case "/api/java/pipeline" -> {
                        int n = Math.max(10, Math.min(
                            Integer.parseInt(params.getOrDefault("n", "1000")), 5000));
                        int delay = Math.max(1, Math.min(
                            Integer.parseInt(params.getOrDefault("delay", "10")), 100));
                        yield toJson(runPipeline(n, delay));
                    }

                    default -> "{\"error\":\"not found\"}";
                };
                respond(ex, body);
            } catch (Exception e) {
                respond(ex, "{\"error\":\"" + e.getMessage() + "\"}");
            }
        });

        server.start();
        System.out.println("[Java 21 Loom] Virtual Thread Server on :" + port);
        System.out.println("  GET /api/java/vthreads?n=50000");
        System.out.println("  GET /api/java/compare?n=500");
        System.out.println("  GET /api/java/pipeline?n=1000&delay=10");

        // 메인 스레드 유지
        Thread.currentThread().join();
    }
}
