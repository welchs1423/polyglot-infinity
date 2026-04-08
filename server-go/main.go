package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
)

// ── 서킷 브레이커 ────────────────────────────────────────────────────────────
// 상태: 0=Closed(정상), 1=Open(차단), 2=HalfOpen(탐색)
const (
	cbClosed   int32 = 0
	cbOpen     int32 = 1
	cbHalfOpen int32 = 2
)

type CircuitBreaker struct {
	name        string
	state       int32
	failures    int32
	successes   int32
	lastFailure time.Time
	mu          sync.Mutex
	threshold   int32         // 실패 N회 → Open
	resetAfter  time.Duration // Open 후 HalfOpen 전환 대기
}

var circuitBreakers = map[string]*CircuitBreaker{}
var cbMu sync.RWMutex

func getOrCreateCB(name string) *CircuitBreaker {
	cbMu.RLock()
	cb, ok := circuitBreakers[name]
	cbMu.RUnlock()
	if ok {
		return cb
	}
	cbMu.Lock()
	defer cbMu.Unlock()
	// Double-checked locking: another goroutine may have inserted between RUnlock and Lock.
	if cb, ok = circuitBreakers[name]; ok {
		return cb
	}
	cb = &CircuitBreaker{name: name, threshold: 3, resetAfter: 30 * time.Second}
	circuitBreakers[name] = cb
	return cb
}

func (cb *CircuitBreaker) Allow() bool {
	switch atomic.LoadInt32(&cb.state) {
	case cbClosed:
		return true
	case cbOpen:
		cb.mu.Lock()
		defer cb.mu.Unlock()
		if time.Since(cb.lastFailure) > cb.resetAfter {
			atomic.StoreInt32(&cb.state, cbHalfOpen)
			return true
		}
		return false
	default: // HalfOpen: allow one probe request
		return true
	}
}

func (cb *CircuitBreaker) RecordSuccess() {
	atomic.StoreInt32(&cb.failures, 0)
	atomic.AddInt32(&cb.successes, 1)
	atomic.StoreInt32(&cb.state, cbClosed)
}

func (cb *CircuitBreaker) RecordFailure() {
	f := atomic.AddInt32(&cb.failures, 1)
	cb.mu.Lock()
	cb.lastFailure = time.Now()
	cb.mu.Unlock()
	if f >= cb.threshold {
		atomic.StoreInt32(&cb.state, cbOpen)
	}
}

// writeFallback writes a 200 OK degraded JSON body.
// Called when the circuit is open or a transport error occurs before any
// upstream response header has been sent to the client.
func writeFallback(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status":  "degraded",
		"message": "Service temporarily unavailable",
	})
}

// cbGet issues an HTTP GET through the named circuit breaker using httpClient.
func cbGet(name, url string) (*http.Response, error) {
	cb := getOrCreateCB(name)
	if !cb.Allow() {
		return nil, fmt.Errorf("circuit open for %s", name)
	}
	resp, err := httpClient.Get(url)
	if err != nil {
		cb.RecordFailure()
		return nil, err
	}
	cb.RecordSuccess()
	return resp, nil
}

// ── Reverse proxy: port constants ────────────────────────────────────────────
// Port assignments for all 22 HTTP-capable backend services.
// core-cpp and core-zig are compiled as shared libraries loaded via FFI.
// wasm-zig is compiled to WASM32 and executed in the browser.
// Neither group exposes a standalone HTTP server.
const (
	portPythonBrain     = 8000
	portRustPipeline    = 8081
	portJuliaEngine     = 8002
	portRStats          = 8003
	portFSharpPricer    = 9001
	portOCamlRisk       = 8004
	portCrystalGateway  = 9002
	portNimAnalytics    = 8005
	portScalaStreamer   = 9003
	portHaskellPricer   = 8006
	portRubyScorer      = 9004
	portDartEngine      = 9005
	portGleamHub        = 4001
	portVQuant          = 4002
	portErlangHot       = 4003
	portElixirHub       = 4000
	portClojureSTM      = 8009
	portJavaLoom        = 8010
	portPrologSolver    = 8011
	portLuaStream       = 8007
	portSwiftActor      = 8008
	portKotlinScheduler = 9000
)

// proxyTransport is shared by all reverse proxy instances.
// ResponseHeaderTimeout caps the wait after a TCP connection is established
// but before the upstream sends the first response header byte.
var proxyTransport = &http.Transport{
	ResponseHeaderTimeout: 30 * time.Second,
}

