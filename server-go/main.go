package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	_ "github.com/lib/pq"
)

var db *sql.DB

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

	// 4. 핸들러 등록
	http.HandleFunc("/api/status", statusHandler)
	http.HandleFunc("/api/history", historyHandler)

	fmt.Println("🏹 Go Hunter Server running on port 8080...")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	// CORS 설정
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	query := `INSERT INTO system_logs (source, message) VALUES ($1, $2)`
	_, dbErr := db.Exec(query, "Go-Hunter", "Client requested status check")

	dbStatus := "connected"
	if dbErr != nil {
		log.Println("DB 기록 실패:", dbErr)
		dbStatus = "error_writing_log"
	}

	resp, err := http.Get("http://localhost:8000/api/analyze")
	var brainData map[string]interface{}
	if err == nil {
		defer resp.Body.Close()
		json.NewDecoder(resp.Body).Decode(&brainData)
	} else {
		brainData = map[string]interface{}{"message": "Brain is offline"}
	}

	response := map[string]interface{}{
		"engine":         "Go-Hunter-v1",
		"status":         "online",
		"database":       dbStatus, // DB 상태 추가
		"brain_analysis": brainData,
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
			log.Println("데이터 스캔 오류:", err)
			continue
		}
		logs = append(logs, l)
	}
	json.NewEncoder(w).Encode(logs)
}
