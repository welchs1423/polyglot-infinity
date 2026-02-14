package main

import (
	"encoding/json"
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Content-Type", "application/json")

		data := map[string]interface{}{
			"status": "online",
			"engine": "Go-Hunter-v1",
			"power":  100,
		}

		json.NewEncoder(w).Encode(data)
	})

	fmt.Println("Go 서버가 8080 포트에서 시작했습니다!")
	http.ListenAndServe(":8080", nil)
}