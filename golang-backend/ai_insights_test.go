package main

import (
	"context"
	"strings"
	"testing"
	"time"
)

func TestInsightsFollowUpsAndAttentionScope(t *testing.T) {
	admin := dashboardFixture(t)
	today := organizationTodayForOrg(admin.OrgID)
	date, _ := time.Parse("2006-01-02", today)
	scope := RecordScope{OrgID: admin.OrgID, OwnerID: admin.ID, TeamID: admin.TeamID, Visibility: "organization"}
	mu.Lock()
	leads = append(leads, Lead{RecordScope: scope, ID: "today-lead", Name: "Today", Status: "New", AssignedTo: admin.Name, FollowUpDate: today}, Lead{RecordScope: scope, ID: "later-lead", Name: "Later", Status: "New", AssignedTo: admin.Name, FollowUpDate: date.AddDate(0, 0, 30).Format("2006-01-02")})
	tasks = []Task{
		{RecordScope: scope, ID: "mine-task", Title: "Mine", Owner: admin.Name, Status: "todo", DueDate: today},
		{RecordScope: scope, ID: "other-task", Title: "Other", Owner: "Another officer", Status: "todo", DueDate: today},
		{RecordScope: scope, ID: "unassigned-task", Title: "Unassigned", Status: "todo", DueDate: today},
	}
	mu.Unlock()
	if err := saveStore(); err != nil {
		t.Fatal(err)
	}
	agent := aiAgent{R: aiUserRequest(context.Background(), admin)}
	answer, err := agent.workspaceInsights("follow_ups", "all")
	if err != nil {
		t.Fatal(err)
	}
	reasons := map[string]string{}
	for _, item := range answer.(map[string]any)["items"].([]insightItem) {
		reasons[item.ID] = item.Reason
	}
	for id, want := range map[string]string{"dash-lead-overdue": "days ago", "today-lead": "due today", "dash-lead-soon": "Upcoming", "later-lead": "Upcoming"} {
		if !strings.Contains(reasons[id], want) {
			t.Fatalf("%s: expected %s, got %s", id, want, reasons[id])
		}
	}
	for _, assignment := range []string{"mine", "all", "unassigned"} {
		answer, err = agent.workspaceInsights("attention", assignment)
		if err != nil {
			t.Fatal(err)
		}
		found := map[string]bool{}
		for _, item := range answer.(map[string]any)["items"].([]insightItem) {
			found[item.ID] = true
		}
		if found["other-task"] != (assignment == "all") || found["mine-task"] != (assignment != "unassigned") || !found["unassigned-task"] {
			t.Fatalf("%s: wrong assignment results: %+v", assignment, found)
		}
	}
	h := expansionTestMux()
	w := dailyUserRequest(t, h, admin, "GET", "/api/dashboard/overview?scope=all", nil)
	assertStatus(t, w, 200)
	overview := decodeOverview(t, w)
	for key, want := range map[string]int{"followUpsDue": 2, "followUpsOverdue": 1, "followUpsToday": 1, "followUpsUpcoming": 2} {
		if got := kpiValue(t, overview, key); got != want {
			t.Fatalf("%s: got %d, want %d", key, got, want)
		}
	}
}

func TestWorkQueueFollowUpReasonsUseWorkspaceDate(t *testing.T) {
	user := User{ID: "staff", Name: "Staff", OrgID: "org"}
	scope := RecordScope{OrgID: user.OrgID, OwnerID: user.ID, Visibility: "organization"}
	today := "2026-10-14"
	s := diskStore{Leads: []Lead{
		{RecordScope: scope, ID: "overdue", Name: "Overdue", Status: "New", AssignedTo: user.Name, FollowUpDate: "2026-10-13", NextAction: "Call"},
		{RecordScope: scope, ID: "today", Name: "Today", Status: "New", AssignedTo: user.Name, FollowUpDate: today, NextAction: "Call"},
		{RecordScope: scope, ID: "upcoming", Name: "Upcoming", Status: "New", AssignedTo: user.Name, FollowUpDate: "2026-10-16", NextAction: "Call"},
		{RecordScope: scope, ID: "missing", Name: "Missing", Status: "New", AssignedTo: user.Name},
		{RecordScope: scope, ID: "later", Name: "Later", Status: "New", AssignedTo: user.Name, FollowUpDate: "2026-11-14"},
		{RecordScope: scope, ID: "invalid", Name: "Invalid", Status: "New", AssignedTo: user.Name, FollowUpDate: "not-a-date"},
	}}
	for _, items := range [][]productivityItem{collectWorkload(user, s, today, "mine", true), aiAttentionScoped(s, user, today, "mine")} {
		reasons := map[string]string{}
		for _, item := range items {
			reasons[item.ID] = item.Reason
		}
		for id, want := range map[string]string{"overdue": "is overdue", "today": "due today", "upcoming": "Upcoming", "missing": "no follow-up date", "later": "Upcoming", "invalid": "date is invalid"} {
			if !strings.Contains(reasons[id], want) {
				t.Fatalf("%s: expected %s, got %s", id, want, reasons[id])
			}
		}
		if !strings.Contains(reasons["later"], "no next action") {
			t.Fatal("future lead must retain missing-action warning")
		}
	}
}
