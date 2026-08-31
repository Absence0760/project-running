package internal

// The queued Art 20 rail's contract with its own schema
// (migration 20270603_001, decisions.md § 717).
//
// Every constant this rail turns on — the status vocabulary, the format
// set, the retry budget, the error-code width, the queue kind — is
// declared twice: once in SQL as a CHECK or a literal, once in Go. The
// pair is what makes the code work, and nothing before this file read
// the SQL half. A widened CHECK with no Go arm leaves a status the
// worker cannot interpret; a Go status the CHECK does not admit is a
// PATCH that 400s and leaves a subject's row saying `running` for ever.
//
// So these read the migration rather than a hand-copied literal, in the
// same shape personal_data_export_guard_test.go reads the schema for the
// table set.

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"

	"github.com/Absence0760/project-running/apps/job_worker/internal/dataexport"
	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

const asyncExportMigration = "20270603_001_async_data_export.sql"

func asyncExportMigrationSQL(t *testing.T) string {
	t.Helper()
	path := filepath.Join(migrationsDir(t), asyncExportMigration)
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(raw)
}

// inListValues pulls the quoted tokens out of a `check (col in ('a','b'))`
// clause named by `constraint`. Fails rather than returning an empty set:
// a guard that silently finds nothing protects nothing.
func inListValues(t *testing.T, sql, constraint string) []string {
	t.Helper()
	re := regexp.MustCompile(`(?is)constraint\s+` + regexp.QuoteMeta(constraint) +
		`\s*\n?\s*check\s*\(\s*\w+\s+in\s*\(([^)]*)\)`)
	m := re.FindStringSubmatch(sql)
	if m == nil {
		t.Fatalf("could not find `%s` in %s — the parser has rotted or the "+
			"constraint was renamed; either way this guard is asserting nothing",
			constraint, asyncExportMigration)
	}
	var out []string
	for _, tok := range regexp.MustCompile(`'([^']*)'`).FindAllStringSubmatch(m[1], -1) {
		out = append(out, tok[1])
	}
	if len(out) == 0 {
		t.Fatalf("`%s` parsed to zero values", constraint)
	}
	sort.Strings(out)
	return out
}

func TestExportJobContract_StatusVocabularyMatchesTheCheck(t *testing.T) {
	got := inListValues(t, asyncExportMigrationSQL(t), "data_export_jobs_status_chk")
	want := []string{"expired", "failed", "queued", "ready", "running"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("data_export_jobs.status admits %v, the rail is written against %v.\n"+
			"A new status needs an arm in dataexport.handleJobsLatest (which signs only "+
			"`ready` and reports only `failed`/`expired` specially), in the reuse check in "+
			"handleJobsCreate (which treats only `queued`/`running` as in flight), in "+
			"ExportJobRow.isStale, and in handleDataExport's early returns.", got, want)
	}
}

func TestExportJobContract_TheReadTimeDerivationsAreNeverWritableStatuses(t *testing.T) {
	// `none` and `stalled` are answers the READER composes; the column
	// can hold neither. Writing one would fail the CHECK, and admitting
	// one into the CHECK would mean a worker could park a row in a state
	// the reuse check does not recognise as in-flight — so the subject
	// could never enqueue again.
	admitted := inListValues(t, asyncExportMigrationSQL(t), "data_export_jobs_status_chk")
	for _, derived := range []string{dataexport.StatusNone, dataexport.StatusStalled} {
		for _, s := range admitted {
			if s == derived {
				t.Fatalf("%q is a read-time derivation and must not be a storable status", derived)
			}
		}
	}
}

func TestExportJobContract_EveryStatusTheWorkerWritesIsAdmitted(t *testing.T) {
	admitted := map[string]bool{}
	for _, s := range inListValues(t, asyncExportMigrationSQL(t), "data_export_jobs_status_chk") {
		admitted[s] = true
	}
	// The three the Go side ever PATCHes onto the row.
	for _, s := range []string{"running", "ready", "failed"} {
		if !admitted[s] {
			t.Errorf("the worker writes status=%q, which the CHECK rejects — "+
				"the PATCH 400s and the row stays where it was", s)
		}
	}
}

func TestExportJobContract_FormatSetMatchesValidFormat(t *testing.T) {
	got := inListValues(t, asyncExportMigrationSQL(t), "data_export_jobs_format_chk")
	for _, f := range got {
		if !dataexport.ValidFormat(f) {
			t.Errorf("the column admits format %q that ValidFormat refuses — "+
				"a row could exist the builder cannot build", f)
		}
	}
	for _, f := range []string{"csv", "gpx", "backup"} {
		found := false
		for _, g := range got {
			if g == f {
				found = true
			}
		}
		if !found {
			t.Errorf("ValidFormat accepts %q but the column does not — the "+
				"endpoint answers 202 and the enqueue then raises 22023", f)
		}
	}
	if dataexport.ValidFormat("zip") || dataexport.ValidFormat("") || dataexport.ValidFormat("CSV") {
		t.Error("ValidFormat must be exact and closed")
	}
}

