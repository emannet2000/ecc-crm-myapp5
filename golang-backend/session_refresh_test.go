package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestSessionRefreshConcurrentClients(t *testing.T) {
	setupStore(t)
	h := featureMux()
	original := demoCookies(t, h)
	// Exercise independent SQL connections, as separate app processes would.
	database.SetMaxOpenConns(4)
	results := make(chan *httptest.ResponseRecorder, 6)
	start := make(chan struct{})
	for i := 0; i < 6; i++ {
		go func() {
			<-start
			r := httptest.NewRequest("POST", "/api/session/refresh", nil)
			for _, cookie := range original {
				r.AddCookie(cookie)
			}
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			results <- w
		}()
	}
	close(start)
	var next []*http.Cookie
	for i := 0; i < 6; i++ {
		w := <-results
		assertStatus(t, w, 200)
		actual := w.Result().Cookies()
		if len(actual) != 2 {
			t.Fatal("missing refreshed cookies")
		}
		if next == nil {
			next = actual
		}
		for j := range next {
			if next[j].Value != actual[j].Value {
				t.Fatal("competing refresh invalidated another client's cookies")
			}
		}
	}
	assertStatus(t, featureRequest(h, "GET", "/api/me", nil, next), 200)
	repeated := featureRequest(h, "POST", "/api/session/refresh", nil, next)
	assertStatus(t, repeated, 200)
	for i, cookie := range repeated.Result().Cookies() {
		if cookie.Value != next[i].Value {
			t.Fatal("current token rotated again during the grace window")
		}
	}
	var encrypted, deadline string
	if err := database.QueryRow("SELECT cookies,expires_at FROM session_refresh_grace").Scan(&encrypted, &deadline); err != nil {
		t.Fatal(err)
	}
	for _, cookie := range next {
		if strings.Contains(encrypted, cookie.Value) {
			t.Fatal("cookie stored in plaintext")
		}
	}
	repeated = featureRequest(h, "POST", "/api/session/refresh", nil, original)
	assertStatus(t, repeated, 200)
	var unchanged string
	if err := database.QueryRow("SELECT expires_at FROM session_refresh_grace").Scan(&unchanged); err != nil {
		t.Fatal(err)
	}
	if deadline != unchanged {
		t.Fatal("replay extended the grace period")
	}
	assertStatus(t, featureRequest(h, "POST", "/api/session/logout", nil, next), 200)
	rejected := featureRequest(h, "POST", "/api/session/refresh", nil, original)
	assertStatus(t, rejected, 401)
	if len(rejected.Result().Cookies()) != 0 {
		t.Fatal("rejected request cleared shared cookies")
	}
	assertStatus(t, featureRequest(h, "POST", "/api/session/refresh", nil, next), 401)
}

func TestSessionRefreshFailureRollsBackRotation(t *testing.T) {
	setupStore(t)
	h := featureMux()
	cookies := demoCookies(t, h)
	if _, err := database.Exec(`CREATE TRIGGER reject_refresh_grace BEFORE INSERT ON session_refresh_grace BEGIN SELECT RAISE(ABORT,'test failure'); END`); err != nil {
		t.Fatal(err)
	}
	w := featureRequest(h, "POST", "/api/session/refresh", nil, cookies)
	assertStatus(t, w, 500)
	if len(w.Result().Cookies()) != 0 {
		t.Fatal("failed rotation issued cookies")
	}
	assertStatus(t, featureRequest(h, "GET", "/api/me", nil, cookies), 200)
	if _, err := database.Exec("DROP TRIGGER reject_refresh_grace"); err != nil {
		t.Fatal(err)
	}
	assertStatus(t, featureRequest(h, "POST", "/api/session/refresh", nil, cookies), 200)
	if _, err := database.Exec("UPDATE sessions SET refresh_expires_at=?", time.Now().Add(-time.Second).UTC().Format(time.RFC3339)); err != nil {
		t.Fatal(err)
	}
	assertStatus(t, featureRequest(h, "POST", "/api/session/refresh", nil, cookies), 401)
}
