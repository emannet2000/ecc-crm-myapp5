package main

import (
	"strings"
	"testing"
)

func TestRecordValidatorsRejectMissingRequiredFields(t *testing.T) {
	setupStore(t)
	cases := []struct {
		name     string
		validate func() map[string]string
	}{
		{"contact", func() map[string]string { return validateContact(contactRequest{}, "") }},
		{"deal", func() map[string]string { return validateDeal(dealRequest{}) }},
		{"task", func() map[string]string { return validateTask(taskRequest{}) }},
		{"activity", func() map[string]string { return validateActivity(activityRequest{}) }},
		{"school", func() map[string]string { return validateSchool(schoolRequest{}) }},
		{"student", func() map[string]string { return validateStudent(studentRequest{}) }},
		{"agent", func() map[string]string { return validateAgent(agentRequest{}) }},
		{"lead", func() map[string]string { return validateLead(leadRequest{}) }},
		{"application", func() map[string]string { return validateCase(caseRequest{}) }},
		{"partner", func() map[string]string { return validatePartner(partnerRequest{}) }},
		{"document", func() map[string]string { return validateDocument(documentRequest{}) }},
		{"invoice", func() map[string]string { return validateInvoice(invoiceRequest{}) }},
	}
	for _, scenario := range cases {
		t.Run(scenario.name, func(t *testing.T) {
			if len(scenario.validate()) == 0 {
				t.Fatalf("%s accepted a record with no required fields", scenario.name)
			}
		})
	}
}

func TestAgentValidatorBoundaries(t *testing.T) {
	valid := agentRequest{Name: strings.Repeat("a", 200), ContractStatus: "Signed", AgentStatus: "Active"}
	if errors := validateAgent(valid); len(errors) != 0 {
		t.Fatalf("valid boundary record rejected: %v", errors)
	}
	cases := []struct {
		name, field string
		request     agentRequest
	}{
		{"name too long", "name", agentRequest{Name: strings.Repeat("a", 201), ContractStatus: "Signed", AgentStatus: "Active"}},
		{"unknown contract status", "contractStatus", agentRequest{Name: "Agent", ContractStatus: "Unknown", AgentStatus: "Active"}},
		{"unknown account status", "agentStatus", agentRequest{Name: "Agent", ContractStatus: "Signed", AgentStatus: "Unknown"}},
		{"negative referrals", "studentsReferred", agentRequest{Name: "Agent", ContractStatus: "Signed", AgentStatus: "Active", StudentsReferred: -1}},
	}
	for _, scenario := range cases {
		t.Run(scenario.name, func(t *testing.T) {
			if validateAgent(scenario.request)[scenario.field] == "" {
				t.Fatalf("missing %s validation", scenario.field)
			}
		})
	}
}
