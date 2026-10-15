package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"strings"
)

func handleLeadCVReview(w http.ResponseWriter, r *http.Request) {
	state, release := runtimeForCall(r)
	defer release()
	var req struct {
		JobID     string            `json:"jobId"`
		Confirmed bool              `json:"confirmed"`
		Fields    map[string]string `json:"fields"`
	}
	if !decodeRequest(w, r, &req) {
		return
	}
	if !req.Confirmed {
		writeError(w, 400, "Review and confirm the CV fields before saving")
		return
	}
	if r.Header.Get("If-Match") == "" {
		writeError(w, 428, "Reload the lead before reviewing CV fields")
		return
	}
	lead, ok := state.getLeadByID(r.PathValue("id"))
	if !ok {
		writeError(w, 404, "Lead not found")
		return
	}
	if lead.ConvertedCaseID != "" {
		writeError(w, 409, "This lead has already become an application. Review the application instead.")
		return
	}
	var raw, docID string
	if storeDB(r).QueryRow("SELECT data,record_id FROM workspace_entries WHERE id=? AND org_id=? AND user_id=? AND category='ai_job'", req.JobID, currentUser(r).OrgID, currentUser(r).ID).Scan(&raw, &docID) != nil {
		writeError(w, 404, "CV draft not found")
		return
	}
	var job assistantJob
	doc, found := state.visibleDocument(docID)
	if json.Unmarshal([]byte(raw), &job) != nil || job.Action != "cv-extract" || job.Entity != "documents" || job.Status != "completed" || !found || doc.LeadID != lead.ID {
		writeError(w, 409, "Choose a completed CV draft for this lead")
		return
	}
	var document map[string]any
	json.Unmarshal([]byte(mustJSON(doc)), &document)
	if job.Version != versionOf(document) {
		writeError(w, 409, "The CV changed. Generate and review a new draft before saving.")
		return
	}
	var values map[string]any
	json.Unmarshal([]byte(mustJSON(lead)), &values)
	allowed := map[string]bool{"name": true, "email": true, "phone": true, "nationality": true, "currentCountry": true, "notes": true}
	for key, value := range req.Fields {
		if !allowed[key] {
			writeError(w, 400, "CV review can only change identity, contact details and notes")
			return
		}
		if len(value) > 12000 {
			writeError(w, 400, "A reviewed field is too long")
			return
		}
		values[key] = strings.TrimSpace(value)
	}
	if country := fmtString(values["nationality"]); country != "" {
		code, valid := normalizedCountry(country)
		if !valid {
			writeError(w, 400, "Choose a valid nationality country code")
			return
		}
		values["nationality"] = code
	}
	r.Body = io.NopCloser(bytes.NewReader([]byte(mustJSON(values))))
	if !normalizeRequest(w, r) {
		return
	}
	state.updateLeadHandler(w, r)
}

