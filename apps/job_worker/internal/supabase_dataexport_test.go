package internal

// HTTP-level coverage for the four `SupabaseClient` methods added in
// the May 2026 backup work: FetchExportRoutes, FetchExportProfile,
// FetchUserSettingsPrefs, DownloadRawTrackBytes. Spins up an
// httptest.Server mimicking the Supabase REST + Storage shape; each
// test asserts the request was shaped correctly (path, query
// params, headers) AND the decoded response matches the wire
// contract. Same pattern as `matcher_osrm_test.go`.

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const testServiceKey = "test-service-role-key"

func newSupabaseTestServer(t *testing.T, handler http.HandlerFunc) *SupabaseClient {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	return NewSupabaseClient(srv.URL, testServiceKey)
}

// ─────────────────── FetchExportRoutes ───────────────────

func TestFetchExportRoutes_HappyPath(t *testing.T) {
	var capturedPath string
	var capturedAuth string
	var capturedApikey string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path + "?" + r.URL.RawQuery
		capturedAuth = r.Header.Get("Authorization")
		capturedApikey = r.Header.Get("apikey")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[
			{"id":"rt-1","name":"Park loop","waypoints":[{"lat":47.37,"lng":8.54},{"lat":47.371,"lng":8.541}],"distance_m":5000,"is_public":true,"tags":["easy"]},
			{"id":"rt-2","name":"Trail run","waypoints":[{"lat":51.5,"lng":-0.1},{"lat":51.6,"lng":-0.2}],"distance_m":10000,"surface":"trail"}
		]`))
	})
	rows, err := client.FetchExportRoutes(context.Background(), "user-A")
	if err != nil {
		t.Fatalf("FetchExportRoutes: %v", err)
	}
	if len(rows) != 2 {
		t.Fatalf("expected 2 routes; got %d", len(rows))
	}
	if rows[0].ID != "rt-1" || rows[0].Name != "Park loop" {
		t.Errorf("row 0=%+v", rows[0])
	}
	if rows[1].Surface == nil || *rows[1].Surface != "trail" {
		t.Errorf("row 1 surface=%v", rows[1].Surface)
	}
	if !strings.Contains(capturedPath, "user_id=eq.user-A") {
		t.Errorf("missing user_id filter: %q", capturedPath)
	}
	if !strings.Contains(capturedPath, "select=") {
		t.Errorf("missing select param: %q", capturedPath)
	}
	if capturedAuth != "Bearer "+testServiceKey {
		t.Errorf("auth header=%q", capturedAuth)
	}
	if capturedApikey != testServiceKey {
		t.Errorf("apikey header=%q", capturedApikey)
	}
}

func TestFetchExportRoutes_EmptyResultReturnsEmptySlice(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[]`))
	})
	rows, err := client.FetchExportRoutes(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if rows == nil {
		t.Errorf("expected non-nil empty slice; got nil")
	}
	if len(rows) != 0 {
		t.Errorf("expected 0 rows; got %d", len(rows))
	}
}

func TestFetchExportRoutes_5xxReturnsHTTPError(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "db down", http.StatusInternalServerError)
	})
	_, err := client.FetchExportRoutes(context.Background(), "user-A")
	if err == nil {
		t.Fatal("expected error on 500")
	}
	httpErr, ok := err.(*HTTPError)
	if !ok {
		t.Fatalf("error is not *HTTPError: %T (%v)", err, err)
	}
	if httpErr.StatusCode != 500 {
		t.Errorf("status=%d", httpErr.StatusCode)
	}
}

