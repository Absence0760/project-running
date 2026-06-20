package internal

// Build-time guard for GDPR Art 20 data-export completeness.
//
// exportPersonalDataSpecs (supabase.go) is the single source of truth
// for which personal-data tables the export bundles. The risk it can't
// protect against on its own is a *new* table: someone adds
// `create table foo (... author_id uuid references auth.users ...)` in a
// migration, ships the feature, and silently never wires foo into the
// export — the subject's foo rows are then missing from every DSAR with
// nothing to flag it.
//
// This test closes that hole. It parses every migration for tables that
// carry an owner-style foreign key to auth.users and asserts each one is
// either:
//
//   - covered by the export spec (appears as a spec.table), or
//   - named in exportGuardExclusions with a written reason.
//
// A new owner-FK-bearing table that is neither fails the build until a
// human consciously wires it into the export or excludes it. The
// exclusion list is itself guarded (no stale / no overlap) so it can't
// rot into a rubber stamp.
//
// Scope note: the guard originally keyed only on the literal `user_id`
// column. That left a blind spot — a table that holds the subject's data
// under a differently-named owner column (session_plans.author_id,
// route_photos.owner_id, event_orders.buyer_user_id/host_user_id, …)
// could ship missing from the export with nothing to flag it (the
// 2026-06-20 GDPR Art 20 finding). The guard now keys on ANY owner-style
// FK to auth.users — user_id / author_id / owner_id / buyer_user_id /
// host_user_id / contact_user_id. `user_id` is matched by name (some
// user_id columns declare their FK as a separate constraint or live in an
// RPC return table, so a name match is the crisp signal there); the other
// owner names are matched only when the column declaration also carries
// an inline `references auth.users`, so an `owner_id`/`author_id` that
// points at a non-user table can't produce a false positive.

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// exportGuardExclusions names every table that HAS an owner-style FK to
// auth.users but is deliberately not fetched by exportPersonalDataSpecs,
// with the reason. Adding a table here is a conscious decision a reviewer
// can see; the test fails if an entry here stops being a real owner-FK
// table (stale) or starts being covered by the spec (redundant).
var exportGuardExclusions = map[string]string{
	// Exported through dedicated, richer paths rather than the generic
	// one-row-per-table fetch: the GPS tracks ship as GPX/CSV via
	// FetchExportRuns + the runs projection, and routes ship via
	// FetchExportRoutes. Putting them in the generic spec too would
	// double-export them.
	"runs":   "exported via FetchExportRuns (GPX/CSV) + the runs projection, not the generic spec",
	"routes": "exported via FetchExportRoutes, not the generic spec",

	// Operational tables keyed by user_id that are not Art-20 portable
	// personal data the subject *provided*. They're drained on account
	// deletion (Art 17) instead — see the delete-account EF.
	"rate_limits":         "operational throttle counters; drained on deletion, not part of an Art 20 export",
	"lifecycle_email_log": "internal send-once guard for transactional mail; operational, not Art 20 portable data",

	// Internal access-control allow-list, not subject-provided personal data:
	// admin status is controller-assigned (an org decision, not data the user
	// gave us under Art 20), and the row's `granted_by` is ANOTHER admin's user
	// id — exporting it to the subject would leak a third party. Admin rows are
	// drained on account deletion (Art 17) via the delete-account path instead.
	// CISO/counsel to confirm this exclusion stands (org SOC 2 / GovRAMP scope).
	"app_admins": "internal access-control allow-list; controller-assigned (not Art-20 user-provided) and granted_by references another admin — drained on deletion, not exported",

	// clubs.owner_id is the subject when they founded a club, but a club is a
	// shared collective entity (name, description, shared membership), not the
	// subject's own portable personal data in the one-row-per-table sense. The
	// subject's relationship to the club ships via club_members; the club row
	// itself belongs to the collective and would leak other members' context if
	// shipped as "the subject's data". Drained/transferred on account deletion
	// (Art 17), not part of the Art 20 portability export.
	// CISO/counsel to confirm this exclusion stands (org SOC 2 / GovRAMP scope).
	"clubs": "shared collective entity (owner_id is the founder); the subject's link ships via club_members — not Art-20 portable personal data of the subject",
}

