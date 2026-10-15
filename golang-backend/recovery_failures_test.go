package main

import (
	"strings"
	"testing"
	"time"
)

func TestSSOCompletionIsAtomicAndSingleUse(t *testing.T) {
	for _, scenario := range []struct{ name, trigger string }{
		{"success", ""},
		{"disabled account", ""},
		{"token failure", `CREATE TRIGGER reject_sso BEFORE UPDATE OF used_at ON auth_tokens BEGIN SELECT RAISE(ABORT,'token failure'); END`},
		{"audit failure", `CREATE TRIGGER reject_sso BEFORE INSERT ON security_events WHEN NEW.event='login.sso_mfa' BEGIN SELECT RAISE(ABORT,'audit failure'); END`},
		{"session failure", `CREATE TRIGGER reject_sso BEFORE INSERT ON sessions BEGIN SELECT RAISE(ABORT,'session failure'); END`},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			setupStore(t)
			user, _ := findUserByEmail("demo@northwind.dev")
			code := "single-use-recovery-code"
			user.RecoveryHashes = []string{hashSecret(code)}
			user.Disabled = scenario.name == "disabled account"
			users[strings.ToLower(user.Email)] = user
			if err := saveStore(); err != nil {
				t.Fatal(err)
			}
			secret := "sso-completion-secret"
			if _, err := database.Exec("INSERT INTO auth_tokens(hash,user_id,purpose,expires_at) VALUES(?,?,?,?)", hashSecret(secret), user.ID, "sso", time.Now().Add(time.Hour).UTC().Format(time.RFC3339)); err != nil {
				t.Fatal(err)
			}
			if scenario.trigger != "" {
				if _, err := database.Exec(scenario.trigger); err != nil {
					t.Fatal(err)
				}
			}
			h := featureMux()
			request := map[string]string{"token": secret, "code": code}
			response := featureRequest(h, "POST", "/api/sso/finish", request, nil)
			if scenario.name == "success" {
				assertStatus(t, response, 200)
				assertStatus(t, featureRequest(h, "POST", "/api/sso/finish", request, nil), 401)
				return
			}
			if scenario.name == "disabled account" {
				assertStatus(t, response, 401)
			} else {
				assertStatus(t, response, 500)
			}
			current, _ := findUserByID(user.ID)
			if len(current.RecoveryHashes) != 1 || current.RecoveryHashes[0] != hashSecret(code) {
				t.Fatal("failed sign-in consumed recovery code")
			}
			for _, query := range []string{"SELECT COUNT(*) FROM auth_tokens WHERE used_at IS NOT NULL", "SELECT COUNT(*) FROM sessions", "SELECT COUNT(*) FROM security_events WHERE event='login.sso_mfa'"} {
				var count int
				if err := database.QueryRow(query).Scan(&count); err != nil || count != 0 {
					t.Fatalf("failed sign-in persisted changes: query=%s count=%d error=%v", query, count, err)
				}
			}
			if len(response.Result().Cookies()) != 0 {
				t.Fatal("failed sign-in issued session cookies")
			}
		})
	}
}

func TestPasswordRecoveryRollsBackWhenTokenRevocationOrAuditFails(t *testing.T) {
	for _, scenario := range []struct{ name, path, purpose, trigger string }{
		{"reset token revocation", "/api/reset-password", "reset", `CREATE TRIGGER reject_recovery BEFORE UPDATE OF used_at ON auth_tokens BEGIN SELECT RAISE(ABORT,'token failure'); END`},
		{"reset audit", "/api/reset-password", "reset", `CREATE TRIGGER reject_recovery BEFORE INSERT ON security_events WHEN NEW.event='password_reset.completed' BEGIN SELECT RAISE(ABORT,'audit failure'); END`},
		{"forgot token revocation", "/api/forgot-password", "reset", `CREATE TRIGGER reject_recovery BEFORE UPDATE OF used_at ON auth_tokens BEGIN SELECT RAISE(ABORT,'token failure'); END`},
		{"forgot audit", "/api/forgot-password", "reset", `CREATE TRIGGER reject_recovery BEFORE INSERT ON security_events WHEN NEW.event='password_reset.requested' BEGIN SELECT RAISE(ABORT,'audit failure'); END`},
		{"invitation token revocation", "/api/invites/accept", "invite", `CREATE TRIGGER reject_recovery BEFORE UPDATE OF used_at ON auth_tokens BEGIN SELECT RAISE(ABORT,'token failure'); END`},
		{"invitation audit", "/api/invites/accept", "invite", `CREATE TRIGGER reject_recovery BEFORE INSERT ON security_events WHEN NEW.event='invite.accepted' BEGIN SELECT RAISE(ABORT,'audit failure'); END`},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			setupStore(t)
			h := featureMux()
			user, _ := findUserByEmail("demo@northwind.dev")
			secret := "audit-recovery-secret"
			_, err := database.Exec("INSERT INTO auth_tokens(hash,user_id,purpose,expires_at) VALUES(?,?,?,?)", hashSecret(secret), user.ID, scenario.purpose, time.Now().Add(time.Hour).UTC().Format(time.RFC3339))
			if err != nil {
				t.Fatal(err)
			}
			if _, err = database.Exec(scenario.trigger); err != nil {
				t.Fatal(err)
			}
			request := map[string]string{"token": secret, "password": "ReplacementPassword123!", "email": user.Email}
			response := featureRequest(h, "POST", scenario.path, request, nil)
			assertStatus(t, response, 500)
			current, _ := findUserByID(user.ID)
			if current.Password != user.Password || current.SessionVersion != user.SessionVersion {
				t.Fatal("failed recovery changed account credentials or sessions")
			}
			var count int
			if err := database.QueryRow("SELECT COUNT(*) FROM auth_tokens WHERE user_id=? AND used_at IS NULL", user.ID).Scan(&count); err != nil || count != 1 {
				t.Fatalf("failed recovery changed valid tokens: count=%d error=%v", count, err)
			}
			if err := database.QueryRow("SELECT COUNT(*) FROM mail_outbox WHERE user_id=? AND kind='password_reset'", user.ID).Scan(&count); err != nil || count != 0 {
				t.Fatalf("failed recovery queued mail: count=%d error=%v", count, err)
			}
		})
	}
}
