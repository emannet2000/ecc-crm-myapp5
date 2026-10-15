package main

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func leadIntakeMux() http.Handler {
	m := http.NewServeMux()
	registerWorkspaceRoutes(m)
	m.HandleFunc("POST /api/login", handleSecureLogin)
	m.HandleFunc("POST /api/register", handleSecureRegister)
	m.HandleFunc("POST /api/leads", authMiddleware(createLeadHandler))
	m.HandleFunc("GET /api/leads/{id}", authMiddleware(getLeadHandler))
	m.HandleFunc("PUT /api/leads/{id}", authMiddleware(updateLeadHandler))
	m.HandleFunc("DELETE /api/leads/{id}", authMiddleware(deleteLeadHandler))
	m.HandleFunc("GET /api/documents", authMiddleware(listDocumentsHandler))
	m.HandleFunc("POST /api/documents", authMiddleware(createDocumentHandler))
	return persistMutations(m)
}

func intakeLead(t *testing.T, h http.Handler, cookies []*http.Cookie) Lead {
	t.Helper()
	w := featureRequest(h, "POST", "/api/leads", map[string]string{"name": "CV client", "email": "cv-client@example.com", "phone": "+639171234567", "source": "Referral", "referrer": "Flor", "assignedTo": "u_1", "status": "New", "followUpDate": "2026-10-20", "interestedCountry": "CA", "notes": "Interested in study options"}, cookies)
	assertStatus(t, w, 201)
	var out struct{ Lead Lead }
	json.Unmarshal(w.Body.Bytes(), &out)
	return out.Lead
}

