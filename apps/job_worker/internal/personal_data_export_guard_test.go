package internal

// Build-time guard for GDPR Art 20 data-export completeness.
//
// exportPersonalDataSpecs (supabase.go) is the single source of truth
// for which personal-data tables the export bundles. The risk it can't
// protect against on its own is a *new* table: someone adds
// `create table foo (... user_id uuid ...)` in a migration, ships the
// feature, and silently never wires foo into the export — the subject's
// foo rows are then missing from every DSAR with nothing to flag it.
//
// This test closes that hole. It parses every migration for tables that
// carry a `user_id` column and asserts each one is either:
//
//   - covered by the export spec (appears as a spec.table), or
//   - named in exportGuardExclusions with a written reason.
//
// A new user_id-bearing table that is neither fails the build until a
// human consciously wires it into the export or excludes it. The
// exclusion list is itself guarded (no stale / no overlap) so it can't
// rot into a rubber stamp.
//
// Scope note: the guard keys on the literal `user_id` column because
// that is a crisp, parseable signal. Tables that hold the subject's
// data under a differently-named owner column (run_photos.owner_id,
// club_posts.author_id, reports.reporter_id, …) are still exported —
// they're in the spec — but they are not what this tripwire watches;
// the spec + its per-table unit tests cover those.

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// exportGuardExclusions names every table that HAS a `user_id` column
// but is deliberately not fetched by exportPersonalDataSpecs, with the
// reason. Adding a table here is a conscious decision a reviewer can
// see; the test fails if an entry here stops being a real user_id table
// (stale) or starts being covered by the spec (redundant).
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
}

func TestPersonalDataExport_EveryUserIdTableIsCoveredOrExcluded(t *testing.T) {
	userIDTables := userIDTablesFromMigrations(t)
	if len(userIDTables) == 0 {
		t.Fatal("parsed zero user_id tables from the migrations — the parser or the " +
			"migrations path is wrong; the guard would silently pass and protect nothing")
	}
	// Sentinel: a few tables we know carry user_id. If the SQL parser
	// silently breaks (regex rot) and stops finding columns, the
	// coverage loop below would pass vacuously — these assertions make
	// that failure mode loud instead.
	for _, sentinel := range []string{"runs", "coach_messages", "race_pings", "gym_workouts"} {
		if !userIDTables[sentinel] {
			t.Fatalf("parser failed to detect the user_id column on %q — the migration "+
				"scanner is broken and the export guard is not actually protecting anything",
				sentinel)
		}
	}

	covered := exportSpecCoveredTables()

	var missing []string
	for table := range userIDTables {
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
		t.Errorf("these tables carry a `user_id` column but are not in the GDPR Art 20 "+
			"export spec (exportPersonalDataSpecs) nor in exportGuardExclusions: %v\n"+
			"Wire each into exportPersonalDataSpecs (and its TS twin backup_spec.test.ts), "+
			"or add it to exportGuardExclusions with a reason if it is genuinely not "+
			"portable personal data.", missing)
	}
}

// The exclusion list must not rot: every entry has to still be a real
// user_id table, and must not overlap the spec (otherwise it's a
// rubber-stamp that hides nothing).
func TestPersonalDataExport_ExclusionListIsNotStale(t *testing.T) {
	userIDTables := userIDTablesFromMigrations(t)
	covered := exportSpecCoveredTables()
	for table, reason := range exportGuardExclusions {
		if reason == "" {
			t.Errorf("exclusion %q has no reason — every exclusion must justify itself", table)
		}
		if !userIDTables[table] {
			t.Errorf("exclusion %q is not (or no longer) a table with a user_id column — "+
				"remove the stale exclusion", table)
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
// two-step gear-id fetch). Neither of those two has a literal `user_id`
// column so they never appear in userIDTablesFromMigrations, but they
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
	// `create table` or `user_id` inside one can't fool the parser.
	reDollarBody  = regexp.MustCompile(`(?s)\$\$.*?\$\$`)
	reLineComment = regexp.MustCompile(`--[^\n]*`)
	// `user_id` as a column, i.e. at a word boundary not preceded by an
	// identifier char (so `follower_id` / `parent_user_id` don't match).
	reUserIDCol = regexp.MustCompile(`(?:^|[\s,(])user_id\b`)
)

// userIDTablesFromMigrations parses every *.sql migration and returns
// the set of tables whose CREATE TABLE body declares a `user_id`
// column. Mirrors the balanced-paren scan used to seed the exclusion
// list; kept dependency-free so it runs under `go test` with no network.
func userIDTablesFromMigrations(t *testing.T) map[string]bool {
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
			if reUserIDCol.MatchString(body) {
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
