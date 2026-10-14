package main

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func kpiValue(t *testing.T, overview dashboardOverview, key string) int {
	t.Helper()
	for _, card := range overview.KPI {
		if card.Key == key {
			return card.Value
		}
	}
	t.Fatalf("dashboard KPI %q is missing", key)
	return 0
}

func stageCount(overview dashboardOverview, stage string) int {
	for _, row := range overview.Cases {
		if row.Stage == stage {
			return row.Count
		}
	}
	return 0
}

func decodeOverview(t *testing.T, w *httptest.ResponseRecorder) dashboardOverview {
	t.Helper()
	var out dashboardOverview
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatalf("dashboard overview did not decode: %s", w.Body.String())
	}
	return out
}

// dashboardFixture builds a small but complete workspace: two active
// applications with different document states, one closed application, an
// overdue and an upcoming lead follow-up, and overdue/due-soon invoices in two
// currencies.
func dashboardFixture(t *testing.T) User {
	t.Helper()
	setupStore(t)
	admin, _ := findUserByEmail("demo@northwind.dev")
	scope := RecordScope{OrgID: admin.OrgID, OwnerID: admin.ID, TeamID: admin.TeamID, Visibility: "organization"}
	today, err := time.Parse("2006-01-02", organizationTodayForOrg(admin.OrgID))
	if err != nil {
		t.Fatal(err)
	}
	days := func(offset int) string { return today.AddDate(0, 0, offset).Format("2006-01-02") }
	mu.Lock()
	cases = nil
	documents = nil
	leads = nil
	invoices = nil
	payments = nil
	cases = append(cases,
		Case{RecordScope: scope, ID: "dash-pending", CaseNumber: "DASH-1", CurrentStage: "Documents Pending", AssignedOfficer: admin.Name},
		Case{RecordScope: scope, ID: "dash-ready", CaseNumber: "DASH-2", CurrentStage: "Ready for Submission", AssignedOfficer: admin.Name},
		Case{RecordScope: scope, ID: "dash-closed", CaseNumber: "DASH-3", CurrentStage: "Closed", AssignedOfficer: admin.Name},
	)
	documents = append(documents,
		Document{RecordScope: scope, ID: "dash-doc-1", CaseID: "dash-pending", DocName: "Passport", Required: true, Status: "Received"},
		Document{RecordScope: scope, ID: "dash-doc-2", CaseID: "dash-ready", DocName: "Passport", Required: true, Status: "Verified", ExpiryDate: "2099-01-01"},
		Document{RecordScope: scope, ID: "dash-doc-3", CaseID: "dash-ready", DocName: "Bank statement", Required: true, Status: "Verified", ExpiryDate: "2000-01-01"},
		Document{RecordScope: scope, ID: "dash-doc-4", CaseID: "dash-closed", DocName: "Passport", Required: true, Status: "Requested"},
		Document{RecordScope: scope, ID: "dash-doc-5", CaseID: "dash-pending", DocName: "Optional letter", Required: false, Status: "Not Requested"},
	)
	leads = append(leads,
		Lead{RecordScope: scope, ID: "dash-lead-overdue", Name: "Overdue inquiry", LeadNumber: "L-1", Status: "New", AssignedTo: admin.Name, FollowUpDate: days(-3)},
		Lead{RecordScope: scope, ID: "dash-lead-soon", Name: "Upcoming inquiry", LeadNumber: "L-2", Status: "Contacted", AssignedTo: admin.Name, FollowUpDate: days(2)},
		Lead{RecordScope: scope, ID: "dash-lead-closed", Name: "Converted inquiry", LeadNumber: "L-3", Status: "Converted", AssignedTo: admin.Name},
	)
	invoices = append(invoices,
		Invoice{RecordScope: scope, ID: "dash-inv-overdue", InvoiceNumber: "INV-1", Currency: "PHP", Balance: 1000, DueDate: days(-10)},
		Invoice{RecordScope: scope, ID: "dash-inv-soon", InvoiceNumber: "INV-2", Currency: "USD", Balance: 250, DueDate: days(3)},
		Invoice{RecordScope: scope, ID: "dash-inv-later", InvoiceNumber: "INV-3", Currency: "USD", Balance: 500, DueDate: days(60)},
		Invoice{RecordScope: scope, ID: "dash-inv-paid", InvoiceNumber: "INV-4", Currency: "USD", Balance: 0, DueDate: days(-30)},
	)
	mu.Unlock()
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}
	return admin
}

