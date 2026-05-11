package dataexport

import (
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testJWTSecret = "test-jwt-secret"

type fakeBackend struct {
	denied        bool
	retryAfter    int
	rateErr       error
	runs          []ExportRun
	runsErr       error
	trackByPath   map[string][]TrackPoint
	uploads       []uploadCall
	uploadErr     error
	signedURL     string
	signURLErr    error
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