// resolveBackend returns the HTTP base URL for a downstream service.
// Lookup order: env SVC_UPPER_SNAKE_NAME > localhost fallback.
// Docker Compose usage: export SVC_PYTHON_BRAIN=python-brain:8000
func resolveBackend(dockerName string, port int) string {
	envKey := "SVC_" + strings.ToUpper(strings.ReplaceAll(dockerName, "-", "_"))
	if addr := os.Getenv(envKey); addr != "" {
		return "http://" + addr
	}
	return fmt.Sprintf("http://localhost:%d", port)
}

// proxyTimeout is the per-request upstream deadline applied by newCBProxy.
// Requests that do not receive a first response header byte within this window
// trigger ErrorHandler, which records a CB failure and writes writeFallback
// instead of the default 502 Bad Gateway.
const proxyTimeout = 5 * time.Second

// newCBProxy constructs a single-host reverse proxy guarded by a circuit breaker.
//
// Request lifecycle:
//  1. cb.Allow() == false → writeFallback (200 degraded); no upstream dial.
//  2. cb.Allow() == true  → request forwarded with a proxyTimeout context deadline.
//  3. Transport error (timeout, refused) → ErrorHandler: RecordFailure + writeFallback.
//  4. Backend HTTP 5xx  → ModifyResponse: RecordFailure, response forwarded unchanged.
//  5. Backend 2xx/3xx/4xx → ModifyResponse: RecordSuccess, response forwarded unchanged.
func newCBProxy(serviceName, target string) http.Handler {
	u, err := url.Parse(target)
	if err != nil {
		log.Fatalf("invalid proxy target %q: %v", target, err)
	}

	cb := getOrCreateCB(serviceName)
	proxy := httputil.NewSingleHostReverseProxy(u)
	proxy.Transport = proxyTransport

	// ModifyResponse: upstream returned a response; classify by HTTP status.
	proxy.ModifyResponse = func(resp *http.Response) error {
		if resp.StatusCode >= 500 {
			cb.RecordFailure()
		} else {
			cb.RecordSuccess()
		}
		return nil
	}

	// ErrorHandler: transport-level error (timeout, connection refused, reset, etc.).
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		cb.RecordFailure()
		writeFallback(w)
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !cb.Allow() {
			writeFallback(w)
			return
		}
		// Bound upstream wait to proxyTimeout so cold-start delays trip the breaker.
		rctx, cancel := context.WithTimeout(r.Context(), proxyTimeout)
		defer cancel()
		proxy.ServeHTTP(w, r.WithContext(rctx))
	})
}

// withCORS wraps a handler to emit CORS headers on every response
// and short-circuit OPTIONS preflight requests before they hit the backend.
func withCORS(h http.Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		h.ServeHTTP(w, r)
	}
}

var (
	db  *sql.DB
	rdb *redis.Client
	ctx = context.Background()

	// 모든 다운스트림 HTTP 호출에 공유되는 클라이언트.
	// 타임아웃 없이 http.Get/Post 를 쓰면 다운스트림 장애 시 고루틴이 영구 블록된다.
	httpClient = &http.Client{Timeout: 5 * time.Second}
)

type SystemLog struct {
	ID        int       `json:"id"`
	Source    string    `json:"source"`
	Message   string    `json:"message"`
	CreatedAt time.Time `json:"created_at"`
}