func TestPersonalDataExport_EveryOwnerFkTableIsCoveredOrExcluded(t *testing.T) {
	ownerTables := ownerFkTablesFromMigrations(t)
	if len(ownerTables) == 0 {
		t.Fatal("parsed zero owner-FK tables from the migrations — the parser or the " +
			"migrations path is wrong; the guard would silently pass and protect nothing")
	}
	// Sentinel: a few tables we know carry an owner-style FK to auth.users.
	// If the SQL parser silently breaks (regex rot) and stops finding
	// columns, the coverage loop below would pass vacuously — these
	// assertions make that failure mode loud instead. The list deliberately
	// spans both the literal `user_id` form (runs, coach_messages, …) and
	// the differently-named owner columns the widened guard now catches
	// (session_plans.author_id, route_photos.owner_id, event_orders.*_user_id)
	// so a regression in either matching path is loud.
	for _, sentinel := range []string{
		"runs", "coach_messages", "race_pings", "gym_workouts",
		"session_plans", "route_photos", "event_orders",
	} {
		if !ownerTables[sentinel] {
			t.Fatalf("parser failed to detect an owner-style FK to auth.users on %q — the "+
				"migration scanner is broken and the export guard is not actually protecting "+
				"anything", sentinel)
		}
	}

	covered := exportSpecCoveredTables()

	var missing []string
	for table := range ownerTables {
		if covered[table] {
			continue
		}
		if _, excluded := exportGuardExclusions[table]; excluded {
			continue
		}
		missing = append(missing, table)
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		t.Errorf("these tables carry an owner-style FK to auth.users (user_id / author_id / "+
			"owner_id / buyer_user_id / host_user_id / contact_user_id) but are not in the "+
			"GDPR Art 20 export spec (exportPersonalDataSpecs) nor in exportGuardExclusions: %v\n"+
			"Wire each into exportPersonalDataSpecs (and its TS twin backup_spec.test.ts), "+
			"or add it to exportGuardExclusions with a reason if it is genuinely not "+
			"portable personal data.", missing)
	}
}

// The exclusion list must not rot: every entry has to still be a real
// owner-FK table, and must not overlap the spec (otherwise it's a
// rubber-stamp that hides nothing).
func TestPersonalDataExport_ExclusionListIsNotStale(t *testing.T) {
	ownerTables := ownerFkTablesFromMigrations(t)
	covered := exportSpecCoveredTables()
	for table, reason := range exportGuardExclusions {
		if reason == "" {
			t.Errorf("exclusion %q has no reason — every exclusion must justify itself", table)
		}
		if !ownerTables[table] {
			t.Errorf("exclusion %q is not (or no longer) a table with an owner-style FK to "+
				"auth.users — remove the stale exclusion", table)
		}
		if covered[table] {
			t.Errorf("exclusion %q is also fetched by the export spec — drop the redundant "+
				"exclusion so the list stays honest", table)
		}
	}
}

// exportSpecCoveredTables is the set of tables the Art 20 export
// actually fetches: every spec.table, plus the two tables fetched
// outside the spec loop (jobs via payload->>user_id, run_gear via the
// two-step gear-id fetch). Neither of those two carries an owner-style FK
// column so they never appear in ownerFkTablesFromMigrations, but they
// are listed for honesty / future-proofing.
func exportSpecCoveredTables() map[string]bool {
	covered := map[string]bool{
		"jobs":     true, // fetched via payload->>user_id summary
		"run_gear": true, // fetched via the two-step gear-id list
	}
	for _, s := range exportPersonalDataSpecs("guard-probe-uid") {
		covered[s.table] = true
	}
	return covered
}

