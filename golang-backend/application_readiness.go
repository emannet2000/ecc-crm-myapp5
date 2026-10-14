package main

import (
	"encoding/json"
	"net/http"
	"strings"
)

// Submission readiness answers one question for one application: can this
// application move to its next submission stage right now? It reuses the
// existing checklist, stage-gate and handoff logic rather than introducing a
// second rule set, and it reports the accessible records only.

type readinessItem struct {
	Kind     string `json:"kind"`
	Title    string `json:"title"`
	Detail   string `json:"detail"`
	Action   string `json:"action"`
	Route    string `json:"route"`
	Blocking bool   `json:"blocking"`
}

type readinessGate struct {
	Stage     string   `json:"stage"`
	Enabled   bool     `json:"enabled"`
	Satisfied bool     `json:"satisfied"`
	Issues    []string `json:"issues"`
}

type readinessBalance struct {
	Currency       string  `json:"currency"`
	Outstanding    float64 `json:"outstanding"`
	PendingReceipt int     `json:"pendingReceipts"`
	Refunds        int     `json:"refunds"`
}

// submissionTarget returns the stage this application is trying to reach. The
// canonical order in validCaseStages drives the answer, so a stage added later
// needs no change here.
func submissionTarget(stage string) string {
	found := false
	for _, candidate := range validCaseStages {
		if candidate == stage {
			found = true
			continue
		}
		if found && candidate == "Submitted" {
			return candidate
		}
	}
	if found {
		return "Ready for Submission"
	}
	return ""
}