func main() {
	var err error
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		connStr = "postgres://dev:polyglot@localhost/polyglot_db?sslmode=disable"
	}
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	if err = db.Ping(); err != nil {
		log.Fatal("DB 접속 실패:", err)
	}
	fmt.Println("🐘 PostgreSQL 연결 성공!")

	redisAddr := os.Getenv("REDIS_URL")
	if redisAddr == "" {
		redisAddr = "localhost:6379"
	}
	rdb = redis.NewClient(&redis.Options{
		Addr: redisAddr,
	})

	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatal("Redis 접속 실패:", err)
	}
	fmt.Println("⚡ Redis 연결 성공!")

	http.HandleFunc("/api/status", statusHandler)
	http.HandleFunc("/api/history", historyHandler)
	http.HandleFunc("/api/pipeline/trigger", pipelineTriggerHandler)
	http.HandleFunc("/api/cache/stats", cacheStatsHandler)
	http.HandleFunc("/api/aggregate", aggregateHandler)
	http.HandleFunc("/api/aggregate/stream", aggregateSSEHandler)
	http.HandleFunc("/api/report", reportHandler)
	// 신규
	http.HandleFunc("/api/workflow/risk-full", workflowRiskFullHandler)
	http.HandleFunc("/api/workflow/option-compare", workflowOptionCompareHandler)
	http.HandleFunc("/api/circuit/status", circuitStatusHandler)

	// ── Reverse proxy routes: 22 canonical + 5 role-based aliases = 27 total ──
	// Each route is guarded by newCBProxy (circuit breaker + 5 s context timeout).
	// Role aliases share CB state with their canonical counterpart because
	// getOrCreateCB returns the same instance for the same service-name key.
	// Set SVC_<UPPER_SNAKE> env vars for Docker Compose internal DNS resolution.
	//
	// Canonical routes (one per language service)
	http.Handle("/api/python/", withCORS(newCBProxy("python-brain", resolveBackend("python-brain", portPythonBrain))))
	http.Handle("/api/rust/", withCORS(newCBProxy("rust-pipeline", resolveBackend("rust-pipeline", portRustPipeline))))
	http.Handle("/api/julia/", withCORS(newCBProxy("julia-engine", resolveBackend("julia-engine", portJuliaEngine))))
	http.Handle("/api/r/", withCORS(newCBProxy("r-stats", resolveBackend("r-stats", portRStats))))
	http.Handle("/api/fsharp/", withCORS(newCBProxy("fsharp-pricer", resolveBackend("fsharp-pricer", portFSharpPricer))))
	http.Handle("/api/ocaml/", withCORS(newCBProxy("ocaml-risk", resolveBackend("ocaml-risk", portOCamlRisk))))
	http.Handle("/api/crystal/", withCORS(newCBProxy("crystal-gateway", resolveBackend("crystal-gateway", portCrystalGateway))))
	http.Handle("/api/nim/", withCORS(newCBProxy("nim-analytics", resolveBackend("nim-analytics", portNimAnalytics))))
	http.Handle("/api/scala/", withCORS(newCBProxy("scala-streamer", resolveBackend("scala-streamer", portScalaStreamer))))
	http.Handle("/api/haskell/", withCORS(newCBProxy("haskell-pricer", resolveBackend("haskell-pricer", portHaskellPricer))))
	http.Handle("/api/ruby/", withCORS(newCBProxy("ruby-scorer", resolveBackend("ruby-scorer", portRubyScorer))))
	http.Handle("/api/dart/", withCORS(newCBProxy("dart-engine", resolveBackend("dart-engine", portDartEngine))))
	http.Handle("/api/gleam/", withCORS(newCBProxy("gleam-hub", resolveBackend("gleam-hub", portGleamHub))))
	http.Handle("/api/v/", withCORS(newCBProxy("v-quant", resolveBackend("v-quant", portVQuant))))
	http.Handle("/api/erlang/", withCORS(newCBProxy("erlang-hot", resolveBackend("erlang-hot", portErlangHot))))
	http.Handle("/api/elixir/", withCORS(newCBProxy("elixir-hub", resolveBackend("elixir-hub", portElixirHub))))
	http.Handle("/api/clojure/", withCORS(newCBProxy("clojure-stm", resolveBackend("clojure-stm", portClojureSTM))))
	http.Handle("/api/java/", withCORS(newCBProxy("java-loom", resolveBackend("java-loom", portJavaLoom))))
	http.Handle("/api/prolog/", withCORS(newCBProxy("prolog-solver", resolveBackend("prolog-solver", portPrologSolver))))
	http.Handle("/api/lua/", withCORS(newCBProxy("lua-stream", resolveBackend("lua-stream", portLuaStream))))
	http.Handle("/api/swift/", withCORS(newCBProxy("swift-actor", resolveBackend("swift-actor", portSwiftActor))))
	http.Handle("/api/kotlin/", withCORS(newCBProxy("kotlin-scheduler", resolveBackend("kotlin-scheduler", portKotlinScheduler))))
	// Role-based aliases (share CB state with canonical routes via same service-name key)
	http.Handle("/api/risk/", withCORS(newCBProxy("ocaml-risk", resolveBackend("ocaml-risk", portOCamlRisk))))
	http.Handle("/api/pricer/", withCORS(newCBProxy("fsharp-pricer", resolveBackend("fsharp-pricer", portFSharpPricer))))
	http.Handle("/api/analytics/", withCORS(newCBProxy("nim-analytics", resolveBackend("nim-analytics", portNimAnalytics))))
	http.Handle("/api/ledger/", withCORS(newCBProxy("clojure-stm", resolveBackend("clojure-stm", portClojureSTM))))
	http.Handle("/api/scheduler/", withCORS(newCBProxy("kotlin-scheduler", resolveBackend("kotlin-scheduler", portKotlinScheduler))))

	fmt.Println("Go Backend Server running on port 8080...")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	_, dbErr := db.Exec("INSERT INTO system_logs (source, message) VALUES ($1, $2)", "Go-Backend", "Status requested")
	dbStatus := "connected"
	if dbErr != nil {
		log.Println("DB 기록 실패:", dbErr)
		dbStatus = "error"
	}

	var engineData map[string]interface{}
	cacheKey := "engine_analysis_cache"
	hitCountKey := "cache_hit_count"
	missCountKey := "cache_miss_count"

	// Lua 스크립트: GET + 히트 카운터 증가를 원자적으로 처리
	luaGetAndCount := redis.NewScript(`
		local val = redis.call('GET', KEYS[1])
		if val then
			redis.call('INCR', KEYS[2])
			return val
		else
			redis.call('INCR', KEYS[3])
			return false
		end
	`)

	result, luaErr := luaGetAndCount.Run(ctx, rdb, []string{cacheKey, hitCountKey, missCountKey}).Result()

	if luaErr == nil && result != nil {
		json.Unmarshal([]byte(result.(string)), &engineData)
		fmt.Println("Cache Hit! [Lua atomic] (Redis에서 즉시 반환)")
		engineData["source"] = "Redis Cache (Lua)"
	} else {
		fmt.Println("Cache MISS! [Lua atomic] (Python 엔진 호출)")
		respPy, err := httpClient.Get("http://localhost:8000/api/analyze")
		if err == nil {
			defer respPy.Body.Close()
			json.NewDecoder(respPy.Body).Decode(&engineData)
			engineData["source"] = "Python Engine"
			jsonData, _ := json.Marshal(engineData)
			// Lua 스크립트: SET + TTL을 원자적으로 처리
			luaSetWithTTL := redis.NewScript(`
				redis.call('SET', KEYS[1], ARGV[1])
				redis.call('EXPIRE', KEYS[1], ARGV[2])
				return 1
			`)
			luaSetWithTTL.Run(ctx, rdb, []string{cacheKey}, string(jsonData), "10")
		} else {
			engineData = map[string]interface{}{"message": "Engine is offline"}
		}
	}

	var rustData map[string]interface{}
	rustResp, rustErr := httpClient.Get("http://localhost:8081/api/rust/status")
	if rustErr == nil {
		defer rustResp.Body.Close()
		json.NewDecoder(rustResp.Body).Decode(&rustData)
	} else {
		rustData = map[string]interface{}{
			"status":  "offline",
			"message": "Rust Pipeline is down",
		}
	}

	response := map[string]interface{}{
		"system":          "Go-Backend-v1",
		"status":          "online",
		"database":        dbStatus,
		"engine_analysis": engineData,
		"pipeline_node":   rustData, // Svelte로 Rust 데이터 전달
	}

	json.NewEncoder(w).Encode(response)
}

func pipelineTriggerHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"Method Not Allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	resp, err := httpClient.Post("http://localhost:8081/api/bulk-insert", "application/json", nil)
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "error",
			"message": "Rust Pipeline is unreachable",
		})
		return
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	_, _ = db.Exec("INSERT INTO system_logs (source, message) VALUES ($1, $2)",
		"Rust-Pipeline", fmt.Sprintf("Bulk insert triggered: %v rows", result["inserted_rows"]))

	json.NewEncoder(w).Encode(result)
}

func cacheStatsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	// Lua 스크립트: hit/miss 카운터를 원자적으로 동시 조회
	luaGetStats := redis.NewScript(`
		local hits  = redis.call('GET', KEYS[1]) or '0'
		local misses = redis.call('GET', KEYS[2]) or '0'
		return {hits, misses}
	`)
	res, err := luaGetStats.Run(ctx, rdb, []string{"cache_hit_count", "cache_miss_count"}).StringSlice()
	hits, misses := "0", "0"
	if err == nil && len(res) == 2 {
		hits, misses = res[0], res[1]
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"engine":       "Lua (Redis EVAL)",
		"cache_hits":   hits,
		"cache_misses": misses,
	})
}

// aggregateHandler: 전체 백엔드 /health 를 병렬 호출해 집계를 반환한다.
// 각 백엔드 호출은 독립 고루틴으로 실행되고, WaitGroup으로 합산한다.
// 타임아웃은 httpClient(5s)가 보장하므로 개별 블록 없음.
func aggregateHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	type ServiceInfo struct {
		Name      string `json:"name"`
		Port      int    `json:"port"`
		HealthURL string `json:"-"`
	}

	services := []ServiceInfo{
		{"Python-Brain", 8000, "http://localhost:8000/health"},
		{"Rust-Pipeline", 8081, "http://localhost:8081/health"},
		{"Julia-Engine", 8002, "http://localhost:8002/health"},
		{"R-Stats", 8003, "http://localhost:8003/health"},
		{"FSharp-Pricer", 9001, "http://localhost:9001/health"},
		{"OCaml-Risk", 8004, "http://localhost:8004/health"},
		{"Crystal-Gateway", 9002, "http://localhost:9002/health"},
		{"Nim-Analytics", 8005, "http://localhost:8005/health"},
		{"Scala-Streamer", 9003, "http://localhost:9003/health"},
		{"Haskell-Pricer", 8006, "http://localhost:8006/health"},
		{"Ruby-Scorer", 9004, "http://localhost:9004/health"},
		{"Dart-Engine", 9005, "http://localhost:9005/health"},
		{"Gleam-Hub", 4001, "http://localhost:4001/health"},
		{"V-Quant", 4002, "http://localhost:4002/health"},
		{"Erlang-Hot", 4003, "http://localhost:4003/health"},
		{"Kotlin-Scheduler", 9000, "http://localhost:9000/health"},
		{"Elixir-Hub", 4000, "http://localhost:4000/health"},
		{"Swift-Actor", 8008, "http://localhost:8008/health"},
		{"Lua-Stream", 8007, "http://localhost:8007/health"},
		{"Clojure-STM", 8009, "http://localhost:8009/health"},
		{"Java-Loom", 8010, "http://localhost:8010/health"},
		{"Prolog-Solver", 8011, "http://localhost:8011/health"},
	}

	type Result struct {
		Name      string `json:"name"`
		Port      int    `json:"port"`
		Status    string `json:"status"`
		LatencyMs int64  `json:"latency_ms"`
	}

	results := make([]Result, len(services))
	var wg sync.WaitGroup

	for i, svc := range services {
		wg.Add(1)
		go func(idx int, s ServiceInfo) {
			defer wg.Done()
			start := time.Now()
			resp, err := httpClient.Get(s.HealthURL)
			latency := time.Since(start).Milliseconds()
			status := "offline"
			if err == nil {
				resp.Body.Close()
				if resp.StatusCode == 200 {
					status = "online"
				}
			}
			results[idx] = Result{
				Name:      s.Name,
				Port:      s.Port,
				Status:    status,
				LatencyMs: latency,
			}
		}(i, svc)
	}

	wg.Wait()

	online := 0
	for _, r := range results {
		if r.Status == "online" {
			online++
		}
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"engine":   "Go-Aggregate-v1",
		"total":    len(results),
		"online":   online,
		"offline":  len(results) - online,
		"services": results,
	})
}

func historyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	rows, err := db.Query("SELECT id, source, message, created_at FROM system_logs ORDER BY id DESC LIMIT 10")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var logs []SystemLog
	for rows.Next() {
		var l SystemLog
		if err := rows.Scan(&l.ID, &l.Source, &l.Message, &l.CreatedAt); err != nil {
			continue
		}
		logs = append(logs, l)
	}
	json.NewEncoder(w).Encode(logs)
}

// aggregateSSEHandler — /api/aggregate/stream
// Server-Sent Events: 클라이언트에게 10초마다 전체 서비스 헬스를 push한다.
func aggregateSSEHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "SSE not supported", http.StatusInternalServerError)
		return
	}

	sendAggregate := func() bool {
		data, err := buildAggregate()
		if err != nil {
			return false
		}
		b, _ := json.Marshal(data)
		fmt.Fprintf(w, "data: %s\n\n", b)
		flusher.Flush()
		return true
	}

	sendAggregate()

	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-r.Context().Done():
			return
		case <-ticker.C:
			if !sendAggregate() {
				return
			}
		}
	}
}

// buildAggregate — aggregateHandler 와 SSE 핸들러가 공유하는 핵심 로직
func buildAggregate() (map[string]interface{}, error) {
	type ServiceInfo struct {
		Name      string
		Port      int
		HealthURL string
	}
	services := []ServiceInfo{
		{"Python-Brain", 8000, "http://localhost:8000/health"},
		{"Rust-Pipeline", 8081, "http://localhost:8081/health"},
		{"Julia-Engine", 8002, "http://localhost:8002/health"},
		{"R-Stats", 8003, "http://localhost:8003/health"},
		{"FSharp-Pricer", 9001, "http://localhost:9001/health"},
		{"OCaml-Risk", 8004, "http://localhost:8004/health"},
		{"Crystal-Gateway", 9002, "http://localhost:9002/health"},
		{"Nim-Analytics", 8005, "http://localhost:8005/health"},
		{"Scala-Streamer", 9003, "http://localhost:9003/health"},
		{"Haskell-Pricer", 8006, "http://localhost:8006/health"},
		{"Ruby-Scorer", 9004, "http://localhost:9004/health"},
		{"Dart-Engine", 9005, "http://localhost:9005/health"},
		{"Gleam-Hub", 4001, "http://localhost:4001/health"},
		{"V-Quant", 4002, "http://localhost:4002/health"},
		{"Erlang-Hot", 4003, "http://localhost:4003/health"},
		{"Kotlin-Scheduler", 9000, "http://localhost:9000/health"},
		{"Elixir-Hub", 4000, "http://localhost:4000/health"},
		{"Swift-Actor", 8008, "http://localhost:8008/health"},
		{"Lua-Stream", 8007, "http://localhost:8007/health"},
		{"Clojure-STM", 8009, "http://localhost:8009/health"},
		{"Java-Loom", 8010, "http://localhost:8010/health"},
		{"Prolog-Solver", 8011, "http://localhost:8011/health"},
	}

	type Result struct {
		Name      string `json:"name"`
		Port      int    `json:"port"`
		Status    string `json:"status"`
		LatencyMs int64  `json:"latency_ms"`
	}

	results := make([]Result, len(services))
	var wg sync.WaitGroup
	for i, svc := range services {
		wg.Add(1)
		go func(idx int, s ServiceInfo) {
			defer wg.Done()
			start := time.Now()
			resp, err := httpClient.Get(s.HealthURL)
			latency := time.Since(start).Milliseconds()
			status := "offline"
			if err == nil {
				resp.Body.Close()
				if resp.StatusCode == 200 {
					status = "online"
				}
			}
			results[idx] = Result{s.Name, s.Port, status, latency}
		}(i, svc)
	}
	wg.Wait()

	online := 0
	for _, r := range results {
		if r.Status == "online" {
			online++
		}
	}
	return map[string]interface{}{
		"engine":    "Go-Aggregate-v1",
		"total":     len(results),
		"online":    online,
		"offline":   len(results) - online,
		"services":  results,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	}, nil
}

