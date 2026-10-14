package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"sort"
	"strings"
)

// The dashboard overview is a read-only roll-up of the records the signed-in
// staff member can already read. It introduces no new source of truth: every
// number comes from the same scoped SQL snapshot that feeds My work today, and
// a team (branch) filter is applied on top of record visibility so a branch view
// can never widen access.

type dashboardKPI struct {
	Key      string `json:"key"`
	Label    string `json:"label"`
	Value    int    `json:"value"`
	Hint     string `json:"hint"`
	Category string `json:"category"`
	Stage    string `json:"stage,omitempty"`
	Severity string `json:"severity,omitempty"`
}

type dashboardStage struct {
	Stage  string `json:"stage"`
	Count  int    `json:"count"`
	Active bool   `json:"active"`
}

type dashboardCompleteness struct {
	Applications      int `json:"applications"`
	Complete          int `json:"complete"`
	Incomplete        int `json:"incomplete"`
	NoRequirements    int `json:"noRequirements"`
	RequiredDocuments int `json:"requiredDocuments"`
	VerifiedDocuments int `json:"verifiedDocuments"`
	ExpiredDocuments  int `json:"expiredDocuments"`
	OutstandingFiles  int `json:"outstandingFiles"`
	CompletePercent   int `json:"completePercent"`
}

type dashboardPaymentBucket struct {
	Currency string  `json:"currency"`
	Amount   float64 `json:"amount"`
	Count    int     `json:"count"`
}

type dashboardPayments struct {
	Overdue    []dashboardPaymentBucket `json:"overdue"`
	DueSoon    []dashboardPaymentBucket `json:"dueSoon"`
	Later      []dashboardPaymentBucket `json:"later"`
	NoDueDate  []dashboardPaymentBucket `json:"noDueDate"`
	OverdueAll int                      `json:"overdueCount"`
	DueSoonAll int                      `json:"dueSoonCount"`
	OpenAll    int                      `json:"openCount"`
	Pending    int                      `json:"pendingApprovals"`
}

type dashboardTeam struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Members        int    `json:"members"`
	ActiveCases    int    `json:"activeCases"`
	OpenLeads      int    `json:"openLeads"`
	FollowUpsDue   int    `json:"followUpsDue"`
	DocumentsShort int    `json:"documentsIncomplete"`
	InvoicesLate   int    `json:"invoicesOverdue"`
	Selected       bool   `json:"selected"`
}

// dashboardTally accumulates the branch (team) counters in a single pass so the
// overview never rescans the snapshot per branch.
type dashboardTally struct {
	activeCases    int
	openLeads      int
	followUpsDue   int
	documentsShort int
	invoicesLate   int
}

type dashboardOverview struct {
	Today          string                `json:"today"`
	GeneratedAt    string                `json:"generatedAt"`
	Scope          string                `json:"scope"`
	TeamID         string                `json:"teamId"`
	TeamName       string                `json:"teamName"`
	TeamSelectable bool                  `json:"teamSelectable"`
	KPI            []dashboardKPI        `json:"kpi"`
	Cases          []dashboardStage      `json:"caseStages"`
	Completeness   dashboardCompleteness `json:"documentCompleteness"`
	Payments       dashboardPayments     `json:"paymentsDue"`
	Teams          []dashboardTeam       `json:"teams"`
}

type dashboardFilter struct {
	assignment string
	team       string
}

func (f dashboardFilter) allows(user User, scope RecordScope, owner string) bool {
	if scope.OrgID != user.OrgID || !canRead(scope, user) || !workAssigned(owner, scope, user, f.assignment) {
		return false
	}
	return f.team == "" || scope.TeamID == f.team
}

// dashboardSnapshot opens one read-only transaction so the overview reports a
// single committed state rather than totals sampled across requests.
func dashboardSnapshot(w http.ResponseWriter, r *http.Request) (*http.Request, diskStore, func(), bool) {
	tx, err := database.BeginTx(r.Context(), &sql.TxOptions{ReadOnly: true})
	if err != nil {
		writeError(w, 503, "Database unavailable; try Refresh again")
		return r, diskStore{}, func() {}, false
	}
	r = r.WithContext(context.WithValue(r.Context(), requestTxKey, tx))
	s, err := dashboardWorkspace(r)
	if err != nil {
		tx.Rollback()
		writeError(w, 500, "Could not load workspace records")
		return r, s, func() {}, false
	}
	return r, s, func() { tx.Rollback() }, true
}

