package dataexport

import (
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testJWTSecret = "test-jwt-secret"

type fakeBackend struct {
	denied      bool
	retryAfter  int
	rateErr     error
	runs        []ExportRun
	runsErr     error
	trackByPath map[string][]TrackPoint
	uploads     []uploadCall
	uploadErr   error
	signedURL   string
	signURLErr  error
	// Backup-format extras (format=backup only).
	routes        []ExportRoute
	routesErr     error
	profile       map[string]interface{}
	profileErr    error
	prefs         map[string]interface{}
	prefsErr      error
	rawTrackBytes map[string][]byte
	rawTrackErr   map[string]error
	// audit/data-export-completeness extras (format=backup only).
	extraTables    map[string][]map[string]interface{}
	extraTablesErr error
	// run-photos bytes (format=backup only) — keyed by storage_path.
	photoBytes map[string][]byte
	photoErr   map[string]error
}

type uploadCall struct {
	Path        string
	ContentType string
	Size        int
}

func (f *fakeBackend) CheckRateLimitTiered(_ context.Context, _, _ string, _, _, _ int) (bool, int, error) {
	return f.denied, f.retryAfter, f.rateErr
}

func (f *fakeBackend) FetchExportRuns(_ context.Context, _ string, _ int) ([]ExportRun, error) {
	return f.runs, f.runsErr
}

func (f *fakeBackend) DownloadTrackBytes(_ context.Context, path string) ([]TrackPoint, error) {
	return f.trackByPath[path], nil
}

func (f *fakeBackend) UploadExportArtifact(_ context.Context, path, contentType string, body []byte) error {
	if f.uploadErr != nil {
		return f.uploadErr
	}
	f.uploads = append(f.uploads, uploadCall{Path: path, ContentType: contentType, Size: len(body)})
	return nil
}

func (f *fakeBackend) CreateSignedURL(_ context.Context, _ string, _ int) (string, error) {
	if f.signURLErr != nil {
		return "", f.signURLErr
	}
	if f.signedURL == "" {
		return "https://signed.example/runs/exports/abc?token=fake", nil
	}
	return f.signedURL, nil
}

func (f *fakeBackend) FetchExportRoutes(_ context.Context, _ string) ([]ExportRoute, error) {
	return f.routes, f.routesErr
}

func (f *fakeBackend) FetchExportProfile(_ context.Context, _ string) (map[string]interface{}, error) {
	return f.profile, f.profileErr
}

func (f *fakeBackend) FetchUserSettingsPrefs(_ context.Context, _ string) (map[string]interface{}, error) {
	return f.prefs, f.prefsErr
}

func (f *fakeBackend) FetchExportPersonalDataTables(
	_ context.Context, _ string,
) (map[string][]map[string]interface{}, error) {
	return f.extraTables, f.extraTablesErr
}

func (f *fakeBackend) DownloadRawTrackBytes(_ context.Context, path string) ([]byte, error) {
	if f.rawTrackErr != nil {
		if err, ok := f.rawTrackErr[path]; ok {
			return nil, err
		}
	}
	return f.rawTrackBytes[path], nil
}

func (f *fakeBackend) DownloadPhoto(_ context.Context, path string) ([]byte, string, error) {
	if f.photoErr != nil {
		if err, ok := f.photoErr[path]; ok {
			return nil, "", err
		}
	}
	b, ok := f.photoBytes[path]
	if !ok {
		return nil, "", fmt.Errorf("photo not found: %s", path)
	}
	return b, "image/jpeg", nil
}

func signTestToken(t *testing.T, sub string, expDelta int) string {
	t.Helper()
	claims := jwt.MapClaims{"sub": sub}
	if expDelta != 0 {
		claims["exp"] = time.Now().Add(time.Duration(expDelta) * time.Second).Unix()
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	s, err := tok.SignedString([]byte(testJWTSecret))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func newTestServer(t *testing.T, srv *Server) (string, func()) {
	t.Helper()
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	return ts.URL, ts.Close
}

func TestServer_MissingJwtSecretIs503(t *testing.T) {
	srv := &Server{} // no JWTSecret
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Post(base+"/v1/export", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 503 {
		t.Fatalf("status=%d, want 503", resp.StatusCode)
	}
}

func TestServer_MethodNotAllowed(t *testing.T) {
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: &fakeBackend{}}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/export")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 405 {
		t.Fatalf("status=%d, want 405", resp.StatusCode)
	}
}

func TestServer_MissingBearerIs401(t *testing.T) {
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: &fakeBackend{}}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Post(base+"/v1/export", "application/json", strings.NewReader(`{"format":"csv"}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 401 {
		t.Fatalf("status=%d, want 401", resp.StatusCode)
	}
}

func TestServer_BadFormatIs400(t *testing.T) {
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: &fakeBackend{}}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export", strings.NewReader(`{"format":"xml"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status=%d, want 400", resp.StatusCode)
	}
}

func TestServer_RateLimitedReturns429(t *testing.T) {
	be := &fakeBackend{denied: true, retryAfter: 1800}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export", strings.NewReader(`{"format":"csv"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 429 {
		t.Fatalf("status=%d, want 429", resp.StatusCode)
	}
	if resp.Header.Get("Retry-After") != "1800" {
		t.Errorf("Retry-After=%q, want 1800", resp.Header.Get("Retry-After"))
	}
}

func TestServer_RateLimitRpcErrorFailsClosed(t *testing.T) {
	be := &fakeBackend{rateErr: errors.New("db down")}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export", strings.NewReader(`{"format":"csv"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 429 {
		t.Fatalf("status=%d, want 429 (fail-closed)", resp.StatusCode)
	}
}

func TestServer_HappyPathCsvUploadsAndSigns(t *testing.T) {
	be := &fakeBackend{
		runs: []ExportRun{
			{
				ID: "run-1", UserID: "user-A", StartedAt: "2026-05-11T10:00:00Z",
				DurationS: 1500, DistanceM: 5000, Source: "app",
				Metadata:  map[string]interface{}{"activity_type": "run", "title": "Morning"},
				CreatedAt: "2026-05-11T11:00:00Z", UpdatedAt: "2026-05-11T11:00:00Z",
			},
		},
	}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export", strings.NewReader(`{"format":"csv"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status=%d, body=%s", resp.StatusCode, body)
	}
	var got map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got["count"] != float64(1) || got["format"] != "csv" {
		t.Errorf("response=%v", got)
	}
	if !strings.HasPrefix(got["url"].(string), "https://signed.example/") {
		t.Errorf("signed url=%v", got["url"])
	}
	if len(be.uploads) != 1 {
		t.Fatalf("expected 1 upload; got %d", len(be.uploads))
	}
	if be.uploads[0].ContentType != "text/csv" {
		t.Errorf("upload content-type=%q, want text/csv", be.uploads[0].ContentType)
	}
	if !strings.HasPrefix(be.uploads[0].Path, "user-A/exports/") || !strings.HasSuffix(be.uploads[0].Path, ".csv") {
		t.Errorf("upload path=%q", be.uploads[0].Path)
	}
}

