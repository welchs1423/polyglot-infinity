package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
)

var (
	db  *sql.DB
	rdb *redis.Client
	ctx = context.Background()
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
	val, err := rdb.Get(ctx, cacheKey).Result()

	if err == nil {
		json.Unmarshal([]byte(val), &engineData)
		fmt.Println("Cache Hit! (Redis에서 즉시 반환)")
		engineData["source"] = "Redis Cache"
	} else {
		fmt.Println("Cache MISS! (Python 엔진 호출)")
		resp, err := http.Get("http://localhost:8000/api/analyze")

		if err == nil {
			defer resp.Body.Close()
			json.NewDecoder(resp.Body).Decode(&engineData)
			engineData["source"] = "Python Engine"
			jsonData, _ := json.Marshal(engineData)
			rdb.Set(ctx, cacheKey, jsonData, 10*time.Second)
		} else {
			engineData = map[string]interface{}{"message": "Engine is offline"}
		}
	}

	var rustData map[string]interface{}
	rustResp, rustErr := http.Get("http://localhost:8081/api/rust/status")
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
