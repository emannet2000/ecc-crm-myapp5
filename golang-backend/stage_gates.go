package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
)

type gateDenied struct{ message string }

func (e gateDenied) Error() string { return e.message }

type StageGateRule struct {
	Stage             string   `json:"stage"`
	Enabled           bool     `json:"enabled"`
	RequiredDocuments bool     `json:"requiredDocuments"`
	DocumentNames     []string `json:"documentNames"`
	Uploaded          bool     `json:"uploaded"`
	Reviewed          bool     `json:"reviewed"`
	Verified          bool     `json:"verified"`
	ManagerApproval   bool     `json:"managerApproval"`
	Revision          string   `json:"revision,omitempty"`
}

func gatePolicy(r *http.Request, org, stage string) (StageGateRule, error) {
	rule := StageGateRule{Stage: stage, DocumentNames: []string{}}
	rows, err := queryObjects(r, "SELECT data FROM application_gate_rules WHERE org_id=? AND stage=?", org, stage)
	if err != nil {
		return rule, err
	}
	if len(rows) > 0 {
		err = json.Unmarshal([]byte(fmtString(rows[0]["data"])), &rule)
	}
	rule.Revision = versionOf(recordMap(rule))
	return rule, err
}
func gateDocuments(c Case, s diskStore, rule StageGateRule) []Document {
	out := []Document{}
	for _, d := range s.Documents {
		if d.CaseID != c.ID || d.OrgID != c.OrgID {
			continue
		}
		selected := rule.RequiredDocuments && d.Required
		for _, name := range rule.DocumentNames {
			if strings.EqualFold(strings.TrimSpace(name), strings.TrimSpace(d.DocName)) {
				selected = true
			}
		}
		if selected {
			out = append(out, d)
		}
	}
	return out
}
func gateFingerprint(c Case, docs []Document, rule StageGateRule) string {
	sort.Slice(docs, func(i, j int) bool { return docs[i].ID < docs[j].ID })
	record := recordMap(c)
	delete(record, "currentStage")
	return versionOf(map[string]any{"application": record, "documents": docs, "rule": rule})
}
func evaluateStageGate(r *http.Request, c Case, s diskStore, rule StageGateRule) ([]string, string, error) {
	docs := gateDocuments(c, s, rule)
	fingerprint := gateFingerprint(c, docs, rule)
	issues := []string{}
	if !rule.Enabled {
		return issues, fingerprint, nil
	}
	if rule.RequiredDocuments && len(docs) == 0 {
		issues = append(issues, "Configure required documents for this application")
	}
	for _, name := range rule.DocumentNames {
		found := false
		for _, d := range docs {
			if strings.EqualFold(strings.TrimSpace(name), strings.TrimSpace(d.DocName)) {
				found = true
			}
		}
		if !found {
			issues = append(issues, "Add the required document: "+name)
		}
	}
	today := todayForOrgDB(storeDB(r), c.OrgID)
	for _, d := range docs {
		label := d.DocName
		if !canRead(d.RecordScope, currentUser(r)) {
			label = "A restricted document"
		}
		if d.ExpiryDate != "" && d.ExpiryDate < today {
			issues = append(issues, label+" has expired")
		}
		if rule.Uploaded || rule.Reviewed || rule.Verified {
			var count int
			if err := storeDB(r).QueryRow("SELECT count(*) FROM file_versions WHERE org_id=? AND document_id=? AND version=?", c.OrgID, d.ID, d.LatestVersion).Scan(&count); err != nil {
				return nil, fingerprint, err
			}
			if d.LatestVersion < 1 || d.FilePath == "" || count == 0 {
				issues = append(issues, label+" needs an uploaded file")
				continue
			}
		}
		if rule.Reviewed && (d.ReviewedVersion != d.LatestVersion || d.ReviewedBy == "" || d.ReviewedAt == "") {
			issues = append(issues, label+" needs review of its current version")
		}
		if rule.Verified && d.Status != "Verified" {
			issues = append(issues, label+" needs verification")
		}
	}
	if rule.ManagerApproval {
		var count int
		err := storeDB(r).QueryRow("SELECT count(*) FROM application_gate_approvals WHERE org_id=? AND case_id=? AND stage=? AND fingerprint=?", c.OrgID, c.ID, rule.Stage, fingerprint).Scan(&count)
		if err != nil {
			return nil, fingerprint, err
		}
		if count == 0 {
			issues = append(issues, "A manager must approve the current application and document versions")
		}
	}
	return issues, fingerprint, nil
}
func handleGatePolicies(w http.ResponseWriter, r *http.Request) {
	if !isManager(currentUser(r)) {
		writeError(w, 403, "Manager access is required")
		return
	}
	if r.Method == "GET" {
		rules := []StageGateRule{}
		for _, stage := range validCaseStages {
			rule, e := gatePolicy(r, currentUser(r).OrgID, stage)
			if e != nil {
				writeError(w, 500, "Could not load stage policies")
				return
			}
			rules = append(rules, rule)
		}
		writeJSON(w, 200, map[string]any{"rules": rules, "stages": validCaseStages})
		return
	}
	var rule StageGateRule
	if !decodeRequest(w, r, &rule) {
		return
	}
	if !isValidCaseStage(rule.Stage) || len(rule.DocumentNames) > 20 {
		writeError(w, 400, "Choose a valid stage and up to 20 document names")
		return
	}
	for i, name := range rule.DocumentNames {
		rule.DocumentNames[i] = strings.TrimSpace(name)
		if rule.DocumentNames[i] == "" || len(name) > 200 {
			writeError(w, 400, "Enter document names of 1–200 characters")
			return
		}
	}
	current, err := gatePolicy(r, currentUser(r).OrgID, rule.Stage)
	if err != nil {
		writeError(w, 500, "Could not load stage gate")
		return
	}
	if rule.Revision == "" || rule.Revision != current.Revision {
		writeError(w, 409, "Stage policy changed. Reload it before saving.")
		return
	}
	if rule.Enabled && !rule.RequiredDocuments && len(rule.DocumentNames) == 0 && !rule.ManagerApproval {
		writeError(w, 400, "Choose document requirements or manager approval")
		return
	}
	rule.Revision = ""
	_, err = storeDB(r).Exec("INSERT INTO application_gate_rules(org_id,stage,data) VALUES(?,?,?) ON CONFLICT(org_id,stage) DO UPDATE SET data=excluded.data", currentUser(r).OrgID, rule.Stage, mustJSON(rule))
	if err != nil || securityEvent(r, currentUser(r), "application.gate_policy_updated:"+rule.Stage) != nil {
		writeError(w, 500, "Could not save stage policy")
		return
	}
	writeJSON(w, 200, map[string]any{"saved": true})
}
func loadGateCase(w http.ResponseWriter, r *http.Request) (Case, diskStore, bool) {
	state, done := runtimeForReadCall(r)
	defer done()
	s := state.snapshot()
	for _, c := range s.Cases {
		if c.ID == r.PathValue("id") {
			rows, err := queryObjects(r, "SELECT data FROM documents WHERE json_extract(data,'$.caseId')=? AND json_extract(data,'$.orgId')=? ORDER BY sort_order,id", c.ID, c.OrgID)
			if err != nil {
				writeError(w, 500, "Could not check application documents")
				return Case{}, s, false
			}
			s.Documents = nil
			for _, row := range rows {
				var doc Document
				if json.Unmarshal([]byte(fmtString(row["data"])), &doc) != nil {
					writeError(w, 500, "Could not check application documents")
					return Case{}, s, false
				}
				s.Documents = append(s.Documents, doc)
			}
			return c, s, true
		}
	}
	writeError(w, 404, "Application not found")
	return Case{}, s, false
}
func handleCaseGates(w http.ResponseWriter, r *http.Request) {
	c, s, ok := loadGateCase(w, r)
	if !ok {
		return
	}
	previews := []map[string]any{}
	for _, stage := range validCaseStages {
		rule, err := gatePolicy(r, c.OrgID, stage)
		if err != nil {
			writeError(w, 500, "Could not load gates")
			return
		}
		issues, fp, err := evaluateStageGate(r, c, s, rule)
		if err != nil {
			writeError(w, 500, "Could not check gates")
			return
		}
		previews = append(previews, map[string]any{"rule": rule, "issues": issues, "fingerprint": fp})
	}
	history, err := queryObjects(r, "SELECT id,data,created_at AS createdAt FROM workspace_entries WHERE org_id=? AND record_id=? AND category IN ('application_transition','application_gate_approval') ORDER BY created_at DESC,id LIMIT 25", c.OrgID, c.ID)
	if err != nil {
		writeError(w, 500, "Could not load transition history")
		return
	}
	writeJSON(w, 200, map[string]any{"case": c, "stages": previews, "history": history, "editable": canWrite(c.RecordScope, currentUser(r)), "manager": isManager(currentUser(r)), "revision": versionOf(recordMap(c))})
}
func gateEntry(r *http.Request, c Case, category string, data any) error {
	_, err := storeDB(r).Exec("INSERT INTO workspace_entries VALUES(?,?,?,?,?,?,?,?)", newID("gate"), c.OrgID, category, currentUser(r).ID, c.ID, mustJSON(data), utcNow(), utcNow())
	return err
}
func handleGateApproval(w http.ResponseWriter, r *http.Request) {
	if !isManager(currentUser(r)) {
		writeError(w, 403, "Manager approval is required")
		return
	}
	c, s, ok := loadGateCase(w, r)
	if !ok {
		return
	}
	var in struct {
		Stage       string
		Fingerprint string
		Reason      string
	}
	if !decodeRequest(w, r, &in) {
		return
	}
	rule, err := gatePolicy(r, c.OrgID, in.Stage)
	if err != nil || !rule.Enabled || !rule.ManagerApproval {
		writeError(w, 400, "This stage does not require approval")
		return
	}
	_, fp, err := evaluateStageGate(r, c, s, rule)
	if err != nil {
		writeError(w, 500, "Could not check application")
		return
	}
	if fp != in.Fingerprint || strings.Trim(r.Header.Get("If-Match"), "\"") != versionOf(recordMap(c)) {
		writeError(w, 409, "Application or documents changed. Review again before approving.")
		return
	}
	if strings.TrimSpace(in.Reason) == "" || len(in.Reason) > 2000 {
		writeError(w, 400, "Enter the approval review note")
		return
	}
	_, err = storeDB(r).Exec("INSERT OR IGNORE INTO application_gate_approvals VALUES(?,?,?,?,?,?,?)", c.OrgID, c.ID, in.Stage, fp, currentUser(r).ID, in.Reason, utcNow())
	if err == nil {
		err = gateEntry(r, c, "application_gate_approval", map[string]any{"stage": in.Stage, "reason": in.Reason, "actor": currentUser(r).Name, "fingerprint": fp})
	}
	if err != nil {
		writeError(w, 500, "Could not save approval")
		return
	}
	writeJSON(w, 200, map[string]any{"approved": true})
}
func handleCaseTransition(w http.ResponseWriter, r *http.Request) {
	c, _, ok := loadGateCase(w, r)
	if !ok {
		return
	}
	var in struct {
		Stage    string
		Override bool
		Reason   string
	}
	if !decodeRequest(w, r, &in) {
		return
	}
	if !canWrite(c.RecordScope, currentUser(r)) {
		writeError(w, 403, "You cannot edit this application")
		return
	}
	if !isValidCaseStage(in.Stage) {
		writeError(w, 400, "Choose a valid stage")
		return
	}
	if strings.Trim(r.Header.Get("If-Match"), "\"") != versionOf(recordMap(c)) {
		writeError(w, 409, "Application changed. Refresh before moving stage.")
		return
	}
	if in.Override {
		if !isManager(currentUser(r)) {
			writeError(w, 403, "Only managers can override a gate")
			return
		}
		if strings.TrimSpace(in.Reason) == "" || len(in.Reason) > 2000 {
			writeError(w, 400, "Explain the manager override")
			return
		}
		meta := metadata(r)
		if meta.GateOverrides == nil {
			meta.GateOverrides = map[string]string{}
		}
		meta.GateOverrides[c.ID] = in.Reason
	}
	state, done := runtimeForCall(r)
	defer done()
	state.mu.Lock()
	for i := range state.cases {
		if state.cases[i].ID == c.ID {
			state.cases[i].CurrentStage = in.Stage
		}
	}
	state.mu.Unlock()
	writeJSON(w, 200, map[string]any{"saved": true})
}

