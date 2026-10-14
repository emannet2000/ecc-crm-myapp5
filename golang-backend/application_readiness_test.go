package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

type readinessResponse struct {
	CaseID          string                       `json:"caseId"`
	CaseNumber      string                       `json:"caseNumber"`
	Stage           string                       `json:"stage"`
	TargetStage     string                       `json:"targetStage"`
	Verdict         string                       `json:"verdict"`
	Ready           bool                         `json:"ready"`
	RequiredCount   int                          `json:"requiredCount"`
	CompletedCount  int                          `json:"completedCount"`
	Outstanding     int                          `json:"outstandingCount"`
	BlockingCount   int                          `json:"blockingCount"`
	PendingHandoffs int                          `json:"pendingHandoffs"`
	Owner           string                       `json:"owner"`
	Items           []readinessItem              `json:"items"`
	Gates           []readinessGate              `json:"gates"`
	Balances        map[string]*readinessBalance `json:"balances"`
}

func decodeReadiness(t *testing.T, w httptestResponse) readinessResponse {
	t.Helper()
	var out readinessResponse
	if err := json.Unmarshal(w.body, &out); err != nil {
		t.Fatalf("readiness did not decode: %s", string(w.body))
	}
	return out
}

// httptestResponse keeps the assertions readable when a body is inspected twice.
type httptestResponse struct {
	status int
	body   []byte
}

func readinessRequest(t *testing.T, h http.Handler, u User, id string) httptestResponse {
	t.Helper()
	w := dailyUserRequest(t, h, u, "GET", "/api/cases/"+id+"/readiness", nil)
	return httptestResponse{status: w.Code, body: w.Body.Bytes()}
}

func readinessWorkspace(t *testing.T) (User, http.Handler) {
	t.Helper()
	setupStore(t)
	admin, _ := findUserByEmail("demo@northwind.dev")
	scope := RecordScope{OrgID: admin.OrgID, OwnerID: admin.ID, TeamID: admin.TeamID, Visibility: "organization"}
	today, err := time.Parse("2006-01-02", organizationTodayForOrg(admin.OrgID))
	if err != nil {
		t.Fatal(err)
	}
	future := today.AddDate(1, 0, 0).Format("2006-01-02")
	mu.Lock()
	cases = []Case{
		{RecordScope: scope, ID: "ready-blocked", CaseNumber: "RDY-1", CurrentStage: "Ready for Submission", AssignedOfficer: admin.Name, ClientID: "c_blocked", ClientName: "Blocked client", NextAction: "Submit the file"},
		{RecordScope: scope, ID: "ready-complete", CaseNumber: "RDY-2", CurrentStage: "Ready for Submission", AssignedOfficer: admin.Name, ClientID: "c_complete", ClientName: "Complete client", NextAction: "Submit the file"},
		{RecordScope: scope, ID: "ready-noplan", CaseNumber: "RDY-3", CurrentStage: "Application Preparation", AssignedOfficer: admin.Name, ClientID: "c_noplan"},
		{RecordScope: scope, ID: "ready-closed", CaseNumber: "RDY-4", CurrentStage: "Approved", AssignedOfficer: admin.Name, NextAction: "Archive the file"},
	}
	documents = []Document{
		{RecordScope: scope, ID: "rdy-doc-1", CaseID: "ready-blocked", DocName: "Passport", Required: true, Status: "Requested"},
		{RecordScope: scope, ID: "rdy-doc-2", CaseID: "ready-complete", DocName: "Passport", Required: true, Status: "Verified", ExpiryDate: future, FilePath: "passport.pdf", LatestVersion: 1},
	}
	invoices = []Invoice{{RecordScope: scope, ID: "rdy-inv", CaseID: "ready-complete", InvoiceNumber: "INV-RDY", Currency: "PHP", Balance: 500}}
	mu.Unlock()
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}
	return admin, workflowMux()
}