func TestServer_HappyPathGpxZipContainsManifestAndPerRunGpx(t *testing.T) {
	trackURL := "user-A/run-1.json.gz"
	be := &fakeBackend{
		runs: []ExportRun{
			{
				ID: "run-1", UserID: "user-A", StartedAt: "2026-05-11T10:00:00Z",
				DurationS: 1500, DistanceM: 5000, Source: "app",
				TrackURL: &trackURL,
				Metadata: map[string]interface{}{"title": "Morning"},
			},
		},
		trackByPath: map[string][]TrackPoint{
			trackURL: {
				{Lat: 51.5, Lng: -0.1},
				{Lat: 51.6, Lng: -0.2},
			},
		},
	}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export", strings.NewReader(`{"format":"gpx"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("status=%d", resp.StatusCode)
	}
	if len(be.uploads) != 1 || be.uploads[0].ContentType != "application/zip" {
		t.Fatalf("upload=%+v", be.uploads)
	}
}

func TestServer_ExpiredTokenIsRejected(t *testing.T) {
	be := &fakeBackend{}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export", strings.NewReader(`{"format":"csv"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", -600))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 401 {
		t.Fatalf("status=%d, want 401", resp.StatusCode)
	}
}

// --- pure helpers --------------------------------------------------------

func TestBuildCSV_ColumnOrderAndDataShape(t *testing.T) {
	runs := []ExportRun{
		{
			ID: "r1", StartedAt: "2026-05-11T10:00:00Z",
			DurationS: 1500, DistanceM: 5000, Source: "app",
			Metadata: map[string]interface{}{
				"activity_type": "run", "title": "Morning", "avg_bpm": 145.0,
			},
			CreatedAt: "2026-05-11T11:00:00Z", UpdatedAt: "2026-05-11T11:00:00Z",
		},
	}
	csv := BuildCSV(runs)
	lines := strings.Split(strings.TrimSpace(csv), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines (header + 1 row); got %d", len(lines))
	}
	if !strings.HasPrefix(lines[0], "id,started_at,distance_m") {
		t.Errorf("header order off: %q", lines[0])
	}
	if !strings.Contains(lines[1], "run") || !strings.Contains(lines[1], "Morning") {
		t.Errorf("row missing metadata fields: %q", lines[1])
	}
	if !strings.Contains(lines[1], "145") {
		t.Errorf("avg_bpm not formatted as integer in row: %q", lines[1])
	}
	// `track_url` is intentionally omitted from the CSV column set
	// (audit/all storage Low). Pin the negative so a refactor that
	// resurrects it can't slip past code review.
	if strings.Contains(lines[0], "track_url") {
		t.Errorf("track_url must not appear in CSV header: %q", lines[0])
	}
}

func TestBuildGpxZip_ManifestAndPerRunFiles(t *testing.T) {
	trackURL := "user-A/r1.json.gz"
	runs := []ExportRun{
		{ID: "r1", UserID: "user-A", StartedAt: "2026-05-11T10:00:00Z", TrackURL: &trackURL},
		{ID: "r2", UserID: "user-A", StartedAt: "2026-05-11T11:00:00Z"}, // no track_url
	}
	fetcher := func(_ context.Context, path string) ([]TrackPoint, error) {
		if path == trackURL {
			return []TrackPoint{{Lat: 51.5, Lng: -0.1}, {Lat: 51.6, Lng: -0.2}}, nil
		}
		return nil, nil
	}
	zipped, err := BuildGpxZip(context.Background(), runs, fetcher)
	if err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(zipped), int64(len(zipped)))
	if err != nil {
		t.Fatal(err)
	}
	names := make([]string, 0, len(zr.File))
	for _, f := range zr.File {
		names = append(names, f.Name)
	}
	wantManifest := false
	wantR1 := false
	for _, n := range names {
		if n == "runs.json" {
			wantManifest = true
		}
		if n == "runs/r1.gpx" {
			wantR1 = true
		}
		if n == "runs/r2.gpx" {
			t.Errorf("r2 had no track_url; per-run gpx should be omitted, got %q", n)
		}
	}
	if !wantManifest {
		t.Errorf("zip missing runs.json manifest; entries=%v", names)
	}
	if !wantR1 {
		t.Errorf("zip missing runs/r1.gpx; entries=%v", names)
	}
}