func TestFetchExportRoutes_MalformedJSONReturnsError(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{not valid json`))
	})
	_, err := client.FetchExportRoutes(context.Background(), "user-A")
	if err == nil {
		t.Fatal("expected error on malformed JSON")
	}
}

func TestFetchExportRoutes_UrlEncodesUserId(t *testing.T) {
	// A UID with a `+` (legacy non-uuid case) must round-trip through
	// the URL query encoder rather than land as a literal space.
	var capturedRaw string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedRaw = r.URL.RawQuery
		_, _ = w.Write([]byte(`[]`))
	})
	_, err := client.FetchExportRoutes(context.Background(), "user+with+plus")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(capturedRaw, "user%2Bwith%2Bplus") {
		t.Errorf("user_id not URL-encoded: %q", capturedRaw)
	}
}

// ─────────────────── FetchExportProfile ───────────────────

func TestFetchExportProfile_HappyPath(t *testing.T) {
	var capturedPath string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path + "?" + r.URL.RawQuery
		_, _ = w.Write([]byte(`[
			{"id":"user-A","display_name":"Jared","preferred_unit":"km","avatar_url":null}
		]`))
	})
	profile, err := client.FetchExportProfile(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if profile == nil {
		t.Fatal("expected profile, got nil")
	}
	if profile["display_name"] != "Jared" {
		t.Errorf("display_name=%v", profile["display_name"])
	}
	if profile["preferred_unit"] != "km" {
		t.Errorf("preferred_unit=%v", profile["preferred_unit"])
	}
	if !strings.Contains(capturedPath, "id=eq.user-A") {
		t.Errorf("missing id filter: %q", capturedPath)
	}
	if !strings.Contains(capturedPath, "limit=1") {
		t.Errorf("missing limit=1: %q", capturedPath)
	}
}

func TestFetchExportProfile_NotPresentReturnsNilNilError(t *testing.T) {
	// Empty array = new account with no row yet. Must return
	// (nil, nil) so the export builder can include null in the
	// archive without ceremony.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[]`))
	})
	profile, err := client.FetchExportProfile(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if profile != nil {
		t.Errorf("expected nil profile; got %v", profile)
	}
}

func TestFetchExportProfile_ServerManagedFieldsAbsentFromQuery(t *testing.T) {
	// Server-managed billing fields (subscription_tier,
	// subscription_at) are not personal data the subject provided
	// and don't belong in an Art 20 export. The column-level revoke
	// from 20260707_001 reinforces this at the DB layer.
	var capturedRaw string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedRaw = r.URL.RawQuery
		_, _ = w.Write([]byte(`[]`))
	})
	_, _ = client.FetchExportProfile(context.Background(), "user-A")
	forbidden := []string{
		"subscription_tier",
		"subscription_at",
	}
	for _, col := range forbidden {
		if strings.Contains(capturedRaw, col) {
			t.Errorf("profile select must not request %q: %q", col, capturedRaw)
		}
	}
}

func TestFetchExportProfile_IncludesPersonalDataColumns(t *testing.T) {
	// audit/data-export-completeness (May 2026): the original select
	// referenced a non-existent `birth_year` column (typo for
	// `date_of_birth`) and omitted `parkrun_number`. Both are
	// personal data the subject provided and Art 20 requires them.
	// Service-role auth (the worker) bypasses the column-grant
	// lockdown so the request goes through; if the adapter ever
	// switches to JWT-auth those grants would need a corresponding
	// fix at the DB layer.
	var capturedRaw string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedRaw = r.URL.RawQuery
		_, _ = w.Write([]byte(`[]`))
	})
	_, _ = client.FetchExportProfile(context.Background(), "user-A")
	required := []string{
		"date_of_birth",
		"parkrun_number",
		"display_name",
		"hr_zones",
		"gender",
	}
	for _, col := range required {
		if !strings.Contains(capturedRaw, col) {
			t.Errorf("profile select must request %q: %q", col, capturedRaw)
		}
	}
	if strings.Contains(capturedRaw, "birth_year") {
		t.Errorf("profile select must not request birth_year — column does not exist (typo for date_of_birth)")
	}
}

func TestFetchExportProfile_PassesThroughHTTPError(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "rls denied", http.StatusForbidden)
	})
	_, err := client.FetchExportProfile(context.Background(), "user-A")
	if err == nil {
		t.Fatal("expected error on 403")
	}
}