func TestExportJobContract_RetryBudgetMatchesTheEnqueuedMaxAttempts(t *testing.T) {
	// The handler decides whether to tell the subject their export failed
	// by comparing the job's attempt count to this. If the SQL grants more
	// attempts than Go believes, a retry that is still coming is reported
	// as a permanent failure; if fewer, the row is never marked failed at
	// all and only the staleness derivation rescues it.
	sql := asyncExportMigrationSQL(t)
	re := regexp.MustCompile(`(?is)insert\s+into\s+jobs\s*\(\s*kind\s*,\s*payload\s*,\s*max_attempts\s*\)\s*values\s*\(([^;]*?)\)\s*;`)
	m := re.FindStringSubmatch(sql)
	if m == nil {
		t.Fatal("could not find the jobs insert in the enqueue RPC")
	}
	nums := regexp.MustCompile(`,\s*(\d+)\s*$`).FindStringSubmatch(strings.TrimSpace(m[1]))
	if nums == nil {
		t.Fatalf("could not read max_attempts out of %q", m[1])
	}
	got, err := strconv.Atoi(nums[1])
	if err != nil {
		t.Fatal(err)
	}
	if got != ExportJobMaxAttempts {
		t.Fatalf("enqueue_data_export stamps max_attempts=%d, ExportJobMaxAttempts=%d",
			got, ExportJobMaxAttempts)
	}
}

func TestExportJobContract_TheQueueKindIsInTheJobsAllowlist(t *testing.T) {
	sql := asyncExportMigrationSQL(t)
	if !regexp.MustCompile(`(?is)constraint\s+jobs_kind_chk[\s\S]*?'data_export'`).MatchString(sql) {
		t.Fatal("jobs_kind_chk does not admit 'data_export' — the enqueue RPC's own " +
			"jobs insert would violate it and no export could ever be queued")
	}
	// And the worker must dispatch it, or the row is claimed and dropped
	// as an unknown kind while the subject watches a `queued` row.
	w := &Worker{Log: nil}
	if !w.knowsExportKind() {
		t.Fatal("the worker does not route kind=data_export")
	}
}

// knowsExportKind reports whether `data_export` reaches a handler rather
// than the unknown-kind branch. Kept beside the guard that needs it
// rather than exported from the worker.
func (w *Worker) knowsExportKind() bool {
	return w.handleTimeoutFor("data_export") == ExportJobTimeout
}

func TestExportJobContract_EveryErrorCodeFitsTheColumn(t *testing.T) {
	// `data_export_jobs_error_code_len_chk` caps the token at 64 chars.
	// A longer one makes the failure PATCH 400 and leaves the row saying
	// `running` — the subject is then told their export is still building
	// until the staleness window expires.
	sql := asyncExportMigrationSQL(t)
	m := regexp.MustCompile(`(?is)data_export_jobs_error_code_len_chk\s*\n?\s*check\s*\([^)]*length\(error_code\)\s*<=\s*(\d+)`).FindStringSubmatch(sql)
	if m == nil {
		t.Fatal("could not read the error_code length CHECK")
	}
	limit, err := strconv.Atoi(m[1])
	if err != nil {
		t.Fatal(err)
	}
	// Every token the Go side can produce: the handler's own fallbacks
	// plus main.go's adapter, whose section codes are `<section>_fetch_failed`
	// over the two sections BuildArtifact names.
	for _, code := range []string{
		"build_failed", "not_configured", "upload_failed",
		"runs_fetch_failed", "routes_fetch_failed",
	} {
		if len(code) > limit {
			t.Errorf("error code %q is %d chars, the column admits %d", code, len(code), limit)
		}
	}
	if exportErrorCode(nil) != "build_failed" {
		t.Errorf("an unclassified failure must still carry a token, got %q", exportErrorCode(nil))
	}
	if got := exportErrorCode(&ExportBuildError{Code: "upload_failed"}); got != "upload_failed" {
		t.Errorf("a classified failure must keep its own token, got %q", got)
	}
	if got := exportErrorCode(&ExportBuildError{Code: ""}); got != "build_failed" {
		t.Errorf("an empty code must fall back rather than write a blank, got %q", got)
	}
}