func TestBuildGpx_MinimalDocumentShape(t *testing.T) {
	run := ExportRun{ID: "r1", UserID: "u1", StartedAt: "2026-05-11T10:00:00Z",
		Metadata: map[string]interface{}{"title": "Morning"}}
	ele := 12.5
	ts := "2026-05-11T10:00:01Z"
	bpm := 145
	track := []TrackPoint{{Lat: 51.5, Lng: -0.1, Ele: &ele, Ts: &ts, Bpm: &bpm}}
	out := BuildGpx(run, track)
	for _, want := range []string{
		`<?xml version="1.0" encoding="UTF-8"?>`,
		`<gpx version="1.1"`,
		`<name>Morning</name>`,
		`<trkpt lat="51.5" lon="-0.1">`,
		`<ele>12.5</ele>`,
		`<time>2026-05-11T10:00:01Z</time>`,
		`<gpxtpx:hr>145</gpxtpx:hr>`,
		`</gpx>`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("GPX missing %q in output:\n%s", want, out)
		}
	}
}

func TestBuildGpx_XmlEscapesTitle(t *testing.T) {
	run := ExportRun{ID: "r1", UserID: "u1", StartedAt: "2026-05-11T10:00:00Z",
		Metadata: map[string]interface{}{"title": "Quirky <run> & stuff"}}
	out := BuildGpx(run, []TrackPoint{{Lat: 51.5, Lng: -0.1}})
	if strings.Contains(out, "<run>") {
		t.Errorf("title should be XML-escaped: %s", out)
	}
	if !strings.Contains(out, "Quirky &lt;run&gt; &amp; stuff") {
		t.Errorf("escaped title not found: %s", out)
	}
}

// ---- format=backup ---------------------------------------------------

func TestServer_RejectsUnknownFormat(t *testing.T) {
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: &fakeBackend{}}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export", strings.NewReader(`{"format":"made-up"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status=%d, want 400", resp.StatusCode)
	}
}

func TestServer_BackupFormatHappyPath(t *testing.T) {
	trackURL := "user-A/run-1.json.gz"
	trueVal := true
	floatVal := 5000.0
	be := &fakeBackend{
		runs: []ExportRun{
			{
				ID: "run-1", UserID: "user-A", StartedAt: "2026-05-11T10:00:00Z",
				DurationS: 1500, DistanceM: 5000, Source: "app",
				TrackURL: &trackURL,
				Metadata: map[string]interface{}{"activity_type": "run", "title": "Morning"},
			},
		},
		routes: []ExportRoute{
			{
				ID:        "rt-1",
				Name:      "Park loop",
				Waypoints: []map[string]interface{}{{"lat": 47.37, "lng": 8.54}, {"lat": 47.371, "lng": 8.541}},
				DistanceM: &floatVal,
				IsPublic:  &trueVal,
				Tags:      []string{"easy", "morning"},
			},
		},
		profile: map[string]interface{}{
			"id":             "user-A",
			"display_name":   "Jared",
			"preferred_unit": "km",
		},
		prefs: map[string]interface{}{
			"unit":        "km",
			"split_audio": true,
		},
		rawTrackBytes: map[string][]byte{
			// Use real gzip bytes so the writer's STORE path
			// passes through actual gzipped content end-to-end.
			trackURL: gzipString(t, `[{"lat":51.5,"lng":-0.1},{"lat":51.6,"lng":-0.2}]`),
		},
	}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export", strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status=%d, body=%s", resp.StatusCode, body)
	}
	var got map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got["format"] != "backup" {
		t.Errorf("format=%v, want backup", got["format"])
	}
	if got["count"] != float64(1) {
		t.Errorf("count=%v, want 1", got["count"])
	}
	if len(be.uploads) != 1 {
		t.Fatalf("expected 1 upload; got %d", len(be.uploads))
	}
	up := be.uploads[0]
	if up.ContentType != "application/zip" {
		t.Errorf("content-type=%q", up.ContentType)
	}
	if !strings.HasPrefix(up.Path, "user-A/exports/") || !strings.HasSuffix(up.Path, ".zip") {
		t.Errorf("path=%q", up.Path)
	}
}