// ─────────────────── FetchUserSettingsPrefs ───────────────────

func TestFetchUserSettingsPrefs_HappyPath(t *testing.T) {
	var capturedPath string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path + "?" + r.URL.RawQuery
		_, _ = w.Write([]byte(`[{"prefs":{"unit":"km","split_audio":true,"hr_zones":[120,140,160,180]}}]`))
	})
	prefs, err := client.FetchUserSettingsPrefs(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if prefs["unit"] != "km" {
		t.Errorf("unit=%v", prefs["unit"])
	}
	if prefs["split_audio"] != true {
		t.Errorf("split_audio=%v", prefs["split_audio"])
	}
	zones, _ := prefs["hr_zones"].([]interface{})
	if len(zones) != 4 {
		t.Errorf("hr_zones=%v", prefs["hr_zones"])
	}
	if !strings.Contains(capturedPath, "user_id=eq.user-A") {
		t.Errorf("missing user_id filter: %q", capturedPath)
	}
}

func TestFetchUserSettingsPrefs_NoRowReturnsEmptyMap(t *testing.T) {
	// New user with no user_settings row yet. The builder must
	// proceed with an empty prefs map rather than null — the
	// restore path tolerates both, but downstream encoders prefer
	// the empty-map shape for JSON consistency.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[]`))
	})
	prefs, err := client.FetchUserSettingsPrefs(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if prefs == nil {
		t.Fatal("prefs must be non-nil empty map; got nil")
	}
	if len(prefs) != 0 {
		t.Errorf("expected empty map; got %d entries", len(prefs))
	}
}

func TestFetchUserSettingsPrefs_NullPrefsColumnReturnsEmptyMap(t *testing.T) {
	// Row exists but prefs is NULL (legacy / wiped). Same
	// degrade-to-empty contract.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[{"prefs":null}]`))
	})
	prefs, err := client.FetchUserSettingsPrefs(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if len(prefs) != 0 {
		t.Errorf("expected empty map for null prefs; got %v", prefs)
	}
}

// ─────────────────── DownloadRawTrackBytes ───────────────────

func TestDownloadRawTrackBytes_ReturnsBytesVerbatim(t *testing.T) {
	// Storage GET serves bytes uninterpreted. The downloader
	// hands them back as-is — the backup builder archives them
	// verbatim, so any decode-on-the-way would corrupt the
	// compressed payload.
	gzippedPayload := []byte{0x1f, 0x8b, 0x08, 0x00, 0xde, 0xad, 0xbe, 0xef}
	var capturedPath string
	var capturedMethod string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path
		capturedMethod = r.Method
		_, _ = w.Write(gzippedPayload)
	})
	bytes, err := client.DownloadRawTrackBytes(context.Background(), "user-A/run-1.json.gz")
	if err != nil {
		t.Fatal(err)
	}
	if string(bytes) != string(gzippedPayload) {
		t.Errorf("bytes round-trip mismatch: got %v, want %v", bytes, gzippedPayload)
	}
	if capturedMethod != "GET" {
		t.Errorf("method=%q, want GET", capturedMethod)
	}
	if capturedPath != "/storage/v1/object/runs/user-A/run-1.json.gz" {
		t.Errorf("path=%q", capturedPath)
	}
}

func TestDownloadRawTrackBytes_404ReturnsHTTPError(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		http.NotFound(w, r)
	})
	_, err := client.DownloadRawTrackBytes(context.Background(), "user-A/missing.json.gz")
	if err == nil {
		t.Fatal("expected error on 404")
	}
	httpErr, ok := err.(*HTTPError)
	if !ok {
		t.Fatalf("error is not *HTTPError: %T", err)
	}
	if httpErr.StatusCode != 404 {
		t.Errorf("status=%d", httpErr.StatusCode)
	}
}

