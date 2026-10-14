package main

import (
	"fmt"
	"sort"
	"strings"
)

// The recurring questions staff ask the adviser — what needs my attention,
// which clients are missing documents, what is overdue, what can be submitted,
// who needs a follow-up, what is unpaid — are answered here from the same
// scoped SQL the dashboard uses. This tool is strictly read-only: it returns
// record identifiers and reasons, never a write, never a status change and
// never a financial action. Every record it names is re-checked for access
// before it becomes a citable source.

const insightsTopics = "attention, missing_documents, overdue_cases, ready_for_submission, follow_ups, overdue_payments"

type insightItem struct {
	Entity   string `json:"entity"`
	ID       string `json:"id"`
	Label    string `json:"label"`
	Reason   string `json:"reason"`
	Action   string `json:"action"`
	Deadline string `json:"deadline,omitempty"`
	Owner    string `json:"owner,omitempty"`
	Route    string `json:"route"`
	SourceID string `json:"sourceId"`
}

func validInsightsTopic(topic string) bool {
	switch topic {
	case "attention", "missing_documents", "overdue_cases", "ready_for_submission", "follow_ups", "overdue_payments":
		return true
	}
	return false
}

// documentCompletenessFor measures one application's accessible required
// documents. An application with no recorded requirements is reported separately
// rather than being described as complete.
func documentCompletenessFor(s diskStore, today string) (required, verified int, outstanding []string) {
	for _, d := range s.Documents {
		if !d.Required {
			continue
		}
		required++
		distance, dated := dateDistance(d.ExpiryDate, today)
		if strings.EqualFold(d.Status, "Verified") && !(dated && distance < 0) {
			verified++
			continue
		}
		detail := d.Status
		if dated && distance < 0 {
			detail = "Expired on " + d.ExpiryDate
		}
		outstanding = append(outstanding, d.DocName+" ("+detail+")")
	}
	return required, verified, outstanding
}

func (a *aiAgent) insight(item insightItem, record map[string]any) insightItem {
	ref := recordReference(item.Entity, item.ID, record)
	a.addSource(ref)
	item.SourceID = ref.SourceID
	if item.Route == "" {
		item.Route = ref.URL
	}
	return item
}