func TestBuildBackupZip_ProducesValidArchive(t *testing.T) {
	trackURL := "uid/run-1.json.gz"
	rawTrack := gzipString(t, `[{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]`)
	runs := []ExportRun{{
		ID: "run-1", UserID: "uid", StartedAt: "2026-05-11T10:00:00Z",
		DurationS: 1500, DistanceM: 5000, Source: "app", TrackURL: &trackURL,
		Metadata: map[string]interface{}{"activity_type": "run"},
	}}
	floatVal := 5000.0
	routes := []ExportRoute{{
		ID: "rt-1", Name: "Park loop",
		Waypoints: []map[string]interface{}{{"lat": 47.37, "lng": 8.54}, {"lat": 47.371, "lng": 8.541}},
		DistanceM: &floatVal,
	}}
	profile := map[string]interface{}{"id": "uid-original", "display_name": "Tester"}
	prefs := map[string]interface{}{"unit": "km"}

	fetcher := func(_ context.Context, path string) ([]byte, error) {
		if path == trackURL {
			return rawTrack, nil
		}
		return nil, nil
	}

	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runs, Routes: routes, Profile: profile, SettingsPrefs: prefs,
		UserID: "uid", ExportedFrom: "test",
	}, fetcher, nil)
	if err != nil {
		t.Fatal(err)
	}

	// Parse the produced ZIP and verify each expected entry.
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("zip parse failed: %v", err)
	}
	files := map[string][]byte{}
	for _, f := range zr.File {
		rc, err := f.Open()
		if err != nil {
			t.Fatalf("open %s: %v", f.Name, err)
		}
		buf, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			t.Fatalf("read %s: %v", f.Name, err)
		}
		files[f.Name] = buf
	}

	// Manifest shape.
	var manifest map[string]any
	if err := json.Unmarshal(files["manifest.json"], &manifest); err != nil {
		t.Fatalf("manifest parse: %v", err)
	}
	if manifest["format"] != BackupFormatName {
		t.Errorf("format=%v, want %s", manifest["format"], BackupFormatName)
	}
	if manifest["version"] != float64(BackupFormatVersion) {
		t.Errorf("version=%v", manifest["version"])
	}
	if manifest["exported_by_user_id"] != "uid" {
		t.Errorf("user_id=%v", manifest["exported_by_user_id"])
	}
	counts := manifest["counts"].(map[string]any)
	if counts["runs"] != float64(1) || counts["routes"] != float64(1) || counts["tracks"] != float64(1) {
		t.Errorf("counts=%v", counts)
	}

	// runs.json — one row with the expected id, user_id stripped.
	var runsOut []map[string]any
	if err := json.Unmarshal(files["runs.json"], &runsOut); err != nil {
		t.Fatalf("runs.json parse: %v", err)
	}
	if len(runsOut) != 1 || runsOut[0]["id"] != "run-1" {
		t.Errorf("runs out=%v", runsOut)
	}

	// routes.json — one row with the name + waypoints.
	var routesOut []map[string]any
	if err := json.Unmarshal(files["routes.json"], &routesOut); err != nil {
		t.Fatalf("routes.json parse: %v", err)
	}
	if len(routesOut) != 1 || routesOut[0]["name"] != "Park loop" {
		t.Errorf("routes out=%v", routesOut)
	}

	// profile.json — id field stripped, display_name preserved.
	var profileOut map[string]any
	if err := json.Unmarshal(files["profile.json"], &profileOut); err != nil {
		t.Fatalf("profile.json parse: %v", err)
	}
	p := profileOut["profile"].(map[string]any)
	if _, hasID := p["id"]; hasID {
		t.Errorf("profile.id should be stripped: %v", p)
	}
	if p["display_name"] != "Tester" {
		t.Errorf("display_name lost: %v", p)
	}
	if profileOut["settings_prefs"].(map[string]any)["unit"] != "km" {
		t.Errorf("prefs lost: %v", profileOut["settings_prefs"])
	}

	// Track entry — raw gzipped bytes round-trip byte-for-byte.
	track := files["tracks/run-1.json.gz"]
	if !bytes.Equal(track, rawTrack) {
		t.Errorf("track bytes not preserved verbatim (got %d bytes, want %d)", len(track), len(rawTrack))
	}
}

func TestBuildBackupZip_PartialTrackFailureDoesNotSinkArchive(t *testing.T) {
	good := "uid/run-good.json.gz"
	bad := "uid/run-bad.json.gz"
	rawTrack := gzipString(t, `[{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]`)
	runs := []ExportRun{
		{ID: "run-good", UserID: "uid", StartedAt: "2026-05-11T10:00:00Z", DurationS: 1500, DistanceM: 5000, Source: "app", TrackURL: &good},
		{ID: "run-bad", UserID: "uid", StartedAt: "2026-05-11T11:00:00Z", DurationS: 1500, DistanceM: 5000, Source: "app", TrackURL: &bad},
	}
	fetcher := func(_ context.Context, path string) ([]byte, error) {
		if path == good {
			return rawTrack, nil
		}
		return nil, errors.New("synthetic download failure")
	}

	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runs, UserID: "uid", ExportedFrom: "test",
	}, fetcher, nil)
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	names := map[string]bool{}
	for _, f := range zr.File {
		names[f.Name] = true
	}
	if !names["tracks/run-good.json.gz"] {
		t.Errorf("good track missing")
	}
	if names["tracks/run-bad.json.gz"] {
		t.Errorf("bad track should be absent")
	}
	// Manifest counts must reflect only what made it in.
	var manifest map[string]any
	for _, f := range zr.File {
		if f.Name == "manifest.json" {
			rc, _ := f.Open()
			b, _ := io.ReadAll(rc)
			rc.Close()
			_ = json.Unmarshal(b, &manifest)
		}
	}
	counts := manifest["counts"].(map[string]any)
	if counts["runs"] != float64(2) || counts["tracks"] != float64(1) {
		t.Errorf("counts=%v (want 2 runs, 1 track)", counts)
	}
}

