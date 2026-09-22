package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

var (
	rootDir   string
	port      string
	authToken string
)

type RequestData struct {
	Cmd  string   `json:"cmd"`
	Args []string `json:"args"`
}

type ResponseData struct {
	Output string `json:"output"`
	Error  string `json:"error"`
}

func generateToken() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("auth")
		if token == "" {
			cookie, err := r.Cookie("auth_token")
			if err == nil {
				token = cookie.Value
			}
		}

		if token != authToken {
			http.Error(w, "Unauthorized access", http.StatusUnauthorized)
			return
		}

		if r.URL.Query().Get("auth") != "" {
			http.SetCookie(w, &http.Cookie{
				Name:     "auth_token",
				Value:    authToken,
				Path:     "/",
				HttpOnly: true,
				SameSite: http.SameSiteStrictMode,
			})
		}
		next(w, r)
	}
}

func runHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req RequestData
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	var cmd *exec.Cmd
	fullCmd := req.Cmd + " " + strings.Join(req.Args, " ")
	if runtime.GOOS == "windows" {
		cmd = exec.Command("powershell", "-Command", fullCmd)
	} else {
		cmd = exec.Command("bash", "-c", fullCmd)
	}

	out, err := cmd.CombinedOutput()
	
	resp := ResponseData{Output: string(out)}
	if err != nil {
		resp.Error = err.Error()
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func main() {
	flag.StringVar(&rootDir, "root", "./ui", "Path to UI directory")
	flag.StringVar(&port, "port", "9999", "Port to listen on")
	flag.Parse()

	rootDir = filepath.FromSlash(rootDir)
	authToken = generateToken()

	http.HandleFunc("/api/run", authMiddleware(runHandler))
	
	fs := http.FileServer(http.Dir(rootDir))
	http.Handle("/", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" {
			fs.ServeHTTP(w, r)
			return
		}
		path := filepath.Join(rootDir, filepath.FromSlash(r.URL.Path))
		if _, err := os.Stat(path); os.IsNotExist(err) {
			http.NotFound(w, r)
			return
		}
		fs.ServeHTTP(w, r)
	}))

	listener, err := net.Listen("tcp", "127.0.0.1:"+port)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	actualPort := listener.Addr().(*net.TCPAddr).Port
	
	fmt.Printf("\n--- Se-Go INFRASTRUCTURE READY ---\n")
	fmt.Printf("OS: %s | ARCH: %s\n", runtime.GOOS, runtime.GOARCH)
	fmt.Printf("ROOT: %s\n", rootDir)
	fmt.Printf("URL: http://127.0.0.1:%d/?auth=%s\n", actualPort, authToken)
	fmt.Printf("----------------------------------\n")

	server := &http.Server{
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}
	server.Serve(listener)
}