func TestApplicationReadinessBlocksOnMissingDocuments(t *testing.T) {
	admin, h := readinessWorkspace(t)
	w := readinessRequest(t, h, admin, "ready-blocked")
	if w.status != 200 {
		t.Fatalf("unexpected status %d: %s", w.status, string(w.body))
	}
	out := decodeReadiness(t, w)
	if out.Verdict != "blocked" || out.Ready {
		t.Fatalf("a missing required document must block submission: %s", string(w.body))
	}
	if out.TargetStage != "Submitted" {
		t.Fatalf("submission target is wrong: %s", string(w.body))
	}
	if out.RequiredCount != 1 || out.CompletedCount != 0 || out.Outstanding != 1 || out.BlockingCount != 1 {
		t.Fatalf("checklist figures are wrong: %s", string(w.body))
	}
	found := false
	for _, item := range out.Items {
		if item.Kind == "document" && item.Title == "Passport" && item.Blocking {
			found = true
		}
	}
	if !found {
		t.Fatalf("the outstanding document is not explained: %s", string(w.body))
	}
}

func TestApplicationReadinessSeparatesDocumentsFromFinance(t *testing.T) {
	admin, h := readinessWorkspace(t)
	w := readinessRequest(t, h, admin, "ready-complete")
	out := decodeReadiness(t, w)
	if out.Verdict != "ready" || !out.Ready {
		t.Fatalf("verified documents with a plan are ready: %s", string(w.body))
	}
	// An outstanding balance is reported but never blocks a stage on its own.
	if out.Balances["PHP"] == nil || out.Balances["PHP"].Outstanding != 500 {
		t.Fatalf("outstanding balance is missing: %s", string(w.body))
	}
	for _, item := range out.Items {
		if item.Kind == "payment" && item.Blocking {
			t.Fatal("finance must not become a new stage gate")
		}
	}
}

func TestApplicationReadinessReportsPlanAndClosedStates(t *testing.T) {
	admin, h := readinessWorkspace(t)
	out := decodeReadiness(t, readinessRequest(t, h, admin, "ready-noplan"))
	if out.Verdict != "incomplete" || out.Ready {
		t.Fatalf("an application without a next action is not ready: %s", mustJSON(out))
	}
	out = decodeReadiness(t, readinessRequest(t, h, admin, "ready-closed"))
	if out.Verdict != "closed" {
		t.Fatalf("a closed application needs no readiness work: %s", mustJSON(out))
	}
}

func TestApplicationReadinessRespectsRecordVisibility(t *testing.T) {
	admin, h := readinessWorkspace(t)
	member := admin
	member.ID = "readiness-member"
	member.Email = "readiness-member@example.com"
	member.Name = "Readiness member"
	member.Role = "member"
	hidden := RecordScope{OrgID: admin.OrgID, OwnerID: "another-adviser", Visibility: "private"}
	mu.Lock()
	users[member.Email] = member
	cases = append(cases, Case{RecordScope: hidden, ID: "ready-hidden", CaseNumber: "RDY-HIDDEN", CurrentStage: "Ready for Submission"})
	mu.Unlock()
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}
	w := readinessRequest(t, h, member, "ready-hidden")
	if w.status != 404 {
		t.Fatalf("a private application must not be readable: %d %s", w.status, string(w.body))
	}
	if strings.Contains(string(w.body), "RDY-HIDDEN") {
		t.Fatal("a hidden application leaked")
	}
	w = readinessRequest(t, h, admin, "absent-application")
	if w.status != 404 {
		t.Fatalf("missing applications must answer 404: %d", w.status)
	}
}

func TestApplicationReadinessPreviewsConfiguredStageGates(t *testing.T) {
	admin, h := readinessWorkspace(t)
	configureTestGate(t, h, StageGateRule{Stage: "Submitted", Enabled: true, DocumentNames: []string{"Bank statement"}, Uploaded: true})
	out := decodeReadiness(t, readinessRequest(t, h, admin, "ready-complete"))
	blockedByGate := false
	for _, gate := range out.Gates {
		if gate.Stage != "Submitted" {
			continue
		}
		if gate.Satisfied || len(gate.Issues) == 0 {
			t.Fatalf("an unmet configured gate must be reported: %s", mustJSON(out))
		}
		blockedByGate = true
	}
	if !blockedByGate {
		t.Fatalf("the configured gate for the next stage is missing: %s", mustJSON(out))
	}
	if out.Verdict != "blocked" {
		t.Fatalf("a configured gate must block the verdict: %s", mustJSON(out))
	}
}