func TestBuildBackupZip_ArchivesHrSidecar(t *testing.T) {
	// Indoor/treadmill run: no track, an HR sidecar at the canonical path.
	// The backup must carry hr/{id}.hr.json.gz so restore can re-home it
	// (decisions §116).
	hrURL := "uid/run-hr.hr.json.gz"
	rawHr := gzipString(t, `[{"bpm":140},{"bpm":150}]`)
	runs := []ExportRun{{
		ID: "run-hr", UserID: "uid", StartedAt: "2026-05-11T10:00:00Z",
		DurationS: 1800, DistanceM: 5000, Source: "app", HrSeriesURL: &hrURL,
		Metadata: map[string]interface{}{"activity_type": "run", "indoor": true},
	}}
	fetcher := func(_ context.Context, path string) ([]byte, error) {
		if path == hrURL {
			return rawHr, nil
		}
		return nil, nil
	}

	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runs, UserID: "uid", ExportedFrom: "test",
	}, fetcher, nil)
	if err != nil {
		t.Fatal(err)
	}

	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("zip parse failed: %v", err)
	}
	files := map[string][]byte{}
	for _, f := range zr.File {
		rc, _ := f.Open()
		buf, _ := io.ReadAll(rc)
		rc.Close()
		files[f.Name] = buf
	}

	if _, ok := files["hr/run-hr.hr.json.gz"]; !ok {
		t.Fatalf("expected hr/run-hr.hr.json.gz in archive, got %v", keysOf(files))
	}
	// Bytes archived verbatim — gunzip back to the same samples.
	gr, err := gzip.NewReader(bytes.NewReader(files["hr/run-hr.hr.json.gz"]))
	if err != nil {
		t.Fatalf("hr gunzip: %v", err)
	}
	hrJSON, _ := io.ReadAll(gr)
	if string(hrJSON) != `[{"bpm":140},{"bpm":150}]` {
		t.Errorf("hr sidecar bytes=%s", hrJSON)
	}

	var manifest map[string]any
	if err := json.Unmarshal(files["manifest.json"], &manifest); err != nil {
		t.Fatalf("manifest parse: %v", err)
	}
	counts := manifest["counts"].(map[string]any)
	if counts["hr_series"] != float64(1) {
		t.Errorf("counts[hr_series]=%v, want 1", counts["hr_series"])
	}

	// runs.json carries the hr_series_url field for completeness.
	var runsOut []map[string]any
	if err := json.Unmarshal(files["runs.json"], &runsOut); err != nil {
		t.Fatalf("runs.json parse: %v", err)
	}
	if len(runsOut) != 1 || runsOut[0]["hr_series_url"] != hrURL {
		t.Errorf("runs.json hr_series_url=%v, want %s", runsOut[0]["hr_series_url"], hrURL)
	}
}

func TestBuildBackupZip_BundlesRunPhotoBytes(t *testing.T) {
	// audit-findings 2026-05-30 High: the Art 20 export must carry the
	// photo bytes, not just `run_photos.json` metadata. The rows come in
	// via ExtraTables; each storage_path's bytes land under `photos/`.
	good := "uid/photo-good.jpg"
	bad := "uid/photo-bad.jpg"
	imgBytes := []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10} // JPEG magic-ish
	extras := map[string][]map[string]interface{}{
		"run_photos.json": {
			{"id": "photo-good", "storage_path": good, "caption": "hi"},
			{"id": "photo-bad", "storage_path": bad},
			{"id": "photo-none"},                                        // no storage_path → skipped silently
			{"id": "photo-evil", "storage_path": "../../../etc/passwd"}, // traversal → skipped before fetch
			{"id": "photo-abs", "storage_path": "/etc/passwd"},          // absolute → skipped before fetch
		},
	}
	photoFetcher := func(_ context.Context, p string) ([]byte, string, error) {
		// A malformed/traversal path must be rejected BEFORE it reaches
		// the service-role downloader — the fetcher fails the test if
		// asked to download one.
		if p != path.Clean(p) || strings.HasPrefix(p, "/") || strings.Contains(p, "..") {
			t.Errorf("photoFetcher must not be called with a non-canonical path: %q", p)
		}
		if p == good {
			return imgBytes, "image/jpeg", nil
		}
		return nil, "", errors.New("synthetic photo download failure")
	}

	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test", ExtraTables: extras,
	}, func(_ context.Context, _ string) ([]byte, error) { return nil, nil }, photoFetcher)
	if err != nil {
		t.Fatal(err)
	}

	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	entries := map[string][]byte{}
	var manifest map[string]any
	for _, f := range zr.File {
		rc, _ := f.Open()
		b, _ := io.ReadAll(rc)
		rc.Close()
		entries[f.Name] = b
		if f.Name == "manifest.json" {
			_ = json.Unmarshal(b, &manifest)
		}
	}
	// The good photo's bytes are archived verbatim under its basename.
	got, ok := entries["photos/photo-good.jpg"]
	if !ok {
		t.Fatalf("photos/photo-good.jpg missing; entries=%v", keysOf(entries))
	}
	if !bytes.Equal(got, imgBytes) {
		t.Errorf("photo bytes mismatch: got %v want %v", got, imgBytes)
	}
	// The failed download is omitted, not fatal.
	if _, ok := entries["photos/photo-bad.jpg"]; ok {
		t.Errorf("failed photo should be absent")
	}
	// Metadata row still ships regardless of byte-download outcome.
	if _, ok := entries["run_photos.json"]; !ok {
		t.Errorf("run_photos.json metadata should still ship")
	}
	counts := manifest["counts"].(map[string]any)
	if counts["photos"] != float64(1) {
		t.Errorf("counts[photos]=%v (want 1)", counts["photos"])
	}
}

func keysOf(m map[string][]byte) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

func TestBuildBackupZip_TrackUrlShapeMismatchSkipsTrack(t *testing.T) {
	// Path-shape assertion: a malformed track_url (legacy / corrupt
	// row) must not feed an unconstrained string into the
	// service-role downloader.
	bogus := "../../../etc/passwd"
	runs := []ExportRun{
		{ID: "run-1", UserID: "uid", StartedAt: "2026-05-11T10:00:00Z", DurationS: 1500, DistanceM: 5000, Source: "app", TrackURL: &bogus},
	}
	called := 0
	fetcher := func(_ context.Context, _ string) ([]byte, error) {
		called++
		return nil, errors.New("must not be called")
	}
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runs, UserID: "uid", ExportedFrom: "test",
	}, fetcher, nil)
	if err != nil {
		t.Fatal(err)
	}
	if called != 0 {
		t.Errorf("malformed track_url should skip the fetcher (called %d times)", called)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	for _, f := range zr.File {
		if strings.HasPrefix(f.Name, "tracks/") {
			t.Errorf("no tracks/ entry should land for a malformed track_url; got %s", f.Name)
		}
	}
}