// workspaceInsights answers one operational question from committed, scoped SQL.
func (a *aiAgent) workspaceInsights(topic, scope string) (any, error) {
	if !validInsightsTopic(topic) {
		return nil, fmt.Errorf("Choose one topic: %s", insightsTopics)
	}
	user := currentUser(a.R)
	assignment := scope
	if assignment == "" {
		assignment = "mine"
	}
	if assignment != "mine" && assignment != "unassigned" && assignment != "all" {
		return nil, fmt.Errorf("Choose mine, unassigned or all")
	}
	var s diskStore
	var err error
	if topic == "attention" {
		s, err = sqlWorkspace(a.R)
	} else {
		s, err = dashboardWorkspace(a.R)
	}
	if err != nil {
		return nil, err
	}
	today := organizationToday(a.R)
	allowed := func(recordScope RecordScope, owner string) bool {
		return recordScope.OrgID == user.OrgID && canRead(recordScope, user) && workAssigned(owner, recordScope, user, assignment)
	}
	items := []insightItem{}

	switch topic {
	case "attention":
		definition := "Open work in the selected assignment scope (" + assignment + "), ordered by urgency. This priority list is not the whole CRM."
		for _, work := range aiAttentionScoped(s, user, today, assignment) {
			ref := recordReference(aiPlural(work.Entity), work.ID, map[string]any{"name": work.Name})
			a.addSource(ref)
			items = append(items, insightItem{Entity: work.Entity, ID: work.ID, Label: work.Name, Reason: work.Reason, Action: work.Action, Deadline: work.Deadline, Route: work.Route, SourceID: ref.SourceID})
		}
		return insightAnswer(topic, definition, items, "Covers up to 30 prioritised items. Use search_crm or workspace_insights for a complete list."), nil
	case "missing_documents":
		definition := "Active applications with at least one accessible required document that is not verified, or is expired."
		for _, c := range s.Cases {
			if !activeApplication(c.CurrentStage) || !allowed(c.RecordScope, c.AssignedOfficer) {
				continue
			}
			required, _, outstanding := documentCompletenessFor(applyCaseDocuments(s, c.ID), today)
			if required == 0 || len(outstanding) == 0 {
				continue
			}
			items = append(items, a.insight(insightItem{Entity: "case", ID: c.ID, Label: c.CaseNumber, Reason: "Missing: " + strings.Join(outstanding, ", "), Action: "Collect and verify the outstanding documents", Deadline: c.NextDeadline, Owner: c.AssignedOfficer, Route: "/cases/" + c.ID}, recordMap(c)))
		}
		sortInsights(items)
		return insightAnswer(topic, definition, items, "Counts accessible documents only. It does not certify that hidden requirements are complete."), nil
	case "overdue_cases":
		definition := "Active applications whose recorded next-action deadline is earlier than the workspace date."
		for _, c := range s.Cases {
			if !activeApplication(c.CurrentStage) || !allowed(c.RecordScope, c.AssignedOfficer) {
				continue
			}
			days, valid := dateDistance(c.NextDeadline, today)
			if !valid || days >= 0 {
				continue
			}
			items = append(items, a.insight(insightItem{Entity: "case", ID: c.ID, Label: c.CaseNumber, Reason: fmt.Sprintf("Next action was due %s (%d days ago) at stage %s", c.NextDeadline, -days, c.CurrentStage), Action: actionOrDefault(c.NextAction, "Set the next action and update the deadline"), Deadline: c.NextDeadline, Owner: c.AssignedOfficer, Route: "/cases/" + c.ID}, recordMap(c)))
		}
		sortInsights(items)
		return insightAnswer(topic, definition, items, "Uses the recorded next-action deadline. An application without a recorded deadline is not counted as overdue."), nil
	case "ready_for_submission":
		definition := "Applications at the Ready for Submission stage whose accessible required documents are all verified and unexpired, and whose next action is recorded."
		for _, c := range s.Cases {
			if c.CurrentStage != "Ready for Submission" || !allowed(c.RecordScope, c.AssignedOfficer) {
				continue
			}
			required, _, outstanding := documentCompletenessFor(applyCaseDocuments(s, c.ID), today)
			var reasons []string
			if required == 0 {
				reasons = append(reasons, "no required documents are recorded")
			}
			if len(outstanding) > 0 {
				reasons = append(reasons, "outstanding documents: "+strings.Join(outstanding, ", "))
			}
			if strings.TrimSpace(c.NextAction) == "" {
				reasons = append(reasons, "no next action is recorded")
			}
			if len(reasons) > 0 {
				continue
			}
			items = append(items, a.insight(insightItem{Entity: "case", ID: c.ID, Label: c.CaseNumber, Reason: fmt.Sprintf("All %d required documents verified at %s", required, c.CurrentStage), Action: "Confirm submission and record the reference", Deadline: c.NextDeadline, Owner: c.AssignedOfficer, Route: "/cases/" + c.ID}, recordMap(c)))
		}
		sortInsights(items)
		return insightAnswer(topic, definition, items, "Submission readiness is reported for accessible documents only. A configured stage gate may still require a manager approval; check the application's stage gates before submitting."), nil
	case "follow_ups":
		definition := "Open inquiries with overdue, today, upcoming or unrecorded follow-up dates."
		for _, l := range s.Leads {
			if !openLead(l.Status) || !allowed(l.RecordScope, l.AssignedTo) {
				continue
			}
			days, valid := dateDistance(l.FollowUpDate, today)
			reason := ""
			switch {
			case !valid:
				reason = "No follow-up date is recorded"
			case days < 0:
				reason = fmt.Sprintf("Follow-up was due %s (%d days ago)", l.FollowUpDate, -days)
			case days == 0:
				reason = "Follow-up is due today"
			default:
				reason = fmt.Sprintf("Upcoming follow-up on %s (in %d days)", l.FollowUpDate, days)
			}
			items = append(items, a.insight(insightItem{Entity: "lead", ID: l.ID, Label: l.LeadNumber + " " + l.Name, Reason: reason + " · status " + l.Status, Action: actionOrDefault(l.NextAction, leadNextAction("")), Deadline: l.FollowUpDate, Owner: l.AssignedTo, Route: "/leads/" + l.ID}, recordMap(l)))
		}
		sort.SliceStable(items, func(i, j int) bool {
			if (items[i].Deadline == "") != (items[j].Deadline == "") {
				return items[i].Deadline != ""
			}
			if items[i].Deadline != items[j].Deadline {
				return items[i].Deadline < items[j].Deadline
			}
			return items[i].Label < items[j].Label
		})
		return insightAnswer(topic, definition, items, "Converted and closed inquiries are excluded. No recorded follow-up date is reported separately from an overdue one."), nil
	case "overdue_payments":
		definition := "Invoices with an outstanding balance whose due date is earlier than the workspace date."
		totals := map[string]float64{}
		for _, inv := range s.Invoices {
			if !allowed(inv.RecordScope, inv.OwnerID) || inv.Balance <= 0 {
				continue
			}
			days, valid := dateDistance(inv.DueDate, today)
			if !valid || days >= 0 {
				continue
			}
			currency := inv.Currency
			if currency == "" {
				currency = "USD"
			}
			totals[currency] = money(totals[currency] + inv.Balance)
			items = append(items, a.insight(insightItem{Entity: "invoice", ID: inv.ID, Label: inv.InvoiceNumber, Reason: fmt.Sprintf("%s %.2f outstanding, due %s (%d days ago)", currency, inv.Balance, inv.DueDate, -days), Action: "Review the balance and recorded receipts", Deadline: inv.DueDate, Route: "/invoices/" + inv.ID}, recordMap(inv)))
		}
		sortInsights(items)
		lines := []string{}
		for currency, amount := range totals {
			lines = append(lines, fmt.Sprintf("%s %.2f", currency, amount))
		}
		sort.Strings(lines)
		return insightAnswer(topic, definition, items, "Amounts stay in their own currency and are never added together: "+strings.Join(lines, ", ")+"."), nil
	}
	return nil, fmt.Errorf("Unsupported topic")
}

func applyCaseDocuments(s diskStore, caseID string) diskStore {
	out := diskStore{}
	for _, d := range s.Documents {
		if d.CaseID == caseID {
			out.Documents = append(out.Documents, d)
		}
	}
	return out
}

func sortInsights(items []insightItem) {
	sort.SliceStable(items, func(i, j int) bool {
		if (items[i].Deadline == "") != (items[j].Deadline == "") {
			return items[i].Deadline != ""
		}
		if items[i].Deadline != items[j].Deadline {
			return items[i].Deadline < items[j].Deadline
		}
		return items[i].Label < items[j].Label
	})
}

func insightAnswer(topic, definition string, items []insightItem, limitations string) map[string]any {
	if items == nil {
		items = []insightItem{}
	}
	return map[string]any{"topic": topic, "definition": definition, "count": len(items), "items": items, "limitations": limitations, "grounded": true}
}