// convertLead runs under the workflow unit-of-work lock. SQL commits the lead,
// newly created records and document reparenting together.
func (state *runtimeStore) convertLead(w http.ResponseWriter, r *http.Request, id, target string, duplicateConfirmed bool) {
	if target == "" {
		target = "contact"
	} // Existing API clients retain contact-only conversion.
	if target != "contact" && target != "application" && target != "student" {
		writeError(w, 400, "Choose contact, application or student")
		return
	}
	for i, lead := range state.leads {
		if lead.ID != id {
			continue
		}
		if !canWrite(lead.RecordScope, currentUser(r)) {
			writeError(w, 403, "You can only convert leads you own")
			return
		}
		result := func() {
			writeJSON(w, 200, map[string]string{"contactId": state.leads[i].ConvertedContactID, "caseId": state.leads[i].ConvertedCaseID, "studentId": state.leads[i].ConvertedStudentID})
		}
		if lead.ConvertedCaseID != "" {
			if _, err := sqlRecord(r, "cases", lead.ConvertedCaseID); err != nil {
				writeError(w, 409, "The converted application is no longer accessible")
				return
			}
			if target == "student" && lead.ConvertedStudentID == "" {
				writeError(w, 409, "This lead already has an application. Link a student from that application instead.")
				return
			}
			result()
			return
		}
		// A conversion must not silently create another client for a matching phone.
		if lead.ConvertedContactID == "" && !duplicateConfirmed {
			for _, c := range state.contacts {
				sameEmail := strings.TrimSpace(lead.Email) != "" && strings.EqualFold(strings.TrimSpace(lead.Email), strings.TrimSpace(c.Email))
				if !sameEmail && phoneIdentity(lead.Phone) != "" && phoneIdentity(lead.Phone) == phoneIdentity(c.Phone) {
					writeFieldErrors(w, map[string]string{"duplicateConfirmed": "A matching contact phone was found. Review the conversion preview and confirm a separate client before proceeding."})
					return
				}
			}
		}
		var contact Contact
		for _, c := range state.contacts {
			if (lead.ConvertedContactID != "" && c.ID == lead.ConvertedContactID) || (lead.ConvertedContactID == "" && lead.Email != "" && strings.EqualFold(strings.TrimSpace(lead.Email), strings.TrimSpace(c.Email))) {
				if !canWrite(c.RecordScope, currentUser(r)) {
					writeError(w, 403, "The matching contact is outside your edit permissions")
					return
				}
				contact = c
				break
			}
		}
		if lead.ConvertedContactID != "" && contact.ID == "" {
			writeError(w, 409, "The converted contact is no longer accessible")
			return
		}
		if contact.ID == "" && strings.TrimSpace(lead.Email) != "" {
			var count int
			if err := storeDB(r).QueryRow("SELECT count(*) FROM contacts WHERE json_extract(data,'$.orgId')=? AND lower(trim(json_extract(data,'$.email')))=lower(?)", currentUser(r).OrgID, strings.TrimSpace(lead.Email)).Scan(&count); err != nil {
				writeError(w, 500, "Could not check matching contacts")
				return
			}
			if count > 0 {
				writeError(w, 409, "A matching contact requires an authorized staff member to resolve this conversion")
				return
			}
		}
		// A hidden attachment must not be silently left behind by conversion.
		if target != "contact" {
			var total int
			if err := storeDB(r).QueryRow("SELECT count(*) FROM documents WHERE json_extract(data,'$.orgId')=? AND json_extract(data,'$.leadId')=?", currentUser(r).OrgID, id).Scan(&total); err != nil {
				writeError(w, 500, "Could not inspect lead documents")
				return
			}
			visible := 0
			for _, d := range state.documents {
				if d.LeadID == id {
					visible++
					if !canWrite(d.RecordScope, currentUser(r)) {
						writeError(w, 403, "A lead document is outside your edit permissions")
						return
					}
				}
			}
			if total != visible {
				writeError(w, 409, "An authorized staff member must resolve restricted lead documents before conversion")
				return
			}
		}
		notes := strings.TrimSpace(lead.Notes + "\n\nLead: " + lead.LeadNumber + "\nClient: " + lead.Name + "\nEmail: " + lead.Email + "\nPhone: " + lead.Phone + "\nCurrent country: " + lead.CurrentCountry + "\nSource: " + lead.Source + "\nReferrer: " + lead.Referrer + "\nNationality: " + lead.Nationality + "\nInterest: " + lead.InterestedService + " / " + lead.InterestedCountry + "\nFollow-up: " + lead.FollowUpDate)
		if contact.ID == "" {
			contact = Contact{RecordScope: lead.RecordScope, ID: newID("c"), Name: lead.Name, Email: lead.Email, Phone: lead.Phone, Location: lead.CurrentCountry, Stage: "Lead", Owner: lead.AssignedTo, Notes: notes, Tags: []string{}, CreatedAt: organizationToday(r)}
			state.contacts = append(state.contacts, contact)
		}
		state.leads[i].ConvertedContactID = contact.ID
		state.leads[i].Status = "Converted"
		if target != "contact" {
			studentID := ""
			if target == "student" {
				studentID = newID("s")
				state.students = append(state.students, Student{RecordScope: lead.RecordScope, ID: studentID, StudentCode: automaticReference("", "ST", studentID), Name: lead.Name, CountryCode: lead.InterestedCountry, ApplicationStage: "Planning", AcceptanceStatus: "Pending", VisaStatus: "Not Started", InvoiceStatus: "Not Issued", NextAction: leadNextAction(lead.NextAction), NextDeadline: lead.FollowUpDate, Notes: notes, CreatedBy: currentUser(r).Name, CreatedAt: organizationToday(r), PreDeparture: []ChecklistItem{}})
				state.leads[i].ConvertedStudentID = studentID
			}
			application := Case{RecordScope: lead.RecordScope, ID: newID("case"), ClientID: contact.ID, ClientName: contact.Name, StudentID: studentID, ServiceCategory: lead.InterestedService, DestinationCountry: lead.InterestedCountry, AssignedOfficer: lead.AssignedTo, DateOpened: organizationToday(r), CurrentStage: "Assessment", Priority: "Medium", NextAction: leadNextAction(lead.NextAction), NextDeadline: lead.FollowUpDate, Notes: notes, CreatedBy: currentUser(r).Name, CreatedAt: organizationToday(r)}
			if application.ServiceCategory == "" {
				application.ServiceCategory = "Consultation"
			}
			application.CaseNumber = automaticReference("", "CASE", application.ID)
			state.cases = append(state.cases, application)
			state.leads[i].ConvertedCaseID = application.ID
			for j, doc := range state.documents {
				if doc.LeadID == id {
					state.documents[j].LeadID = ""
					state.documents[j].CaseID = application.ID
					state.documents[j].CaseNumber = application.CaseNumber
				}
			}
		}
		result()
		return
	}
	writeError(w, 404, "Lead not found")
}

