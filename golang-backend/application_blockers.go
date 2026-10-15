package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

type ApplicationBlocker struct {
	Kind     string `json:"kind"`
	Title    string `json:"title"`
	Detail   string `json:"detail"`
	Action   string `json:"action"`
	Route    string `json:"route"`
	Blocking bool   `json:"blocking"`
}

func readCaseRows[T any](r *http.Request, entity, where string, args ...any) ([]T, error) {
	clean := r.Clone(r.Context())
	url := *r.URL
	url.RawQuery = ""
	clean.URL = &url
	scope, scopeArgs := repositoryPredicate(clean, entity)
	rows, err := storeDB(r).Query("SELECT record.data FROM "+entity+" record WHERE "+scope+" AND "+where+" ORDER BY record.sort_order,record.id", append(scopeArgs, args...)...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []T{}
	for rows.Next() {
		var raw string
		var item T
		if err = rows.Scan(&raw); err != nil {
			return nil, err
		}
		if err = json.Unmarshal([]byte(raw), &item); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}
func handleApplicationBlockers(w http.ResponseWriter, r *http.Request) {
	tx, err := database.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, 503, "Could not load application requirements")
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

	out := []ApplicationBlocker{}
	for _, d := range docs {
		if !d.Required || (!documentNeedsReview(d, today) && strings.EqualFold(d.Status, "Verified")) {
			continue
		}
		action := "Review document"
		detail := d.Status
		if d.Status == "Requested" || d.Status == "Not Requested" || d.Status == "Correction Required" || d.LatestVersion == 0 && !strings.EqualFold(d.Status, "Verified") {
			action = "Upload document"
		}
		if d.ExpiryDate != "" && d.ExpiryDate < today {
			detail = "Expired on " + d.ExpiryDate
			action = "Upload replacement"
		}
		out = append(out, ApplicationBlocker{"document", d.DocName, detail, action, "/cases/" + c.ID + "#record-tools?tab=documents&document=" + d.ID, c.AutoAdvance && documentNeedsReview(d, today)})
	}
	for _, inv := range invoices {
		route := "/invoices/" + inv.ID
		if inv.Balance > 0 {
			out = append(out, ApplicationBlocker{"payment", inv.InvoiceNumber, fmt.Sprintf("Outstanding balance: %s %.2f", currencyOf(inv.Currency), inv.Balance), "Review balance and receipts", route, false})
		}
		var pending int
		if err = storeDB(r).QueryRow("SELECT count(*) FROM payments WHERE json_extract(data,'$.orgId')=? AND json_extract(data,'$.invoiceId')=? AND json_extract(data,'$.status')='pending_approval'", inv.OrgID, inv.ID).Scan(&pending); err != nil {
			writeError(w, 500, "Could not load pending approvals")
			return
		}
		if pending > 0 {
			out = append(out, ApplicationBlocker{"approval", inv.InvoiceNumber, "Receipt approval is pending; these receipts do not reduce the posted balance.", "Review pending receipts", route + "#receipt-approvals", false})
		}
		if inv.RefundStatus == "Requested" || inv.RefundStatus == "Approved" {
			out = append(out, ApplicationBlocker{"refund", inv.InvoiceNumber, "Refund " + strings.ToLower(inv.RefundStatus), "Review refund", route + "#record-tools?tab=workflows", false})
		}
	}
	history, err := handoffHistory(r, c.ID)
	if err != nil {
		writeError(w, 500, "Could not load handoffs")
		return
	}
	for _, h := range history {
		if h.Status == "pending" {
			detail := "Awaiting " + h.ToName + "; the current owner remains responsible."
			if h.DueDate < today {
				detail = "Overdue handoff. " + detail
			}
			out = append(out, ApplicationBlocker{"handoff", "Ownership handoff", detail, "Review handoff", "/cases/" + c.ID + "#handoff", false})
		}
	}
	// Preview the immediate destination with the same rules used by transitions.
	// Include restricted documents in evaluation; evaluateStageGate redacts names.
	nextStage := ""
	if activeApplication(c.CurrentStage) {
		for i, stage := range validCaseStages {
			if stage == c.CurrentStage && i+1 < len(validCaseStages) {
				nextStage = validCaseStages[i+1]
				break
			}
		}
	}
	gate := map[string]any{"stage": nextStage, "enabled": false, "items": []map[string]any{}}
	if nextStage != "" {
		rule, gateErr := gatePolicy(r, c.OrgID, nextStage)
		if gateErr != nil {
			writeError(w, 500, "Could not load next-stage requirements")
			return
		}
		gate["enabled"] = rule.Enabled
		if rule.Enabled {
			rows, gateErr := queryObjects(r, "SELECT data FROM documents WHERE json_extract(data,'$.caseId')=? AND json_extract(data,'$.orgId')=? ORDER BY sort_order,id", c.ID, c.OrgID)
			if gateErr != nil {
				writeError(w, 500, "Could not load next-stage documents")
				return
			}
			snapshot := diskStore{Cases: []Case{c}}
			for _, row := range rows {
				var doc Document
				if json.Unmarshal([]byte(fmtString(row["data"])), &doc) != nil {
					writeError(w, 500, "Could not load next-stage documents")
					return
				}
				snapshot.Documents = append(snapshot.Documents, doc)
			}
			issues, _, gateErr := evaluateStageGate(r, c, snapshot, rule)
			if gateErr != nil {
				writeError(w, 500, "Could not evaluate next-stage requirements")
				return
			}
			gateItems := []map[string]any{}
			for _, issue := range issues {
				responsible, due, action := c.AssignedOfficer, c.NextDeadline, "Review stage requirements"
				route := "/cases/" + c.ID + "#record-tools?tab=overview&stage=" + strings.ReplaceAll(nextStage, " ", "%20")
				if strings.HasPrefix(issue, "A manager must approve") {
					responsible = "Workspace manager"
					action = "Review approval"
				}
				for _, requirement := range checklist {
					if strings.HasPrefix(issue, requirement.Title+" ") {
						responsible, due, action, route = requirement.Responsible, requirement.DueDate, "Review document", requirement.Route
						break
					}
				}
				gateItems = append(gateItems, map[string]any{"detail": issue, "responsible": responsible, "deadline": due, "action": action, "route": route})
			}
			gate["items"] = gateItems
		}
	}
	blocking := 0
	for _, b := range out {
		if b.Blocking {
			blocking++
		}
	}
	enriched := []map[string]any{}
	for _, item := range out {
		var row map[string]any
		json.Unmarshal([]byte(mustJSON(item)), &row)
		row["responsible"] = c.AssignedOfficer
		row["deadline"] = c.NextDeadline
		if item.Kind == "document" {
			for _, requirement := range checklist {
				if requirement.Route == item.Route {
					row["responsible"] = requirement.Responsible
					row["deadline"] = requirement.DueDate
				}
			}
		}
		if item.Kind == "payment" || item.Kind == "approval" || item.Kind == "refund" {
			for _, inv := range invoices {
				if item.Title == inv.InvoiceNumber {
					row["deadline"] = inv.DueDate
					if u, ok := committedUser(r, "id", inv.OwnerID); ok && u.OrgID == c.OrgID {
						row["responsible"] = u.Name
					}
				}
			}
		}
		enriched = append(enriched, row)
	}
	writeJSON(w, 200, map[string]any{"caseNumber": c.CaseNumber, "editable": canWrite(c.RecordScope, currentUser(r)), "nextStageGate": gate, "active": activeApplication(c.CurrentStage), "items": enriched, "checklist": checklist, "requiredCount": len(checklist), "completedCount": completed, "owner": c.AssignedOfficer, "nextAction": c.NextAction, "deadline": c.NextDeadline, "blockingCount": blocking, "autoAdvance": c.AutoAdvance, "scope": "Accessible application records", "today": today})
}
