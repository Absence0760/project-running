package internal

// Column-level guard for GDPR Art 20 export completeness on
// `user_profiles`.
//
// personal_data_export_guard_test.go closes the hole one level up: a new
// personal-data TABLE fails the build until it is exported or
// consciously excluded. `user_profiles` is the one table that hole does
// not cover, because it is not fetched by the generic one-row-per-table
// spec at all — it has a projection of its own
// (`FetchExportProfile`'s enumerated select), and it is the only path by
// which anything on that table reaches the archive. A column added to it
// is therefore invisible to every other guard: the migration lands, the
// feature ships, and the subject's Art 20 archive silently omits it.
//
// The projection is enumerated rather than `*` because that is the
// deliberate choice — some of this table is controller-internal — so the
// guard is the same shape as the table one: every column is exported, or
// named here with a reason.

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// profileGuardExclusions names every `user_profiles` column deliberately
// absent from the Art 20 profile projection, with the reason. The test
// fails when an entry here stops being a real column (stale) or starts
// being exported (redundant), so the list cannot rot into a rubber stamp.
var profileGuardExclusions = map[string]string{
	// Internal ordering key for RevenueCat webhook delivery: the
	// timestamp of the billing EVENT that last moved the tier, kept so a
	// late-arriving webhook cannot overwrite a newer state. The
	// subject's own commercial facts (subscription_tier,
	// subscription_at, billing_issue_at) are exported; this is the
	// bookkeeping that orders them.
	"tier_updated_event_ts": "internal webhook-ordering key for the tier columns that ARE exported; not data the subject provided",

	// Moderation state, controller-assigned by the auto-hide sweep
	// (20270218_001). Handing the subject the flag would let a shadowed
	// account confirm its own state, which is the one thing the
	// mechanism exists to withhold. Drained with the account on deletion
	// (Art 17). CISO/counsel to confirm this exclusion stands.
	"shadow_hidden": "moderation state, controller-assigned; disclosure defeats the auto-hide mechanism",
}

func userProfilesColumns(t *testing.T) map[string]string {
	t.Helper()
	dir := migrationsDir(t)
	files, err := filepath.Glob(filepath.Join(dir, "*.sql"))
	if err != nil {
		t.Fatalf("glob migrations: %v", err)
	}
	if len(files) == 0 {
		t.Fatalf("no .sql migrations under %s", dir)
	}
	sort.Strings(files)

	reCreate := regexp.MustCompile(`(?is)create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?user_profiles"?\s*\(`)
	reColumn := regexp.MustCompile(`^([a-z_][a-z0-9_]*)\s+(uuid|text|integer|int|bigint|boolean|timestamptz|date|numeric|jsonb|smallint|real|double)\b`)
	reAdd := regexp.MustCompile(`(?is)alter\s+table\s+(?:only\s+)?(?:public\.)?"?user_profiles"?\s+add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?`)
	reDrop := regexp.MustCompile(`(?is)alter\s+table\s+(?:only\s+)?(?:public\.)?"?user_profiles"?\s+drop\s+column\s+(?:if\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?`)

	cols := map[string]string{}
	for _, f := range files {
		raw, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("read %s: %v", f, err)
		}
		sql := reLineComment.ReplaceAllString(string(raw), "")
		sql = reDollarBody.ReplaceAllString(sql, "")
		base := filepath.Base(f)

		if m := reCreate.FindStringIndex(sql); m != nil {
			body := sql[m[1]:]
			depth := 1
			end := 0
			for i, r := range body {
				if r == '(' {
					depth++
				} else if r == ')' {
					depth--
					if depth == 0 {
						end = i
						break
					}
				}
			}
			for _, line := range strings.Split(body[:end], "\n") {
				if mm := reColumn.FindStringSubmatch(strings.TrimSpace(line)); mm != nil {
					cols[mm[1]] = base
				}
			}
		}
		for _, mm := range reAdd.FindAllStringSubmatch(sql, -1) {
			cols[mm[1]] = base
		}
		for _, mm := range reDrop.FindAllStringSubmatch(sql, -1) {
			delete(cols, mm[1])
		}
	}
	if len(cols) < 10 {
		t.Fatalf("parsed only %d user_profiles columns (%v) — the parser has rotted and "+
			"this guard would pass over anything", len(cols), cols)
	}
	// Sentinels: if the parser silently stops seeing these, it is broken.
	for _, sentinel := range []string{"id", "display_name", "subscription_tier", "date_of_birth"} {
		if _, ok := cols[sentinel]; !ok {
			t.Fatalf("parser did not find the %q column; it cannot be trusted", sentinel)
		}
	}
	return cols
}

