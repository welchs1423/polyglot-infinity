package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
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
	cb = &CircuitBreaker{name: name, threshold: 3, resetAfter: 30 * time.Second}
	circuitBreakers[name] = cb
	return cb
}

func (cb *CircuitBreaker) Allow() bool {
	state := atomic.LoadInt32(&cb.state)
	if state == cbClosed {
		return true
	}
	if state == cbOpen {
		cb.mu.Lock()
		if time.Since(cb.lastFailure) > cb.resetAfter {
			atomic.StoreInt32(&cb.state, cbHalfOpen)
			cb.mu.Unlock()
			return true
		}
		cb.mu.Unlock()
		return false
	}
	// HalfOpen: 1회 허용
	return true
}

func (cb *CircuitBreaker) RecordSuccess() {
	atomic.StoreInt32(&cb.failures, 0)
	atomic.StoreInt32(&cb.successes, atomic.LoadInt32(&cb.successes)+1)
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

// cbGet — 서킷 브레이커를 통한 HTTP GET
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
	connStr := "postgres://dev:polyglot@localhost/polyglot_db?sslmode=disable"
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	if err = db.Ping(); err != nil {
		log.Fatal("DB 접속 실패:", err)
	}
	fmt.Println("🐘 PostgreSQL 연결 성공!")

	rdb = redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
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
// Python 분석 → Rust 저장 → Kotlin 리포트 엔드-투-엔드 파이프라인
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
		"engine":       "Go-Workflow-v1",
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
		{"Python+ZigFFI", fmt.Sprintf("http://localhost:8000/api/analyze")},
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
