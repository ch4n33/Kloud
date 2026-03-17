package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"time"
)

type Response struct {
	Hostname  string `json:"hostname"`
	Timestamp string `json:"timestamp"`
	Arch      string `json:"arch"`
}

func main() {
	hostname, _ := os.Hostname()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		resp := Response{
			Hostname:  hostname,
			Timestamp: time.Now().Format(time.RFC3339),
			Arch:      runtime.GOARCH,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "ok")
	})

	fmt.Println("Listening on :8080")
	http.ListenAndServe(":8080", nil)
}
