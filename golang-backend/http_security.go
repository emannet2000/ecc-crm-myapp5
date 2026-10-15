package main

import (
	"net/http"
	"strings"
	"sync"
	"time"
)

type requestWindow struct {
	Start time.Time
	Count int
}

var rateMu sync.Mutex
var rateWindows = map[string]requestWindow{}

func protectHTTP(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")
		w.Header().Set("X-Frame-Options", "SAMEORIGIN")
		w.Header().Set("Permissions-Policy", "camera=(self), microphone=(), geolocation=()")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-src 'self'; frame-ancestors 'self'; base-uri 'self'; object-src 'none'; form-action 'self' https:")
		if strings.HasPrefix(r.URL.Path, "/api/") {
			w.Header().Set("Cache-Control", "no-store")
			limit := 600
			key := requestIP(r)
			if r.URL.Path == "/api/portal/session" || r.URL.Path == "/api/login" || r.URL.Path == "/api/register" || r.URL.Path == "/api/forgot-password" || r.URL.Path == "/api/reset-password" || r.URL.Path == "/api/sso/finish" {
				limit = 20
				key = "auth:" + key
			}
			rateMu.Lock()
			now := time.Now()
			window := rateWindows[key]
			if now.Sub(window.Start) > time.Minute {
				window = requestWindow{Start: now}
			}
			window.Count++
			rateWindows[key] = window
			if len(rateWindows) > 10000 {
				for k, v := range rateWindows {
					if now.Sub(v.Start) > 2*time.Minute {
						delete(rateWindows, k)
					}
				}
			}
			rateMu.Unlock()
			if window.Count > limit {
				w.Header().Set("Retry-After", "60")
				writeError(w, 429, "Too many requests. Wait one minute and retry.")
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
