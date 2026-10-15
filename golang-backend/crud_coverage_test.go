package main

import (
	"encoding/json"
	"net/http"
	"testing"
)

func recordCRUDMux() http.Handler {
	m := http.NewServeMux()
	m.HandleFunc("POST /api/login", handleSecureLogin)
	for _, route := range []struct {
		pattern string
		handler http.HandlerFunc
	}{
		{"GET /api/agents", listAgentsHandler}, {"GET /api/agents/{id}", getAgentHandler},
		{"POST /api/agents", createAgentHandler}, {"PUT /api/agents/{id}", updateAgentHandler}, {"DELETE /api/agents/{id}", deleteAgentHandler},
		{"GET /api/schools", listSchoolsHandler}, {"GET /api/schools/{id}", getSchoolHandler},
		{"POST /api/schools", createSchoolHandler}, {"PUT /api/schools/{id}", updateSchoolHandler}, {"DELETE /api/schools/{id}", deleteSchoolHandler},
		{"GET /api/tasks", listTasks}, {"GET /api/tasks/{id}", getTask},
		{"POST /api/tasks", createTask}, {"PUT /api/tasks/{id}", updateTask}, {"DELETE /api/tasks/{id}", deleteTask}, {"PATCH /api/tasks/{id}/status", updateTaskStatus},
		{"GET /api/contacts/{id}/activities", listActivities}, {"POST /api/contacts/{id}/activities", createActivity}, {"DELETE /api/activities/{id}", deleteActivity},
	} {
		m.HandleFunc(route.pattern, authMiddleware(route.handler))
	}
	return persistMutations(m)
}

func TestCatalogAndTaskCRUDPersistsValidatesAndFilters(t *testing.T) {
	setupStore(t)
	h := recordCRUDMux()
	cookies := demoCookies(t, h)
	for _, scenario := range []struct {
		entity, singular, nameField string
		input                       map[string]any
	}{
		{"agents", "agent", "name", map[string]any{"name": "Coverage catalog fixture", "agentCode": "COVER", "countryCode": "ph", "contractStatus": "Signed", "agentStatus": "Active", "studentsReferred": 0}},
		{"schools", "school", "name", map[string]any{"name": "Coverage catalog fixture", "countryCode": "ph", "contractStatus": "Signed", "studentsEnrolled": 0}},
		{"tasks", "task", "title", map[string]any{"title": "Coverage catalog fixture", "description": "Regression next action", "status": "todo"}},
	} {
		t.Run(scenario.entity, func(t *testing.T) {
			base := "/api/" + scenario.entity
			assertStatus(t, featureRequest(h, "POST", base, map[string]any{}, cookies), 400)
			created := featureRequest(h, "POST", base, scenario.input, cookies)
			assertStatus(t, created, 201)
			var body map[string]map[string]any
			if err := json.Unmarshal(created.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			id, ok := body[scenario.singular]["id"].(string)
			if !ok || id == "" {
				t.Fatal("created record has no identifier")
			}
			get := featureRequest(h, "GET", base+"/"+id, nil, cookies)
			assertStatus(t, get, 200)
			var fetched map[string]map[string]any
			if err := json.Unmarshal(get.Body.Bytes(), &fetched); err != nil {
				t.Fatal(err)
			}
			if fetched[scenario.singular][scenario.nameField] != scenario.input[scenario.nameField] {
				t.Fatal("created record was not persisted")
			}
			if scenario.entity != "tasks" && fetched[scenario.singular]["countryCode"] != "PH" {
				t.Fatal("country code was not normalized")
			}
			listing := featureRequest(h, "GET", base+"?q=Coverage%20catalog&limit=1&offset=0", nil, cookies)
			assertStatus(t, listing, 200)
			var page struct{ Total int }
			if err := json.Unmarshal(listing.Body.Bytes(), &page); err != nil || page.Total != 1 {
				t.Fatalf("search did not isolate the record: %s", listing.Body.String())
			}
			assertStatus(t, featureRequest(h, "PUT", base+"/"+id, map[string]any{}, cookies), 400)
			scenario.input[scenario.nameField] = "Updated coverage fixture"
			assertStatus(t, featureRequest(h, "PUT", base+"/"+id, scenario.input, cookies), 200)
			updated := featureRequest(h, "GET", base+"/"+id, nil, cookies)
			assertStatus(t, updated, 200)
			if err := json.Unmarshal(updated.Body.Bytes(), &fetched); err != nil || fetched[scenario.singular][scenario.nameField] != "Updated coverage fixture" {
				t.Fatalf("update was not persisted: %s", updated.Body.String())
			}
			if scenario.entity == "tasks" {
				assertStatus(t, featureRequest(h, "PATCH", base+"/"+id+"/status", map[string]string{"status": "invalid"}, cookies), 400)
				assertStatus(t, featureRequest(h, "PATCH", base+"/"+id+"/status", map[string]string{"status": "done"}, cookies), 200)
				done := featureRequest(h, "GET", base+"/"+id, nil, cookies)
				if err := json.Unmarshal(done.Body.Bytes(), &fetched); err != nil || fetched[scenario.singular]["status"] != "done" {
					t.Fatal("task status change was not persisted")
				}
			}
			assertStatus(t, featureRequest(h, "DELETE", base+"/"+id, nil, cookies), 200)
			assertStatus(t, featureRequest(h, "GET", base+"/"+id, nil, cookies), 404)
			assertStatus(t, featureRequest(h, "PUT", base+"/"+id, scenario.input, cookies), 404)
			assertStatus(t, featureRequest(h, "DELETE", base+"/"+id, nil, cookies), 404)
		})
	}
}

func TestActivityCRUDPersistsAndKeepsContactBoundary(t *testing.T) {
	setupStore(t)
	h := recordCRUDMux()
	cookies := demoCookies(t, h)
	contactID := contacts[0].ID
	base := "/api/contacts/" + contactID + "/activities"
	assertStatus(t, featureRequest(h, "POST", base, map[string]string{"kind": "invalid", "title": "Invalid kind"}, cookies), 400)
	assertStatus(t, featureRequest(h, "POST", "/api/contacts/missing/activities", map[string]string{"kind": "note", "title": "No contact"}, cookies), 404)
	created := featureRequest(h, "POST", base, map[string]string{"kind": "note", "title": "Coverage activity", "body": "Keep this note", "occurredAt": "2026-10-15T10:00:00Z"}, cookies)
	assertStatus(t, created, 201)
	var out struct{ Activity Activity }
	if err := json.Unmarshal(created.Body.Bytes(), &out); err != nil || out.Activity.ID == "" {
		t.Fatalf("invalid activity response: %s", created.Body.String())
	}
	listing := featureRequest(h, "GET", base, nil, cookies)
	assertStatus(t, listing, 200)
	var records struct{ Activities []Activity }
	if err := json.Unmarshal(listing.Body.Bytes(), &records); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, record := range records.Activities {
		if record.ContactID != contactID {
			t.Fatal("contact activity list crossed a contact boundary")
		}
		if record.ID == out.Activity.ID {
			found = record.Title == "Coverage activity" && record.Body == "Keep this note"
		}
	}
	if !found {
		t.Fatal("activity was not persisted")
	}
	assertStatus(t, featureRequest(h, "DELETE", "/api/activities/"+out.Activity.ID, nil, cookies), 200)
	assertStatus(t, featureRequest(h, "DELETE", "/api/activities/"+out.Activity.ID, nil, cookies), 404)
	assertStatus(t, featureRequest(h, "GET", "/api/contacts/missing/activities", nil, cookies), 404)
}