// reportHandler — /api/report
// 주요 분석 서비스에서 데이터를 동시 수집해 통합 리스크 리포트를 반환한다.
func reportHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	type fetchResult struct {
		key  string
		data map[string]interface{}
	}

	endpoints := []struct {
		key string
		url string
	}{
		{"rust_risk", "http://localhost:8081/api/risk/summary"},
		{"python_analysis", "http://localhost:8000/api/analyze"},
		{"julia_mc", "http://localhost:8002/api/julia/simulate?paths=50&days=252&vol=0.20&mu=0.05"},
		{"r_stats", "http://localhost:8003/api/r/stats"},
		{"ocaml_risk", "http://localhost:8004/api/ocaml/risk"},
		{"haskell_mc", "http://localhost:8006/api/haskell/montecarlo?s=100&vol=0.2&mu=0.05&n=500&days=252"},
	}

	ch := make(chan fetchResult, len(endpoints))
	for _, ep := range endpoints {
		go func(key, url string) {
			var data map[string]interface{}
			resp, err := httpClient.Get(url)
			if err == nil {
				defer resp.Body.Close()
				json.NewDecoder(resp.Body).Decode(&data)
			} else {
				data = map[string]interface{}{"status": "offline"}
			}
			ch <- fetchResult{key, data}
		}(ep.key, ep.url)
	}

	report := map[string]interface{}{
		"generated_at": time.Now().UTC().Format(time.RFC3339),
		"engine":       "Go-Unified-Report-v1",
	}
	for range endpoints {
		r := <-ch
		report[r.key] = r.data
	}

	_, _ = db.Exec("INSERT INTO system_logs (source, message) VALUES ($1, $2)",
		"Go-Report", fmt.Sprintf("Unified report generated at %s", report["generated_at"]))

	json.NewEncoder(w).Encode(report)
}