func TestBuildBackupZip_EmptyInputProducesValidManifestOnlyArchive(t *testing.T) {
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test",
	}, func(_ context.Context, _ string) ([]byte, error) {
		return nil, errors.New("must not be called")
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if len(zr.File) < 4 {
		t.Fatalf("expected at least manifest + runs + routes + profile entries; got %d", len(zr.File))
	}
}

func TestBuildBackupZip_NilProfileSerialisesAsNull(t *testing.T) {
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test", Profile: nil,
	}, func(_ context.Context, _ string) ([]byte, error) { return nil, nil }, nil)
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	for _, f := range zr.File {
		if f.Name == "profile.json" {
			rc, _ := f.Open()
			b, _ := io.ReadAll(rc)
			rc.Close()
			var pp map[string]any
			_ = json.Unmarshal(b, &pp)
			if pp["profile"] != nil {
				t.Errorf("profile should be null, got %v", pp["profile"])
			}
			if _, ok := pp["settings_prefs"]; !ok {
				t.Errorf("settings_prefs key must be present (even when empty)")
			}
			return
		}
	}
	t.Fatal("profile.json not found in archive")
}

// ---- format=backup edge cases ----------------------------------------

func TestServer_BackupFormatMissingBearerIs401(t *testing.T) {
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: &fakeBackend{}}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 401 {
		t.Fatalf("status=%d, want 401", resp.StatusCode)
	}
}

func TestServer_BackupFormatExpiredTokenIs401(t *testing.T) {
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: &fakeBackend{}}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	// expDelta = -60 means the token expired 60 seconds ago.
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", -60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 401 {
		t.Fatalf("status=%d, want 401", resp.StatusCode)
	}
}

func TestServer_BackupFormatRateLimitedReturns429(t *testing.T) {
	be := &fakeBackend{denied: true, retryAfter: 1800}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 429 {
		t.Fatalf("status=%d, want 429", resp.StatusCode)
	}
	if resp.Header.Get("Retry-After") != "1800" {
		t.Errorf("Retry-After=%q, want 1800", resp.Header.Get("Retry-After"))
	}
}

func TestServer_BackupFormatRateLimitRpcErrorFailsClosed(t *testing.T) {
	be := &fakeBackend{rateErr: errors.New("db down")}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 429 {
		t.Fatalf("status=%d, want 429 (fail-closed)", resp.StatusCode)
	}
}

func TestServer_BackupFormatRoutesFetchErrorReturns500(t *testing.T) {
	be := &fakeBackend{
		runs:      []ExportRun{},
		routesErr: errors.New("routes table on fire"),
	}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 500 {
		t.Fatalf("status=%d, want 500", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	if !strings.Contains(string(body), "routes_fetch_failed") {
		t.Errorf("error body=%s", body)
	}
}

func TestServer_BackupFormatProfileFetchErrorDegradesGracefully(t *testing.T) {
	// A profile fetch failure must NOT sink the whole backup —
	// runs + routes still get archived, profile.profile is null.
	be := &fakeBackend{
		runs:       []ExportRun{},
		routes:     []ExportRoute{},
		profileErr: errors.New("rpc unavailable"),
		prefs:      map[string]interface{}{"unit": "km"},
	}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status=%d, body=%s", resp.StatusCode, body)
	}
	if len(be.uploads) != 1 {
		t.Fatalf("expected 1 upload; got %d", len(be.uploads))
	}
}

func TestServer_BackupFormatPrefsFetchErrorDegradesGracefully(t *testing.T) {
	be := &fakeBackend{
		runs:     []ExportRun{},
		routes:   []ExportRoute{},
		profile:  map[string]interface{}{"display_name": "Test"},
		prefsErr: errors.New("user_settings unavailable"),
	}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status=%d, body=%s", resp.StatusCode, body)
	}
}

func TestServer_BackupFormatRunsFetchErrorReturns500(t *testing.T) {
	be := &fakeBackend{runsErr: errors.New("runs table down")}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 500 {
		t.Fatalf("status=%d, want 500", resp.StatusCode)
	}
}

func TestBuildBackupZip_PathTraversalAttemptIsBlocked(t *testing.T) {
	// Variations that the path-shape assertion must reject. Each
	// of these would feed an unconstrained string into the
	// service-role Storage downloader if the guard regressed.
	traversalAttempts := []string{
		"../../../etc/passwd",
		"/etc/passwd",
		"other-user/run-1.json.gz",      // wrong owner prefix
		"uid/../other-user/r-1.json.gz", // dot-dot mid-string
		"uid/run-1.json",                // wrong suffix
		"uid//run-1.json.gz",            // double slash
		"uid/r-1.json.gz/extra",         // suffix-after-suffix
	}
	for _, attempt := range traversalAttempts {
		t.Run(attempt, func(t *testing.T) {
			tu := attempt
			runs := []ExportRun{{
				ID: "r-1", UserID: "uid", StartedAt: "2026-05-11T10:00:00Z",
				DurationS: 1500, DistanceM: 5000, Source: "app", TrackURL: &tu,
			}}
			called := 0
			fetcher := func(_ context.Context, _ string) ([]byte, error) {
				called++
				return []byte("payload"), nil
			}
			body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
				Runs: runs, UserID: "uid", ExportedFrom: "test",
			}, fetcher, nil)
			if err != nil {
				t.Fatal(err)
			}
			if called != 0 {
				t.Errorf("fetcher called %d times for malformed track_url %q; want 0",
					called, attempt)
			}
			zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
			for _, f := range zr.File {
				if strings.HasPrefix(f.Name, "tracks/") {
					t.Errorf("track entry should not land for %q; got %s", attempt, f.Name)
				}
			}
		})
	}
}