func TestDashboardOverviewReportsStagesDocumentsAndPayments(t *testing.T) {
	admin := dashboardFixture(t)
	h := expansionTestMux()

	w := dailyUserRequest(t, h, admin, "GET", "/api/dashboard/overview?scope=all", nil)
	assertStatus(t, w, 200)
	overview := decodeOverview(t, w)

	if overview.Today != organizationTodayForOrg(admin.OrgID) || overview.Scope != "all" || overview.GeneratedAt == "" {
		t.Fatalf("overview header is wrong: %s", w.Body.String())
	}
	if stageCount(overview, "Documents Pending") != 1 || stageCount(overview, "Ready for Submission") != 1 {
		t.Fatalf("case stage summary is wrong: %s", w.Body.String())
	}
	// Stages are reported in pipeline order, not map order.
	if len(overview.Cases) != 3 || overview.Cases[0].Stage != "Documents Pending" || overview.Cases[2].Stage != "Closed" {
		t.Fatalf("case stages are out of pipeline order: %s", w.Body.String())
	}
	if kpiValue(t, overview, "activeCases") != 2 {
		t.Fatalf("only applications that are still running may count as active: %s", w.Body.String())
	}
	if kpiValue(t, overview, "readyForSubmission") != 1 {
		t.Fatalf("ready for submission must be its own figure: %s", w.Body.String())
	}
	if overview.Completeness.Applications != 2 || overview.Completeness.RequiredDocuments != 3 || overview.Completeness.VerifiedDocuments != 1 {
		t.Fatalf("document completeness must ignore closed applications and optional files: %s", w.Body.String())
	}
	if overview.Completeness.Incomplete != 2 || overview.Completeness.Complete != 0 || overview.Completeness.CompletePercent != 0 {
		t.Fatalf("an expired verified file must not count as complete: %s", w.Body.String())
	}
	if overview.Completeness.ExpiredDocuments != 1 || overview.Completeness.OutstandingFiles != 2 {
		t.Fatalf("expired and outstanding document counts are wrong: %s", w.Body.String())
	}
	if kpiValue(t, overview, "openLeads") != 2 || kpiValue(t, overview, "followUpsOverdue") != 1 {
		t.Fatalf("lead counts are wrong: %s", w.Body.String())
	}
	if kpiValue(t, overview, "invoicesOverdue") != 1 || kpiValue(t, overview, "invoicesDueSoon") != 1 {
		t.Fatalf("payment buckets are wrong: %s", w.Body.String())
	}
	if len(overview.Payments.Overdue) != 1 || overview.Payments.Overdue[0].Currency != "PHP" || overview.Payments.Overdue[0].Amount != 1000 {
		t.Fatalf("overdue payments must stay in their own currency: %s", w.Body.String())
	}
	if overview.Payments.OpenAll != 3 {
		t.Fatalf("settled invoices must not count as due: %s", w.Body.String())
	}
	if overview.TeamID != "" || overview.TeamSelectable != true {
		t.Fatalf("an unfiltered overview must report every branch: %s", w.Body.String())
	}
	if len(overview.Teams) == 0 {
		t.Fatal("the workspace branch list is empty")
	}
}