func TestExportJobContract_TheRowIsNeverExportedIntoItsOwnArchive(t *testing.T) {
	// data_export_jobs carries an owner FK to auth.users, so the
	// completeness guard would demand it be exported. It is deliberately
	// excluded — the row is fulfilment metadata about the request, and
	// shipping it inside the archive it describes is circular. Pinned
	// here so the exclusion cannot quietly become an omission.
	if _, ok := exportGuardExclusions["data_export_jobs"]; !ok {
		t.Fatal("data_export_jobs must stay a conscious, documented export exclusion")
	}
	for _, spec := range exportPersonalDataSpecs("user-A") {
		if spec.table == "data_export_jobs" {
			t.Fatal("the export bundles its own job rows")
		}
	}
}

func TestExportJobContract_TheArtifactBucketIsTheOneWithNoPolicies(t *testing.T) {
	// § 703/§ 708: the artifact moved off `runs` (25 MB ceiling, and a
	// bucket with policies) onto `exports`. Both halves matter — the
	// ceiling, and that a path is inert without a service-role signature.
	if schema.BucketExports != "exports" {
		t.Fatalf("BucketExports=%q, want the policy-free exports bucket", schema.BucketExports)
	}
	up := (&SupabaseClient{BaseURL: "https://x", ServiceKey: "k"}).
		OpenExportArtifact(context.Background(), "user-A/exports/x.zip", "application/zip")
	if up.bucket != schema.BucketExports {
		t.Fatalf("the tus session opens against %q, want %q", up.bucket, schema.BucketExports)
	}
}

// exportJobColumns parses the `data_export_jobs` CREATE TABLE body and
// returns its column names.
func exportJobColumns(t *testing.T) map[string]bool {
	t.Helper()
	sql := asyncExportMigrationSQL(t)
	start := regexp.MustCompile(`(?is)create\s+table\s+data_export_jobs\s*\(`).FindStringIndex(sql)
	if start == nil {
		t.Fatal("could not find the data_export_jobs CREATE TABLE")
	}
	body := sql[start[1]:]
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
	if end == 0 {
		t.Fatal("unbalanced parentheses in the data_export_jobs CREATE TABLE")
	}
	cols := map[string]bool{}
	for _, line := range strings.Split(body[:end], "\n") {
		line = strings.TrimSpace(regexp.MustCompile(`--.*$`).ReplaceAllString(line, ""))
		m := regexp.MustCompile(`^([a-z_][a-z0-9_]*)\s+(uuid|text|integer|boolean|timestamptz)\b`).FindStringSubmatch(line)
		if m != nil {
			cols[m[1]] = true
		}
	}
	if len(cols) < 8 {
		t.Fatalf("parsed only %d columns from data_export_jobs (%v) — the parser has rotted", len(cols), cols)
	}
	return cols
}

func TestExportJobContract_EveryDecodedFieldIsARealColumn(t *testing.T) {
	// A typo'd tag does not fail: PostgREST returns the row, the field
	// decodes to its zero value, and every `ready` row then reads as one
	// carrying no artifact path. Nothing else in the rail would notice.
	cols := exportJobColumns(t)
	rt := reflect.TypeOf(ExportJobRow{})
	seen := 0
	for i := 0; i < rt.NumField(); i++ {
		tag := strings.Split(rt.Field(i).Tag.Get("json"), ",")[0]
		if tag == "" || tag == "-" {
			t.Fatalf("%s carries no json tag; it would decode off its Go name", rt.Field(i).Name)
		}
		if !cols[tag] {
			t.Errorf("ExportJobRow.%s decodes `%s`, which data_export_jobs does not have",
				rt.Field(i).Name, tag)
		}
		seen++
	}
	if seen != len(cols) {
		var missing []string
		for c := range cols {
			found := false
			for i := 0; i < rt.NumField(); i++ {
				if strings.Split(rt.Field(i).Tag.Get("json"), ",")[0] == c {
					found = true
				}
			}
			if !found {
				missing = append(missing, c)
			}
		}
		sort.Strings(missing)
		t.Errorf("data_export_jobs columns not read by ExportJobRow: %v — a new column "+
			"the status endpoint should report would be invisible to it", missing)
	}
}

func TestExportJobContract_EveryPatchedKeyIsARealColumn(t *testing.T) {
	// FinishDataExportJob builds its PATCH body from string literals
	// rather than from the struct tags, so a renamed column surfaces as
	// a PostgREST 400 in production and as nothing at all in a fake.
	cols := exportJobColumns(t)
	for _, key := range []string{
		"status", "started_at", "finished_at",
		"object_path", "run_count", "total_runs", "complete", "error_code",
	} {
		if !cols[key] {
			t.Errorf("the worker PATCHes %q, which data_export_jobs does not have", key)
		}
	}
}