// applicationStageFollowUp creates the single task a stage change makes
// necessary. It runs inside the same transaction as the change, so the task and
// the transition share one audit entry, and it is idempotent: an equivalent open
// task is never duplicated. Existing business logic supplies the facts — the
// checklist decides whether documents are outstanding and the case itself
// supplies the owner and deadline.
func applicationStageFollowUp(after *diskStore, c Case, today string) {
	if !activeApplication(c.CurrentStage) {
		return
	}
	title, description := "", ""
	switch {
	case strings.TrimSpace(c.NextAction) == "":
		title = "Record the next action: " + c.CaseNumber
		description = c.CaseNumber + " moved to " + c.CurrentStage + " without a next staff action."
	default:
		submissionStage := c.CurrentStage == "Ready for Submission" || c.CurrentStage == "Submitted"
		if !submissionStage {
			return
		}
		for _, d := range after.Documents {
			if d.CaseID != c.ID || !d.Required || !documentNeedsReview(d, today) {
				continue
			}
			title = "Complete required documents: " + c.CaseNumber
			description = c.CaseNumber + " is at " + c.CurrentStage + " and still needs " + d.DocName + " (" + d.Status + ")."
			break
		}
	}
	if title == "" {
		return
	}
	for _, existing := range after.Tasks {
		if existing.ContactID == c.ClientID && existing.Title == title && existing.Status != "done" {
			return
		}
	}
	due := c.NextDeadline
	if due == "" {
		due = today
	}
	after.Tasks = append(after.Tasks, Task{RecordScope: c.RecordScope, ID: newID("t"), Title: title, Description: description, Status: "todo", DueDate: due, ContactID: c.ClientID, ContactName: c.ClientName, Owner: c.AssignedOfficer, CreatedAt: today})
}