// ── workflowRiskFullHandler — /api/workflow/risk-full ───────────────────────
// Python 분석 → Rust 저장 → Rust VaR → Kotlin 리포트 → Nim GARCH 파이프라인
// 각 단계는 순차적으로 실행되며, 이전 단계 결과가 다음 단계에 전달된다.
func workflowRiskFullHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	t0 := time.Now()
	steps := []map[string]interface{}{}
	overallStatus := "ok"

	// Step 1: Python 분석 (리스크 계산)
	step1 := map[string]interface{}{"step": 1, "service": "Python-Brain", "action": "analyze"}
	var pyData map[string]interface{}
	resp1, err := cbGet("Python-Brain", "http://localhost:8000/api/analyze")
	if err == nil {
		defer resp1.Body.Close()
		json.NewDecoder(resp1.Body).Decode(&pyData)
		step1["status"] = "ok"
		step1["data"] = pyData
	} else {
		step1["status"] = "error"
		step1["error"] = err.Error()
		overallStatus = "partial"
	}
	steps = append(steps, step1)

	// Step 2: Rust 벌크 인서트 (데이터 영구 저장)
	step2 := map[string]interface{}{"step": 2, "service": "Rust-Pipeline", "action": "bulk-insert"}
	var rustData map[string]interface{}
	resp2, err := httpClient.Post("http://localhost:8081/api/bulk-insert", "application/json", nil)
	if err == nil {
		defer resp2.Body.Close()
		json.NewDecoder(resp2.Body).Decode(&rustData)
		step2["status"] = "ok"
		step2["data"] = rustData
	} else {
		step2["status"] = "error"
		step2["error"] = err.Error()
		overallStatus = "partial"
	}
	steps = append(steps, step2)

	// Step 3: Rust VaR 요약 (저장된 데이터 집계)
	step3 := map[string]interface{}{"step": 3, "service": "Rust-Pipeline", "action": "risk-summary"}
	var summaryData map[string]interface{}
	resp3, err := cbGet("Rust-Pipeline", "http://localhost:8081/api/risk/summary")
	if err == nil {
		defer resp3.Body.Close()
		json.NewDecoder(resp3.Body).Decode(&summaryData)
		step3["status"] = "ok"
		step3["data"] = summaryData
	} else {
		step3["status"] = "error"
		step3["error"] = err.Error()
		overallStatus = "partial"
	}
	steps = append(steps, step3)

	// Step 4: Kotlin 리포트 생성
	step4 := map[string]interface{}{"step": 4, "service": "Kotlin-Scheduler", "action": "report-now"}
	var reportData map[string]interface{}
	resp4, err := cbGet("Kotlin-Scheduler", "http://localhost:9000/api/reports/now")
	if err == nil {
		defer resp4.Body.Close()
		json.NewDecoder(resp4.Body).Decode(&reportData)
		step4["status"] = "ok"
		step4["data"] = reportData
	} else {
		step4["status"] = "error"
		step4["error"] = err.Error()
		overallStatus = "partial"
	}
	steps = append(steps, step4)

	// Step 5: Nim GARCH 변동성 추정
	step5 := map[string]interface{}{"step": 5, "service": "Nim-Analytics", "action": "garch"}
	var nimData map[string]interface{}
	resp5, err := cbGet("Nim-Analytics", "http://localhost:8005/api/nim/garch?omega=0.000001&alpha=0.1&beta=0.85&n=252")
	if err == nil {
		defer resp5.Body.Close()
		json.NewDecoder(resp5.Body).Decode(&nimData)
		step5["status"] = "ok"
		step5["data"] = nimData
	} else {
		step5["status"] = "error"
		step5["error"] = err.Error()
		overallStatus = "partial"
	}
	steps = append(steps, step5)

	elapsed := time.Since(t0).Milliseconds()

	// Redis Pub/Sub 이벤트 발행 — Elixir가 구독해서 Phoenix Channel로 브로드캐스트
	eventPayload, _ := json.Marshal(map[string]interface{}{
		"event":      "risk-full-completed",
		"status":     overallStatus,
		"elapsed_ms": elapsed,
		"timestamp":  time.Now().UTC().Format(time.RFC3339),
	})
	rdb.Publish(ctx, "polyglot:events", string(eventPayload))

	_, _ = db.Exec("INSERT INTO system_logs (source, message) VALUES ($1, $2)",
		"Go-Workflow", fmt.Sprintf("risk-full pipeline completed in %dms status=%s", elapsed, overallStatus))

	json.NewEncoder(w).Encode(map[string]interface{}{
		"workflow":     "risk-full",
		"status":       overallStatus,
		"elapsed_ms":   elapsed,
		"steps":        steps,
		"engine":       "Go-Workflow-v2",
		"completed_at": time.Now().UTC().Format(time.RFC3339),
	})
}

