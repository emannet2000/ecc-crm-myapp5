package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestAutomaticReferences(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 5000; i++ {
		id := newID("st")
		code := automaticReference("", "ST", id)
		if seen[code] || !strings.HasPrefix(code, "ECC-ST-") || code != automaticReference(" ", "ST", id) {
			t.Fatal("generated references must be unique and stable")
		}
		seen[code] = true
	}
	if automaticReference(" SCHOOL-123 ", "ST", "st_abc") != "SCHOOL-123" || referenceOnUpdate("", "CUSTOM", "ST", "st_abc") != "CUSTOM" || referenceOnUpdate("", "", "ST", "st_abc") != "ECC-ST-ABC" {
		t.Fatal("existing references must be preserved, with automatic fallback")
	}
}

func TestCreationGeneratesReferencesWithoutManualInput(t *testing.T) {
	setupStore(t)
	m := http.NewServeMux()
	m.HandleFunc("POST /api/login", handleSecureLogin)
	m.HandleFunc("POST /api/students", authMiddleware(createStudentHandler))
	m.HandleFunc("PUT /api/students/{id}", authMiddleware(updateStudentHandler))
	m.HandleFunc("POST /api/agents", authMiddleware(createAgentHandler))
	m.HandleFunc("POST /api/invoices", authMiddleware(createInvoiceHandler))
	m.HandleFunc("POST /api/cases", authMiddleware(createCaseHandler))
	h := persistMutations(m)
	cookies := demoCookies(t, h)
	for _, scenario := range []struct {
		entity, singular, field, prefix string
		body                            map[string]string
	}{
		{"students", "student", "studentCode", "ECC-ST-", map[string]string{"name": "Automatic student", "acceptanceStatus": "Pending", "visaStatus": "Not Started", "invoiceStatus": "Not Issued"}},
		{"agents", "agent", "agentCode", "ECC-AG-", map[string]string{"name": "Automatic agent", "contractStatus": "Signed", "agentStatus": "Active"}},
		{"invoices", "invoice", "invoiceNumber", "ECC-INV-", map[string]string{"clientId": "c_1", "paymentMilestone": "Quotation Issued", "currency": "USD"}},
		{"cases", "case", "caseNumber", "ECC-CASE-", map[string]string{"clientId": "c_1", "serviceCategory": "Consultation", "currentStage": "Assessment", "priority": "Medium", "dateOpened": "2026-10-15"}},
	} {
		response := featureRequest(h, "POST", "/api/"+scenario.entity, scenario.body, cookies)
		assertStatus(t, response, 201)
		var out map[string]map[string]any
		if err := json.Unmarshal(response.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		record := out[scenario.singular]
		code, _ := record[scenario.field].(string)
		if !strings.HasPrefix(code, scenario.prefix) {
			t.Fatalf("%s reference missing: %s", scenario.entity, response.Body.String())
		}
		if scenario.entity == "students" {
			updated := featureRequest(h, "PUT", "/api/students/"+record["id"].(string), scenario.body, cookies)
			assertStatus(t, updated, 200)
			if !strings.Contains(updated.Body.String(), code) {
				t.Fatal("editing without a reference changed it")
			}
		}
	}
}
