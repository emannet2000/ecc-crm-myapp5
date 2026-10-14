package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"
)

func aiRecordURL(entity, id string) string {
	switch entity {
	case "tasks", "activities", "documents", "payments":
		return "/" + entity
	}
	return "/" + entity + "/" + id
}
func recordReference(entity, id string, record map[string]any) aiReference {
	return aiReference{Kind: "record", Entity: entity, ID: id, Title: recordLabel(mustJSON(record)), URL: aiRecordURL(entity, id), SourceID: entity + ":" + id}
}
func minimizedRecord(record map[string]any) map[string]any {
	out := map[string]any{}
	for _, key := range []string{"id", "name", "title", "caseNumber", "invoiceNumber", "docName", "status", "currentStage", "stage", "email", "company", "dueDate", "followUpDate", "nextDeadline", "nextAction", "clientName", "contactName", "balance", "currency", "value"} {
		if v, ok := record[key]; ok {
			out[key] = v
		}
	}
	return out
}
func (a *aiAgent) search(query, entity string, offset int) (any, error) {
	query = strings.TrimSpace(query)
	if len(query) > 200 || offset < 0 || offset > 1000000 || entity != "" && !validEntity(entity) {
		return nil, fmt.Errorf("Choose a valid entity, a search of up to 200 characters, and a nonnegative offset")
	}
	s, err := sqlWorkspace(a.R)
	if err != nil {
		return nil, err
	}
	type match struct {
		Entity, ID, Label string
		Record            map[string]any
	}
	matches := []match{}
	for table, items := range recordsOf(s) {
		if !validEntity(table) || entity != "" && entity != table {
			continue
		}
		for id, payload := range items {
			var record map[string]any
			if json.Unmarshal([]byte(payload), &record) != nil {
				continue
			}
			searchText := ""
			for key, v := range record {
				if key == "orgId" || key == "ownerId" || key == "teamId" || key == "filePath" {
					continue
				}
				if text, ok := v.(string); ok {
					searchText += " " + strings.ToLower(text)
				}
			}
			found := true
			for _, term := range strings.Fields(strings.ToLower(query)) {
				if !strings.Contains(searchText, term) {
					found = false
					break
				}
			}
			if found {
				matches = append(matches, match{table, id, recordLabel(payload), record})
			}
		}
	}
	sort.Slice(matches, func(i, j int) bool {
		return strings.ToLower(matches[i].Label)+matches[i].Entity+matches[i].ID < strings.ToLower(matches[j].Label)+matches[j].Entity+matches[j].ID
	})
	results := []map[string]any{}
	end := offset + 20
	if end > len(matches) {
		end = len(matches)
	}
	for i := offset; i < end; i++ {
		m := matches[i]
		ref := recordReference(m.Entity, m.ID, m.Record)
		a.addSource(ref)
		results = append(results, map[string]any{"entity": m.Entity, "record": minimizedRecord(m.Record), "sourceId": ref.SourceID})
	}
	return map[string]any{"results": results, "total": len(matches), "offset": offset, "nextOffset": end, "hasMore": end < len(matches)}, nil
}
func sanitizedRecord(record map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range record {
		if key == "filePath" {
			continue
		}
		if text, ok := value.(string); ok {
			value = compactWorkText(text, 4000)
		}
		out[key] = value
	}
	return out
}
func (a *aiAgent) readRecord(entity, id string) (any, error) {
	record, err := sqlRecord(a.R, entity, id)
	if err != nil {
		return nil, fmt.Errorf("Record not found or no longer accessible")
	}
	ref := recordReference(entity, id, record)
	a.addSource(ref)
	related := []map[string]any{}
	s, err := sqlWorkspace(a.R)
	if err != nil {
		return nil, err
	}
	groups := recordsOf(s)
	tables := append([]string{}, entityTables...)
	sort.Strings(tables)
	for _, table := range tables {
		ids := []string{}
		for recordID := range groups[table] {
			ids = append(ids, recordID)
		}
		sort.Strings(ids)
		for _, recordID := range ids {
			if len(related) >= 12 {
				break
			}
			if table == entity && recordID == id {
				continue
			}
			var candidate map[string]any
			json.Unmarshal([]byte(groups[table][recordID]), &candidate)
			linked := false
			for _, key := range []string{"contactId", "clientId", "studentId", "caseId", "dealId", "schoolId", "agentId", "partnerId", "invoiceId"} {
				if fmtString(candidate[key]) == id {
					linked = true
				}
				if fmtString(record[key]) == recordID {
					linked = true
				}
			}
			if linked {
				linkRef := recordReference(table, recordID, candidate)
				a.addSource(linkRef)
				related = append(related, map[string]any{"entity": table, "sourceId": linkRef.SourceID, "record": minimizedRecord(candidate)})
			}
		}
	}
	return map[string]any{"record": sanitizedRecord(record), "entity": entity, "sourceId": ref.SourceID, "editableFields": aiEditableFields(entity), "related": related, "relatedLimit": 12}, nil
}
func (a *aiAgent) analyze(from, to string) (any, error) {
	today := organizationToday(a.R)
	end, err := time.Parse("2006-01-02", today)
	if err != nil {
		return nil, err
	}
	if to == "" {
		to = today
	} else {
		end, err = time.Parse("2006-01-02", to)
		if err != nil {
			return nil, fmt.Errorf("Use YYYY-MM-DD dates")
		}
	}
	if from == "" {
		from = end.AddDate(0, 0, -29).Format("2006-01-02")
	}
	start, err := time.Parse("2006-01-02", from)
	if err != nil || start.After(end) || end.Sub(start) > 3660*24*time.Hour {
		return nil, fmt.Errorf("Choose an ordered date range of up to ten years")
	}
	days := int(end.Sub(start).Hours()/24) + 1
	priorTo := start.AddDate(0, 0, -1).Format("2006-01-02")
	priorFrom := start.AddDate(0, 0, -days).Format("2006-01-02")
	s, err := sqlWorkspace(a.R)
	if err != nil {
		return nil, err
	}
	currentSources, enrollment, agents := cohortMetrics(s, from, to)
	previousSources, previousEnrollment, _ := cohortMetrics(s, priorFrom, priorTo)
	type currencyMetric struct {
		Currency       string  `json:"currency"`
		OpenPipeline   float64 `json:"openPipeline"`
		InvoiceBalance float64 `json:"invoiceBalance"`
		Received       float64 `json:"received"`
	}
	currencies := map[string]*currencyMetric{}
	metric := func(currency string) *currencyMetric {
		if currency == "" {
			currency = "USD"
		}
		if currencies[currency] == nil {
			currencies[currency] = &currencyMetric{Currency: currency}
		}
		return currencies[currency]
	}
	stageCounts := map[string]int{}
	openTasks, overdueTasks, openCases, overdueCases := 0, 0, 0, 0
	for _, d := range s.Deals {
		stageCounts[d.Stage]++
		if d.Stage != "Won" && d.Stage != "Lost" {
			metric(d.Currency).OpenPipeline += d.Value
		}
	}
	for _, i := range s.Invoices {
		metric(i.Currency).InvoiceBalance += i.Balance
		metric(i.Currency).Received += i.AmountReceived
	}
	for _, task := range s.Tasks {
		if task.Status != "done" {
			openTasks++
			if distance, ok := dateDistance(task.DueDate, today); ok && distance < 0 {
				overdueTasks++
			}
		}
	}
	for _, c := range s.Cases {
		if c.CurrentStage != "Closed" && c.CurrentStage != "Approved" {
			openCases++
			if distance, ok := dateDistance(c.NextDeadline, today); ok && distance < 0 {
				overdueCases++
			}
		}
	}
	currencyResults := []currencyMetric{}
	for _, c := range currencies {
		c.OpenPipeline = money(c.OpenPipeline)
		c.InvoiceBalance = money(c.InvoiceBalance)
		c.Received = money(c.Received)
		currencyResults = append(currencyResults, *c)
	}
	sort.Slice(currencyResults, func(i, j int) bool { return currencyResults[i].Currency < currencyResults[j].Currency })
	riskItems := aiAttention(s, currentUser(a.R), today)
	if a.Settings.RecordContext {
		for _, item := range riskItems {
			a.addSource(aiReference{Kind: "record", Entity: aiPlural(item.Entity), ID: item.ID, Title: item.Name, URL: item.Route, SourceID: aiPlural(item.Entity) + ":" + item.ID})
		}
	} else {
		riskItems = nil
	}
	a.addSource(aiReference{Kind: "report", ID: from + "_" + to, Title: "CRM report: " + from + " to " + to, SourceID: "report:" + from + ":" + to, URL: "/reports"})
	return map[string]any{"sourceId": "report:" + from + ":" + to, "cohort": map[string]string{"from": from, "to": to, "definition": "Lead and student creation-date cohorts; conversion is the current status of each created lead, not conversion events during the period"}, "current": map[string]any{"conversion": currentSources, "enrollment": enrollment, "agents": agents}, "previous": map[string]any{"from": priorFrom, "to": priorTo, "conversion": previousSources, "enrollment": previousEnrollment}, "currentWorkspace": map[string]any{"contacts": len(s.Contacts), "leads": len(s.Leads), "students": len(s.Students), "stageCounts": stageCounts, "openTasks": openTasks, "overdueTasks": overdueTasks, "openCases": openCases, "overdueCases": overdueCases, "currencies": currencyResults, "attention": riskItems}, "limitations": "Amounts are separated by currency and not exchange-converted. Workspace totals are current balances, not revenue during the cohort period. Recommendations and causes require human investigation."}, nil
}
func aiPlural(entity string) string {
	switch entity {
	case "case":
		return "cases"
	case "task":
		return "tasks"
	case "lead":
		return "leads"
	case "deal":
		return "deals"
	}
	return entity
}
func aiAttention(s diskStore, user User, today string) []productivityItem {
	return aiAttentionScoped(s, user, today, "mine")
}

