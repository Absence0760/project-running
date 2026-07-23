package livehub

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// The live-hub authorizer (auth.go) is exhaustively unit-tested against
// STUB fetchers. These tests pin the REAL PostgREST-backed fetchers the
// authorizer trusts in production: a wrong query or a fail-open parse here
// silently defeats the whole gate even with the authorizer logic correct.
// Every fetcher is on a location-privacy / harassment-safety path, so the
// non-2xx and malformed-body cases must fail CLOSED (return an error, which
// the authorizer maps to deny).

// ---------------- SupabaseBlockChecker (harassment safety) ----------------

func TestSupabaseBlockChecker_QueriesBothDirections(t *testing.T) {
	var gotOr string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotOr = r.URL.Query().Get("or")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[]`))
	}))
	defer srv.Close()

	f := &SupabaseBlockChecker{BaseURL: srv.URL, ServiceKey: "k", HTTP: srv.Client()}
	if _, err := f.IsBlockedEitherWay(context.Background(), "viewer", "owner"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// A block is symmetric — a one-directional query would let a blocked
	// viewer keep watching. Both orderings must be in the OR filter.
	if !strings.Contains(gotOr, "and(blocker_id.eq.viewer,blocked_id.eq.owner)") {
		t.Errorf("missing viewer→owner direction in query: %q", gotOr)
	}
	if !strings.Contains(gotOr, "and(blocker_id.eq.owner,blocked_id.eq.viewer)") {
		t.Errorf("missing owner→viewer direction in query: %q", gotOr)
	}
}

func TestSupabaseBlockChecker_RowPresentIsBlocked(t *testing.T) {
	f := blockCheckerServing(t, http.StatusOK, `[{"blocker_id":"owner"}]`)
	blocked, err := f.IsBlockedEitherWay(context.Background(), "viewer", "owner")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !blocked {
		t.Fatal("a matching user_blocks row must report blocked=true")
	}
}

func TestSupabaseBlockChecker_NoRowNotBlocked(t *testing.T) {
	f := blockCheckerServing(t, http.StatusOK, `[]`)
	blocked, err := f.IsBlockedEitherWay(context.Background(), "viewer", "owner")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if blocked {
		t.Fatal("no row must report blocked=false")
	}
}

func TestSupabaseBlockChecker_Non2xxFailsClosed(t *testing.T) {
	f := blockCheckerServing(t, http.StatusInternalServerError, `{"message":"boom"}`)
	if _, err := f.IsBlockedEitherWay(context.Background(), "viewer", "owner"); err == nil {
		t.Fatal("a non-2xx block lookup must fail closed (error), not report not-blocked")
	}
}

func TestSupabaseBlockChecker_MalformedJSONFailsClosed(t *testing.T) {
	f := blockCheckerServing(t, http.StatusOK, `not json`)
	if _, err := f.IsBlockedEitherWay(context.Background(), "viewer", "owner"); err == nil {
		t.Fatal("a malformed block body must fail closed (error)")
	}
}

func blockCheckerServing(t *testing.T, status int, body string) *SupabaseBlockChecker {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	return &SupabaseBlockChecker{BaseURL: srv.URL, ServiceKey: "k", HTTP: srv.Client()}
}

// ---------------- SupabaseRunMetaFetcher (owner + public gate) ----------------

func TestSupabaseRunMetaFetcher_PublicRow(t *testing.T) {
	var gotQuery string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotQuery = r.URL.RawQuery
		_, _ = w.Write([]byte(`[{"user_id":"u-1","is_public":true}]`))
	}))
	defer srv.Close()
	f := &SupabaseRunMetaFetcher{BaseURL: srv.URL, ServiceKey: "k", HTTP: srv.Client()}

	meta, err := f.RunMeta(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if meta == nil || meta.UserID != "u-1" || !meta.IsPublic {
		t.Fatalf("got %+v, want {u-1 true}", meta)
	}
	if !strings.Contains(gotQuery, "id=eq.run-1") {
		t.Errorf("query must filter on the run id: %q", gotQuery)
	}
}

func TestSupabaseRunMetaFetcher_PrivateRowStaysPrivate(t *testing.T) {
	f := runMetaServing(t, http.StatusOK, `[{"user_id":"u-1","is_public":false}]`)
	meta, err := f.RunMeta(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if meta == nil || meta.IsPublic {
		t.Fatalf("private run must report IsPublic=false, got %+v", meta)
	}
}

// A row missing the is_public field must default to PRIVATE (Go bool
// zero-value), never anon-viewable — the fail-safe direction.
func TestSupabaseRunMetaFetcher_MissingIsPublicDefaultsPrivate(t *testing.T) {
	f := runMetaServing(t, http.StatusOK, `[{"user_id":"u-1"}]`)
	meta, err := f.RunMeta(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if meta == nil || meta.IsPublic {
		t.Fatalf("absent is_public must default to private, got %+v", meta)
	}
}

func TestSupabaseRunMetaFetcher_UnknownRunReturnsNil(t *testing.T) {
	f := runMetaServing(t, http.StatusOK, `[]`)
	meta, err := f.RunMeta(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if meta != nil {
		t.Fatalf("unknown run must return (nil, nil), got %+v", meta)
	}
}

func TestSupabaseRunMetaFetcher_Non2xxFailsClosed(t *testing.T) {
	f := runMetaServing(t, http.StatusServiceUnavailable, `{"message":"down"}`)
	if _, err := f.RunMeta(context.Background(), "run-1"); err == nil {
		t.Fatal("a non-2xx run-meta lookup must fail closed (error)")
	}
}

func runMetaServing(t *testing.T, status int, body string) *SupabaseRunMetaFetcher {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	return &SupabaseRunMetaFetcher{BaseURL: srv.URL, ServiceKey: "k", HTTP: srv.Client()}
}

// ---------------- SupabaseZoneFetcher (home-location privacy) ----------------

// zoneServer routes the two PostgREST round-trips: the runs owner lookup and
// the user_settings prefs lookup. Either can be given a status + body.
func zoneServer(t *testing.T, runsStatus int, runsBody string, prefsStatus int, prefsBody string) *SupabaseZoneFetcher {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "user_settings") {
			w.WriteHeader(prefsStatus)
			_, _ = w.Write([]byte(prefsBody))
			return
		}
		w.WriteHeader(runsStatus)
		_, _ = w.Write([]byte(runsBody))
	}))
	t.Cleanup(srv.Close)
	return &SupabaseZoneFetcher{BaseURL: srv.URL, ServiceKey: "k", HTTP: srv.Client()}
}

func TestSupabaseZoneFetcher_ReturnsConfiguredZones(t *testing.T) {
	f := zoneServer(t,
		http.StatusOK, `[{"user_id":"owner-1"}]`,
		http.StatusOK, `[{"prefs":{"privacy_zones":[{"lat":1.5,"lng":2.5,"radius_m":300}]}}]`)
	zones, err := f.Zones(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(zones) != 1 || zones[0].Lat != 1.5 || zones[0].Lng != 2.5 || zones[0].RadiusM != 300 {
		t.Fatalf("got %+v, want one {1.5 2.5 300} zone", zones)
	}
}

func TestSupabaseZoneFetcher_NoPrefsRowMeansNoZones(t *testing.T) {
	f := zoneServer(t, http.StatusOK, `[{"user_id":"owner-1"}]`, http.StatusOK, `[]`)
	zones, err := f.Zones(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if zones != nil {
		t.Fatalf("no settings row means no zones, got %+v", zones)
	}
}

func TestSupabaseZoneFetcher_NullPrefsMeansNoZones(t *testing.T) {
	f := zoneServer(t, http.StatusOK, `[{"user_id":"owner-1"}]`, http.StatusOK, `[{"prefs":null}]`)
	zones, err := f.Zones(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if zones != nil {
		t.Fatalf("null prefs means no zones, got %+v", zones)
	}
}

func TestSupabaseZoneFetcher_MissingPrivacyZonesKeyMeansNoZones(t *testing.T) {
	f := zoneServer(t, http.StatusOK, `[{"user_id":"owner-1"}]`, http.StatusOK, `[{"prefs":{"units":"km"}}]`)
	zones, err := f.Zones(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if zones != nil {
		t.Fatalf("prefs without a privacy_zones key means no zones, got %+v", zones)
	}
}

func TestSupabaseZoneFetcher_UnknownRunMeansNoZones(t *testing.T) {
	// Run owner lookup empty → return (nil, nil) without a second call.
	f := zoneServer(t, http.StatusOK, `[]`, http.StatusInternalServerError, `should-not-be-hit`)
	zones, err := f.Zones(context.Background(), "run-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if zones != nil {
		t.Fatalf("unknown run means no zones, got %+v", zones)
	}
}

func TestSupabaseZoneFetcher_Non2xxOnOwnerFailsClosed(t *testing.T) {
	f := zoneServer(t, http.StatusInternalServerError, `{"message":"boom"}`, http.StatusOK, `[]`)
	if _, err := f.Zones(context.Background(), "run-1"); err == nil {
		t.Fatal("a non-2xx run-owner lookup must fail closed (error)")
	}
}

func TestSupabaseZoneFetcher_MalformedPrivacyZonesFailsClosed(t *testing.T) {
	f := zoneServer(t,
		http.StatusOK, `[{"user_id":"owner-1"}]`,
		http.StatusOK, `[{"prefs":{"privacy_zones":"not-an-array"}}]`)
	if _, err := f.Zones(context.Background(), "run-1"); err == nil {
		t.Fatal("a malformed privacy_zones payload must fail closed (error)")
	}
}