func TestLeadCVVersionsConversionAndIsolation(t *testing.T) {
	setupStore(t)
	h := leadIntakeMux()
	cookies := demoCookies(t, h)
	lead := intakeLead(t, h, cookies)
	initialDocuments, initialCases, initialStudents, initialContacts := len(documents), len(cases), len(students), len(contacts)
	assertStatus(t, multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "bad.pdf", []byte("bad"), cookies, nil), 400)
	if len(documents) != initialDocuments {
		t.Fatal("failed upload created a document")
	}
	var doc Document
	for _, data := range []string{"%PDF-1.4 original", "%PDF-1.4 revised"} {
		w := multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.pdf", []byte(data), cookies, nil)
		assertStatus(t, w, 201)
		var out struct{ Document Document }
		json.Unmarshal(w.Body.Bytes(), &out)
		doc = out.Document
	}
	if doc.LeadID != lead.ID || doc.CaseID != "" || doc.LatestVersion != 2 || len(documents) != initialDocuments+1 {
		t.Fatal("CV did not stay on lead with two versions")
	}
	w := featureRequest(h, "GET", "/api/documents?leadId="+lead.ID, nil, cookies)
	assertStatus(t, w, 200)
	if !strings.Contains(w.Body.String(), doc.ID) {
		t.Fatal("SQL list hid lead CV")
	}
	assertStatus(t, featureRequest(h, "GET", "/api/records/documents/"+doc.ID, nil, cookies), 200)
	other := featureRequest(h, "POST", "/api/register", map[string]string{"name": "Other", "email": "other-cv@example.com", "password": "LongEnoughPassword!"}, nil).Result().Cookies()
	assertStatus(t, featureRequest(h, "GET", "/api/documents/"+doc.ID+"/files/1", nil, other), 404)
	assertStatus(t, multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.pdf", []byte("%PDF-1.4"), other, nil), 404)
	w = featureRequest(h, "POST", "/api/workflows/lead-convert", map[string]string{"id": lead.ID, "target": "student"}, cookies)
	assertStatus(t, w, 200)
	var converted map[string]string
	json.Unmarshal(w.Body.Bytes(), &converted)
	if converted["contactId"] == "" || converted["studentId"] == "" || converted["caseId"] == "" {
		t.Fatal("conversion links missing")
	}
	for _, student := range students {
		if student.ID == converted["studentId"] && !strings.HasPrefix(student.StudentCode, "ECC-ST-") {
			t.Fatal("converted student lacks automatic reference")
		}
	}
	assertStatus(t, featureRequest(h, "POST", "/api/workflows/lead-convert", map[string]string{"id": lead.ID, "target": "student"}, cookies), 200)
	if len(cases) != initialCases+1 || len(students) != initialStudents+1 || len(contacts) != initialContacts+1 {
		t.Fatal("repeat conversion created duplicate records")
	}
	for _, d := range documents {
		if d.ID == doc.ID && (d.CaseID != converted["caseId"] || d.LeadID != "" || d.LatestVersion != 2) {
			t.Fatal("CV metadata was lost on conversion")
		}
	}
	for _, c := range cases {
		if c.ID == converted["caseId"] && (!strings.Contains(c.Notes, "Flor") || c.NextDeadline != lead.FollowUpDate || c.AssignedOfficer != lead.AssignedTo) {
			t.Fatal("intake context was not carried forward")
		}
	}
	w = featureRequest(h, "GET", "/api/documents/"+doc.ID+"/files/1", nil, cookies)
	assertStatus(t, w, 200)
	if w.Body.String() != "%PDF-1.4 original" {
		t.Fatal("original CV bytes changed")
	}
	assertStatus(t, multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.pdf", []byte("%PDF-1.4"), cookies, nil), 409)
}

func TestCVExtractionReviewAndStaleDraft(t *testing.T) {
	setupStore(t)
	t.Setenv("OPENAI_API_KEY", "test-key")
	t.Setenv("OPENAI_MODEL", "configured-model")
	h := leadIntakeMux()
	cookies := demoCookies(t, h)
	lead := intakeLead(t, h, cookies)
	var file bytes.Buffer
	z := zip.NewWriter(&file)
	part, _ := z.Create("word/document.xml")
	part.Write([]byte(`<document><p>Reviewed Client cv-review@example.com</p></document>`))
	z.Close()
	w := multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.docx", file.Bytes(), cookies, nil)
	assertStatus(t, w, 201)
	var uploaded struct{ Document Document }
	json.Unmarshal(w.Body.Bytes(), &uploaded)
	assertStatus(t, featureRequest(h, "PUT", "/api/admin/assistant", map[string]bool{"enabled": true}, cookies), 200)
	old := providerHTTP
	t.Cleanup(func() { providerHTTP = old })
	providerHTTP = &http.Client{Transport: testTransport(func(r *http.Request) (*http.Response, error) {
		var input map[string]any
		json.NewDecoder(r.Body).Decode(&input)
		if !strings.Contains(mustJSON(input["input"]), "Reviewed Client") || !strings.Contains(mustJSON(input["input"]), "staff review") {
			t.Fatal("CV text or review instructions absent")
		}
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(mustJSON(map[string]any{"status": "completed", "output": []any{map[string]any{"content": []any{map[string]any{"type": "output_text", "text": `{"fields":{"name":"Reviewed Client","email":"cv-review@example.com"},"uncertainties":[],"missing_fields":[]}`}}}}})))}, nil
	})}
	w = featureRequest(h, "POST", "/api/assistant", map[string]string{"entity": "documents", "id": uploaded.Document.ID, "action": "cv-extract"}, cookies)
	assertStatus(t, w, 202)
	var queued map[string]string
	json.Unmarshal(w.Body.Bytes(), &queued)
	processAssistantJobs(context.Background())
	reloadFixtureAssertions()
	assertStatus(t, featureRequest(h, "GET", "/api/assistant/jobs/"+queued["id"], nil, cookies), 200)
	current, _ := getLeadByID(lead.ID)
	if current.Name != lead.Name {
		t.Fatal("extraction automatically saved lead")
	}
	version := func() string {
		var out struct{ Record map[string]any }
		w := featureRequest(h, "GET", "/api/records/leads/"+lead.ID, nil, cookies)
		json.Unmarshal(w.Body.Bytes(), &out)
		return fmtString(out.Record["_revision"])
	}
	save := func(body any, revision string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", "/api/leads/"+lead.ID+"/cv-review", strings.NewReader(mustJSON(body)))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("If-Match", revision)
		for _, c := range cookies {
			r.AddCookie(c)
		}
		w := httptest.NewRecorder()
		serveFixtureRequest(h, w, r)
		return w
	}
	revision := version()
	body := map[string]any{"jobId": queued["id"], "confirmed": false, "fields": map[string]string{"name": "Reviewed Client"}}
	assertStatus(t, save(body, revision), 400)
	body["confirmed"] = true
	assertStatus(t, save(body, ""), 428)
	assertStatus(t, save(body, revision), 200)
	current, _ = getLeadByID(lead.ID)
	if current.Name != "Reviewed Client" || current.Referrer != "Flor" || current.Source != "Referral" || current.FollowUpDate != lead.FollowUpDate {
		t.Fatal("review changed intake context")
	}
	assertStatus(t, save(body, revision), 409)
	assertStatus(t, multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.txt", []byte("Changed CV"), cookies, nil), 201)
	assertStatus(t, save(body, version()), 409)
}

