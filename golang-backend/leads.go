package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

type leadRequest struct {
	NextAction         string `json:"nextAction"`
	DuplicateConfirmed bool   `json:"duplicateConfirmed"`
	Referrer           string `json:"referrer"`
	LeadNumber         string `json:"leadNumber"`
	Name               string `json:"name"`
	Email              string `json:"email"`
	Phone              string `json:"phone"`
	Nationality        string `json:"nationality"`
	CurrentCountry     string `json:"currentCountry"`
	InterestedCountry  string `json:"interestedCountry"`
	InterestedService  string `json:"interestedService"`
	Source             string `json:"source"`
	AssignedTo         string `json:"assignedTo"`
	Status             string `json:"status"`
	FollowUpDate       string `json:"followUpDate"`
	Notes              string `json:"notes"`
}

var validLeadSources = []string{
	"Website", "Facebook", "Instagram", "WhatsApp",
	"Referral", "School Partner", "Event", "Walk-in", "Other",
}

var validLeadStatuses = []string{
	"New", "Contacted", "Qualified", "Consultation Booked",
	"Proposal Sent", "Converted", "Closed/Lost",
}

func isValidLeadSource(s string) bool {
	for _, v := range validLeadSources {
		if v == s {
			return true
		}
	}
	return false
}

func isValidLeadStatus(s string) bool {
	for _, v := range validLeadStatuses {
		if v == s {
			return true
		}
	}
	return false
}

func validateLead(req leadRequest) map[string]string {
	fields := map[string]string{}

	name := strings.TrimSpace(req.Name)
	source := strings.TrimSpace(req.Source)
	status := strings.TrimSpace(req.Status)

	if name == "" {
		fields["name"] = "Lead name is required"
	} else if len(name) > 200 {
		fields["name"] = "Name must be 200 characters or fewer"
	}

	if source == "" {
		fields["source"] = "Source is required"
	} else if !isValidLeadSource(source) {
		fields["source"] = "Invalid source"
	}

	if status == "" {
		fields["status"] = "Status is required"
	} else if !isValidLeadStatus(status) {
		fields["status"] = "Invalid status"
	}

	if len(req.NextAction) > 1000 {
		fields["nextAction"] = "Next action must be 1,000 characters or fewer"
	}
	if req.FollowUpDate != "" {
		if _, err := time.Parse("2006-01-02", req.FollowUpDate); err != nil {
			fields["followUpDate"] = "Choose a valid follow-up date"
		}
	}
	return fields
}

