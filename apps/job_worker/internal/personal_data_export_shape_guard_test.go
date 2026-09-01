package internal

// Structural guard for the GDPR Art 20 export spec.
//
// personal_data_export_guard_test.go asks whether every personal-data
// TABLE is in the spec. This asks whether the spec entries it does carry
// can actually run. The two failure modes it closes are both silent, and
// both end with a subject holding an archive that is missing data:
//
//   - **A projection or filter naming a column that is not there.**
//     PostgREST answers 400, and StreamExportPersonalDataTables
//     deliberately TOLERATES a per-table read failure (an outage on one
//     section must not strand the rest of the archive). So a renamed
//     column does not fail the export — it drops that table's rows and
//     records the section short, which nothing but a reader comparing
//     the manifest to their own memory would ever notice.
//
//   - **A dotted filter without the matching `!inner` embed.** Two specs
//     filter on a PARENT table's column (`runs.user_id`,
//     `events.host_user_id`) to reach rows that carry no uid of their
//     own. PostgREST only applies such a filter as a restriction when
//     the embed is an INNER join; a plain embed leaves it a filter on
//     an outer-joined relation, and the read then returns every row in
//     the table with a null embed. On `run_kudos_received` that is every
//     kudos in the database, in one subject's archive.
//
// Both are graded by exportSpecProblems, which is pure over
// (specs, columns) so the guard's own rejection can be pinned against
// deliberately broken specs rather than only asserted about the real
// ones — a check that has never been shown to fail is not evidence.

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

var (
	// A column declaration inside a create-table body: a name followed by
	// a type. Anchored per line, so a table-level `constraint …` or
	// `primary key (…)` clause cannot be read as a column.
	reExportColDecl = regexp.MustCompile(`^"?([a-z_][a-z0-9_]*)"?\s+(uuid|text|citext|integer|int|int4|int8|bigint|smallint|boolean|bool|timestamptz|timestamp|date|numeric|jsonb|json|real|double|bytea|interval|serial|bigserial)\b`)
	reExportAddCol  = regexp.MustCompile(`(?is)alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s+add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?`)
	reExportDropCol = regexp.MustCompile(`(?is)alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s+drop\s+column\s+(?:if\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?`)
	reExportRenCol  = regexp.MustCompile(`(?is)alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s+rename\s+column\s+"?([a-z_][a-z0-9_]*)"?\s+to\s+"?([a-z_][a-z0-9_]*)"?`)
	// An embed in a select clause: `alias:table(…)`, `table!inner(…)` or
	// a bare `table(…)`. Only the leading segment before `(` is read.
	reExportEmbed = regexp.MustCompile(`^(?:([a-z_][a-z0-9_]*):)?([a-z_][a-z0-9_]*)(![a-z]+)?\($`)
)

// migrationTableColumns replays every migration in filename order and
// returns table -> column set. Adds, drops and renames are all applied,
// so a column the schema no longer has reads as absent — the guard is
// only as honest as the replay is.
func migrationTableColumns(t *testing.T) map[string]map[string]bool {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(migrationsDir(t), "*.sql"))
	if err != nil {
		t.Fatalf("glob migrations: %v", err)
	}
	if len(files) == 0 {
		t.Fatalf("no .sql migrations found")
	}
	sort.Strings(files)

	out := map[string]map[string]bool{}
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
			if out[table] == nil {
				out[table] = map[string]bool{}
			}
			for _, line := range strings.Split(balancedParenBody(lower, m[1]-1), "\n") {
				if mm := reExportColDecl.FindStringSubmatch(strings.TrimSpace(line)); mm != nil {
					out[table][mm[1]] = true
				}
			}
		}
		for _, m := range reExportAddCol.FindAllStringSubmatch(lower, -1) {
			if out[m[1]] == nil {
				out[m[1]] = map[string]bool{}
			}
			out[m[1]][m[2]] = true
		}
		for _, m := range reExportRenCol.FindAllStringSubmatch(lower, -1) {
			if cols, ok := out[m[1]]; ok {
				delete(cols, m[2])
				cols[m[3]] = true
			}
		}
		for _, m := range reExportDropCol.FindAllStringSubmatch(lower, -1) {
			if cols, ok := out[m[1]]; ok {
				delete(cols, m[2])
			}
		}
	}
	return out
}