func TestDashboardOverviewHidesInaccessibleRecords(t *testing.T) {
	admin := dashboardFixture(t)
	member := admin
	member.ID = "dash-member"
	member.Email = "dash-member@example.com"
	member.Name = "Dash member"
	member.Role = "member"
	member.TeamID = "team_default"
	hidden := RecordScope{OrgID: admin.OrgID, OwnerID: "another-adviser", TeamID: member.TeamID, Visibility: "private"}
	mu.Lock()
	users[member.Email] = member
	documents = append(documents, Document{RecordScope: hidden, ID: "dash-doc-hidden", CaseID: "dash-pending", DocName: "Private passport", Required: true, Status: "Requested"})
	mu.Unlock()
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}

	w := dailyUserRequest(t, expansionTestMux(), member, "GET", "/api/dashboard/overview?scope=all", nil)
	assertStatus(t, w, 200)
	if body := w.Body.String(); strings.Contains(body, "Private passport") || strings.Contains(body, "another-adviser") || strings.Contains(body, "dash-doc-hidden") {
		t.Fatalf("a private record leaked into the overview: %s", body)
	}
	overview := decodeOverview(t, w)
	// The application itself is organisation-visible, but the hidden required
	// file must not be counted as outstanding for this reader.
	if overview.Completeness.RequiredDocuments != 3 {
		t.Fatalf("completeness must only count readable documents: %s", w.Body.String())
	}
	if overview.TeamSelectable {
		t.Fatal("members must not be offered a branch switcher")
	}
	if len(overview.Teams) != 1 || overview.Teams[0].ID != member.TeamID {
		t.Fatalf("members see their own branch only: %s", w.Body.String())
	}
}

func TestDashboardOverviewRestrictsBranchSelectionToManagers(t *testing.T) {
	admin := dashboardFixture(t)
	if _, err := database.Exec("INSERT OR IGNORE INTO teams VALUES('team_other','" + admin.OrgID + "','Other branch')"); err != nil {
		t.Fatal(err)
	}
	member := admin
	member.ID = "dash-branch-member"
	member.Email = "dash-branch-member@example.com"
	member.Name = "Branch member"
	member.Role = "member"
	member.TeamID = "team_default"
	mu.Lock()
	users[member.Email] = member
	mu.Unlock()
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}
	h := expansionTestMux()

	// A member asking for any other branch is refused without being told whether
	// that branch exists.
	assertStatus(t, dailyUserRequest(t, h, member, "GET", "/api/dashboard/overview?team=team_other", nil), 403)
	assertStatus(t, dailyUserRequest(t, h, member, "GET", "/api/my-work?team=team_other", nil), 403)
	assertStatus(t, dailyUserRequest(t, h, member, "GET", "/api/dashboard/overview?team=team_unknown", nil), 403)
	assertStatus(t, dailyUserRequest(t, h, admin, "GET", "/api/dashboard/overview?scope=invalid", nil), 400)
	assertStatus(t, dailyUserRequest(t, h, admin, "GET", "/api/dashboard/overview?team=team_unknown", nil), 400)
	assertStatus(t, dailyUserRequest(t, h, member, "GET", "/api/dashboard/overview?team=team_default", nil), 200)

	w := dailyUserRequest(t, h, admin, "GET", "/api/dashboard/overview?scope=all&team=team_other", nil)
	assertStatus(t, w, 200)
	overview := decodeOverview(t, w)
	if overview.TeamID != "team_other" || overview.TeamName != "Other branch" || !overview.TeamSelectable {
		t.Fatalf("branch selection was not applied: %s", w.Body.String())
	}
	// Every record in the fixture belongs to the default branch, so the other
	// branch is genuinely empty rather than silently reporting workspace totals.
	if kpiValue(t, overview, "activeCases") != 0 || kpiValue(t, overview, "openLeads") != 0 || overview.Completeness.Applications != 0 {
		t.Fatalf("a branch filter must narrow the figures: %s", w.Body.String())
	}
	for _, category := range []string{"applications", "leads", "documents", "invoicesOverdue"} {
		work := dailyUserRequest(t, h, admin, "GET", "/api/my-work?scope=all&team=team_other&dashboard=1&category="+category, nil)
		assertStatus(t, work, 200)
		var out struct{ Total int }
		json.Unmarshal(work.Body.Bytes(), &out)
		if out.Total != 0 {
			t.Fatalf("empty branch returned records: %s", work.Body.String())
		}
	}
	for _, team := range overview.Teams {
		if team.ID == admin.TeamID && (team.ActiveCases != 2 || team.OpenLeads != 2 || team.DocumentsShort != 2 || team.InvoicesLate != 1) {
			t.Fatalf("branch roll-up is wrong: %+v", team)
		}
	}
	// The branch comparison list stays available so managers can switch back.
	if len(overview.Teams) != 2 {
		t.Fatalf("branch comparison list is wrong: %s", w.Body.String())
	}
}