func TestDownloadRawTrackBytes_AuthHeadersPresent(t *testing.T) {
	// Storage GETs from service-role must carry both apikey +
	// Authorization headers. The shared do() helper enforces
	// this; this test pins that the auth path applies to the
	// raw-track download too (it goes through the same do()).
	var auth, apikey string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		apikey = r.Header.Get("apikey")
		_, _ = w.Write([]byte("ok"))
	})
	_, err := client.DownloadRawTrackBytes(context.Background(), "user-A/r.json.gz")
	if err != nil {
		t.Fatal(err)
	}
	if auth != "Bearer "+testServiceKey {
		t.Errorf("Authorization=%q", auth)
	}
	if apikey != testServiceKey {
		t.Errorf("apikey=%q", apikey)
	}
}

func TestDownloadRawTrackBytes_LargeBodyRoundTrips(t *testing.T) {
	// 1 MB payload — sanity check that the io.ReadAll path in
	// do() doesn't truncate or buffer pathologically.
	body := make([]byte, 1024*1024)
	for i := range body {
		body[i] = byte(i % 256)
	}
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/gzip")
		_, _ = w.Write(body)
	})
	got, err := client.DownloadRawTrackBytes(context.Background(), "user-A/r.json.gz")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(body) {
		t.Errorf("length mismatch: got %d, want %d", len(got), len(body))
	}
	if got[0] != body[0] || got[len(got)-1] != body[len(body)-1] {
		t.Errorf("byte mismatch at endpoints")
	}
}

// ─────────────────── adapter via dataexport.Backend round-trip ───────────────────
//
// The main.go dataexportBackend wires SupabaseClient methods into
// the dataexport.Backend interface. We can't import `dataexport`
// here without a cycle, but we can pin that the SupabaseClient
// methods round-trip the JSON shape the adapter then handles —
// the adapter is a pure field-copy.

func TestFetchExportRoutes_OptionalPointerFieldsRoundTrip(t *testing.T) {
	// A row with every optional column set — confirms the pointer
	// fields decode to non-nil, with the right value.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := json.Marshal([]map[string]interface{}{
			{
				"id":          "rt-1",
				"name":        "Full",
				"waypoints":   []map[string]float64{{"lat": 1, "lng": 2}},
				"distance_m":  5000.5,
				"elevation_m": 250.0,
				"surface":     "trail",
				"is_public":   true,
				"slug":        "full-loop",
				"tags":        []string{"easy", "morning"},
				"featured":    false,
				"run_count":   42,
				"is_starred":  true,
				"description": "A grand tour.",
				"club_id":     "club-uuid",
				"created_at":  "2026-01-01T00:00:00Z",
				"updated_at":  "2026-05-11T10:00:00Z",
			},
		})
		_, _ = w.Write(body)
	})
	rows, err := client.FetchExportRoutes(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("expected 1 route; got %d", len(rows))
	}
	r := rows[0]
	cases := []struct {
		name string
		nil  bool
	}{
		{"DistanceM", r.DistanceM == nil},
		{"ElevationM", r.ElevationM == nil},
		{"Surface", r.Surface == nil},
		{"IsPublic", r.IsPublic == nil},
		{"Slug", r.Slug == nil},
		{"Featured", r.Featured == nil},
		{"RunCount", r.RunCount == nil},
		{"IsStarred", r.IsStarred == nil},
		{"Description", r.Description == nil},
		{"ClubID", r.ClubID == nil},
		{"CreatedAt", r.CreatedAt == nil},
		{"UpdatedAt", r.UpdatedAt == nil},
	}
	for _, c := range cases {
		if c.nil {
			t.Errorf("%s was nil; expected non-nil pointer", c.name)
		}
	}
	if len(r.Tags) != 2 || r.Tags[0] != "easy" {
		t.Errorf("Tags=%v", r.Tags)
	}
}

// ─────────────────── context cancellation ───────────────────