// splitTopLevel cuts a PostgREST select clause on its top-level commas,
// leaving the commas inside an embed's parens alone.
func splitTopLevel(sel string) []string {
	var out []string
	depth, start := 0, 0
	for i, r := range sel {
		switch r {
		case '(':
			depth++
		case ')':
			depth--
		case ',':
			if depth == 0 {
				out = append(out, sel[start:i])
				start = i + 1
			}
		}
	}
	return append(out, sel[start:])
}

// exportSpecProblems grades the spec list against the schema. Returns one
// human-readable line per defect; empty means the spec can run.
func exportSpecProblems(specs []exportTableSpec, cols map[string]map[string]bool) []string {
	var problems []string
	seen := map[string]bool{}
	for _, s := range specs {
		if seen[s.name] {
			problems = append(problems, fmt.Sprintf(
				"%s: two specs claim this archive entry — the second overwrites the first's "+
					"completeness ledger row and the reader sees one table where two shipped", s.name))
		}
		seen[s.name] = true
		if !strings.HasSuffix(s.name, ".json") {
			problems = append(problems, fmt.Sprintf("%s: archive entry name does not end in .json", s.name))
		}
		if cols[s.table] == nil {
			problems = append(problems, fmt.Sprintf(
				"%s: table %q is in no migration — the read 404s and the section ships empty", s.name, s.table))
			continue
		}

		// Which embeds the select declares, and whether each is inner.
		embeds := map[string]bool{}
		for _, field := range splitTopLevel(s.sel) {
			field = strings.TrimSpace(field)
			if field == "" || field == "*" {
				continue
			}
			open := strings.IndexByte(field, '(')
			if open < 0 {
				if !cols[s.table][field] {
					problems = append(problems, fmt.Sprintf(
						"%s: select projects %s.%s, which no migration declares — PostgREST 400s and "+
							"the whole section is recorded short", s.name, s.table, field))
				}
				continue
			}
			m := reExportEmbed.FindStringSubmatch(field[:open+1])
			if m == nil {
				problems = append(problems, fmt.Sprintf("%s: unreadable embed %q", s.name, field))
				continue
			}
			embedded := m[2]
			if cols[embedded] == nil {
				problems = append(problems, fmt.Sprintf(
					"%s: select embeds %q, which is in no migration", s.name, embedded))
				continue
			}
			embeds[embedded] = m[3] == "!inner"
		}

		for _, kv := range strings.Split(s.filter, "&") {
			lhs, _, ok := strings.Cut(kv, "=")
			if !ok || lhs == "" {
				problems = append(problems, fmt.Sprintf("%s: filter fragment %q is not a key=value", s.name, kv))
				continue
			}
			parent, col, dotted := strings.Cut(lhs, ".")
			if !dotted {
				if !cols[s.table][lhs] {
					problems = append(problems, fmt.Sprintf(
						"%s: filter names %s.%s, which no migration declares — the read 400s and the "+
							"subject's rows are recorded short rather than shipped", s.name, s.table, lhs))
				}
				continue
			}
			if cols[parent] == nil {
				problems = append(problems, fmt.Sprintf(
					"%s: filter reaches through %q, which is in no migration", s.name, parent))
				continue
			}
			if !cols[parent][col] {
				problems = append(problems, fmt.Sprintf(
					"%s: filter names %s.%s on the embedded table, which no migration declares", s.name, parent, col))
			}
			inner, embedded := embeds[parent]
			if !embedded {
				problems = append(problems, fmt.Sprintf(
					"%s: filter reaches through %q but the select embeds no such relation — "+
						"PostgREST cannot apply the filter at all", s.name, parent))
			} else if !inner {
				problems = append(problems, fmt.Sprintf(
					"%s: filter reaches through %q on an OUTER embed — the filter does not restrict the "+
						"parent rows, so the read returns every row in %s and the archive carries other "+
						"people's data", s.name, parent, s.table))
			}
		}
	}
	sort.Strings(problems)
	return problems
}

