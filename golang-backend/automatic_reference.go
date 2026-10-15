package main

import "strings"

// Use all of the record's random identifier, rather than a count or shortened
// timestamp, so references remain stable across edits, deletions and imports.
func automaticReference(supplied, kind, recordID string) string {
	if value := strings.TrimSpace(supplied); value != "" {
		return value
	}
	_, entropy, found := strings.Cut(recordID, "_")
	if !found {
		entropy = recordID
	}
	return "ECC-" + kind + "-" + strings.ToUpper(entropy)
}

func referenceOnUpdate(supplied, existing, kind, recordID string) string {
	if strings.TrimSpace(supplied) == "" {
		supplied = existing
	}
	return automaticReference(supplied, kind, recordID)
}
