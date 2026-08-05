package internal

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// The worker's notification deep links are consumed by three channels (email
// CTA, web push, native push) and land in inboxes and notification trays that
// outlive any deploy — a dead target is unfixable after the fact. Asserting the
// emitted strings, which is all mailer_test.go used to do, is exactly what let
// /events/{id} and /notifications ship: both were pinned, neither was a route.
//
// These guards assert the two properties string equality can't: every kind the
// database can produce is routed explicitly, and every URL pathForKind can emit
// resolves against the real apps/web/src/routes tree.

const (
	webRoutesDir = "../../web/src/routes"
	webTypesFile = "../../web/src/lib/types.ts"
)

// notificationKindsFromWeb parses the NotificationKind union in
// apps/web/src/lib/types.ts — the same source apps/web's
// notification_kind_coverage.test.ts reads, and kept in lockstep with the
// notifications_kind_check CHECK constraint.
func notificationKindsFromWeb(t *testing.T) []string {
	t.Helper()
	src, err := os.ReadFile(webTypesFile)
	if err != nil {
		t.Fatalf("read %s: %v", webTypesFile, err)
	}
	i := strings.Index(string(src), "export type NotificationKind")
	if i < 0 {
		t.Fatalf("NotificationKind union not found in %s", webTypesFile)
	}
	decl := string(src)[i:]
	if end := strings.Index(decl, ";"); end >= 0 {
		decl = decl[:end]
	}
	kinds := []string{}
	for _, m := range regexp.MustCompile(`'([a-z_]+)'`).FindAllStringSubmatch(decl, -1) {
		kinds = append(kinds, m[1])
	}
	if len(kinds) < 14 {
		t.Fatalf("expected the full NotificationKind union, parsed %d: %v", len(kinds), kinds)
	}
	return kinds
}

// webPageRoutes walks the SvelteKit route tree and returns one matcher per page
// route. SvelteKit segment forms in this app: literal, [param] (one segment),
// [[param]] (optional segment), [...rest] (zero or more). There are no route
// groups and no param matchers, so a per-segment regex is a faithful model.
func webPageRoutes(t *testing.T) []*regexp.Regexp {
	t.Helper()
	var routes []*regexp.Regexp
	err := filepath.WalkDir(webRoutesDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || d.Name() != "+page.svelte" {
			return nil
		}
		rel, err := filepath.Rel(webRoutesDir, filepath.Dir(path))
		if err != nil {
			return err
		}
		pattern := "^"
		if rel != "." {
			for _, seg := range strings.Split(rel, string(filepath.Separator)) {
				switch {
				case strings.HasPrefix(seg, "[[") && strings.HasSuffix(seg, "]]"):
					pattern += `(?:/[^/]+)?`
				case strings.HasPrefix(seg, "[...") && strings.HasSuffix(seg, "]"):
					pattern += `(?:/[^/]+)*`
				case strings.HasPrefix(seg, "[") && strings.HasSuffix(seg, "]"):
					pattern += `/[^/]+`
				default:
					pattern += "/" + regexp.QuoteMeta(seg)
				}
			}
		}
		routes = append(routes, regexp.MustCompile(pattern+"/?$"))
		return nil
	})
	if err != nil {
		t.Fatalf("walk %s: %v", webRoutesDir, err)
	}
	if len(routes) < 50 {
		t.Fatalf("expected the full web route tree, found %d page routes", len(routes))
	}
	return routes
}

func resolvesOnWeb(routes []*regexp.Regexp, base, url string) bool {
	path := strings.TrimPrefix(url, base)
	if q := strings.IndexByte(path, '?'); q >= 0 {
		path = path[:q]
	}
	if path == "" {
		path = "/"
	}
	for _, r := range routes {
		if r.MatchString(path) {
			return true
		}
	}
	return false
}

// TestPathForKind_RoutesResolve is the guard that makes a dead deep link fail
// loudly: for every kind the DB can store, in every FK-presence permutation the
// row can arrive in, the emitted URL must match a real page route.
func TestPathForKind_RoutesResolve(t *testing.T) {
	const base = "https://threkir.test"
	routes := webPageRoutes(t)
	id := "9f1c3a52-0000-4000-8000-000000000001"

	// Every shape a row can reach the renderer in: fully populated, and with
	// each optional FK absent so the fallback arms are covered too.
	rows := []struct {
		name string
		row  NotificationRow
	}{
		{"all FKs set", NotificationRow{
			UserID: id, RunID: &id, EventID: &id, ClubID: &id, CommentID: &id,
			PlanID: &id, AchievementID: &id, ChallengeID: &id,
		}},
		{"no FKs", NotificationRow{UserID: id}},
		{"no user_id", NotificationRow{}},
	}

	for _, kind := range append(notificationKindsFromWeb(t), "some_future_kind") {
		for _, r := range rows {
			r.row.Kind = kind
			got := pathForKind(kind, base, r.row)
			if !strings.HasPrefix(got, base) {
				t.Errorf("%s (%s): %q is not under the app origin", kind, r.name, got)
				continue
			}
			if !resolvesOnWeb(routes, base, got) {
				t.Errorf("%s (%s): pathForKind emits %q, which matches no route under %s — "+
					"a link sent to an inbox or notification tray cannot be fixed later, so "+
					"either add the route or point the kind at an existing one",
					kind, r.name, got, webRoutesDir)
			}
		}
	}
}

// TestPathForKind_EveryKindRoutedExplicitly keeps a new kind from inheriting the
// default arm by accident. The default exists for a kind the worker binary
// predates (an older deploy draining a newer queue), not as the resting place
// for kinds we know about — those deserve a considered target.
func TestPathForKind_EveryKindRoutedExplicitly(t *testing.T) {
	src, err := os.ReadFile("mailer.go")
	if err != nil {
		t.Fatalf("read mailer.go: %v", err)
	}
	i := strings.Index(string(src), "func pathForKind(")
	if i < 0 {
		t.Fatal("pathForKind not found in mailer.go")
	}
	body := string(src)[i:]
	if end := strings.Index(body, "\n}\n"); end >= 0 {
		body = body[:end]
	}
	for _, kind := range notificationKindsFromWeb(t) {
		if !strings.Contains(body, `"`+kind+`"`) {
			t.Errorf("pathForKind has no explicit case for %q — it would fall through to the "+
				"inbox fallback instead of a considered deep link", kind)
		}
	}
	if !strings.Contains(body, "default:") {
		t.Error("pathForKind must keep a default arm for a kind newer than this binary")
	}
}