// dashboardWorkspace loads only the modules the overview counts, matching the
// trimmed snapshot used by My work today so both screens agree on visibility.
func dashboardWorkspace(r *http.Request) (diskStore, error) {
	var s diskStore
	var err error
	if s.Cases, err = readScopedRows[Case](r, "cases"); err != nil {
		return s, err
	}
	if s.Leads, err = readScopedRows[Lead](r, "leads"); err != nil {
		return s, err
	}
	if s.Invoices, err = readScopedRows[Invoice](r, "invoices"); err != nil {
		return s, err
	}
	docs, err := readScopedRows[Document](r, "documents")
	if err != nil {
		return s, err
	}
	visible := map[string]bool{}
	for _, c := range s.Cases {
		visible[c.ID] = true
	}
	s.Documents = docs[:0]
	for _, d := range docs {
		if d.CaseID != "" && visible[d.CaseID] {
			s.Documents = append(s.Documents, d)
		}
	}
	return s, nil
}

// resolveDashboardFilter validates the assignment and branch selectors. Members
// stay on their own branch; managers and administrators may inspect any branch
// in their workspace. An unknown branch is rejected rather than silently ignored.
func resolveDashboardFilter(w http.ResponseWriter, r *http.Request) (dashboardFilter, bool) {
	user := currentUser(r)
	assignment := r.URL.Query().Get("scope")
	if assignment == "" {
		assignment = "mine"
	}
	if assignment != "mine" && assignment != "unassigned" && assignment != "all" {
		writeError(w, 400, "Choose mine, unassigned or all")
		return dashboardFilter{}, false
	}
	team := strings.TrimSpace(r.URL.Query().Get("team"))
	if team != "" && team != user.TeamID && !isManager(user) {
		writeError(w, 403, "Only managers and administrators can view another branch")
		return dashboardFilter{}, false
	}
	if team != "" && !teamInOrganization(r, team) {
		writeError(w, 400, "Choose a branch from your workspace")
		return dashboardFilter{}, false
	}
	return dashboardFilter{assignment: assignment, team: team}, true
}

func mergePaymentBucket(rows map[string]*dashboardPaymentBucket, currency string, amount float64) {
	if currency == "" {
		currency = "USD"
	}
	if rows[currency] == nil {
		rows[currency] = &dashboardPaymentBucket{Currency: currency}
	}
	rows[currency].Amount = money(rows[currency].Amount + amount)
	rows[currency].Count++
}

func sortedPaymentBuckets(rows map[string]*dashboardPaymentBucket) []dashboardPaymentBucket {
	out := make([]dashboardPaymentBucket, 0, len(rows))
	for _, row := range rows {
		out = append(out, *row)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Currency < out[j].Currency })
	return out
}

func severityFor(condition bool) string {
	if condition {
		return "attention"
	}
	return ""
}

func containsStage(stages []string, value string) bool {
	for _, stage := range stages {
		if stage == value {
			return true
		}
	}
	return false
}

func teamName(r *http.Request, id string) string {
	name := ""
	storeDB(r).QueryRow("SELECT name FROM teams WHERE id=? AND org_id=?", id, currentUser(r).OrgID).Scan(&name)
	if name == "" {
		return "Branch"
	}
	return name
}

// workspaceTeams lists the branches of the current organization with their
// active staff counts. It is the only team-shaped query in this file.
func workspaceTeams(r *http.Request) []dashboardTeam {
	rows, err := storeDB(r).Query("SELECT t.id,t.name,count(u.id) FROM teams t LEFT JOIN users u ON u.team_id=t.id AND u.org_id=t.org_id AND u.disabled=0 WHERE t.org_id=? GROUP BY t.id,t.name ORDER BY t.name", currentUser(r).OrgID)
	if err != nil {
		return []dashboardTeam{}
	}
	defer rows.Close()
	out := []dashboardTeam{}
	for rows.Next() {
		var team dashboardTeam
		if rows.Scan(&team.ID, &team.Name, &team.Members) != nil {
			break
		}
		out = append(out, team)
	}
	return out
}