func TestMyWorkDrillsIntoStagesCompletenessAndPayments(t *testing.T) {
	admin := dashboardFixture(t)
	h := expansionTestMux()

	w := dailyUserRequest(t, h, admin, "GET", "/api/my-work?scope=all&category=caseStages&stage=Ready%20for%20Submission", nil)
	assertStatus(t, w, 200)
	var out struct {
		Items []productivityItem
		Total int
	}
	json.Unmarshal(w.Body.Bytes(), &out)
	if out.Total != 1 || len(out.Items) != 1 || out.Items[0].ID != "dash-ready" {
		t.Fatalf("stage drill-down must list that stage only: %s", w.Body.String())
	}

	w = dailyUserRequest(t, h, admin, "GET", "/api/my-work?scope=all&category=caseStages", nil)
	assertStatus(t, w, 200)
	json.Unmarshal(w.Body.Bytes(), &out)
	if out.Total != 2 {
		t.Fatalf("the stage view must exclude closed applications: %s", w.Body.String())
	}

	w = dailyUserRequest(t, h, admin, "GET", "/api/my-work?scope=all&category=documentsComplete", nil)
	assertStatus(t, w, 200)
	json.Unmarshal(w.Body.Bytes(), &out)
	if out.Total != 0 {
		t.Fatalf("no application has a complete checklist here: %s", w.Body.String())
	}

	w = dailyUserRequest(t, h, admin, "GET", "/api/my-work?scope=all&category=invoicesOverdue", nil)
	assertStatus(t, w, 200)
	json.Unmarshal(w.Body.Bytes(), &out)
	if out.Total != 1 || out.Items[0].ID != "dash-inv-overdue" {
		t.Fatalf("overdue invoice drill-down is wrong: %s", w.Body.String())
	}

	w = dailyUserRequest(t, h, admin, "GET", "/api/my-work?scope=all&category=invoicesDueSoon", nil)
	assertStatus(t, w, 200)
	json.Unmarshal(w.Body.Bytes(), &out)
	if out.Total != 1 || out.Items[0].ID != "dash-inv-soon" {
		t.Fatalf("due-soon invoice drill-down is wrong: %s", w.Body.String())
	}

	var counts struct {
		Counts map[string]int
	}
	w = dailyUserRequest(t, h, admin, "GET", "/api/my-work?scope=all", nil)
	json.Unmarshal(w.Body.Bytes(), &counts)
	if counts.Counts["invoicesOverdue"] != 1 || counts.Counts["invoicesDueSoon"] != 1 || counts.Counts["documentsComplete"] != 0 {
		t.Fatalf("new summary counts are missing: %s", w.Body.String())
	}

	assertStatus(t, dailyUserRequest(t, h, admin, "GET", "/api/my-work?category=invoices&stage=Submitted", nil), 400)
	assertStatus(t, dailyUserRequest(t, h, admin, "GET", "/api/my-work?category=caseStages&stage=Unknown", nil), 400)
}

func TestDashboardDrillDownMatchesWholeRecordSets(t *testing.T) {
	admin := dashboardFixture(t)
	h := expansionTestMux()
	for _, check := range []struct {
		query string
		count int
	}{
		{"category=caseStages&stage=Closed", 1},
		{"category=applications&dashboard=1", 2},
		{"category=leads&dashboard=1", 2},
		{"category=followups&dashboard=1", 1},
		{"category=documents&dashboard=1", 2},
		{"category=invoices&dashboard=1", 3},
		{"category=caseStages&stage=Closed&team=" + admin.TeamID, 1},
	} {
		w := dailyUserRequest(t, h, admin, "GET", "/api/my-work?scope=all&"+check.query, nil)
		assertStatus(t, w, 200)
		var out struct{ Total int }
		if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		if out.Total != check.count {
			t.Fatalf("%s: expected %d records, got %s", check.query, check.count, w.Body.String())
		}
	}
	assertStatus(t, dailyUserRequest(t, h, admin, "GET", "/api/my-work?team=unknown", nil), 400)
}