// ── workflowOptionCompareHandler — /api/workflow/option-compare ─────────────
// F#, Haskell, Python(Zig FFI) 3개 엔진의 Black-Scholes 결과를 병렬로 수집·비교
func workflowOptionCompareHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	q := r.URL.Query()
	s := q.Get("s")
	if s == "" {
		s = "100"
	}
	k := q.Get("k")
	if k == "" {
		k = "100"
	}
	sigma := q.Get("sigma")
	if sigma == "" {
		sigma = "0.20"
	}
	t := q.Get("t")
	if t == "" {
		t = "1.0"
	}
	rRate := q.Get("r")
	if rRate == "" {
		rRate = "0.05"
	}

	type engineResult struct {
		engine string
		data   map[string]interface{}
		ms     int64
		err    string
	}

	engines := []struct {
		name string
		url  string
	}{
		{"F#", fmt.Sprintf("http://localhost:9001/api/fsharp/option?s=%s&k=%s&r=%s&sigma=%s&t=%s", s, k, rRate, sigma, t)},
		{"Haskell", fmt.Sprintf("http://localhost:8006/api/haskell/blackscholes?s=%s&k=%s&r=%s&sigma=%s&t=%s", s, k, rRate, sigma, t)},
		{"Python+ZigFFI", "http://localhost:8000/api/analyze"},
	}

	ch := make(chan engineResult, len(engines))
	for _, eng := range engines {
		go func(name, url string) {
			ts := time.Now()
			resp, err := cbGet(name, url)
			ms := time.Since(ts).Milliseconds()
			if err != nil {
				ch <- engineResult{engine: name, err: err.Error(), ms: ms}
				return
			}
			defer resp.Body.Close()
			var data map[string]interface{}
			json.NewDecoder(resp.Body).Decode(&data)
			ch <- engineResult{engine: name, data: data, ms: ms}
		}(eng.name, eng.url)
	}

	results := map[string]interface{}{}
	for range engines {
		r := <-ch
		if r.err != "" {
			results[r.engine] = map[string]interface{}{"status": "error", "error": r.err, "latency_ms": r.ms}
		} else {
			results[r.engine] = map[string]interface{}{"status": "ok", "data": r.data, "latency_ms": r.ms}
		}
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"workflow": "option-compare",
		"params":   map[string]string{"s": s, "k": k, "sigma": sigma, "t": t, "r": rRate},
		"engines":  results,
		"engine":   "Go-Workflow-v1",
	})
}

// ── circuitStatusHandler — /api/circuit/status ───────────────────────────────
// 모든 서킷 브레이커 상태 조회
func circuitStatusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	stateNames := []string{"closed", "open", "half-open"}

	cbMu.RLock()
	defer cbMu.RUnlock()

	breakers := map[string]interface{}{}
	for name, cb := range circuitBreakers {
		state := atomic.LoadInt32(&cb.state)
		stateName := "closed"
		if int(state) < len(stateNames) {
			stateName = stateNames[state]
		}
		breakers[name] = map[string]interface{}{
			"state":     stateName,
			"failures":  atomic.LoadInt32(&cb.failures),
			"successes": atomic.LoadInt32(&cb.successes),
		}
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"circuit_breakers": breakers,
		"engine":           "Go-CircuitBreaker-v1",
	})
}