func TestExportSpecShape_TheShippedSpecCanRun(t *testing.T) {
	cols := migrationTableColumns(t)
	// Sentinels: if the replay silently stops finding columns, every
	// existence check below would pass vacuously.
	for table, col := range map[string]string{
		"runs":       "user_id",
		"run_photos": "owner_id",
		"gym_sets":   "exercise_name",
		"events":     "host_user_id",
	} {
		if !cols[table][col] {
			t.Fatalf("the migration replay did not find %s.%s — it cannot be trusted and this "+
				"guard would pass over anything", table, col)
		}
	}
	// A column the schema DROPPED must read as absent, or the replay is
	// additive-only and a projection of a removed column would still pass.
	// `runs.kind` was promoted away by 20261206_001 (F1/D1).
	if cols["runs"]["kind"] {
		t.Fatal("the replay reports runs.kind, which migration 20261206_001 dropped — " +
			"drops are not being applied, so a projection of a removed column would pass")
	}

	if problems := exportSpecProblems(exportPersonalDataSpecs("guard-probe-uid"), cols); len(problems) > 0 {
		t.Errorf("the Art 20 export spec cannot run as written:\n  %s", strings.Join(problems, "\n  "))
	}
}

// The grader has to be able to say no. Each case is one real way the spec
// has been able to break, fed through the same function the shipped specs
// are graded by.
func TestExportSpecShape_TheGraderRejectsEachDefect(t *testing.T) {
	cols := map[string]map[string]bool{
		"kudos": {"id": true, "run_id": true, "user_id": true},
		"runs":  {"id": true, "user_id": true},
	}
	cases := []struct {
		name string
		spec exportTableSpec
		want string
	}{
		{
			name: "a filter column the schema does not have",
			spec: exportTableSpec{name: "kudos.json", table: "kudos", filter: "owner_id=eq.U", sel: "*"},
			want: "filter names kudos.owner_id",
		},
		{
			name: "a projected column the schema does not have",
			spec: exportTableSpec{name: "kudos.json", table: "kudos", filter: "user_id=eq.U", sel: "id,gone_away"},
			want: "select projects kudos.gone_away",
		},
		{
			name: "a table no migration creates",
			spec: exportTableSpec{name: "ghost.json", table: "ghost", filter: "user_id=eq.U", sel: "*"},
			want: `table "ghost" is in no migration`,
		},
		{
			name: "a parent filter with no embed at all",
			spec: exportTableSpec{name: "kudos.json", table: "kudos", filter: "runs.user_id=eq.U", sel: "*"},
			want: "the select embeds no such relation",
		},
		{
			name: "a parent filter over an OUTER embed leaks the whole table",
			spec: exportTableSpec{name: "kudos.json", table: "kudos", filter: "runs.user_id=eq.U", sel: "*,runs(user_id)"},
			want: "on an OUTER embed",
		},
		{
			name: "a parent filter naming a column the parent does not have",
			spec: exportTableSpec{name: "kudos.json", table: "kudos", filter: "runs.owner_id=eq.U", sel: "*,runs!inner(owner_id)"},
			want: "filter names runs.owner_id on the embedded table",
		},
		{
			name: "an embed of a table no migration creates",
			spec: exportTableSpec{name: "kudos.json", table: "kudos", filter: "user_id=eq.U", sel: "*,ghosts:ghost(*)"},
			want: `select embeds "ghost"`,
		},
		{
			name: "an entry name that is not a json file",
			spec: exportTableSpec{name: "kudos", table: "kudos", filter: "user_id=eq.U", sel: "*"},
			want: "does not end in .json",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := exportSpecProblems([]exportTableSpec{tc.spec}, cols)
			if len(got) == 0 {
				t.Fatalf("the grader accepted %+v", tc.spec)
			}
			if !strings.Contains(strings.Join(got, "\n"), tc.want) {
				t.Fatalf("problems %v do not name %q", got, tc.want)
			}
		})
	}

	// A second spec claiming an entry name the first already claimed.
	dup := exportTableSpec{name: "kudos.json", table: "kudos", filter: "user_id=eq.U", sel: "*"}
	if got := exportSpecProblems([]exportTableSpec{dup, dup}, cols); len(got) == 0 ||
		!strings.Contains(strings.Join(got, "\n"), "two specs claim this archive entry") {
		t.Fatalf("a duplicated archive entry name was accepted: %v", got)
	}

	// And the positive control: a well-formed pair, including a parent
	// filter over an inner embed, is accepted.
	ok := []exportTableSpec{
		{name: "kudos.json", table: "kudos", filter: "user_id=eq.U", sel: "*"},
		{name: "kudos_received.json", table: "kudos", filter: "runs.user_id=eq.U", sel: "*,runs!inner(user_id)"},
	}
	if got := exportSpecProblems(ok, cols); len(got) > 0 {
		t.Fatalf("the grader rejected a well-formed spec: %v", got)
	}
}