func TestFetchExportRoutes_RespectsContextCancellation(t *testing.T) {
	// Slow handler — cancel before it returns. The client must
	// surface the cancellation rather than hang or return a stale
	// response.
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		// Block until the test cancels — the request error path
		// fires when the client disconnects.
		<-r.Context().Done()
	})
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		// Give the client a moment to send the request, then cancel.
		// In practice the cancel fires within microseconds; tests
		// race-friendly because the assertion is "err != nil".
		cancel()
	}()
	_, err := client.FetchExportRoutes(ctx, "user-A")
	if err == nil {
		t.Fatal("expected error on context cancel")
	}
}

// ─────────────────── header verification helper ───────────────────

func TestSupabaseClient_AllNewMethodsCarryAuthHeaders(t *testing.T) {
	// Belt-and-braces: every new method (routes / profile /
	// prefs / raw-track) MUST flow through the shared `do()`
	// helper that injects apikey + Authorization. A future
	// refactor that introduces a bare `http.Client.Do()` call
	// would break service-role auth silently.
	type call struct {
		path   string
		apikey string
		auth   string
	}
	calls := []call{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls = append(calls, call{
			path:   r.URL.Path,
			apikey: r.Header.Get("apikey"),
			auth:   r.Header.Get("Authorization"),
		})
		// Reply with empty JSON arrays / objects so each method
		// completes successfully.
		switch {
		case strings.HasPrefix(r.URL.Path, "/rest/v1/routes"):
			_, _ = w.Write([]byte("[]"))
		case strings.HasPrefix(r.URL.Path, "/rest/v1/user_profiles"):
			_, _ = w.Write([]byte("[]"))
		case strings.HasPrefix(r.URL.Path, "/rest/v1/user_settings"):
			_, _ = w.Write([]byte("[]"))
		case strings.HasPrefix(r.URL.Path, "/storage/v1/object/runs/"):
			_, _ = io.WriteString(w, "track-bytes")
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	c := NewSupabaseClient(srv.URL, testServiceKey)

	_, _ = c.FetchExportRoutes(context.Background(), "user-A")
	_, _ = c.FetchExportProfile(context.Background(), "user-A")
	_, _ = c.FetchUserSettingsPrefs(context.Background(), "user-A")
	_, _ = c.DownloadRawTrackBytes(context.Background(), "user-A/r.json.gz")

	if len(calls) != 4 {
		t.Fatalf("expected 4 HTTP calls; got %d", len(calls))
	}
	for i, c := range calls {
		if c.apikey != testServiceKey {
			t.Errorf("call %d (path=%s): apikey=%q, want %q",
				i, c.path, c.apikey, testServiceKey)
		}
		if c.auth != "Bearer "+testServiceKey {
			t.Errorf("call %d (path=%s): auth=%q, want Bearer prefix",
				i, c.path, c.auth)
		}
	}
}

// ─────────────────── FetchExportPersonalDataTables ───────────────────
//
// audit/data-export-completeness (May 2026) — the audit/self-audit
// pass caught that the run_gear filter used a SQL subselect inside
// PostgREST's `in.()` operator, which PostgREST rejects (it expects
// a literal comma-separated value list, not a SQL fragment). The
// fixed shape is a two-step fetch: gear ids first, then run_gear
// filtered by the literal id list.

func TestFetchExportPersonalDataTables_RunGearUsesTwoStepFetch(t *testing.T) {
	var observed []string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		observed = append(observed, r.URL.Path+"?"+r.URL.RawQuery)
		w.Header().Set("Content-Type", "application/json")
		switch {
		case strings.Contains(r.URL.Path, "/rest/v1/gear"):
			_, _ = w.Write([]byte(`[{"id":"g-1","kind":"shoe"},{"id":"g-2","kind":"bike"}]`))
		case strings.Contains(r.URL.Path, "/rest/v1/run_gear"):
			_, _ = w.Write([]byte(`[{"run_id":"r-1","gear_id":"g-1"}]`))
		default:
			_, _ = w.Write([]byte(`[]`))
		}
	})
	_, err := client.FetchExportPersonalDataTables(context.Background(), "user-A")
	if err != nil {
		t.Fatalf("FetchExportPersonalDataTables: %v", err)
	}

	// Verify the run_gear request used the literal id list, NOT a
	// SQL subselect (the bug audit/self-audit caught).
	var runGearURL string
	for _, p := range observed {
		if strings.Contains(p, "/rest/v1/run_gear") {
			runGearURL = p
			break
		}
	}
	if runGearURL == "" {
		t.Fatalf("expected a request to /rest/v1/run_gear; saw %v", observed)
	}
	// Bug shape: the subselect form contains "select id from gear".
	if strings.Contains(runGearURL, "select id from gear") {
		t.Errorf("run_gear filter must not use a SQL subselect inside in.() "+
			"(PostgREST rejects it). Got: %q", runGearURL)
	}
	// Correct shape: the literal id list contains the gear ids.
	if !strings.Contains(runGearURL, "gear_id=in.(g-1,g-2)") {
		t.Errorf("run_gear filter must be gear_id=in.(<ids>) with literal "+
			"value list. Got: %q", runGearURL)
	}
}

