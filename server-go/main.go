package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
)

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