func aiAttentionScoped(s diskStore, user User, today, scope string) []productivityItem {
	items := collectWorkload(user, s, today, scope, false)
	for _, d := range s.Deals {
		if d.Stage == "Won" || d.Stage == "Lost" || d.OrgID != user.OrgID || !canRead(d.RecordScope, user) || !workAssigned(d.Owner, d.RecordScope, user, scope) {
			continue
		}
		if distance, ok := dateDistance(d.CloseDate, today); ok && distance < 0 {
			items = append(items, productivityItem{ID: d.ID, Entity: "deal", Name: d.Title, Reason: "Expected close date has passed", Action: "Review deal progress and agree on a next step", Deadline: d.CloseDate, Priority: "high", Route: aiRecordURL("deals", d.ID), Rank: 1})
		}
	}
	for _, c := range s.Cases {
		if !activeApplication(c.CurrentStage) || c.OrgID != user.OrgID || !canRead(c.RecordScope, user) || !workAssigned(c.AssignedOfficer, c.RecordScope, user, scope) {
			continue
		}
		if distance, ok := dateDistance(c.DateOpened, today); ok && distance <= -30 && c.NextAction == "" {
			items = append(items, productivityItem{ID: c.ID, Entity: "case", Name: c.CaseNumber, Reason: "Case has been open at least 30 days without a next action", Action: "Investigate the blocker and assign a next action", Priority: "high", Route: aiRecordURL("cases", c.ID), Rank: 1})
		}
	}
	sort.SliceStable(items, func(i, j int) bool { return items[i].Rank < items[j].Rank })
	unique := []productivityItem{}
	seen := map[string]bool{}
	for _, item := range items {
		key := item.Entity + ":" + item.ID
		if !seen[key] {
			unique = append(unique, item)
			seen[key] = true
		}
		if len(unique) >= 30 {
			break
		}
	}
	return unique
}
func aiReferencesAllowed(r *http.Request, refs []aiReference, settings aiSettings) bool {
	for _, ref := range refs {
		switch ref.Kind {
		case "record":
			if !settings.RecordContext {
				return false
			}
			if _, err := sqlRecord(r, ref.Entity, ref.ID); err != nil {
				return false
			}
		case "knowledge":
			if !settings.Knowledge {
				return false
			}
			if _, err := loadKnowledge(r, ref.ID); err != nil {
				return false
			}
		case "report":
			if !settings.Reports {
				return false
			}
		default:
			return false
		}
	}
	return true
}
