package dataexport

import (
	"encoding/json"
	"os"
	"regexp"
	"strings"
	"testing"
)

// The EF rail these tests hold this one to.
const efRenderPath = "../../../backend/supabase/functions/export-data/render.ts"

func TestHrCoverageCellGradesRatherThanPassesThrough(t *testing.T) {
	// Decoded through JSON exactly as an exported row arrives, so the cases
	// are the ones a stored `metadata` bag can actually produce.
	cases := []struct {
		raw  string
		want string
	}{
		{`0.51`, "0.51"},
		// A sensor that was enabled and delivered nothing is a measurement,
		// not an absence, so it must not render as the empty cell an
		// unmeasured run gets.
		{`0`, "0"},
		{`1`, "1"},
		{`null`, ""},
		{`"0.8"`, ""},
		// The writer's contract is a fraction. A percentage would otherwise
		// put 85 in a column whose consumer reads it as 8500 %.
		{`85`, ""},
		{`-0.1`, ""},
		{`1.0000001`, ""},
	}
	for _, c := range cases {
		var v interface{}
		if err := json.Unmarshal([]byte(c.raw), &v); err != nil {
			t.Fatalf("%s: %v", c.raw, err)
		}
		if got := hrCoverageCell(v); got != c.want {
			t.Errorf("hrCoverageCell(%s) = %q, want %q", c.raw, got, c.want)
		}
	}
}

// A value both rails consider well formed must render as the same bytes on
// both, or one export contradicts the other. `stringy`'s %g does not: it
// writes 1e-07 and 1e-06 where JS String() writes 1e-7 and 0.000001.
func TestHrCoverageCellMatchesJavaScriptNumberToString(t *testing.T) {
	// left: the JSON literal; right: the exact output of String(n) in V8.
	cases := [][2]string{
		{`0`, "0"},
		{`1`, "1"},
		{`0.5`, "0.5"},
		{`0.51`, "0.51"},
		{`0.07`, "0.07"},
		{`0.3333333333333333`, "0.3333333333333333"},
		{`0.30000000000000004`, "0.30000000000000004"},
		{`0.9999999999999999`, "0.9999999999999999"},
		{`0.000001`, "0.000001"},
		{`1e-7`, "1e-7"},
		{`1e-21`, "1e-21"},
	}
	for _, c := range cases {
		var v interface{}
		if err := json.Unmarshal([]byte(c[0]), &v); err != nil {
			t.Fatalf("%s: %v", c[0], err)
		}
		if got := hrCoverageCell(v); got != c[1] {
			t.Errorf("hrCoverageCell(%s) = %q, want %q (JS String())", c[0], got, c[1])
		}
	}
}

// The Go rail hand-mirrors the EF's CSV_COLS and nothing compared the two, so
// a column added on one side reached a runner's archive on one transport and
// not the other. `hr_coverage` was exactly that: the EF gained it and this
// rail -- the one most runners reach -- did not.
func TestCSVColumnsMatchTheEdgeFunctionRail(t *testing.T) {
	src, err := os.ReadFile(efRenderPath)
	if err != nil {
		t.Fatalf("cannot read the EF rail at %s: %v", efRenderPath, err)
	}
	m := regexp.MustCompile(`(?s)export const CSV_COLS = \[(.*?)\n\]`).FindSubmatch(src)
	if m == nil {
		t.Fatal("CSV_COLS not found in the EF rail; this guard reads its source and the shape changed")
	}
	var ef []string
	for _, q := range regexp.MustCompile(`'([^']+)'`).FindAllStringSubmatch(string(m[1]), -1) {
		ef = append(ef, q[1])
	}
	if len(ef) < 10 {
		t.Fatalf("parsed only %d EF columns (%v); the guard is not reading what it thinks", len(ef), ef)
	}
	if strings.Join(ef, ",") != strings.Join(csvColumns, ",") {
		t.Errorf("CSV column rails disagree.\n  EF: %v\n  Go: %v", ef, csvColumns)
	}
}