func handleDashboardOverview(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "private, no-store")
	filter, ok := resolveDashboardFilter(w, r)
	if !ok {
		return
	}
	r, s, close, ok := dashboardSnapshot(w, r)
	if !ok {
		return
	}
	defer close()
	user := currentUser(r)
	today := organizationToday(r)

	pendingApprovals, err := pendingInvoiceReceiptCounts(r)
	if err != nil {
		writeError(w, 500, "Could not load receipt approval totals")
		return
	}

	// A branch roll-up ignores the requested branch so managers can compare, but
	// still honours visibility and the assignment filter for every record.
	all := dashboardFilter{assignment: filter.assignment}
	tallies := map[string]*dashboardTally{}
	for _, team := range workspaceTeams(r) {
		tallies[team.ID] = &dashboardTally{}
	}

	stageCounts := map[string]int{}
	stageActive := map[string]bool{}
	for _, c := range s.Cases {
		if !all.allows(user, c.RecordScope, c.AssignedOfficer) {
			continue
		}
		if activeApplication(c.CurrentStage) {
			if tally := tallies[c.TeamID]; tally != nil {
				tally.activeCases++
			}
		}
		// The stage summary follows the selected branch; the comparison tallies
		// above deliberately ignore it so managers can switch between branches.
		if !filter.allows(user, c.RecordScope, c.AssignedOfficer) {
			continue
		}
		stageCounts[c.CurrentStage]++
		if activeApplication(c.CurrentStage) {
			stageActive[c.CurrentStage] = true
		}
	}

	// Document completeness is a property of the whole checklist, so it is
	// measured per application rather than per document.
	required, verified, expired := map[string]int{}, map[string]int{}, map[string]int{}
	for _, d := range s.Documents {
		if !d.Required {
			continue
		}
		required[d.CaseID]++
		distance, dated := dateDistance(d.ExpiryDate, today)
		switch {
		case dated && distance < 0:
			expired[d.CaseID]++
		case strings.EqualFold(d.Status, "Verified"):
			verified[d.CaseID]++
		}
	}
	completeness := dashboardCompleteness{}
	for _, c := range s.Cases {
		if !activeApplication(c.CurrentStage) || !all.allows(user, c.RecordScope, c.AssignedOfficer) {
			continue
		}
		if required[c.ID] > verified[c.ID] {
			if tally := tallies[c.TeamID]; tally != nil {
				tally.documentsShort++
			}
		}
		if !filter.allows(user, c.RecordScope, c.AssignedOfficer) {
			continue
		}
		completeness.Applications++
		completeness.RequiredDocuments += required[c.ID]
		completeness.VerifiedDocuments += verified[c.ID]
		completeness.ExpiredDocuments += expired[c.ID]
		if required[c.ID] == 0 {
			completeness.NoRequirements++
			continue
		}
		if verified[c.ID] == required[c.ID] {
			completeness.Complete++
			continue
		}
		completeness.Incomplete++
		completeness.OutstandingFiles += required[c.ID] - verified[c.ID]
	}
	if completeness.Applications > 0 {
		completeness.CompletePercent = completeness.Complete * 100 / completeness.Applications
	}

	payments := dashboardPayments{}
	overdueRows, dueSoonRows, laterRows, noDateRows := map[string]*dashboardPaymentBucket{}, map[string]*dashboardPaymentBucket{}, map[string]*dashboardPaymentBucket{}, map[string]*dashboardPaymentBucket{}
	overdueCount, dueSoonCount, openCount, approvalCount := 0, 0, 0, 0
	for _, inv := range s.Invoices {
		if !all.allows(user, inv.RecordScope, inv.OwnerID) {
			continue
		}
		approvals := pendingApprovals[inv.ID]
		open := inv.Balance > 0 || approvals > 0
		distance, dated := dateDistance(inv.DueDate, today)
		if inv.Balance > 0 && dated && distance < 0 {
			if tally := tallies[inv.TeamID]; tally != nil {
				tally.invoicesLate++
			}
		}
		if !filter.allows(user, inv.RecordScope, inv.OwnerID) {
			continue
		}
		approvalCount += approvals
		if !open {
			continue
		}
		openCount++
		if inv.Balance <= 0 {
			// The balance is already covered by receipts awaiting approval, so
			// there is no money due yet.
			continue
		}
		switch {
		case !dated:
			mergePaymentBucket(noDateRows, inv.Currency, inv.Balance)
		case distance < 0:
			overdueCount++
			mergePaymentBucket(overdueRows, inv.Currency, inv.Balance)
		case distance <= 7:
			dueSoonCount++
			mergePaymentBucket(dueSoonRows, inv.Currency, inv.Balance)
		default:
			mergePaymentBucket(laterRows, inv.Currency, inv.Balance)
		}
	}
	payments.Overdue, payments.DueSoon = sortedPaymentBuckets(overdueRows), sortedPaymentBuckets(dueSoonRows)
	payments.Later, payments.NoDueDate = sortedPaymentBuckets(laterRows), sortedPaymentBuckets(noDateRows)
	payments.OverdueAll, payments.DueSoonAll, payments.OpenAll, payments.Pending = overdueCount, dueSoonCount, openCount, approvalCount

	openLeads, followUpsDue, followUpsOverdue, followUpsToday, followUpsUpcoming, qualifying := 0, 0, 0, 0, 0, 0
	for _, l := range s.Leads {
		if !all.allows(user, l.RecordScope, l.AssignedTo) || !openLead(l.Status) {
			continue
		}
		distance, dated := dateDistance(l.FollowUpDate, today)
		if tally := tallies[l.TeamID]; tally != nil {
			tally.openLeads++
			if dated && distance <= 0 {
				tally.followUpsDue++
			}
		}
		if !filter.allows(user, l.RecordScope, l.AssignedTo) {
			continue
		}
		openLeads++
		if l.Status == "New" || l.Status == "Contacted" {
			qualifying++
		}
		if !dated {
			continue
		}
		switch {
		case distance < 0:
			followUpsDue++
			followUpsOverdue++
		case distance == 0:
			followUpsDue++
			followUpsToday++
		default:
			followUpsUpcoming++
		}
	}

	teams := workspaceTeams(r)
	if !isManager(user) && user.TeamID != "" {
		own := []dashboardTeam{}
		for _, team := range teams {
			if team.ID == user.TeamID {
				own = append(own, team)
			}
		}
		if len(own) == 0 {
			own = append(own, dashboardTeam{ID: user.TeamID, Name: "My branch"})
		}
		teams = own
	}
	for i := range teams {
		teams[i].Selected = teams[i].ID == filter.team || filter.team == "" && teams[i].ID == user.TeamID
		tally := tallies[teams[i].ID]
		if tally != nil {
			teams[i].ActiveCases = tally.activeCases
			teams[i].OpenLeads = tally.openLeads
			teams[i].FollowUpsDue = tally.followUpsDue
			teams[i].DocumentsShort = tally.documentsShort
			teams[i].InvoicesLate = tally.invoicesLate
		}
	}

	stages := make([]dashboardStage, 0, len(validCaseStages))
	for _, stage := range validCaseStages {
		if count := stageCounts[stage]; count > 0 {
			stages = append(stages, dashboardStage{Stage: stage, Count: count, Active: stageActive[stage]})
		}
	}
	// Stages written by an older build are reported rather than silently dropped.
	unknown := []string{}
	for stage, count := range stageCounts {
		if count > 0 && !containsStage(validCaseStages, stage) {
			unknown = append(unknown, stage)
		}
	}
	sort.Strings(unknown)
	for _, stage := range unknown {
		stages = append(stages, dashboardStage{Stage: stage, Count: stageCounts[stage], Active: stageActive[stage]})
	}

	activeCases, readyForSubmission := 0, 0
	for _, stage := range stages {
		if stage.Active {
			activeCases += stage.Count
		}
		if stage.Stage == "Ready for Submission" {
			readyForSubmission = stage.Count
		}
	}

	overview := dashboardOverview{
		Today: today, GeneratedAt: utcNow(), Scope: filter.assignment,
		TeamID: filter.team, TeamSelectable: isManager(user),
		Cases: stages, Completeness: completeness, Payments: payments, Teams: teams,
	}
	if filter.team != "" {
		overview.TeamName = teamName(r, filter.team)
	}
	overview.KPI = []dashboardKPI{
		{Key: "activeCases", Label: "Active applications", Value: activeCases, Hint: "Not approved, refused or closed", Category: "applications"},
		{Key: "openLeads", Label: "Open leads", Value: openLeads, Hint: fmt.Sprintf("%d still in qualification", qualifying), Category: "leads"},
		{Key: "followUpsDue", Label: "Follow-ups due", Value: followUpsDue, Hint: fmt.Sprintf("%d overdue", followUpsOverdue), Category: "followups", Severity: severityFor(followUpsOverdue > 0)},
		{Key: "followUpsToday", Label: "Follow-ups today", Value: followUpsToday, Hint: "Due on the workspace date", Category: "followupsToday"},
		{Key: "followUpsUpcoming", Label: "Upcoming follow-ups", Value: followUpsUpcoming, Hint: "Scheduled after the workspace date", Category: "followupsUpcoming"},
		{Key: "followUpsOverdue", Label: "Overdue follow-ups", Value: followUpsOverdue, Hint: "Follow-up date has passed", Category: "overdueLeads", Severity: severityFor(followUpsOverdue > 0)},
		{Key: "documentsIncomplete", Label: "Applications needing documents", Value: completeness.Incomplete, Hint: fmt.Sprintf("%d required files outstanding", completeness.OutstandingFiles), Category: "documents", Severity: severityFor(completeness.Incomplete > 0)},
		{Key: "documentsComplete", Label: "Documents complete", Value: completeness.Complete, Hint: fmt.Sprintf("%d%% of active applications", completeness.CompletePercent), Category: "documentsComplete"},
		{Key: "readyForSubmission", Label: "Ready for submission", Value: readyForSubmission, Hint: "Awaiting submission or a decision", Category: "caseStages", Stage: "Ready for Submission"},
		{Key: "invoicesOverdue", Label: "Payments overdue", Value: overdueCount, Hint: fmt.Sprintf("%d outstanding invoices in total", openCount), Category: "invoicesOverdue", Severity: severityFor(overdueCount > 0)},
		{Key: "invoicesDueSoon", Label: "Payments due this week", Value: dueSoonCount, Hint: "Due within seven days", Category: "invoicesDueSoon"},
	}
	writeJSON(w, 200, overview)
}