func TestFetchExportPersonalDataTables_RunGearSkippedWhenUserHasNoGear(t *testing.T) {
	var runGearCalled bool
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case strings.Contains(r.URL.Path, "/rest/v1/gear"):
			_, _ = w.Write([]byte(`[]`))
		case strings.Contains(r.URL.Path, "/rest/v1/run_gear"):
			runGearCalled = true
			_, _ = w.Write([]byte(`[]`))
		default:
			_, _ = w.Write([]byte(`[]`))
		}
	})
	out, err := client.FetchExportPersonalDataTables(context.Background(), "user-A")
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if runGearCalled {
		t.Errorf("run_gear must not be queried when the user has no gear")
	}
	if _, present := out["run_gear.json"]; present {
		t.Errorf("run_gear.json must be omitted when there are no gear rows")
	}
}

func TestFetchExportPersonalDataTables_RedactsDeviceTokens(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if strings.Contains(r.URL.Path, "/rest/v1/device_tokens") {
			_, _ = w.Write([]byte(`[{"token":"secret-fcm-token-do-not-leak","platform":"android"}]`))
			return
		}
		_, _ = w.Write([]byte(`[]`))
	})
	out, err := client.FetchExportPersonalDataTables(context.Background(), "user-A")
	if err != nil {
		t.Fatal(err)
	}
	rows, ok := out["device_tokens.json"]
	if !ok || len(rows) != 1 {
		t.Fatalf("device_tokens.json missing or wrong count: %v", out)
	}
	if rows[0]["token"] != "<redacted>" {
		t.Errorf("device_tokens.token must be redacted; got %v", rows[0]["token"])
	}
	if rows[0]["platform"] != "android" {
		t.Errorf("non-secret columns must be preserved; got platform=%v", rows[0]["platform"])
	}
}

func TestFetchExportPersonalDataTables_PerTableErrorIsTolerated(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if strings.Contains(r.URL.Path, "/rest/v1/coach_messages") {
			http.Error(w, "supabase down", http.StatusInternalServerError)
			return
		}
		_, _ = w.Write([]byte(`[{"id":"x"}]`))
	})
	out, err := client.FetchExportPersonalDataTables(context.Background(), "user-A")
	if err != nil {
		t.Errorf("per-table failures must be swallowed; got err=%v", err)
	}
	if _, present := out["coach_messages.json"]; present {
		t.Errorf("failing table must be omitted from the result")
	}
	if _, present := out["notifications.json"]; !present {
		t.Errorf("other tables must still be returned: %v", extraTableKeys(out))
	}
}

func extraTableKeys(m map[string][]map[string]interface{}) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