// Every persisted stage change is checked, including edits through legacy forms.
func enforceApplicationGates(r *http.Request, before diskStore, after *diskStore) error {
	old := map[string]Case{}
	for _, c := range before.Cases {
		old[c.ID] = c
	}
	for i, c := range after.Cases {
		previous, exists := old[c.ID]
		if exists && previous.CurrentStage == c.CurrentStage {
			continue
		}
		rule, err := gatePolicy(r, c.OrgID, c.CurrentStage)
		if err != nil {
			return err
		}
		issues, _, err := evaluateStageGate(r, c, *after, rule)
		if err != nil {
			return err
		}
		override := ""
		if meta := metadata(r); meta != nil {
			override = meta.GateOverrides[c.ID]
		}
		if len(issues) > 0 && override == "" {
			explicit := strings.HasPrefix(r.URL.Path, "/api/cases") || strings.Contains(r.URL.Path, "/transition")
			if exists && c.AutoAdvance && !explicit {
				after.Cases[i].CurrentStage = previous.CurrentStage
				continue
			}
			return gateDenied{fmt.Sprintf("Stage gate for %s: %s", c.CurrentStage, strings.Join(issues, "; "))}
		}
		applicationStageFollowUp(after, c, todayForOrgDB(storeDB(r), c.OrgID))
		if !rule.Enabled && override == "" {
			continue
		}
		if err := gateEntry(r, c, "application_transition", map[string]any{"from": previous.CurrentStage, "stage": c.CurrentStage, "override": override != "", "reason": override, "actor": currentUser(r).Name, "issues": issues}); err != nil {
			return err
		}
	}
	return nil
}
