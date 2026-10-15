package main

import (
	"path/filepath"
	"testing"
)

func TestFreshDatabaseOnlyCreatesDemoAccountsAfterExplicitOptIn(t *testing.T) {
	for _, setting := range []string{"", "false", "true"} {
		t.Run("seed="+setting, func(t *testing.T) {
			t.Setenv("SEED_DEMO_DATA", setting)
			t.Setenv("LEGACY_DATA_FILE", "")
			t.Cleanup(func() {
				if database != nil {
					database.Close()
					database = nil
					fixtureBaseline = diskStore{}
				}
			})
			if err := loadStore(filepath.Join(t.TempDir(), "crm.sqlite3")); err != nil {
				t.Fatal(err)
			}
			var accounts int
			if err := database.QueryRow("SELECT COUNT(*) FROM users").Scan(&accounts); err != nil {
				t.Fatal(err)
			}
			_, demo := findUserByEmail("demo@northwind.dev")
			if setting == "true" {
				if accounts != 1 || !demo {
					t.Fatalf("explicit demo opt-in not honored: accounts=%d demo=%v", accounts, demo)
				}
			} else {
				if accounts != 0 || demo {
					t.Fatalf("fresh installation created a predictable account without opt-in: accounts=%d demo=%v", accounts, demo)
				}
				t.Setenv("ALLOW_SIGNUP", "true")
				fixtureBaseline = cloneStore()
				handler := featureMux()
				response := featureRequest(handler, "POST", "/api/register", map[string]string{"name": "Workspace Owner", "email": "owner@test.invalid", "password": "OwnerPassword123!"}, nil)
				assertStatus(t, response, 201)
				owner, found := findUserByEmail("owner@test.invalid")
				if !found || owner.Role != "admin" || owner.OrgID == "" {
					t.Fatal("empty installation could not bootstrap an administrator")
				}
			}
		})
	}
}