func handleLeadCVUpload(w http.ResponseWriter, r *http.Request) {
	state, release := runtimeForCall(r)
	defer release()
	lead, ok := state.getLeadByID(r.PathValue("id"))
	if !ok {
		writeError(w, 404, "Lead not found")
		return
	}
	if !canWrite(lead.RecordScope, currentUser(r)) {
		writeError(w, 403, "You can only upload files to leads you own")
		return
	}
	if lead.ConvertedCaseID != "" {
		writeError(w, 409, "Upload further documents on the converted application")
		return
	}
	var doc Document
	for _, d := range state.documents {
		if d.LeadID == lead.ID && d.DocName == "Client CV" {
			doc = d
			break
		}
	}
	if doc.ID != "" && !canWrite(doc.RecordScope, currentUser(r)) {
		writeError(w, 403, "The CV is outside your edit permissions")
		return
	}
	if doc.ID == "" {
		var existing int
		if err := storeDB(r).QueryRow("SELECT count(*) FROM documents WHERE json_extract(data,'$.orgId')=? AND json_extract(data,'$.leadId')=? AND json_extract(data,'$.docName')='Client CV'", currentUser(r).OrgID, lead.ID).Scan(&existing); err != nil {
			writeError(w, 500, "Could not inspect the existing CV")
			return
		}
		if existing > 0 {
			writeError(w, 409, "An authorized staff member must resolve the restricted CV before uploading another version")
			return
		}
		doc = Document{RecordScope: lead.RecordScope, ID: newID("doc"), LeadID: lead.ID, DocName: "Client CV", Status: "Requested", CreatedBy: currentUser(r).Name, CreatedAt: organizationToday(r)}
		state.documents = append(state.documents, doc)
	}
	r.SetPathValue("id", doc.ID)
	state.handleFileUpload(w, r)
}
