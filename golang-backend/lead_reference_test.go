package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLeadReferenceSequenceSurvivesEditsDeletionAndRestart(t *testing.T) {
	setupStore(t)
	h := leadIntakeMux()
	cookies := demoCookies(t, h)
	user, _ := findUserByEmail("demo@northwind.dev")
	prefix := "ECC-LD-" + todayForOrgDB(database, user.OrgID)[:4] + "-"
	create := func(name, reference string) Lead {
		t.Helper()
		w := featureRequest(h, "POST", "/api/leads", map[string]string{"name": name, "leadNumber": reference, "source": "Referral", "status": "New"}, cookies)
		assertStatus(t, w, http.StatusCreated)
		var out struct{ Lead Lead }
		if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		return out.Lead
	}
	custom := create("Imported reference", prefix+"00041")
	if custom.LeadNumber != prefix+"00041" {
		t.Fatal("an imported reference was replaced")
	}
	created := create("Automatic inquiry", "")
	if created.LeadNumber != prefix+"00042" {
		t.Fatalf("must continue after existing numbers: %s", created.LeadNumber)
	}
	w := featureRequest(h, "PUT", "/api/leads/"+created.ID, map[string]string{"name": "Renamed inquiry", "source": "Referral", "status": "New", "leadNumber": "REPLACE"}, cookies)
	assertStatus(t, w, http.StatusOK)
	var updated struct{ Lead Lead }
	json.Unmarshal(w.Body.Bytes(), &updated)
	if updated.Lead.LeadNumber != created.LeadNumber {
		t.Fatal("editing must preserve the assigned reference")
	}
	assertStatus(t, featureRequest(h, "DELETE", "/api/leads/"+created.ID, nil, cookies), http.StatusOK)
	if err := loadStore(dataPath); err != nil {
		t.Fatal(err)
	}
	fixtureBaseline = cloneStore()
	if next := create("After restart", ""); next.LeadNumber != prefix+"00043" {
		t.Fatalf("a deleted reference was reused after restart: %s", next.LeadNumber)
	}
}

func TestConcurrentLeadSavesReceiveDistinctReferences(t *testing.T) {
	setupStore(t)
	h := leadIntakeMux()
	cookies := demoCookies(t, h)
	// Use the production handler directly: the compatibility fixture wrapper
	// deliberately publishes globals and is not part of concurrent requests.
	type result struct {
		status int
		body   string
	}
	results := make(chan result, 8)
	start := make(chan struct{})
	for i := 0; i < cap(results); i++ {
		go func(i int) {
			<-start
			r := httptest.NewRequest("POST", "/api/leads", strings.NewReader(mustJSON(map[string]string{"name": fmt.Sprintf("Concurrent inquiry %d", i), "source": "Referral", "status": "New"})))
			r.Header.Set("Content-Type", "application/json")
			for _, cookie := range cookies {
				r.AddCookie(cookie)
			}
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			results <- result{w.Code, w.Body.String()}
		}(i)
	}
	close(start)
	seen := map[string]bool{}
	for i := 0; i < cap(results); i++ {
		out := <-results
		if out.status != http.StatusCreated {
			t.Errorf("concurrent save: %d %s", out.status, out.body)
			continue
		}
		var response struct{ Lead Lead }
		if err := json.Unmarshal([]byte(out.body), &response); err != nil {
			t.Error(err)
		}
		if response.Lead.LeadNumber == "" || seen[response.Lead.LeadNumber] {
			t.Errorf("duplicate or missing reference: %s", response.Lead.LeadNumber)
		}
		seen[response.Lead.LeadNumber] = true
	}
}
