package dataexport

// Coverage guard for the Art 20 export's `runs` projection.
//
// Both transports read the run row through a hand-written column list, and
// neither had ever been widened as the table gained columns: measured against
// the generated row type, `public.runs` had 24 columns and the projection
// selected 17. Four of the seven missing ones used to be exported and stopped
// -- migration 20270325_001 promoted the `fastest_*_s` PR times out of
// `runs.metadata` into real columns and stripped the keys from the bag in the
// same statement, so they left the CSV's `metadata` cell and `runs.json`'s
// `metadata` object the day it ran (decisions § 1171).
//
// Nothing could see it. `manifest.json`'s completeness contract is row counts
// against each section's authoritative total, and every row was present: the
// archive was short by COLUMNS, and reported itself complete.
//
// So the direction is inverted here. The projection is derived from the table
// rather than curated from it, and each format declares what it OMITS, with a
// reason. A column added to `runs` is exported by default and this file fails
// the PR that does not decide otherwise.

import (
	"encoding/json"
	"os"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

const (
	dbTypesPath = "../../../web/src/lib/database.types.ts"
	efIndexPath = "../../../backend/supabase/functions/export-data/index.ts"
)

// runsColumnsFromGeneratedTypes reads the `runs` Row out of the committed
// database.types.ts. That file is regenerated from the migrations on every
// schema change and CI fails a PR that skips the regeneration, so it is the
// cheapest honest statement of what the table holds.
func runsColumnsFromGeneratedTypes(t *testing.T) []string {
	t.Helper()
	src, err := os.ReadFile(dbTypesPath)
	if err != nil {
		t.Fatalf("cannot read the generated row types at %s: %v", dbTypesPath, err)
	}
	m := regexp.MustCompile(`(?s)\n      runs: \{\n        Row: \{\n(.*?)\n        \}\n`).FindSubmatch(src)
	if m == nil {
		t.Fatal("runs Row not found in database.types.ts; this guard reads its source and the shape changed")
	}
	var cols []string
	for _, line := range strings.Split(string(m[1]), "\n") {
		f := strings.SplitN(strings.TrimSpace(line), ":", 2)
		if len(f) == 2 && f[0] != "" {
			cols = append(cols, f[0])
		}
	}
	if len(cols) < 15 {
		t.Fatalf("parsed only %d runs columns (%v); the guard is not reading what it thinks", len(cols), cols)
	}
	sort.Strings(cols)
	return cols
}

// jsonTags is the wire shape of a struct: the JSON name of every field that
// marshals, which for these row structs is exactly the column set.
func jsonTags(v interface{}) []string {
	rt := reflect.TypeOf(v)
	var out []string
	for i := 0; i < rt.NumField(); i++ {
		tag := strings.Split(rt.Field(i).Tag.Get("json"), ",")[0]
		if tag != "" && tag != "-" {
			out = append(out, tag)
		}
	}
	sort.Strings(out)
	return out
}

func splitList(raw string) []string {
	var out []string
	for _, p := range strings.Split(raw, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	sort.Strings(out)
	return out
}

// quotedList pulls the single-quoted entries out of a TypeScript array
// literal named `name` in `src`.
func quotedList(t *testing.T, src []byte, name string) []string {
	t.Helper()
	m := regexp.MustCompile(`(?s)export const ` + name + ` = \[(.*?)\]`).FindSubmatch(src)
	if m == nil {
		t.Fatalf("%s not found in the EF rail; this guard reads its source and the shape changed", name)
	}
	var out []string
	for _, q := range regexp.MustCompile(`'([^']+)'`).FindAllStringSubmatch(string(m[1]), -1) {
		out = append(out, q[1])
	}
	sort.Strings(out)
	return out
}

func TestExportRunProjectionCoversEveryRunsColumn(t *testing.T) {
	cols := runsColumnsFromGeneratedTypes(t)

	if got := jsonTags(ExportRun{}); !reflect.DeepEqual(got, cols) {
		t.Errorf("ExportRun does not mirror public.runs.\n  table: %v\n  struct: %v", cols, got)
	}

	efSrc, err := os.ReadFile(efIndexPath)
	if err != nil {
		t.Fatalf("cannot read the EF rail at %s: %v", efIndexPath, err)
	}
	m := regexp.MustCompile(`(?s)const RUNS_SELECT =\s*'([^']+)'`).FindSubmatch(efSrc)
	if m == nil {
		t.Fatal("RUNS_SELECT not found in the EF rail; this guard reads its source and the shape changed")
	}
	if got := splitList(string(m[1])); !reflect.DeepEqual(got, cols) {
		t.Errorf("the Edge Function selects a different set than the table holds.\n  table: %v\n  RUNS_SELECT: %v", cols, got)
	}
}

func TestCSVCarriesEveryRunsColumnExceptTheOnesItDeclares(t *testing.T) {
	cols := runsColumnsFromGeneratedTypes(t)

	// The five cells the header names out of the `metadata` bag. They are
	// not table columns and are not part of the derivation.
	fromBag := map[string]bool{
		schema.MetaTitle: true, schema.MetaAvgBPM: true, schema.MetaHRCoverage: true,
		schema.MetaSteps: true, schema.MetaElevationM: true,
	}
	carried := append([]string{}, csvOmit...)
	for _, c := range csvColumns {
		if !fromBag[c] {
			carried = append(carried, c)
		}
	}
	sort.Strings(carried)
	if !reflect.DeepEqual(carried, cols) {
		t.Errorf("the CSV neither carries nor declines every runs column.\n  table: %v\n  carried+declined: %v", cols, carried)
	}

	efSrc, err := os.ReadFile(efRenderPath)
	if err != nil {
		t.Fatalf("cannot read the EF rail at %s: %v", efRenderPath, err)
	}
	want := append([]string{}, csvOmit...)
	sort.Strings(want)
	if got := quotedList(t, efSrc, "CSV_OMIT"); !reflect.DeepEqual(got, want) {
		t.Errorf("the two rails decline different columns.\n  EF: %v\n  Go: %v", got, want)
	}
}

// The two `runs.json` projections, driven rather than read: what a row
// actually serialises to is the only statement about them that cannot be
// true of the source and false of the archive.
func TestRunsJsonProjectionsOmitOnlyWhatTheyDeclare(t *testing.T) {
	cols := runsColumnsFromGeneratedTypes(t)
	row := ExportRun{}

	efSrc, err := os.ReadFile(efRenderPath)
	if err != nil {
		t.Fatalf("cannot read the EF rail at %s: %v", efRenderPath, err)
	}

	for _, c := range []struct {
		name  string
		value interface{}
		omit  []string
		efVar string
	}{
		{"backup runs.json", backupRun{ExportRun: row}, []string{"user_id"}, "RUNS_JSON_OMIT"},
		{
			"gpx runs.json", gpxManifestRun{ExportRun: row},
			[]string{"user_id", "track_url", "hr_series_url", "created_at", "updated_at"},
			"GPX_MANIFEST_OMIT",
		},
	} {
		b, err := json.Marshal(c.value)
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		var m map[string]interface{}
		if err := json.Unmarshal(b, &m); err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		got := append([]string{}, c.omit...)
		for k := range m {
			got = append(got, k)
		}
		sort.Strings(got)
		if !reflect.DeepEqual(got, cols) {
			t.Errorf("%s neither carries nor declines every runs column.\n  table: %v\n  carried+declined: %v", c.name, cols, got)
		}
		for _, k := range c.omit {
			if _, present := m[k]; present {
				t.Errorf("%s still carries %s", c.name, k)
			}
		}
		want := append([]string{}, c.omit...)
		sort.Strings(want)
		if ef := quotedList(t, efSrc, c.efVar); !reflect.DeepEqual(ef, want) {
			t.Errorf("%s: the two rails omit different fields.\n  EF %s: %v\n  Go: %v", c.name, c.efVar, ef, want)
		}
	}
}