// exportedProfileColumns is the projection FetchExportProfile puts on
// the wire, read from the source rather than restated, so a change to
// the select is a change to what this guard measures.
func exportedProfileColumns(t *testing.T) map[string]bool {
	t.Helper()
	src, err := os.ReadFile("supabase.go")
	if err != nil {
		t.Fatalf("read supabase.go: %v", err)
	}
	// The literal may be split across concatenated lines, so every
	// quoted segment of the q.Set call is collected rather than the
	// first one — a partial read would understate the projection and
	// report exported columns as missing.
	m := regexp.MustCompile(`(?s)func \(c \*SupabaseClient\) FetchExportProfile\(.*?q\.Set\("select", (.*?)\)\n`).
		FindSubmatch(src)
	if m == nil {
		t.Fatal("could not read FetchExportProfile's select clause")
	}
	var clause strings.Builder
	for _, seg := range regexp.MustCompile(`"([^"]*)"`).FindAllSubmatch(m[1], -1) {
		clause.Write(seg[1])
	}
	out := map[string]bool{}
	for _, c := range strings.Split(clause.String(), ",") {
		c = strings.TrimSpace(c)
		if c != "" {
			out[c] = true
		}
	}
	if len(out) < 5 {
		t.Fatalf("parsed %d projected columns, which cannot be right", len(out))
	}
	return out
}

func TestPersonalDataExport_EveryProfileColumnIsExportedOrExcluded(t *testing.T) {
	cols := userProfilesColumns(t)
	exported := exportedProfileColumns(t)

	var missing []string
	for col, addedBy := range cols {
		if exported[col] {
			continue
		}
		if _, excused := profileGuardExclusions[col]; excused {
			continue
		}
		missing = append(missing, col+" ("+addedBy+")")
	}
	sort.Strings(missing)
	if len(missing) > 0 {
		t.Fatalf("user_profiles columns reaching no Art 20 export path: %v\n"+
			"user_profiles is fetched ONLY by FetchExportProfile's enumerated select, so a "+
			"column absent from it is absent from the subject's archive. Add it to that "+
			"select, or to profileGuardExclusions with the reason it is not portable "+
			"personal data.", missing)
	}
}

func TestPersonalDataExport_TheProfileProjectionAsksForRealColumnsOnly(t *testing.T) {
	// PostgREST 400s the whole read on one unknown column, and
	// BuildArtifact tolerates a failed profile fetch by shipping a null
	// profile — so a typo here empties `profile.json` and nothing else
	// notices. This has happened: `hr_zones` / `activity_default` /
	// `privacy_default` were projected on both rails and live in the
	// `user_settings.prefs` bag, not on this table.
	cols := userProfilesColumns(t)
	var bogus []string
	for col := range exportedProfileColumns(t) {
		if _, ok := cols[col]; !ok {
			bogus = append(bogus, col)
		}
	}
	sort.Strings(bogus)
	if len(bogus) > 0 {
		t.Fatalf("FetchExportProfile projects columns user_profiles does not have: %v", bogus)
	}
}

func TestPersonalDataExport_TheProfileExclusionListIsNotStale(t *testing.T) {
	cols := userProfilesColumns(t)
	for col, reason := range profileGuardExclusions {
		if reason == "" {
			t.Errorf("exclusion %q carries no reason", col)
		}
		if _, ok := cols[col]; !ok {
			t.Errorf("excluded column %q is not a user_profiles column any more — "+
				"drop the entry rather than leaving a rubber stamp", col)
		}
		if exportedProfileColumns(t)[col] {
			t.Errorf("column %q is excluded AND exported; one of the two is wrong", col)
		}
	}
}

func TestPersonalDataExport_TheHealthTripleIsExportedTogether(t *testing.T) {
	// `withdraw_health_data_consent()` nulls date_of_birth, gender and
	// height_cm as one Art 9 set (decisions.md § 718). Exporting two of
	// the three would be an archive that disagrees with the controller's
	// own account of what it holds.
	exported := exportedProfileColumns(t)
	for _, col := range []string{"date_of_birth", "gender", "height_cm"} {
		if !exported[col] {
			t.Errorf("%q is part of the Art 9 set the withdrawal RPC clears but is not exported", col)
		}
	}
}