func TestStageChangeCreatesOneFollowUpTask(t *testing.T) {
	setupStore(t)
	h := workflowMux()
	admin, _ := findUserByEmail("demo@northwind.dev")
	c := cases[0]
	c.CurrentStage = "Assessment"
	c.NextAction = ""
	c.ClientID = "c_followup"
	c.ClientName = "Follow-up client"
	c.AssignedOfficer = admin.Name
	cases[0] = c
	documents = nil
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}
	rev, _, _ := gatePreview(t, h, c.ID, "Ready for Submission")
	assertStatus(t, expansionRequest(t, h, "PUT", "/api/cases/"+c.ID+"/stage", map[string]any{"currentStage": "Ready for Submission"}, rev), 200)
	title := "Record the next action: " + c.CaseNumber
	if count := openFollowUpTasks(t, title); count != 1 {
		t.Fatalf("a stage change without a plan must create exactly one task: %d", count)
	}
	// Repeating the same move is idempotent, and moving to another stage without
	// a plan adds the matching task rather than duplicating anything.
	rev, _, _ = gatePreview(t, h, c.ID, "Ready for Submission")
	assertStatus(t, expansionRequest(t, h, "PUT", "/api/cases/"+c.ID+"/stage", map[string]any{"currentStage": "Ready for Submission"}, rev), 200)
	if count := openFollowUpTasks(t, title); count != 1 {
		t.Fatalf("the follow-up task was duplicated: %d", count)
	}
	// The task is linked to the application and is auditable.
	tasks := http.NewServeMux()
	registerWorkspaceRoutes(tasks)
	tasks.HandleFunc("GET /api/tasks", authMiddleware(listTasks))
	w := expansionRequest(t, persistMutations(tasks), "GET", "/api/tasks?limit=200", nil, "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), title) {
		t.Fatalf("the follow-up task is not visible in the task list: %d %s", w.Code, w.Body.String())
	}
	var audited int
	if err := database.QueryRow("SELECT count(*) FROM audit_events WHERE entity='tasks' AND json_extract(scope_data,'$.orgId')=?", admin.OrgID).Scan(&audited); err != nil || audited == 0 {
		t.Fatalf("the generated task was not audited: %d %v", audited, err)
	}
}

func TestStageChangeWithPlanAndCompleteDocumentsCreatesNoTask(t *testing.T) {
	setupStore(t)
	h := workflowMux()
	admin, _ := findUserByEmail("demo@northwind.dev")
	c := cases[0]
	c.CurrentStage = "Assessment"
	c.NextAction = "Submit the file"
	c.AssignedOfficer = admin.Name
	cases[0] = c
	documents = nil
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}
	rev, _, _ := gatePreview(t, h, c.ID, "Ready for Submission")
	assertStatus(t, expansionRequest(t, h, "PUT", "/api/cases/"+c.ID+"/stage", map[string]any{"currentStage": "Ready for Submission"}, rev), 200)
	if count := openFollowUpTasks(t, "Complete required documents: "+c.CaseNumber); count != 0 {
		t.Fatalf("a complete checklist must not create a document task: %d", count)
	}
	if count := openFollowUpTasks(t, "Record the next action: "+c.CaseNumber); count != 0 {
		t.Fatalf("a recorded plan must not create a planning task: %d", count)
	}
}

func TestStageChangeWithOutstandingDocumentsCreatesOneDocumentTask(t *testing.T) {
	setupStore(t)
	h := workflowMux()
	admin, _ := findUserByEmail("demo@northwind.dev")
	c := cases[0]
	c.CurrentStage = "Assessment"
	c.NextAction = "Submit the file"
	c.ClientID = "c_documents"
	c.AssignedOfficer = admin.Name
	cases[0] = c
	documents = []Document{{RecordScope: c.RecordScope, ID: "follow-up-doc", CaseID: c.ID, DocName: "Passport", Required: true, Status: "Requested"}}
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}
	rev, _, _ := gatePreview(t, h, c.ID, "Ready for Submission")
	assertStatus(t, expansionRequest(t, h, "PUT", "/api/cases/"+c.ID+"/stage", map[string]any{"currentStage": "Ready for Submission"}, rev), 200)
	if count := openFollowUpTasks(t, "Complete required documents: "+c.CaseNumber); count != 1 {
		t.Fatalf("an outstanding required document must create one task: %d", count)
	}
}

func openFollowUpTasks(t *testing.T, title string) int {
	t.Helper()
	var count int
	if err := database.QueryRow("SELECT count(*) FROM tasks WHERE json_extract(data,'$.title')=? AND json_extract(data,'$.status')<>'done'", title).Scan(&count); err != nil {
		t.Fatal(err)
	}
	return count
}