func (state *runtimeStore) listLeadsHandler(w http.ResponseWriter, r *http.Request) {
	q := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	limit, offset := parseLimitOffset(r, 50, 0)

	all := state.listLeads()
	filtered := make([]Lead, 0, len(all))
	for _, l := range all {
		if q == "" ||
			strings.Contains(strings.ToLower(l.Name), q) ||
			strings.Contains(strings.ToLower(l.LeadNumber), q) ||
			strings.Contains(strings.ToLower(l.Email), q) ||
			strings.Contains(strings.ToLower(l.InterestedCountry), q) ||
			strings.Contains(strings.ToLower(l.AssignedTo), q) {
			filtered = append(filtered, l)
		}
	}
	filtered = sortRecords(filtered, r)
	total := len(filtered)
	writeJSON(w, http.StatusOK, map[string]any{
		"leads":  slicePage(filtered, offset, limit),
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

func listLeadsHandler(w http.ResponseWriter, r *http.Request) {
	state, release := runtimeForReadCall(r)
	defer release()
	state.listLeadsHandler(w, r)
}

func (state *runtimeStore) getLeadHandler(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	l, ok := state.getLeadByID(id)
	if !ok {
		writeError(w, http.StatusNotFound, "Lead not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"lead": l})
}

func getLeadHandler(w http.ResponseWriter, r *http.Request) {
	state, release := runtimeForReadCall(r)
	defer release()
	state.getLeadHandler(w, r)
}

func (state *runtimeStore) createLeadHandler(w http.ResponseWriter, r *http.Request) {
	var req leadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	req.Status = strings.TrimSpace(req.Status)
	if fields := validateLead(req); len(fields) > 0 {
		writeFieldErrors(w, fields)
		return
	}

	if req.Status == "Converted" {
		writeFieldErrors(w, map[string]string{"status": "Use CV & conversion to create the linked client record."})
		return
	}
	var valid bool
	req.AssignedTo, valid = normalizeStaffAssignment(w, r, req.AssignedTo, "", "assignedTo", newRecordScope(r))
	if !valid {
		return
	}
	if !state.checkLeadDuplicates(w, r, "", req) {
		return
	}
	email, _ := r.Context().Value(ctxUserEmail).(string)
	createdBy := "Unknown"
	if email != "" {
		if u, ok := state.findUserByEmail(email); ok {
			createdBy = u.Name
		}
	}

	now := time.Now().Format("2006-01-02")
	reference, err := leadReference(r, req.LeadNumber, "")
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "Could not assign a lead number; retry saving")
		return
	}
	newLead := Lead{
		RecordScope:       newRecordScope(r),
		ID:                newID("l"),
		LeadNumber:        reference,
		NextAction:        leadNextAction(req.NextAction),
		CreatedAtTime:     utcNow(),
		Referrer:          strings.TrimSpace(req.Referrer),
		Name:              strings.TrimSpace(req.Name),
		Email:             strings.TrimSpace(req.Email),
		Phone:             strings.TrimSpace(req.Phone),
		Nationality:       strings.TrimSpace(strings.ToUpper(req.Nationality)),
		CurrentCountry:    strings.TrimSpace(strings.ToUpper(req.CurrentCountry)),
		InterestedCountry: strings.TrimSpace(strings.ToUpper(req.InterestedCountry)),
		InterestedService: strings.TrimSpace(req.InterestedService),
		Source:            strings.TrimSpace(req.Source),
		AssignedTo:        strings.TrimSpace(req.AssignedTo),
		Status:            strings.TrimSpace(req.Status),
		FollowUpDate:      strings.TrimSpace(req.FollowUpDate),
		Notes:             req.Notes,
		CreatedBy:         createdBy,
		CreatedAt:         now,
	}

	state.mu.Lock()
	state.leads = append(state.leads, newLead)
	state.mu.Unlock()

	writeJSON(w, http.StatusCreated, map[string]any{"lead": newLead})
}

func createLeadHandler(w http.ResponseWriter, r *http.Request) {
	state, release := runtimeForCall(r)
	defer release()
	state.createLeadHandler(w, r)
}

func (state *runtimeStore) updateLeadHandler(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")

	var req leadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	req.Status = strings.TrimSpace(req.Status)
	if fields := validateLead(req); len(fields) > 0 {
		writeFieldErrors(w, fields)
		return
	}

	state.mu.Lock()
	defer state.mu.Unlock()

	idx := -1
	for i, l := range state.leads {
		if l.ID == id {
			idx = i
			break
		}
	}
	if idx == -1 {
		writeError(w, http.StatusNotFound, "Lead not found")
		return
	}

	old := state.leads[idx]
	if req.Status != old.Status && (req.Status == "Converted" || old.ConvertedContactID != "" || old.ConvertedCaseID != "" || old.ConvertedStudentID != "") {
		writeFieldErrors(w, map[string]string{"status": "Use the conversion action when the client proceeds. Linked converted leads cannot be reopened by changing status."})
		return
	}
	var valid bool
	req.AssignedTo, valid = normalizeStaffAssignment(w, r, req.AssignedTo, old.AssignedTo, "assignedTo", old.RecordScope)
	if !valid {
		return
	}
	if qualityKey(old.Email) != qualityKey(req.Email) || phoneIdentity(old.Phone) != phoneIdentity(req.Phone) {
		if !state.checkLeadDuplicates(w, r, id, req) {
			return
		}
	}
	updated := state.leads[idx]
	reference, err := leadReference(r, req.LeadNumber, old.LeadNumber)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "Could not assign a lead number; retry saving")
		return
	}
	updated.LeadNumber = reference
	updated.Referrer = strings.TrimSpace(req.Referrer)
	updated.NextAction = leadNextAction(req.NextAction)
	updated.Name = strings.TrimSpace(req.Name)
	updated.Email = strings.TrimSpace(req.Email)
	updated.Phone = strings.TrimSpace(req.Phone)
	updated.Nationality = strings.TrimSpace(strings.ToUpper(req.Nationality))
	updated.CurrentCountry = strings.TrimSpace(strings.ToUpper(req.CurrentCountry))
	updated.InterestedCountry = strings.TrimSpace(strings.ToUpper(req.InterestedCountry))
	updated.InterestedService = strings.TrimSpace(req.InterestedService)
	updated.Source = strings.TrimSpace(req.Source)
	updated.AssignedTo = strings.TrimSpace(req.AssignedTo)
	updated.Status = strings.TrimSpace(req.Status)
	updated.FollowUpDate = strings.TrimSpace(req.FollowUpDate)
	updated.Notes = req.Notes

	state.leads[idx] = updated
	writeJSON(w, http.StatusOK, map[string]any{"lead": updated})
}

func updateLeadHandler(w http.ResponseWriter, r *http.Request) {
	state, release := runtimeForCall(r)
	defer release()
	state.updateLeadHandler(w, r)
}

func (state *runtimeStore) deleteLeadHandler(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")

	state.mu.Lock()
	defer state.mu.Unlock()

	idx := -1
	for i, l := range state.leads {
		if l.ID == id {
			idx = i
			break
		}
	}
	if idx == -1 {
		writeError(w, http.StatusNotFound, "Lead not found")
		return
	}

	state.leads = append(state.leads[:idx], state.leads[idx+1:]...)
	keptDocs := state.documents[:0]
	for _, doc := range state.documents {
		if doc.LeadID != id {
			keptDocs = append(keptDocs, doc)
		}
	}
	state.documents = keptDocs
	writeJSON(w, http.StatusOK, map[string]any{"deleted": id})
}

func deleteLeadHandler(w http.ResponseWriter, r *http.Request) {
	state, release := runtimeForCall(r)
	defer release()
	state.deleteLeadHandler(w, r)
}
