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

func TestFetchExportRuns_PagesPastThePostgrestRowCap(t *testing.T) {
	runs := &clampedTable{table: "runs", total: 2400, failFromOffset: -1}
	client := clampedServer(t, runs)

	rows, comp, err := client.FetchExportRuns(context.Background(), "user-A", 5000)
	if err != nil {
		t.Fatalf("FetchExportRuns: %v", err)
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

func TestFetchExportRuns_HonoursTheCallerCeilingAndSaysSo(t *testing.T) {
	runs := &clampedTable{table: "runs", total: 2400, failFromOffset: -1}
	client := clampedServer(t, runs)

	rows, comp, err := client.FetchExportRuns(context.Background(), "user-A", 2000)
	if err != nil {
		t.Fatalf("FetchExportRuns: %v", err)
	}
	if len(rows) != 2000 {
		t.Fatalf("rows=%d; want the 2000 the caller allowed", len(rows))
	}
	if comp.Totals["runs"] != 2400 {
		t.Errorf("count=%d; want the true 2400, not the 2000 exported", comp.Totals["runs"])
	}
	if len(comp.Incomplete) != 1 || comp.Incomplete[0] != "runs" {
		t.Errorf("incomplete=%v; a truncated section must be named", comp.Incomplete)
	}
}

func TestFetchExportRuns_AFailedPageKeepsRowsButNeverClaimsCompleteness(t *testing.T) {
	runs := &clampedTable{table: "runs", total: 2400, failFromOffset: 1000}
	client := clampedServer(t, runs)

	rows, comp, err := client.FetchExportRuns(context.Background(), "user-A", 5000)
	if err == nil {
		t.Fatal("a failed page must surface as an error so the handler can refuse")
	}
	if len(rows) != 1000 {
		t.Errorf("rows=%d; want the first page kept", len(rows))
	}
	if comp.Totals["runs"] != 2400 || len(comp.Incomplete) != 1 {
		t.Errorf("comp=%+v; want the true total and a short flag", comp)
	}
}

func TestFetchExportRoutes_PagesPastTheRowCap(t *testing.T) {
	routes := &clampedTable{table: "routes", total: 1500, failFromOffset: -1}
	client := clampedServer(t, routes)

	rows, comp, err := client.FetchExportRoutes(context.Background(), "user-A")
	if err != nil {
		t.Fatalf("FetchExportRoutes: %v", err)
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

	out, comp, err := client.FetchExportPersonalDataTables(context.Background(), "user-A")
	if err != nil {
		t.Fatalf("FetchExportPersonalDataTables: %v", err)
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

	out, comp, err := client.FetchExportPersonalDataTables(context.Background(), "user-A")
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