// migrationsDir resolves the backend migrations directory relative to
// this package (Go test working dir == package dir). Skips loudly if it
// can't be found so a contributor running the package from an unusual
// cwd gets a clear message rather than a false pass.
func migrationsDir(t *testing.T) string {
	t.Helper()
	dir := filepath.Join("..", "..", "backend", "supabase", "migrations")
	if _, err := os.Stat(dir); err != nil {
		t.Skipf("migrations dir not found at %s (%v) — run from apps/job_worker so the "+
			"export-completeness guard can read the schema", dir, err)
	}
	return dir
}

var (
	// create [if not exists] [public.]"?name"? (
	reCreateTable = regexp.MustCompile(`(?is)create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s*\(`)
	// $$ ... $$ dollar-quoted bodies (function bodies) — stripped so a
	// `create table` or owner column inside one can't fool the parser.
	reDollarBody  = regexp.MustCompile(`(?s)\$\$.*?\$\$`)
	reLineComment = regexp.MustCompile(`--[^\n]*`)
	// `user_id` as a column, i.e. at a word boundary not preceded by an
	// identifier char (so `follower_id` / `parent_user_id` don't match).
	// Kept name-only because user_id columns frequently declare their FK as
	// a separate constraint (or appear in RPC return-table signatures), so
	// the bare name is the crisp signal here — same rule the guard has always
	// applied.
	reUserIDCol = regexp.MustCompile(`(?:^|[\s,(])user_id\b`)
	// The differently-named owner columns the widened guard now catches.
	// These are required to carry an inline `references auth.users` on the
	// same column declaration so a same-named column pointing at a DIFFERENT
	// table (a hypothetical `owner_id references clubs`) can't false-positive.
	// `[^,]*` keeps the match inside the single (comma-separated) column def.
	reOwnerFkCol = regexp.MustCompile(
		`(?:^|[\s,(])(?:author_id|owner_id|buyer_user_id|host_user_id|contact_user_id)\s+uuid[^,]*references\s+auth\.users`)
)

// ownerFkTablesFromMigrations parses every *.sql migration and returns
// the set of tables whose CREATE TABLE body declares an owner-style
// foreign key to auth.users — either a `user_id` column (by name) or one
// of the differently-named owner columns (author_id / owner_id /
// buyer_user_id / host_user_id / contact_user_id) carrying an inline
// `references auth.users`. Kept dependency-free so it runs under
// `go test` with no network.
func ownerFkTablesFromMigrations(t *testing.T) map[string]bool {
	t.Helper()
	dir := migrationsDir(t)
	files, err := filepath.Glob(filepath.Join(dir, "*.sql"))
	if err != nil {
		t.Fatalf("glob migrations: %v", err)
	}
	if len(files) == 0 {
		t.Fatalf("no .sql migrations found under %s", dir)
	}
	out := map[string]bool{}
	for _, f := range files {
		raw, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("read %s: %v", f, err)
		}
		sql := reLineComment.ReplaceAllString(string(raw), "")
		sql = reDollarBody.ReplaceAllString(sql, "")
		lower := strings.ToLower(sql)
		for _, m := range reCreateTable.FindAllStringSubmatchIndex(lower, -1) {
			table := lower[m[2]:m[3]]
			body := balancedParenBody(lower, m[1]-1) // m[1]-1 points at the '('
			if reUserIDCol.MatchString(body) || reOwnerFkCol.MatchString(body) {
				out[table] = true
			}
		}
	}
	return out
}

// balancedParenBody returns the text inside the parenthesised group
// that opens at openIdx (which must index a '('). Handles the nested
// parens of column types like numeric(10,2) and inline CHECKs.
func balancedParenBody(s string, openIdx int) string {
	depth := 0
	for i := openIdx; i < len(s); i++ {
		switch s[i] {
		case '(':
			depth++
		case ')':
			depth--
			if depth == 0 {
				return s[openIdx+1 : i]
			}
		}
	}
	return ""
}