func handleApplicationReadiness(w http.ResponseWriter, r *http.Request) {
	tx, err := database.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, 503, "Could not load submission readiness")
		return
	}
	defer tx.Rollback()
	r = withDBTransaction(r, tx)
	record, err := sqlRecord(r, "cases", r.PathValue("id"))
	if err != nil {
		writeError(w, 404, "Application not found")
		return
	}
	var c Case
	json.Unmarshal([]byte(mustJSON(record)), &c)
	docs, err := readCaseRows[Document](r, "documents", "json_extract(record.data,'$.caseId')=?", c.ID)
	if err != nil {
		writeError(w, 500, "Could not load documents")
		return
	}
	invoices, err := readCaseRows[Invoice](r, "invoices", "json_extract(record.data,'$.caseId')=?", c.ID)
	if err != nil {
		writeError(w, 500, "Could not load invoices")
		return
	}
	today := organizationToday(r)
	checklist, completed, err := documentChecklist(r, c, docs, today)
	if err != nil {
		writeError(w, 500, "Could not load requirement responsibility")
		return
	}

	items := []readinessItem{}
	for _, d := range docs {
		if !d.Required || !documentNeedsReview(d, today) && strings.EqualFold(d.Status, "Verified") {
			continue
		}
		action, detail := "Review document", d.Status
		if d.FilePath == "" {
			action = "Upload document"
		}
		if d.ExpiryDate != "" && d.ExpiryDate < today {
			action, detail = "Upload replacement", "Expired on "+d.ExpiryDate
		}
		items = append(items, readinessItem{"document", d.DocName, detail, action, "/cases/" + c.ID + "#record-tools?tab=documents&document=" + d.ID, true})
	}
	balances := map[string]*readinessBalance{}
	balanceFor := func(inv Invoice) *readinessBalance {
		currency := inv.Currency
		if currency == "" {
			currency = "USD"
		}
		if balances[currency] == nil {
			balances[currency] = &readinessBalance{Currency: currency}
		}
		return balances[currency]
	}
	for _, inv := range invoices {
		entry := balanceFor(inv)
		if inv.Balance > 0 {
			entry.Outstanding = money(entry.Outstanding + inv.Balance)
			items = append(items, readinessItem{"payment", inv.InvoiceNumber, "Outstanding balance: " + currencyOf(inv.Currency) + " " + formatMoney(inv.Balance), "Review balance and receipts", "/invoices/" + inv.ID, false})
		}
		var pending int
		if err = storeDB(r).QueryRow("SELECT count(*) FROM payments WHERE json_extract(data,'$.orgId')=? AND json_extract(data,'$.invoiceId')=? AND json_extract(data,'$.status')='pending_approval'", inv.OrgID, inv.ID).Scan(&pending); err != nil {
			writeError(w, 500, "Could not load pending approvals")
			return
		}
		if pending > 0 {
			entry.PendingReceipt += pending
			items = append(items, readinessItem{"approval", inv.InvoiceNumber, "Receipt approval is pending; these receipts do not reduce the posted balance.", "Review pending receipts", "/invoices/" + inv.ID + "#receipt-approvals", false})
		}
		if inv.RefundStatus == "Requested" || inv.RefundStatus == "Approved" {
			entry.Refunds++
			items = append(items, readinessItem{"refund", inv.InvoiceNumber, "Refund " + strings.ToLower(inv.RefundStatus), "Review refund", "/invoices/" + inv.ID + "#record-tools?tab=workflows", false})
		}
	}
	history, err := handoffHistory(r, c.ID)
	if err != nil {
		writeError(w, 500, "Could not load handoffs")
		return
	}
	pendingHandoffs := 0
	for _, h := range history {
		if h.Status == "pending" {
			pendingHandoffs++
			items = append(items, readinessItem{"handoff", "Ownership handoff", "Awaiting " + h.ToName + "; the current owner remains responsible.", "Review handoff", "/cases/" + c.ID + "#handoff", false})
		}
	}

	// Preview every stage gate that still sits ahead of this application so the
	// answer covers "can it be submitted" and "what would stop the next move".
	snapshot := diskStore{Cases: []Case{c}, Documents: docs}
	position := -1
	for i, candidate := range validCaseStages {
		if candidate == c.CurrentStage {
			position = i
		}
	}
	gates := []readinessGate{}
	for i := position + 1; i < len(validCaseStages); i++ {
		rule, err := gatePolicy(r, c.OrgID, validCaseStages[i])
		if err != nil {
			writeError(w, 500, "Could not load stage gate policies")
			return
		}
		if !rule.Enabled {
			continue
		}
		issues, _, err := evaluateStageGate(r, c, snapshot, rule)
		if err != nil {
			writeError(w, 500, "Could not evaluate stage gate policies")
			return
		}
		gates = append(gates, readinessGate{Stage: rule.Stage, Enabled: true, Satisfied: len(issues) == 0, Issues: issues})
		for _, issue := range issues {
			items = append(items, readinessItem{"gate", "Stage gate: " + rule.Stage, issue, "Resolve the requirement or ask a manager to override", "/cases/" + c.ID + "#record-tools?tab=gates", true})
		}
	}

	blocking, outstanding := 0, len(checklist)-completed
	for _, item := range items {
		if item.Blocking {
			blocking++
		}
	}
	verdict := "ready"
	if !activeApplication(c.CurrentStage) {
		verdict = "closed"
	} else if blocking > 0 || outstanding > 0 {
		verdict = "blocked"
	} else if strings.TrimSpace(c.NextAction) == "" {
		verdict = "incomplete"
		items = append(items, readinessItem{"plan", "Next action", "Record the next staff action before this application can progress.", "Set the next action", "/cases/" + c.ID, true})
	}
	writeJSON(w, 200, map[string]any{
		"caseId": c.ID, "caseNumber": c.CaseNumber, "stage": c.CurrentStage, "active": activeApplication(c.CurrentStage),
		"owner": c.AssignedOfficer, "nextAction": c.NextAction, "deadline": c.NextDeadline, "targetSubmission": c.TargetSubmission,
		"targetStage": submissionTarget(c.CurrentStage), "verdict": verdict, "ready": verdict == "ready",
		"requiredCount": len(checklist), "completedCount": completed, "outstandingCount": outstanding, "blockingCount": blocking,
		"pendingHandoffs": pendingHandoffs, "balances": balances, "gates": gates, "items": items,
		"checklist": checklist, "scope": "Accessible application records", "today": today,
	})
}
