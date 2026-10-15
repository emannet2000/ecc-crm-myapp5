package main

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestProfileUpdateRetainsSessionAndCannotUndoLogout(t *testing.T) {
	setupStore(t)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/login", handleSecureLogin)
	mux.HandleFunc("POST /api/session/logout", handleSessionLogout)
	mux.HandleFunc("GET /api/me", authMiddleware(handleMe))
	mux.HandleFunc("PUT /api/me", authMiddleware(handleUpdateMe))
	h := persistMutations(mux)
	cookies := demoCookies(t, h)
	var before int
	if err := database.QueryRow("SELECT COUNT(*) FROM sessions").Scan(&before); err != nil {
		t.Fatal(err)
	}
	response := featureRequest(h, "PUT", "/api/me", map[string]any{"name": "Updated profile", "email": "updated-profile@example.com"}, cookies)
	assertStatus(t, response, http.StatusOK)
	if len(response.Result().Cookies()) != 0 {
		t.Fatal("profile response must not replace login cookies")
	}
	var result profileUpdateResponse
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Token != "cookie-session" || result.User.Name != "Updated profile" || result.User.Email != "updated-profile@example.com" {
		t.Fatalf("unexpected profile response: %+v", result)
	}
	var after int
	if err := database.QueryRow("SELECT COUNT(*) FROM sessions").Scan(&after); err != nil {
		t.Fatal(err)
	}
	if after != before {
		t.Fatalf("profile save created a session: before=%d after=%d", before, after)
	}
	assertStatus(t, featureRequest(h, "GET", "/api/me", nil, cookies), http.StatusOK)
	// The profile response can arrive late. There must be no successor session
	// that its cookies could restore after the original session is revoked.
	assertStatus(t, featureRequest(h, "POST", "/api/session/logout", nil, cookies), http.StatusOK)
	assertStatus(t, featureRequest(h, "GET", "/api/me", nil, cookies), http.StatusUnauthorized)
	var active int
	if err := database.QueryRow("SELECT COUNT(*) FROM sessions WHERE revoked_at IS NULL").Scan(&active); err != nil {
		t.Fatal(err)
	}
	if active != 0 {
		t.Fatalf("profile save left %d sessions active after logout", active)
	}
}
