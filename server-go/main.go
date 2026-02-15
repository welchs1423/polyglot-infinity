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

func statusHandler(w http.ResponseWriter, r *http.Request){
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	resp, err := http.Get("http://localhost:8080/api/analyze")
	var brainData map[string]interface{}

	if err == nil {
		defer resp.Body.Close()
		json.NewDecoder(resp.Body).Decode(&brainData)
	} else {
		brainData = map[string]interface{}{"message": "Brain is offline"}
	}

	response := map[string]interface{}{
		"engine" : "Go-Hunter-v1",
		"status" : "online",
		"brain_analysis": brainData,
	}

	json.NewEncoder(w).Encode(response)
}