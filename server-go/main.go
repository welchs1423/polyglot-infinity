package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	_ "github.com/lib/pq" // Postgres 드라이버
)

var db *sql.DB

func main() {
	var err error
	// 1. DB 접속 정보 (Connection String)
	// sslmode=disable : 로컬 개발환경이라 보안 인증서 무시
	connStr := "postgres://dev:polyglot@localhost/polyglot_db?sslmode=disable"

	// 2. DB 연결 시도
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close() // 메인 함수 끝나면 DB 연결 끊기

	if err = db.Ping(); err != nil {
		log.Fatal("DB 접속 실패:", err)
	}
	fmt.Println("🐘 PostgreSQL(The Memory) 연결 성공!")

	// 4. 핸들러 등록
	http.HandleFunc("/api/status", statusHandler)

	fmt.Println("🏹 Go Hunter Server running on port 8080...")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	// CORS 설정
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	// SQL Injection 방지를 위해 $1, $2 파라미터 사용
	query := `INSERT INTO system_logs (source, message) VALUES ($1, $2)`
	_, dbErr := db.Exec(query, "Go-Hunter", "Client requested status check")

	dbStatus := "connected"
	if dbErr != nil {
		log.Println("DB 기록 실패:", dbErr)
		dbStatus = "error_writing_log"
	} else {
		fmt.Println("📝 DB에 로그 기록 완료!")
	}

	resp, err := http.Get("http://localhost:8000/api/analyze")
	var brainData map[string]interface{}

	if err == nil {
		defer resp.Body.Close()
		json.NewDecoder(resp.Body).Decode(&brainData)
	} else {
		brainData = map[string]interface{}{"message": "Brain is offline"}
	}

	// 최종 응답
	response := map[string]interface{}{
		"engine":         "Go-Hunter-v1",
		"status":         "online",
		"database":       dbStatus, // DB 상태 추가
		"brain_analysis": brainData,
	}

	json.NewEncoder(w).Encode(response)
}
