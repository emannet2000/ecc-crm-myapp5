package main

import (
	"fmt"
	"net/http"
	"strings"
)

// Called inside persistMutations' writer transaction. The durable high-water
// mark survives deletion and is seeded from all of the organization's records,
// including records the current staff member cannot see.
func nextLeadReference(r *http.Request) (string, error) {
	db := storeDB(r)
	org := currentUser(r).OrgID
	year := todayForOrgDB(db, org)[:4]
	prefix := "ECC-LD-" + year + "-"
	var highest int64
	if err := db.QueryRow(`SELECT COALESCE(MAX(CAST(substr(json_extract(data,'$.leadNumber'),?) AS INTEGER)),0)
		FROM leads WHERE json_extract(data,'$.orgId')=? AND json_extract(data,'$.leadNumber') LIKE ?`,
		len(prefix)+1, org, prefix+"%").Scan(&highest); err != nil {
		return "", err
	}
	if highest == 1<<63-1 {
		return "", fmt.Errorf("lead reference sequence exhausted")
	}
	var next int64
	err := db.QueryRow(`INSERT INTO app_meta(key,value) VALUES(?,CAST(? AS TEXT))
		ON CONFLICT(key) DO UPDATE SET value=CAST(MAX(CAST(app_meta.value AS INTEGER)+1,CAST(excluded.value AS INTEGER)) AS TEXT)
		RETURNING value`, "lead_sequence:"+org+":"+year, highest+1).Scan(&next)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s%05d", prefix, next), nil
}

func leadReference(r *http.Request, supplied, existing string) (string, error) {
	if strings.TrimSpace(existing) != "" {
		return existing, nil
	}
	if supplied = strings.TrimSpace(supplied); supplied != "" {
		return supplied, nil
	}
	return nextLeadReference(r)
}
