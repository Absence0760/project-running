package internal

// The Art 20 export used to read every table with a single unbounded
// PostgREST GET. PostgREST clamps a response to `db-max-rows` (1000 on
// Supabase) and reports the truncation nowhere in the body — even an
// explicit `limit=5000` comes back with 1000 rows — so a runner past
// their thousandth run, photo, food-log row or gym set received a
// silently short archive whose manifest asserted it was whole.
//
// These tests stand up a PostgREST that clamps exactly the way the real
// one does, and would return 1000 of 2400 rows against the pre-paging
// code.

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"testing"
)

const postgrestMaxRows = 1000

// clampedTable serves `total` rows of `table` the way PostgREST does:
// honouring limit/offset but never returning more than db-max-rows, and
// reporting the true count in Content-Range only when asked.
type clampedTable struct {
	table string
	total int
	// failFromOffset makes every page at or past this offset 500, to
	// exercise a walk that breaks part-way. Negative disables it.
	failFromOffset int

	mu      sync.Mutex
	windows [][2]int
	orders  []string
}

func (c *clampedTable) serve(w http.ResponseWriter, r *http.Request) bool {
	if !strings.HasPrefix(r.URL.Path, "/rest/v1/"+c.table) {
		return false
	}
	q := r.URL.Query()
	offset, _ := strconv.Atoi(q.Get("offset"))
	limit, err := strconv.Atoi(q.Get("limit"))
	if err != nil || limit <= 0 || limit > postgrestMaxRows {
		limit = postgrestMaxRows
	}
	c.mu.Lock()
	c.windows = append(c.windows, [2]int{offset, limit})
	c.orders = append(c.orders, q.Get("order"))
	c.mu.Unlock()

	if c.failFromOffset >= 0 && offset >= c.failFromOffset {
		http.Error(w, `{"message":"boom"}`, http.StatusInternalServerError)
		return true
	}
	n := c.total - offset
	if n < 0 {
		n = 0
	}
	if n > limit {
		n = limit
	}
	rows := make([]string, 0, n)
	for i := 0; i < n; i++ {
		rows = append(rows, fmt.Sprintf(`{"id":"row-%04d","user_id":"user-A","started_at":"2026-01-01T00:00:00Z"}`, offset+i))
	}
	if strings.Contains(r.Header.Get("Prefer"), "count=exact") {
		w.Header().Set("Content-Range", fmt.Sprintf("%d-%d/%d", offset, offset+n-1, c.total))
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte("[" + strings.Join(rows, ",") + "]"))
	return true
}

func clampedServer(t *testing.T, tables ...*clampedTable) *SupabaseClient {
	t.Helper()
	return newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		for _, tbl := range tables {
			if tbl.serve(w, r) {
				return
			}
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte("[]"))
	})
}

// collectExportRuns / collectExportRoutes / collectExportTables drain a
// streaming walk into the shape the assertions below read. Production
// never collects — that is the point of the change — so the collecting
// lives here, in the tests that need something to look at.
func collectExportRuns(c *SupabaseClient, ctx context.Context, userID string) ([]ExportRunRow, ExportCompleteness, error) {
	var rows []ExportRunRow
	comp, err := c.StreamExportRuns(ctx, userID, func(page []ExportRunRow) error {
		rows = append(rows, page...)
		return nil
	})
	return rows, comp, err
}

func collectExportRoutes(c *SupabaseClient, ctx context.Context, userID string) ([]ExportRouteRow, ExportCompleteness, error) {
	var rows []ExportRouteRow
	comp, err := c.StreamExportRoutes(ctx, userID, func(page []ExportRouteRow) error {
		rows = append(rows, page...)
		return nil
	})
	return rows, comp, err
}

func collectExportTables(c *SupabaseClient, ctx context.Context, userID string) (map[string][]map[string]interface{}, ExportCompleteness, error) {
	out := map[string][]map[string]interface{}{}
	comp, err := c.StreamExportPersonalDataTables(ctx, userID, func(entry string, rows []map[string]interface{}) error {
		out[entry] = append(out[entry], rows...)
		return nil
	})
	return out, comp, err
}

