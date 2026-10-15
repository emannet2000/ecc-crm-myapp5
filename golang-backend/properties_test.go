package main

import (
	"math"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/quick"
)

func TestRecordPermissionProperties(t *testing.T) {
	roles := []string{"admin", "manager", "member", "viewer"}
	property := func(org, otherOrg, userID, owner, team, otherTeam, visibility string, roleIndex uint8) bool {
		role := roles[int(roleIndex)%len(roles)]
		user := User{ID: userID, OrgID: org, TeamID: team, Role: role}
		scope := RecordScope{OrgID: otherOrg, OwnerID: owner, TeamID: otherTeam, Visibility: visibility}
		read, write := canRead(scope, user), canWrite(scope, user)
		if (org == "" || org != otherOrg) && (read || write) {
			return false
		}
		if role == "viewer" && write {
			return false
		}
		if write && !read {
			return false
		}
		if org != "" && org == otherOrg && (role == "admin" || role == "manager") && (!read || !write) {
			return false
		}
		return true
	}
	if err := quick.Check(property, &quick.Config{MaxCount: 5000, Rand: rand.New(rand.NewSource(20261014))}); err != nil {
		t.Fatal(err)
	}
	// Include same-workspace cases; independently generated organization strings
	// almost never match, so randomized tests alone would miss these boundaries.
	for _, role := range roles {
		for _, visibility := range []string{"private", "team", "organization", ""} {
			for _, owner := range []string{"self", "other", ""} {
				for _, team := range []string{"matching", "other", ""} {
					user := User{ID: "self", OrgID: "org", TeamID: "matching", Role: role}
					scope := RecordScope{OrgID: "org", OwnerID: owner, TeamID: team, Visibility: visibility}
					if canWrite(scope, user) && !canRead(scope, user) {
						t.Fatalf("write without read: role=%s scope=%+v", role, scope)
					}
					if role == "viewer" && canWrite(scope, user) {
						t.Fatal("viewer obtained write access")
					}
				}
			}
		}
	}
}

func FuzzPhoneNormalization(f *testing.F) {
	for _, seed := range []string{"", "+63 (917) 123-4567", "0000000", "++1234567", "１２３４５６７", "abc", "\x00+1234567"} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, input string) {
		if len(input) > 10000 {
			t.Skip()
		}
		normalized := normalizePhone(input)
		if normalizePhone(normalized) != normalized {
			t.Fatalf("normalization is not idempotent: %q", input)
		}
		if validPhone(input) != validPhone(normalized) {
			t.Fatalf("normalization changed validity: %q", input)
		}
		if normalized != "" && validPhone(input) {
			digits := strings.TrimPrefix(normalized, "+")
			if len(digits) < 7 || len(digits) > 15 {
				t.Fatal("accepted wrong length")
			}
			for _, digit := range digits {
				if digit < '0' || digit > '9' {
					t.Fatal("accepted non-ASCII phone digit")
				}
			}
		}
	})
}

func FuzzCurrencyValidation(f *testing.F) {
	for _, seed := range []string{"USD", "PHP", "EUR", "USD|EUR", "|USD", "USD|", "usd", "", "USD\x00", "USD|EUR|GBP"} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, input string) {
		supported := map[string]bool{"USD": true, "EUR": true, "GBP": true, "CAD": true, "AUD": true, "NZD": true, "PHP": true, "SGD": true, "INR": true, "JPY": true, "CNY": true, "AED": true, "HKD": true, "CHF": true, "KRW": true, "MYR": true, "THB": true, "IDR": true}
		if validCurrency(input) != supported[input] {
			t.Fatalf("currency validity disagrees with exact supported codes: %q", input)
		}
	})
}

func FuzzCSVFormulaNeutralization(f *testing.F) {
	for _, seed := range []string{"=1+1", "+cmd", "-1", "@SUM(A1)", " \t\r\n=1", "ordinary", "'already safe", "\"quoted, value\"", ""} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, input string) {
		if len(input) > 10000 {
			t.Skip()
		}
		output := csvValue(input)
		trimmed := strings.TrimLeft(output, " \t\r\n")
		if len(trimmed) > 0 && strings.ContainsAny(trimmed[:1], "=+-@") {
			t.Fatalf("formula remains executable: %q", input)
		}
		if csvValue(output) != output {
			t.Fatalf("CSV safety transform is not idempotent: %q", input)
		}
	})
}

func FuzzRecordVersionProperties(f *testing.F) {
	for _, seed := range []string{"", "normal", "\x00", "<script>alert(1)</script>", "世界"} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, input string) {
		record := map[string]any{"id": "record", "name": input}
		version := versionOf(record)
		record["_revision"] = "untrusted revision"
		if versionOf(record) != version {
			t.Fatal("revision metadata changed content version")
		}
		reversed := map[string]any{"name": input, "id": "record"}
		if versionOf(reversed) != version {
			t.Fatal("map insertion order changed content version")
		}
		if record["_revision"] != "untrusted revision" || record["name"] != input {
			t.Fatal("version calculation mutated its input")
		}
		if len(version) != 64 {
			t.Fatal("invalid version length")
		}
	})
}

func FuzzMoneyRounding(f *testing.F) {
	for _, seed := range []float64{0, 0.005, 0.015, 1.235, -1.235, 99999.99} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, input float64) {
		if math.IsNaN(input) || math.IsInf(input, 0) || math.Abs(input) > 1e8 {
			t.Skip()
		}
		rounded := money(input)
		if money(rounded) != rounded {
			t.Fatalf("money rounding is not idempotent: %v", input)
		}
		if math.Abs(rounded-input) > 0.0050001 {
			t.Fatalf("rounding changed more than half a cent: %v -> %v", input, rounded)
		}
	})
}

func TestQRPermissionPolicyAllowsOnlySameOriginCamera(t *testing.T) {
	h := protectHTTP(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(200) }))
	response := httptest.NewRecorder()
	h.ServeHTTP(response, httptest.NewRequest("GET", "/workspace?tab=qr", nil))
	policy := response.Header().Get("Permissions-Policy")
	if !strings.Contains(policy, "camera=(self)") || !strings.Contains(policy, "microphone=()") || !strings.Contains(policy, "geolocation=()") {
		t.Fatalf("unexpected policy: %s", policy)
	}
}