func TestBuildBackupZip_ManyRoutesAndTracksScale(t *testing.T) {
	// Smoke check that a "realistic" sized backup builds and
	// produces a valid archive — 100 runs + 50 routes + 100
	// track files. Catches O(n²) regressions in the writer's
	// hot loop.
	const numRuns = 100
	const numRoutes = 50
	runs := make([]ExportRun, numRuns)
	rawBytes := make(map[string][]byte, numRuns)
	for i := 0; i < numRuns; i++ {
		id := fmt.Sprintf("run-%03d", i)
		path := fmt.Sprintf("uid/%s.json.gz", id)
		runs[i] = ExportRun{
			ID: id, UserID: "uid", StartedAt: "2026-05-11T10:00:00Z",
			DurationS: 1500, DistanceM: 5000, Source: "app",
			TrackURL: &path,
		}
		rawBytes[path] = gzipString(t, fmt.Sprintf(`[{"lat":1.0,"lng":2.0,"i":%d}]`, i))
	}
	routes := make([]ExportRoute, numRoutes)
	for i := 0; i < numRoutes; i++ {
		routes[i] = ExportRoute{
			ID:        fmt.Sprintf("rt-%03d", i),
			Name:      fmt.Sprintf("Route %d", i),
			Waypoints: []map[string]interface{}{{"lat": 0.0, "lng": 0.0}, {"lat": 1.0, "lng": 1.0}},
		}
	}
	fetcher := func(_ context.Context, path string) ([]byte, error) {
		return rawBytes[path], nil
	}
	start := time.Now()
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runs, Routes: routes, UserID: "uid", ExportedFrom: "test",
	}, fetcher, nil)
	elapsed := time.Since(start)
	if err != nil {
		t.Fatal(err)
	}
	if elapsed > 5*time.Second {
		t.Errorf("100-run / 50-route backup took %v (regression?)", elapsed)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	trackCount, hasRuns, hasRoutes, hasManifest := 0, false, false, false
	for _, f := range zr.File {
		switch {
		case f.Name == "runs.json":
			hasRuns = true
		case f.Name == "routes.json":
			hasRoutes = true
		case f.Name == "manifest.json":
			hasManifest = true
		case strings.HasPrefix(f.Name, "tracks/"):
			trackCount++
		}
	}
	if !hasRuns || !hasRoutes || !hasManifest {
		t.Errorf("missing metadata: runs=%v routes=%v manifest=%v",
			hasRuns, hasRoutes, hasManifest)
	}
	if trackCount != numRuns {
		t.Errorf("track count=%d, want %d", trackCount, numRuns)
	}
}

func TestBuildBackupZip_RouteWithNilPointerFieldsRoundTrips(t *testing.T) {
	// A route row with all the optional pointer fields nil must
	// still serialise cleanly — the writer's "only include if
	// non-nil" branch covers each.
	routes := []ExportRoute{{
		ID:        "rt-1",
		Name:      "Minimal route",
		Waypoints: []map[string]interface{}{{"lat": 0.0, "lng": 0.0}, {"lat": 1.0, "lng": 1.0}},
		// Every other field nil.
	}}
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		Routes: routes, UserID: "uid", ExportedFrom: "test",
	}, func(_ context.Context, _ string) ([]byte, error) { return nil, nil }, nil)
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	for _, f := range zr.File {
		if f.Name == "routes.json" {
			rc, _ := f.Open()
			raw, _ := io.ReadAll(rc)
			rc.Close()
			var parsed []map[string]any
			if err := json.Unmarshal(raw, &parsed); err != nil {
				t.Fatalf("routes.json parse: %v", err)
			}
			if len(parsed) != 1 {
				t.Fatalf("expected 1 route; got %d", len(parsed))
			}
			row := parsed[0]
			if row["name"] != "Minimal route" {
				t.Errorf("name=%v", row["name"])
			}
			// Optional fields must be absent from the output (the
			// writer's "if non-nil" branches).
			for _, optKey := range []string{"distance_m", "elevation_m", "surface", "tags",
				"featured", "run_count", "is_starred", "description", "club_id"} {
				if _, ok := row[optKey]; ok {
					t.Errorf("optional field %q should be absent on a minimal route; got %v",
						optKey, row[optKey])
				}
			}
			return
		}
	}
	t.Fatal("routes.json not found")
}

func TestBuildBackupZip_StripsUserIdFromRuns(t *testing.T) {
	// runs.json must not carry user_id (re-homeability invariant —
	// restore stamps the new owner's uid on every row).
	runs := []ExportRun{
		{ID: "run-1", UserID: "old-uid", StartedAt: "2026-05-11T10:00:00Z",
			DurationS: 1500, DistanceM: 5000, Source: "app"},
	}
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runs, UserID: "new-uid", ExportedFrom: "test",
	}, func(_ context.Context, _ string) ([]byte, error) { return nil, nil }, nil)
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	for _, f := range zr.File {
		if f.Name == "runs.json" {
			rc, _ := f.Open()
			raw, _ := io.ReadAll(rc)
			rc.Close()
			var parsed []map[string]any
			_ = json.Unmarshal(raw, &parsed)
			if _, hasUID := parsed[0]["user_id"]; hasUID {
				t.Errorf("runs.json must not carry user_id; got %v", parsed[0])
			}
			return
		}
	}
	t.Fatal("runs.json not found")
}