func TestLeadCVParentPermissionsAndRestrictedConversion(t *testing.T) {
	setupStore(t)
	h := leadIntakeMux()
	admin := demoCookies(t, h)
	lead := intakeLead(t, h, admin)
	w := multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.txt", []byte("Private client CV"), admin, nil)
	assertStatus(t, w, 201)
	var upload struct{ Document Document }
	json.Unmarshal(w.Body.Bytes(), &upload)
	staff := map[string][]*http.Cookie{}
	var memberID string
	for _, role := range []string{"member", "viewer"} {
		w = featureRequest(h, "POST", "/api/admin/users", map[string]string{"name": role, "email": role + "-cv@example.com", "password": "StaffCVPassword!", "role": role}, admin)
		assertStatus(t, w, 201)
		if role == "member" {
			var response map[string]any
			json.Unmarshal(w.Body.Bytes(), &response)
			memberID = fmtString(response["id"])
		}
		w = featureRequest(h, "POST", "/api/login", map[string]string{"email": role + "-cv@example.com", "password": "StaffCVPassword!"}, nil)
		assertStatus(t, w, 200)
		staff[role] = w.Result().Cookies()
		assertStatus(t, featureRequest(h, "GET", "/api/documents/"+upload.Document.ID+"/files/1", nil, staff[role]), 200)
		assertStatus(t, multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.txt", []byte("Forbidden update"), staff[role], nil), 403)
		assertStatus(t, featureRequest(h, "POST", "/api/workflows/lead-convert", map[string]string{"id": lead.ID, "target": "application"}, staff[role]), 403)
	}
	assertStatus(t, featureRequest(h, "PATCH", "/api/access/leads/"+lead.ID, map[string]string{"visibility": "private", "ownerId": "u_1"}, admin), 200)
	for _, cookies := range staff {
		assertStatus(t, featureRequest(h, "GET", "/api/documents/"+upload.Document.ID+"/files/1", nil, cookies), 404)
		assertStatus(t, featureRequest(h, "GET", "/api/records/documents/"+upload.Document.ID, nil, cookies), 404)
		w = featureRequest(h, "GET", "/api/documents?leadId="+lead.ID, nil, cookies)
		assertStatus(t, w, 200)
		if strings.Contains(w.Body.String(), upload.Document.ID) {
			t.Fatal("SQL list revealed a CV whose parent is private")
		}
	}
	if memberID == "" {
		user, _ := findUserByEmail("member-cv@example.com")
		memberID = user.ID
	}
	assertStatus(t, featureRequest(h, "PATCH", "/api/access/leads/"+lead.ID, map[string]string{"visibility": "private", "ownerId": memberID}, admin), 200)
	assertStatus(t, featureRequest(h, "PATCH", "/api/access/documents/"+upload.Document.ID, map[string]string{"visibility": "private", "ownerId": "u_1"}, admin), 200)
	beforeCases, beforeContacts := len(cases), len(contacts)
	assertStatus(t, featureRequest(h, "POST", "/api/workflows/lead-convert", map[string]string{"id": lead.ID, "target": "application"}, staff["member"]), 409)
	assertStatus(t, multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.txt", []byte("Replacement"), staff["member"], nil), 409)
	if len(cases) != beforeCases || len(contacts) != beforeContacts {
		t.Fatal("restricted conversion partially committed")
	}
}

func TestLeadCVDeletionRestoresOriginalAttachment(t *testing.T) {
	setupStore(t)
	h := leadIntakeMux()
	cookies := demoCookies(t, h)
	lead := intakeLead(t, h, cookies)
	w := multipartRequest(h, "/api/leads/"+lead.ID+"/cv", "file", "client.txt", []byte("Original CV"), cookies, nil)
	assertStatus(t, w, 201)
	var upload struct{ Document Document }
	json.Unmarshal(w.Body.Bytes(), &upload)
	assertStatus(t, featureRequest(h, "DELETE", "/api/leads/"+lead.ID, nil, cookies), 200)
	assertStatus(t, featureRequest(h, "GET", "/api/documents/"+upload.Document.ID+"/files/1", nil, cookies), 404)
	w = featureRequest(h, "GET", "/api/trash", nil, cookies)
	assertStatus(t, w, 200)
	var trash struct{ Batches []struct{ ID string } }
	json.Unmarshal(w.Body.Bytes(), &trash)
	if len(trash.Batches) != 1 {
		t.Fatal("lead and CV should share a deletion batch")
	}
	assertStatus(t, featureRequest(h, "POST", "/api/trash/"+trash.Batches[0].ID+"/restore", map[string]any{}, cookies), 200)
	w = featureRequest(h, "GET", "/api/documents/"+upload.Document.ID+"/files/1", nil, cookies)
	assertStatus(t, w, 200)
	if w.Body.String() != "Original CV" {
		t.Fatal("restored lead lost its original CV")
	}
}