func TestFetchExportRuns_PagesPastThePostgrestRowCap(t *testing.T) {
	runs := &clampedTable{table: "runs", total: 2400, failFromOffset: -1}
	client := clampedServer(t, runs)

	rows, comp, err := collectExportRuns(client, context.Background(), "user-A")
	if err != nil {
		t.Fatalf("StreamExportRuns: %v", err)
	}
	if len(rows) != 2400 {
		t.Fatalf("got %d runs; want every one of the 2400 (a single unpaged read returns %d)", len(rows), postgrestMaxRows)
	}
	if comp.Totals["runs"] != 2400 {
		t.Errorf("manifest count=%d; want the database's own 2400", comp.Totals["runs"])
	}
	if len(comp.Incomplete) != 0 {
		t.Errorf("a fully-read export must not be flagged short: %v", comp.Incomplete)
	}
	if len(runs.windows) != 3 {
		t.Fatalf("windows=%v; want three 1000-row pages", runs.windows)
	}
	// `started_at` alone is not a total order — two runs can share one.
	for _, o := range runs.orders {
		if o != "started_at.desc,id.asc" {
			t.Errorf("order=%q; want a total order", o)
		}
	}
}

// The runs walk used to stop at a caller-supplied ceiling
// (MaxRunsPerExport = 5000) and flag the section short, because the
// archive was assembled in one bytes.Buffer. Both are gone: the walk
// runs to the end of the history and each page is serialised as it
// arrives, so a runner far past either deleted bound receives their
// whole history and the manifest says the export is complete.
func TestStreamExportRuns_WalksPastEveryDeletedCeiling(t *testing.T) {
	runs := &clampedTable{table: "runs", total: 120_000, failFromOffset: -1}
	client := clampedServer(t, runs)

	seen, biggestPage := 0, 0
	comp, err := client.StreamExportRuns(context.Background(), "user-A", func(page []ExportRunRow) error {
		seen += len(page)
		if len(page) > biggestPage {
			biggestPage = len(page)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("StreamExportRuns: %v", err)
	}
	if seen != 120_000 {
		t.Fatalf("streamed %d runs; want all 120000 — far past the deleted 5000-run cap", seen)
	}
	if comp.Totals["runs"] != 120_000 || len(comp.Incomplete) != 0 {
		t.Errorf("comp=%+v; a whole history must not be flagged short", comp)
	}
	// The consumer never sees more than one page at a time, which is the
	// property that makes the walk flat in the size of the history.
	if biggestPage != postgrestMaxRows {
		t.Errorf("biggest page=%d; want one PostgREST page, never the whole set", biggestPage)
	}
	// 121, not 120: offset paging cannot know a full page was the last
	// one, so a history that is an exact multiple of the page size costs
	// one extra empty read to prove it ended.
	if len(runs.windows) != 121 {
		t.Errorf("windows=%d; want 120 full pages plus the empty one that ends the walk", len(runs.windows))
	}
}

// Same for a high-cardinality personal-data section: `live_run_pings`
// runs into the millions on a deep history and is what the 50,000-row
// exportRowCeiling was written for.
func TestStreamExportPersonalDataTables_WalksPastTheDeletedRowCeiling(t *testing.T) {
	pings := &clampedTable{table: "live_run_pings", total: 120_000, failFromOffset: -1}
	client := clampedServer(t, pings)

	seen, biggestPage := 0, 0
	comp, err := client.StreamExportPersonalDataTables(context.Background(), "user-A",
		func(entry string, rows []map[string]interface{}) error {
			if entry != "live_run_pings.json" {
				return nil
			}
			seen += len(rows)
			if len(rows) > biggestPage {
				biggestPage = len(rows)
			}
			return nil
		})
	if err != nil {
		t.Fatalf("StreamExportPersonalDataTables: %v", err)
	}
	if seen != 120_000 {
		t.Fatalf("streamed %d pings; want all 120000 — far past the deleted 50000-row ceiling", seen)
	}
	if comp.Totals["live_run_pings"] != 120_000 {
		t.Errorf("count=%d; want 120000", comp.Totals["live_run_pings"])
	}
	for _, name := range comp.Incomplete {
		if name == "live_run_pings" {
			t.Error("a fully-read section must not be flagged short")
		}
	}
	if biggestPage != postgrestMaxRows {
		t.Errorf("biggest page=%d; want one PostgREST page", biggestPage)
	}
}

// A consumer failure is the archive dying, not a table coming up short.
// Recording it as a short table would hand the subject an export whose
// manifest blamed the database for a write that never happened — and
// would let the walk carry on writing into a dead archive.
func TestStreamExportPersonalDataTables_ConsumerFailureIsNotAShortTable(t *testing.T) {
	food := &clampedTable{table: "food_log", total: 2400, failFromOffset: -1}
	client := clampedServer(t, food)

	boom := errors.New("chunk upload failed")
	calls := 0
	comp, err := client.StreamExportPersonalDataTables(context.Background(), "user-A",
		func(entry string, rows []map[string]interface{}) error {
			if entry != "food_log.json" {
				return nil
			}
			calls++
			return boom
		})
	if !errors.Is(err, boom) {
		t.Fatalf("err=%v; a consumer failure must surface unwrapped so the handler can 500", err)
	}
	if calls != 1 {
		t.Errorf("emit called %d times; the walk must stop at the first consumer failure", calls)
	}
	for _, name := range comp.Incomplete {
		if name == "food_log" {
			t.Error("the table was readable; only the archive failed")
		}
	}
}

func TestFetchExportRuns_AFailedPageKeepsRowsButNeverClaimsCompleteness(t *testing.T) {
	runs := &clampedTable{table: "runs", total: 2400, failFromOffset: 1000}
	client := clampedServer(t, runs)

	rows, comp, err := collectExportRuns(client, context.Background(), "user-A")
	if err == nil {
		t.Fatal("a failed page must surface as an error so the handler can refuse")
	}
	if len(rows) != 1000 {
		t.Errorf("rows=%d; want the first page emitted before the failure", len(rows))
	}
	if comp.Totals["runs"] != 2400 || len(comp.Incomplete) != 1 {
		t.Errorf("comp=%+v; want the true total and a short flag", comp)
	}
}

func TestFetchExportRoutes_PagesPastTheRowCap(t *testing.T) {
	routes := &clampedTable{table: "routes", total: 1500, failFromOffset: -1}
	client := clampedServer(t, routes)

	rows, comp, err := collectExportRoutes(client, context.Background(), "user-A")
	if err != nil {
		t.Fatalf("StreamExportRoutes: %v", err)
	}
	if len(rows) != 1500 {
		t.Fatalf("routes=%d; want 1500", len(rows))
	}
	if comp.Totals["routes"] != 1500 || len(comp.Incomplete) != 0 {
		t.Errorf("comp=%+v", comp)
	}
}

func TestFetchExportPersonalDataTables_PagesEveryTable(t *testing.T) {
	// food_log is the archetype of the row-heavy victim: one row per
	// item eaten, so a daily logger crosses 1000 inside a year.
	food := &clampedTable{table: "food_log", total: 2400, failFromOffset: -1}
	client := clampedServer(t, food)

	out, comp, err := collectExportTables(client, context.Background(), "user-A")
	if err != nil {
		t.Fatalf("StreamExportPersonalDataTables: %v", err)
	}
	if got := len(out["food_log.json"]); got != 2400 {
		t.Fatalf("food_log rows=%d; want all 2400", got)
	}
	if comp.Totals["food_log"] != 2400 {
		t.Errorf("food_log count=%d; want 2400", comp.Totals["food_log"])
	}
	for _, name := range comp.Incomplete {
		if name == "food_log" {
			t.Error("a fully-read table must not be flagged short")
		}
	}
}

func TestFetchExportPersonalDataTables_ShortTableIsNamedNotHidden(t *testing.T) {
	gym := &clampedTable{table: "gym_workouts", total: 3000, failFromOffset: 2000}
	client := clampedServer(t, gym)

	out, comp, err := collectExportTables(client, context.Background(), "user-A")
	if err != nil {
		t.Fatalf("a per-table failure stays tolerated: %v", err)
	}
	if got := len(out["gym_workouts.json"]); got != 2000 {
		t.Fatalf("rows=%d; want the two pages that did come back", got)
	}
	if comp.Totals["gym_workouts"] != 3000 {
		t.Errorf("count=%d; want the true 3000", comp.Totals["gym_workouts"])
	}
	found := false
	for _, name := range comp.Incomplete {
		if name == "gym_workouts" {
			found = true
		}
	}
	if !found {
		t.Errorf("incomplete=%v; the short table must be named", comp.Incomplete)
	}
}

func TestExportTableOrderCoversEveryCompositeKey(t *testing.T) {
	// Offset paging under a non-total order repeats one row and drops
	// another; a dropped row is one the subject never receives.
	cases := map[string]string{
		"user_follows":         "follower_id,followee_id",
		"run_kudos":            "user_id,run_id",
		"run_gear":             "run_id,gear_id",
		"personal_records":     "user_id,distance",
		"event_attendees":      "event_id,user_id,instance_start",
		"user_device_settings": "user_id,device_id",
		"food_log":             "id",
		"runs":                 "id",
	}
	for table, want := range cases {
		if got := orderForExportTable(table); got != want {
			t.Errorf("orderForExportTable(%q)=%q; want %q", table, got, want)
		}
	}
}

func TestParseContentRangeTotal(t *testing.T) {
	cases := map[string]int{
		"0-999/1212": 1212,
		"*/0":        0,
		"0-999/*":    -1,
		"garbage":    -1,
		"":           -1,
	}
	for in, want := range cases {
		if got := parseContentRangeTotal(in); got != want {
			t.Errorf("parseContentRangeTotal(%q)=%d; want %d", in, got, want)
		}
	}
}
