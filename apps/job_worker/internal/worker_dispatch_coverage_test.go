package internal

// Every job kind the database admits must reach a handler.
//
// `jobs_kind_chk` is the producer side of the queue: a trigger, a cron
// schedule or an RPC can insert exactly the kinds it names, and nothing
// else. `dispatch` is the consumer side. The two are edited in different
// files by different changes, and when they disagree the queue does not
// stop — it degrades quietly in one of two directions:
//
//   - A kind the CHECK admits with no `case`: the worker claims the row,
//     falls into the default branch, and fails it as an unknown kind.
//     The retry budget burns down, the row lands in `failed`, and the
//     user-visible effect is that a thing they asked for (an export, a
//     safety alert, a push) simply never happens. Nothing in the queue
//     distinguishes that from an outage.
//   - A `case` for a kind the CHECK forbids: dead code that reads as a
//     shipped feature. Whatever was supposed to enqueue it cannot.
//
// The forward direction is measured by DRIVING dispatch rather than by
// reading its source, so a `case` that falls through to the wrong
// handler, or a kind routed by something other than the switch, is
// measured as it behaves. The reverse direction has to read the source —
// there is no way to enumerate a switch's labels at run time — and is
// anchored by the forward pass, which fails if the two disagree.

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

var (
	// The LAST `check (kind in (…))` attached to jobs_kind_chk wins: the
	// migrations drop and re-add the constraint whenever a kind is added.
	reJobsKindChk = regexp.MustCompile(`(?is)constraint\s+jobs_kind_chk\s+check\s*\(\s*kind\s+in\s*\(([^)]*)\)`)
	reQuoted      = regexp.MustCompile(`'([a-z_]+)'`)
	reDispatchFn  = regexp.MustCompile(`(?s)func \(w \*Worker\) dispatch\(ctx context\.Context, job \*Job\) error \{(.*?)\n\}`)
	reCaseKind    = regexp.MustCompile(`case "([a-z_]+)":`)
)

// jobKindAllowlist replays the migrations in filename order and returns
// the kinds the final jobs_kind_chk admits.
func jobKindAllowlist(t *testing.T) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(migrationsDir(t), "*.sql"))
	if err != nil {
		t.Fatalf("glob migrations: %v", err)
	}
	sort.Strings(files)

	var kinds []string
	for _, f := range files {
		raw, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("read %s: %v", f, err)
		}
		sql := reLineComment.ReplaceAllString(string(raw), "")
		sql = reDollarBody.ReplaceAllString(sql, "")
		for _, m := range reJobsKindChk.FindAllStringSubmatch(sql, -1) {
			var next []string
			for _, q := range reQuoted.FindAllStringSubmatch(m[1], -1) {
				next = append(next, q[1])
			}
			if len(next) > 0 {
				kinds = next
			}
		}
	}
	if len(kinds) == 0 {
		t.Fatal("parsed no kinds from jobs_kind_chk — the scanner has rotted and this guard " +
			"would pass over an empty set")
	}
	// Sentinels: the oldest kind and the newest. If the replay stops at
	// the first definition it will still hold map_match and miss the rest.
	for _, sentinel := range []string{"map_match", "data_export", "safety_sms"} {
		if !slicesContains(kinds, sentinel) {
			t.Fatalf("the replayed allowlist %v does not hold %q — it is not the final "+
				"constraint", kinds, sentinel)
		}
	}
	sort.Strings(kinds)
	return kinds
}

func slicesContains(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}

// unknownKindErr is what the default branch answers with. Read from the
// branch itself by driving a kind no constraint could ever admit, so the
// assertions below cannot be satisfied by a changed message.
func unknownKindErr(t *testing.T, kind string) string {
	t.Helper()
	return fmt.Sprintf("unknown job kind %q", kind)
}

func TestWorkerDispatch_EveryAdmittedKindReachesAHandler(t *testing.T) {
	kinds := jobKindAllowlist(t)

	// Negative control first: the assertion below is only meaningful if
	// the default branch is reachable and says what we look for. A kind
	// the CHECK could never admit must land there.
	w := newTestWorker(&fakeBackend{}, nil)
	err := w.dispatch(context.Background(), &Job{Kind: "kind_no_migration_admits", Payload: []byte("{}")})
	if err == nil || !strings.Contains(err.Error(), unknownKindErr(t, "kind_no_migration_admits")) {
		t.Fatalf("an unroutable kind did not reach the default branch (got %v) — every "+
			"assertion below would pass vacuously", err)
	}

	var unrouted []string
	for _, kind := range kinds {
		// A payload no handler can parse. Every handler is reached with
		// the same one, so the only thing separating them is the switch:
		// a routed kind fails (or no-ops on an unconfigured sender), an
		// unrouted one names itself in the default branch's message.
		err := w.dispatch(context.Background(), &Job{Kind: kind, Payload: []byte("~")})
		if err != nil && strings.Contains(err.Error(), unknownKindErr(t, kind)) {
			unrouted = append(unrouted, kind)
		}
	}
	if len(unrouted) > 0 {
		t.Errorf("jobs_kind_chk admits these kinds but dispatch routes none of them, so every "+
			"row a producer enqueues is claimed, failed as unknown, retried to exhaustion and "+
			"lost: %v", unrouted)
	}
}

func TestWorkerDispatch_NoCaseExistsForAKindTheDatabaseForbids(t *testing.T) {
	src, err := os.ReadFile("worker.go")
	if err != nil {
		t.Fatalf("read worker.go: %v", err)
	}
	body := reDispatchFn.FindSubmatch(src)
	if body == nil {
		t.Fatal("could not locate dispatch's body in worker.go — the reader has rotted")
	}
	var cases []string
	for _, m := range reCaseKind.FindAllSubmatch(body[1], -1) {
		cases = append(cases, string(m[1]))
	}
	if len(cases) < 10 {
		t.Fatalf("read %d cases out of dispatch (%v), which cannot be right", len(cases), cases)
	}

	allowed := map[string]bool{}
	for _, k := range jobKindAllowlist(t) {
		allowed[k] = true
	}
	var orphaned []string
	for _, c := range cases {
		if !allowed[c] {
			orphaned = append(orphaned, c)
		}
	}
	sort.Strings(orphaned)
	if len(orphaned) > 0 {
		t.Errorf("dispatch routes these kinds but jobs_kind_chk forbids them, so nothing can "+
			"ever enqueue one and the handler is dead code reading as a shipped feature: %v",
			orphaned)
	}

	// Both sides are the same size, so neither test can be satisfied by a
	// subset. Stated separately from the two directional checks because a
	// duplicated `case` would keep both of those green.
	if len(cases) != len(allowed) {
		sort.Strings(cases)
		t.Errorf("dispatch has %d cases (%v) against %d admitted kinds — a duplicate case, "+
			"or a mismatch the directional checks above cannot see", len(cases), cases, len(allowed))
	}
}