func TestBuildBackupZip_ManifestExportedFromIsPreserved(t *testing.T) {
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "go-service-test",
	}, func(_ context.Context, _ string) ([]byte, error) { return nil, nil }, nil)
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	for _, f := range zr.File {
		if f.Name == "manifest.json" {
			rc, _ := f.Open()
			raw, _ := io.ReadAll(rc)
			rc.Close()
			var manifest map[string]any
			_ = json.Unmarshal(raw, &manifest)
			if manifest["exported_from"] != "go-service-test" {
				t.Errorf("exported_from=%v", manifest["exported_from"])
			}
			return
		}
	}
	t.Fatal("manifest.json not found")
}

// gzipString returns a gzipped representation of s, useful for the
// backup-format tests that feed raw track bytes through the writer.
func gzipString(t *testing.T, s string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write([]byte(s)); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestDecodeTrackBytes_GzippedJSON(t *testing.T) {
	original := []TrackPoint{{Lat: 51.5, Lng: -0.1}}
	plain, _ := json.Marshal(original)
	// Plain (non-gzipped) blob → decoder treats it as raw JSON.
	out, err := DecodeTrackBytes(plain)
	if err != nil || len(out) != 1 || out[0].Lat != 51.5 {
		t.Fatalf("plain decode failed: out=%+v err=%v", out, err)
	}
	// Gzipped blob → decoder detects the magic bytes + unzips.
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	_, _ = zw.Write(plain)
	_ = zw.Close()
	out2, err := DecodeTrackBytes(buf.Bytes())
	if err != nil || len(out2) != 1 || out2[0].Lat != 51.5 {
		t.Fatalf("gzipped decode failed: out=%+v err=%v", out2, err)
	}
}

// audit/data-export-completeness (May 2026) — the backup format now
// also carries every personal-data table the subject has an Art 20
// right to receive. The backend bundles them into ExtraTables; the
// builder writes each non-empty entry verbatim and adds a manifest
// count keyed by the table name.

func TestBuildBackupZip_ExtraTablesAppearAsZipEntries(t *testing.T) {
	extras := map[string][]map[string]interface{}{
		"coach_messages.json": {
			{"id": "m1", "body": "hello", "role": "user"},
			{"id": "m2", "body": "hi back", "role": "assistant"},
		},
		"notifications.json": {
			{"id": "n1", "kind": "kudos", "read_at": nil},
		},
		"integrations.json": {
			{"id": "i1", "provider": "strava", "scope": "activity:read_all"},
		},
		"empty_table.json": {}, // empty -> should be omitted
	}
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: nil, Routes: nil, UserID: "uid", ExportedFrom: "test",
		ExtraTables: extras,
	}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("zip parse: %v", err)
	}
	names := map[string]bool{}
	files := map[string][]byte{}
	for _, f := range zr.File {
		names[f.Name] = true
		rc, _ := f.Open()
		b, _ := io.ReadAll(rc)
		rc.Close()
		files[f.Name] = b
	}
	for _, want := range []string{"coach_messages.json", "notifications.json", "integrations.json"} {
		if !names[want] {
			t.Errorf("expected zip entry %q in backup; got %v", want, names)
		}
	}
	if names["empty_table.json"] {
		t.Errorf("empty extra table must be omitted from the zip")
	}

	// Manifest counts include the new keys (under the bare table name).
	var manifest map[string]any
	if err := json.Unmarshal(files["manifest.json"], &manifest); err != nil {
		t.Fatal(err)
	}
	counts := manifest["counts"].(map[string]any)
	for k, want := range map[string]float64{
		"coach_messages": 2,
		"notifications":  1,
		"integrations":   1,
	} {
		got, ok := counts[k]
		if !ok {
			t.Errorf("manifest.counts missing %q", k)
			continue
		}
		if got != want {
			t.Errorf("manifest.counts[%q]=%v, want %v", k, got, want)
		}
	}
	if _, present := counts["empty_table"]; present {
		t.Errorf("empty extra table must not appear in manifest.counts")
	}
}

func TestBuildBackupZip_ExtraTablesContentIsPreservedAsArray(t *testing.T) {
	extras := map[string][]map[string]interface{}{
		"coach_messages.json": {
			{"id": "m1", "body": "hello"},
		},
	}
	body, err := BuildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test", ExtraTables: extras,
	}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	for _, f := range zr.File {
		if f.Name != "coach_messages.json" {
			continue
		}
		rc, _ := f.Open()
		b, _ := io.ReadAll(rc)
		rc.Close()
		var rows []map[string]any
		if err := json.Unmarshal(b, &rows); err != nil {
			t.Fatalf("coach_messages.json parse: %v", err)
		}
		if len(rows) != 1 || rows[0]["body"] != "hello" {
			t.Errorf("coach_messages content lost: %v", rows)
		}
	}
}

func TestServer_BackupFormatToleratesExtraTablesError(t *testing.T) {
	// audit/data-export-completeness: a single failing table must
	// not sink the entire export. The handler logs + ships a
	// partial archive.
	be := &fakeBackend{
		runs:           []ExportRun{},
		routes:         []ExportRoute{},
		extraTablesErr: errors.New("supabase down"),
	}
	srv := &Server{JWTSecret: []byte(testJWTSecret), Backend: be}
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	req := httptest.NewRequest(http.MethodPost, "/v1/export",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 3600))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("backup export must ship despite extra-tables error; got %d: %s", w.Code, w.Body.String())
	}
}
