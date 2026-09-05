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
	"log/slog"
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
	// uploadFailAfter > 0 makes the sink fail mid-archive rather than
	// on Finish, standing in for a chunk PATCH that died in flight.
	uploadFailAfter int
	sink            *fakeSink
	// pageSize splits the fake's rows into pages the way a real paged
	// walk would; 0 hands everything over in one page.
	pageSize   int
	signedURL  string
	signURLErr error
	// Queued-rail state (decisions.md § 717). `latestJob` is what the
	// status read returns; `enqueued` records every enqueue so a test
	// can assert a re-POST started no second build.
	latestJob    *ExportJobRow
	latestJobErr error
	enqueueRef   ExportJobRef
	enqueueErr   error
	enqueued     []ExportJobRef
	signCalls    int
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
	// avatars-bucket bytes (format=backup only) — keyed by object path.
	avatarBytes map[string][]byte
	// per-bucket object listings for the orphan sweep (format=backup only).
	listedObjects map[string][]string
	listErr       error
	// completeness the fetchers report back (paging ledger).
	runsComp   ExportCompleteness
	routesComp ExportCompleteness
	extrasComp ExportCompleteness
}

type uploadCall struct {
	Path        string
	ContentType string
	Size        int
}

func (f *fakeBackend) CheckRateLimitTiered(_ context.Context, _, _ string, _, _, _ int) (bool, int, error) {
	return f.denied, f.retryAfter, f.rateErr
}

func (f *fakeBackend) StreamExportRuns(ctx context.Context, _ string, emit func([]ExportRun) error) (ExportCompleteness, error) {
	if f.runsErr != nil {
		return f.runsComp, f.runsErr
	}
	return f.runsComp, emitPages(f.runs, f.pageSize, emit)
}

func (f *fakeBackend) DownloadTrackBytes(_ context.Context, path string) ([]TrackPoint, error) {
	return f.trackByPath[path], nil
}

func (f *fakeBackend) OpenExportArtifact(_ context.Context, path, contentType string) ArtifactSink {
	sink := &fakeSink{be: f, path: path, contentType: contentType, failAfter: f.uploadFailAfter, err: f.uploadErr}
	f.sink = sink
	return sink
}

// fakeSink stands in for the tus session: it accumulates so a test can
// unzip the archive, and it records the call only on Finish — so a test
// asserting "no artifact" is asserting exactly what Storage would hold.
type fakeSink struct {
	be          *fakeBackend
	path        string
	contentType string
	body        bytes.Buffer
	// err is returned once failAfter bytes have been written (0 = on
	// Finish), standing in for a chunk PATCH that failed mid-archive.
	err       error
	failAfter int
	aborted   bool
	finished  bool
}

func (s *fakeSink) Write(p []byte) (int, error) {
	if s.err != nil && s.failAfter > 0 && s.body.Len()+len(p) >= s.failAfter {
		return 0, s.err
	}
	return s.body.Write(p)
}

func (s *fakeSink) Finish() error {
	if s.err != nil {
		return s.err
	}
	s.finished = true
	s.be.uploads = append(s.be.uploads, uploadCall{Path: s.path, ContentType: s.contentType, Size: s.body.Len()})
	return nil
}

func (s *fakeSink) Abort() { s.aborted = true }

// emitPages hands `rows` over in pages of `size` (one page when unset),
// the way a paged PostgREST walk would.
func emitPages[T any](rows []T, size int, emit func([]T) error) error {
	if len(rows) == 0 {
		return nil
	}
	if size <= 0 {
		size = len(rows)
	}
	for off := 0; off < len(rows); off += size {
		end := off + size
		if end > len(rows) {
			end = len(rows)
		}
		if err := emit(rows[off:end]); err != nil {
			return err
		}
	}
	return nil
}

func (f *fakeBackend) EnqueueDataExport(_ context.Context, userID, format string) (ExportJobRef, error) {
	if f.enqueueErr != nil {
		return ExportJobRef{}, f.enqueueErr
	}
	ref := f.enqueueRef
	if ref.ID == "" {
		ref = ExportJobRef{ID: "job-1", Status: "queued", Format: format}
	}
	f.enqueued = append(f.enqueued, ref)
	return ref, nil
}

func (f *fakeBackend) LatestDataExportJob(_ context.Context, _ string) (*ExportJobRow, error) {
	if f.latestJobErr != nil {
		return nil, f.latestJobErr
	}
	if f.latestJob == nil {
		return nil, nil
	}
	copied := *f.latestJob
	return &copied, nil
}

func (f *fakeBackend) CreateSignedURL(_ context.Context, _ string, _ int) (string, error) {
	f.signCalls++
	if f.signURLErr != nil {
		return "", f.signURLErr
	}
	if f.signedURL == "" {
		return "https://signed.example/runs/exports/abc?token=fake", nil
	}
	return f.signedURL, nil
}

func (f *fakeBackend) StreamExportRoutes(ctx context.Context, _ string, emit func([]ExportRoute) error) (ExportCompleteness, error) {
	if f.routesErr != nil {
		return f.routesComp, f.routesErr
	}
	return f.routesComp, emitPages(f.routes, f.pageSize, emit)
}

func (f *fakeBackend) FetchExportProfile(_ context.Context, _ string) (map[string]interface{}, error) {
	return f.profile, f.profileErr
}

func (f *fakeBackend) FetchUserSettingsPrefs(_ context.Context, _ string) (map[string]interface{}, error) {
	return f.prefs, f.prefsErr
}

func (f *fakeBackend) StreamExportPersonalDataTables(
	_ context.Context, _ string, emit func(string, []map[string]interface{}) error,
) (ExportCompleteness, error) {
	if f.extraTablesErr != nil {
		return f.extrasComp, f.extraTablesErr
	}
	return f.extrasComp, emitTables(f.extraTables, emit)
}

// emitTables walks the fake's tables in a stable order, one section at a
// time, the way the real walk does.
func emitTables(tables map[string][]map[string]interface{}, emit func(string, []map[string]interface{}) error) error {
	names := make([]string, 0, len(tables))
	for n := range tables {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		if len(tables[n]) == 0 {
			continue
		}
		if err := emit(n, tables[n]); err != nil {
			return err
		}
	}
	return nil
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

func (f *fakeBackend) DownloadAvatar(_ context.Context, path string) ([]byte, string, error) {
	b, ok := f.avatarBytes[path]
	if !ok {
		return nil, "", fmt.Errorf("avatar not found: %s", path)
	}
	return b, "image/png", nil
}

func (f *fakeBackend) ListStorageObjects(_ context.Context, bucket, _ string) ([]string, error) {
	if f.listErr != nil {
		return nil, f.listErr
	}
	return f.listedObjects[bucket], nil
}

// runSource / routeSource / tableSource wrap a fixture slice as the
// paged source the streaming builders consume, so a test can still
// state its input as rows. `comp` is the ledger the walk reports back.
func runSource(runs []ExportRun, comp ...ExportCompleteness) RunSource {
	return func(_ context.Context, emit func([]ExportRun) error) (ExportCompleteness, error) {
		return firstComp(comp), emitPages(runs, 0, emit)
	}
}

func routeSource(routes []ExportRoute, comp ...ExportCompleteness) RouteSource {
	return func(_ context.Context, emit func([]ExportRoute) error) (ExportCompleteness, error) {
		return firstComp(comp), emitPages(routes, 0, emit)
	}
}

func tableSource(tables map[string][]map[string]interface{}, comp ...ExportCompleteness) TableSource {
	return func(_ context.Context, emit func(string, []map[string]interface{}) error) (ExportCompleteness, error) {
		return firstComp(comp), emitTables(tables, emit)
	}
}

func firstComp(comp []ExportCompleteness) ExportCompleteness {
	if len(comp) == 0 {
		return ExportCompleteness{}
	}
	return comp[0]
}

func buildBackupZip(ctx context.Context, in BuildBackupZipInput, f BackupFetchers) ([]byte, error) {
	// Production always wires all three sources; a fixture that only
	// cares about one gets empty walks for the rest rather than a nil
	// guard in the builder, where "no source" and "no rows" must not be
	// the same thing.
	if in.Runs == nil {
		in.Runs = runSource(nil)
	}
	if in.Routes == nil {
		in.Routes = routeSource(nil)
	}
	if in.ExtraTables == nil {
		in.ExtraTables = tableSource(nil)
	}
	var buf bytes.Buffer
	if _, err := WriteBackupZip(ctx, &buf, in, f); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func buildGpxZip(ctx context.Context, runs []ExportRun, fetcher TrackFetcher) ([]byte, error) {
	var buf bytes.Buffer
	if _, err := WriteGpxZip(ctx, &buf, runSource(runs), fetcher); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func buildCSV(t *testing.T, runs []ExportRun) string {
	t.Helper()
	var buf bytes.Buffer
	if _, err := WriteCSV(context.Background(), &buf, runSource(runs)); err != nil {
		t.Fatal(err)
	}
	return buf.String()
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

// buildFor runs the shared archive builder the way the queued rail's
// job handler does. The synchronous POST /v1/export that used to reach
// it over HTTP is gone (decisions.md § 724), so what these tests pin is
// the builder itself; the translation of its errors into the machine
// codes a client renders lives in main.go's `dataexportBuilder`.
func buildFor(t *testing.T, be *fakeBackend, format string) (ArtifactBuild, error) {
	t.Helper()
	return BuildArtifact(context.Background(), be,
		slog.New(slog.NewTextHandler(io.Discard, nil)), "user-A", format)
}

func TestBuildArtifact_CsvLandsInTheExportsBucketAndSignsNothing(t *testing.T) {
	be := &fakeBackend{
		runs: []ExportRun{
			{
				ID: "run-1", UserID: "user-A", StartedAt: "2026-05-11T10:00:00Z",
				DurationS: 1500, DistanceM: 5000, Source: "app",
				ActivityType: "run",
				Metadata:     map[string]interface{}{"title": "Morning"},
				CreatedAt:    "2026-05-11T11:00:00Z", UpdatedAt: "2026-05-11T11:00:00Z",
			},
		},
	}
	built, err := buildFor(t, be, "csv")
	if err != nil {
		t.Fatal(err)
	}
	if built.Runs != 1 {
		t.Errorf("runs=%d, want 1", built.Runs)
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
	if built.ObjectPath != be.uploads[0].Path {
		t.Errorf("ObjectPath=%q, want the uploaded path %q", built.ObjectPath, be.uploads[0].Path)
	}
	// The builder must NOT mint a URL: a signed URL created when the
	// build happened to finish starts its ten minutes at a moment the
	// subject had no part in choosing (decisions.md § 717).
	if be.signCalls != 0 {
		t.Errorf("signCalls=%d; the build must not sign anything", be.signCalls)
	}
}

func TestBuildArtifact_GpxZipUploadsAZip(t *testing.T) {
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
	if _, err := buildFor(t, be, "gpx"); err != nil {
		t.Fatal(err)
	}
	if len(be.uploads) != 1 || be.uploads[0].ContentType != "application/zip" {
		t.Fatalf("upload=%+v", be.uploads)
	}
}

func TestBuildArtifact_RejectsUnknownFormat(t *testing.T) {
	be := &fakeBackend{}
	if _, err := buildFor(t, be, "made-up"); err == nil {
		t.Fatal("an unknown format must not build an archive")
	}
	if len(be.uploads) != 0 {
		t.Errorf("uploads=%v; nothing may be written for a format nobody asked for", be.uploads)
	}
}

// --- pure helpers --------------------------------------------------------

func TestBuildCSV_ColumnOrderAndDataShape(t *testing.T) {
	runs := []ExportRun{
		{
			ID: "r1", StartedAt: "2026-05-11T10:00:00Z",
			DurationS: 1500, DistanceM: 5000, Source: "app",
			ActivityType: "run", IsDNF: false,
			Metadata: map[string]interface{}{
				"title": "Morning", "avg_bpm": 145.0,
			},
			CreatedAt: "2026-05-11T11:00:00Z", UpdatedAt: "2026-05-11T11:00:00Z",
		},
	}
	csv := buildCSV(t, runs)
	lines := strings.Split(strings.TrimSpace(csv), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines (header + 1 row); got %d", len(lines))
	}
	if !strings.HasPrefix(lines[0], "id,started_at,concluded_at,distance_m") {
		t.Errorf("header order off: %q", lines[0])
	}
	// activity_type + is_dnf are real columns now (F3); they come from the
	// ExportRun fields, not the metadata bag.
	if !strings.Contains(lines[0], "activity_type") || !strings.Contains(lines[0], "is_dnf") {
		t.Errorf("header missing activity_type/is_dnf columns: %q", lines[0])
	}
	if !strings.Contains(lines[1], "run") || !strings.Contains(lines[1], "Morning") {
		t.Errorf("row missing activity_type / title fields: %q", lines[1])
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
	zipped, err := buildGpxZip(context.Background(), runs, fetcher)
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

func TestBuildArtifact_BackupFormatHappyPath(t *testing.T) {
	trackURL := "user-A/run-1.json.gz"
	trueVal := true
	floatVal := 5000.0
	be := &fakeBackend{
		runs: []ExportRun{
			{
				ID: "run-1", UserID: "user-A", StartedAt: "2026-05-11T10:00:00Z",
				DurationS: 1500, DistanceM: 5000, Source: "app",
				TrackURL:     &trackURL,
				ActivityType: "run",
				Metadata:     map[string]interface{}{"title": "Morning"},
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
	built, err := buildFor(t, be, "backup")
	if err != nil {
		t.Fatal(err)
	}
	if built.Runs != 1 {
		t.Errorf("runs=%d, want 1", built.Runs)
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
		ActivityType: "run",
		Metadata:     map[string]interface{}{},
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

	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(runs), Routes: routeSource(routes), Profile: profile, SettingsPrefs: prefs,
		UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{RawTrack: fetcher})
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

	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(runs), UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{RawTrack: fetcher})
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
		ActivityType: "run",
		Metadata:     map[string]interface{}{"indoor": true},
	}}
	fetcher := func(_ context.Context, path string) ([]byte, error) {
		if path == hrURL {
			return rawHr, nil
		}
		return nil, nil
	}

	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(runs), UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{RawTrack: fetcher})
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

	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test", ExtraTables: tableSource(extras),
	}, BackupFetchers{RawTrack: func(_ context.Context, _ string) ([]byte, error) { return nil, nil }, Photo: photoFetcher})
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

func TestBuildBackupZip_ArchivesAvatarBytes(t *testing.T) {
	// data-export-completeness Medium: the avatars-bucket object was
	// never archived — the backup carried avatar_url only. The builder
	// probes the enumerable `{uid}/avatar.{ext}` candidate set and
	// archives every hit verbatim.
	imgBytes := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A}
	var probed []string
	avatar := func(_ context.Context, p string) ([]byte, string, error) {
		probed = append(probed, p)
		if p == "uid/avatar.png" {
			return imgBytes, "image/png", nil
		}
		return nil, "", errors.New("object not found")
	}

	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{Avatar: avatar})
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
	got, ok := entries["avatar.png"]
	if !ok {
		t.Fatalf("avatar.png missing; entries=%v", keysOf(entries))
	}
	if !bytes.Equal(got, imgBytes) {
		t.Errorf("avatar bytes mismatch: got %v want %v", got, imgBytes)
	}
	wantProbes := []string{"uid/avatar.jpg", "uid/avatar.png", "uid/avatar.webp"}
	if fmt.Sprint(probed) != fmt.Sprint(wantProbes) {
		t.Errorf("probed=%v, want exactly the canonical candidate set %v", probed, wantProbes)
	}
	counts := manifest["counts"].(map[string]any)
	if counts["avatars"] != float64(1) {
		t.Errorf("counts[avatars]=%v, want 1", counts["avatars"])
	}
}

func TestBuildBackupZip_NoAvatarShipsZeroCount(t *testing.T) {
	avatar := func(_ context.Context, _ string) ([]byte, string, error) {
		return nil, "", errors.New("object not found")
	}
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{Avatar: avatar})
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	var manifest map[string]any
	for _, f := range zr.File {
		if strings.HasPrefix(f.Name, "avatar.") {
			t.Errorf("no avatar entry should land when every probe misses; got %s", f.Name)
		}
		if f.Name == "manifest.json" {
			rc, _ := f.Open()
			b, _ := io.ReadAll(rc)
			rc.Close()
			_ = json.Unmarshal(b, &manifest)
		}
	}
	counts := manifest["counts"].(map[string]any)
	if counts["avatars"] != float64(0) {
		t.Errorf("counts[avatars]=%v, want 0", counts["avatars"])
	}
}

func TestBuildBackupZip_PrefixWalkArchivesOrphanObjects(t *testing.T) {
	// data-export-completeness Medium: row-driven fetches miss objects
	// with no DB row (CAS-orphaned matched tracks, legacy tracks, photo
	// thumbnails). The prefix walk sweeps every object under {uid}/ into
	// storage/{bucket}/, deduped against the row-driven entries, with
	// exports/ and traversal names excluded.
	trackURL := "uid/run-1.json.gz"
	rawTrack := gzipString(t, `[{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]`)
	matchedBytes := gzipString(t, `[{"lat":1.1,"lng":2.1}]`)
	thumbBytes := []byte{0xFF, 0xD8, 0xFF}
	runs := []ExportRun{{
		ID: "run-1", UserID: "uid", StartedAt: "2026-05-11T10:00:00Z",
		DurationS: 1500, DistanceM: 5000, Source: "app", TrackURL: &trackURL,
	}}
	extras := map[string][]map[string]interface{}{
		"run_photos.json": {
			{"id": "photo-1", "storage_path": "uid/photo-1.jpg"},
		},
	}
	rawFetch := func(_ context.Context, p string) ([]byte, error) {
		switch p {
		case trackURL:
			return rawTrack, nil
		case "uid/run-1.matched.json.gz":
			return matchedBytes, nil
		}
		return nil, errors.New("unexpected raw fetch: " + p)
	}
	photoFetch := func(_ context.Context, p string) ([]byte, string, error) {
		switch p {
		case "uid/photo-1.jpg":
			return []byte{0x01}, "image/jpeg", nil
		case "uid/photo-1_512.jpg":
			return thumbBytes, "image/jpeg", nil
		}
		return nil, "", errors.New("unexpected photo fetch: " + p)
	}
	lister := func(_ context.Context, bucket, prefix string) ([]string, error) {
		if prefix != "uid" {
			t.Errorf("lister prefix=%q, want uid", prefix)
		}
		switch bucket {
		case "runs":
			return []string{
				trackURL,                     // already archived row-driven → deduped
				"uid/run-1.matched.json.gz",  // CAS orphan → swept
				"uid/exports/2026-01-01.zip", // prior export artifact → skipped
				"uid/../etc/passwd",          // traversal name → skipped
				"other/run-9.json.gz",        // outside the prefix → skipped
			}, nil
		case "run-photos":
			return []string{
				"uid/photo-1.jpg",     // already archived row-driven → deduped
				"uid/photo-1_512.jpg", // worker thumbnail, no export row → swept
			}, nil
		}
		return nil, errors.New("unexpected bucket: " + bucket)
	}

	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(runs), UserID: "uid", ExportedFrom: "test", ExtraTables: tableSource(extras),
	}, BackupFetchers{RawTrack: rawFetch, Photo: photoFetch, ListObjects: lister})
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
	if got := entries["storage/runs/run-1.matched.json.gz"]; !bytes.Equal(got, matchedBytes) {
		t.Errorf("orphaned matched track not swept verbatim; entries=%v", keysOf(entries))
	}
	if got := entries["storage/run-photos/photo-1_512.jpg"]; !bytes.Equal(got, thumbBytes) {
		t.Errorf("orphaned thumbnail not swept verbatim; entries=%v", keysOf(entries))
	}
	for name := range entries {
		if name == "storage/runs/run-1.json.gz" || name == "storage/run-photos/photo-1.jpg" {
			t.Errorf("row-driven object duplicated by the walk: %s", name)
		}
		if strings.HasPrefix(name, "storage/runs/exports/") {
			t.Errorf("exports/ artifact must be skipped: %s", name)
		}
		if strings.Contains(name, "..") {
			t.Errorf("traversal entry landed in the zip: %s", name)
		}
	}
	counts := manifest["counts"].(map[string]any)
	if counts["storage_orphans"] != float64(2) {
		t.Errorf("counts[storage_orphans]=%v, want 2", counts["storage_orphans"])
	}
	if counts["tracks"] != float64(1) || counts["photos"] != float64(1) {
		t.Errorf("row-driven counts drifted: %v", counts)
	}
}

func TestBuildBackupZip_ListerErrorDoesNotSinkArchive(t *testing.T) {
	trackURL := "uid/run-1.json.gz"
	rawTrack := gzipString(t, `[{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]`)
	runs := []ExportRun{{
		ID: "run-1", UserID: "uid", StartedAt: "2026-05-11T10:00:00Z",
		DurationS: 1500, DistanceM: 5000, Source: "app", TrackURL: &trackURL,
	}}
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(runs), UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{
		RawTrack: func(_ context.Context, _ string) ([]byte, error) { return rawTrack, nil },
		ListObjects: func(_ context.Context, _, _ string) ([]string, error) {
			return nil, errors.New("storage list unavailable")
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	var manifest map[string]any
	hasTrack := false
	for _, f := range zr.File {
		if f.Name == "tracks/run-1.json.gz" {
			hasTrack = true
		}
		if f.Name == "manifest.json" {
			rc, _ := f.Open()
			b, _ := io.ReadAll(rc)
			rc.Close()
			_ = json.Unmarshal(b, &manifest)
		}
	}
	if !hasTrack {
		t.Errorf("row-driven track must still ship when the lister fails")
	}
	counts := manifest["counts"].(map[string]any)
	if counts["storage_orphans"] != float64(0) {
		t.Errorf("counts[storage_orphans]=%v, want 0", counts["storage_orphans"])
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
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(runs), UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{RawTrack: fetcher})
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
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{RawTrack: func(_ context.Context, _ string) ([]byte, error) {
		return nil, errors.New("must not be called")
	}})
	if err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if len(zr.File) < 4 {
		t.Fatalf("expected at least manifest + runs + routes + profile entries; got %d", len(zr.File))
	}
}

func TestBuildBackupZip_NilProfileSerialisesAsNull(t *testing.T) {
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test", Profile: nil,
	}, BackupFetchers{RawTrack: func(_ context.Context, _ string) ([]byte, error) { return nil, nil }})
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

func TestBuildArtifact_RoutesFetchErrorNamesTheSection(t *testing.T) {
	be := &fakeBackend{
		runs:      []ExportRun{},
		routesErr: errors.New("routes table on fire"),
	}
	_, err := buildFor(t, be, "backup")
	if err == nil {
		t.Fatal("a section that would not read must fail the build")
	}
	// The section name is what main.go's adapter turns into the
	// `routes_fetch_failed` code the subject's client renders.
	if got := SectionOf(err); got != "routes" {
		t.Errorf("SectionOf=%q, want routes", got)
	}
	if len(be.uploads) != 0 {
		t.Errorf("uploads=%v; a failed build must leave no artifact", be.uploads)
	}
}

func TestBuildArtifact_ProfileFetchErrorDegradesGracefully(t *testing.T) {
	// A profile fetch failure must NOT sink the whole backup —
	// runs + routes still get archived, profile.profile is null.
	be := &fakeBackend{
		runs:       []ExportRun{},
		routes:     []ExportRoute{},
		profileErr: errors.New("rpc unavailable"),
		prefs:      map[string]interface{}{"unit": "km"},
	}
	if _, err := buildFor(t, be, "backup"); err != nil {
		t.Fatalf("build failed: %v", err)
	}
	if len(be.uploads) != 1 {
		t.Fatalf("expected 1 upload; got %d", len(be.uploads))
	}
}

func TestBuildArtifact_PrefsFetchErrorDegradesGracefully(t *testing.T) {
	be := &fakeBackend{
		runs:     []ExportRun{},
		routes:   []ExportRoute{},
		profile:  map[string]interface{}{"display_name": "Test"},
		prefsErr: errors.New("user_settings unavailable"),
	}
	if _, err := buildFor(t, be, "backup"); err != nil {
		t.Fatalf("build failed: %v", err)
	}
	if len(be.uploads) != 1 {
		t.Fatalf("expected 1 upload; got %d", len(be.uploads))
	}
}

func TestBuildArtifact_RunsFetchErrorNamesTheSection(t *testing.T) {
	be := &fakeBackend{runsErr: errors.New("runs table down")}
	_, err := buildFor(t, be, "backup")
	if err == nil {
		t.Fatal("a runs walk that would not read must fail the build")
	}
	if got := SectionOf(err); got != "runs" {
		t.Errorf("SectionOf=%q, want runs", got)
	}
	if len(be.uploads) != 0 {
		t.Errorf("uploads=%v; a failed build must leave no artifact", be.uploads)
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
			body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
				Runs: runSource(runs), UserID: "uid", ExportedFrom: "test",
			}, BackupFetchers{RawTrack: fetcher})
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
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(runs), Routes: routeSource(routes), UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{RawTrack: fetcher})
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
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Routes: routeSource(routes), UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{RawTrack: func(_ context.Context, _ string) ([]byte, error) { return nil, nil }})
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
				"is_featured", "run_count", "is_starred", "description", "club_id"} {
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
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(runs), UserID: "new-uid", ExportedFrom: "test",
	}, BackupFetchers{RawTrack: func(_ context.Context, _ string) ([]byte, error) { return nil, nil }})
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
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "go-service-test",
	}, BackupFetchers{RawTrack: func(_ context.Context, _ string) ([]byte, error) { return nil, nil }})
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
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(nil), Routes: routeSource(nil), UserID: "uid", ExportedFrom: "test",
		ExtraTables: tableSource(extras),
	}, BackupFetchers{})
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
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		UserID: "uid", ExportedFrom: "test", ExtraTables: tableSource(extras),
	}, BackupFetchers{})
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

func TestBuildArtifact_ToleratesExtraTablesError(t *testing.T) {
	// audit/data-export-completeness: a single failing table must
	// not sink the entire export. The builder logs + ships a
	// partial archive.
	be := &fakeBackend{
		runs:           []ExportRun{},
		routes:         []ExportRoute{},
		extraTablesErr: errors.New("supabase down"),
	}
	if _, err := buildFor(t, be, "backup"); err != nil {
		t.Errorf("backup export must ship despite extra-tables error; got %v", err)
	}
	if len(be.uploads) != 1 {
		t.Errorf("expected 1 upload; got %d", len(be.uploads))
	}
}

// TestBuildBackupZip_NilRawTrackFetcherSkipsSection pins BackupFetchers'
// documented contract — "a nil field skips its section". Every section honoured
// it except the tracks and HR-sidecar loops, which called through the nil func
// as soon as a run carried a track_url in the canonical shape, panicking the
// export handler. The existing section tests only survived because their
// fixtures had no matching TrackURL.
func TestBuildBackupZip_NilRawTrackFetcherSkipsSection(t *testing.T) {
	trackURL := "uid/r1.json.gz"
	hrURL := "uid/r1.hr.json.gz"
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		UserID:       "uid",
		ExportedFrom: "test",
		Runs: runSource([]ExportRun{{
			ID: "r1", UserID: "uid",
			TrackURL: &trackURL, HrSeriesURL: &hrURL,
		}}),
	}, BackupFetchers{})
	if err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range zr.File {
		if strings.HasPrefix(f.Name, "tracks/") || strings.HasPrefix(f.Name, "hr/") {
			t.Errorf("nil RawTrack fetcher must skip its section; got %s", f.Name)
		}
	}
}

func TestGpxFloat_NeverUsesScientificNotation(t *testing.T) {
	// %v switches to %e below 1e-4, so a longitude near the prime meridian
	// printed as "-1.23e-05". GPX 1.1 types lat/lon/ele as xsd:decimal, whose
	// lexical space forbids an exponent, so a schema-validating importer
	// rejected the whole file — it hits anyone running at Greenwich.
	cases := []struct {
		in   float64
		want string
	}{
		{-0.0000123, "-0.0000123"},
		{0.000021, "0.000021"},
		{0, "0"},
		{51.4779, "51.4779"},
		{-122.4194, "-122.4194"},
		{1234567.5, "1234567.5"},
	}
	for _, c := range cases {
		got := gpxFloat(c.in)
		if got != c.want {
			t.Errorf("gpxFloat(%v) = %q, want %q", c.in, got, c.want)
		}
		if strings.ContainsAny(got, "eE") {
			t.Errorf("gpxFloat(%v) = %q contains an exponent — invalid xsd:decimal", c.in, got)
		}
	}
}

// ─────────────────── manifest honesty ───────────────────
//
// The manifest's per-table count is the AUTHORITATIVE row count the
// database holds, not the number of rows this archive happens to carry.
// A section the pager could not read in full is named in `incomplete`
// and flips `complete` to false — the check a data subject (or a
// regulator) runs is "does runs.json hold counts.runs rows", and a
// count copied from the truncated fetch defeats exactly that check.

func manifestOf(t *testing.T, zipped []byte) map[string]any {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(zipped), int64(len(zipped)))
	if err != nil {
		t.Fatalf("zip parse: %v", err)
	}
	for _, f := range zr.File {
		if f.Name != "manifest.json" {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			t.Fatalf("open manifest: %v", err)
		}
		defer rc.Close()
		buf, err := io.ReadAll(rc)
		if err != nil {
			t.Fatalf("read manifest: %v", err)
		}
		var m map[string]any
		if err := json.Unmarshal(buf, &m); err != nil {
			t.Fatalf("manifest parse: %v", err)
		}
		return m
	}
	t.Fatal("no manifest.json in the archive")
	return nil
}

func TestBuildBackupZip_ManifestCountsTheDatabaseNotTheArchive(t *testing.T) {
	zipped, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(
			[]ExportRun{{ID: "r-1", UserID: "uid"}, {ID: "r-2", UserID: "uid"}},
			ExportCompleteness{Totals: map[string]int{"runs": 12000}, Incomplete: []string{"runs"}},
		),
		UserID: "uid",
		Routes: routeSource(nil),
		ExtraTables: tableSource(
			map[string][]map[string]interface{}{"food_log.json": {{"id": "f-1"}}},
			ExportCompleteness{Totals: map[string]int{"food_log": 4000}, Incomplete: []string{"food_log"}},
		),
	}, BackupFetchers{})
	if err != nil {
		t.Fatalf("BuildBackupZip: %v", err)
	}
	m := manifestOf(t, zipped)
	if m["complete"] != false {
		t.Errorf("complete=%v; a short archive must not claim completeness", m["complete"])
	}
	inc, _ := m["incomplete"].([]any)
	if len(inc) != 2 || inc[0] != "food_log" || inc[1] != "runs" {
		t.Errorf("incomplete=%v; want both short sections, sorted", m["incomplete"])
	}
	counts := m["counts"].(map[string]any)
	if counts["runs"] != float64(12000) {
		t.Errorf("counts.runs=%v; want the database's 12000, not the 2 rows exported", counts["runs"])
	}
	if counts["food_log"] != float64(4000) {
		t.Errorf("counts.food_log=%v; want 4000", counts["food_log"])
	}
}

func TestBuildBackupZip_CompleteExportSaysSo(t *testing.T) {
	zipped, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs:   runSource([]ExportRun{{ID: "r-1", UserID: "uid"}}, ExportCompleteness{Totals: map[string]int{"runs": 1}}),
		Routes: routeSource(nil),
		UserID: "uid",
	}, BackupFetchers{})
	if err != nil {
		t.Fatalf("BuildBackupZip: %v", err)
	}
	m := manifestOf(t, zipped)
	if m["complete"] != true {
		t.Errorf("complete=%v; a whole archive should say so", m["complete"])
	}
	if inc, _ := m["incomplete"].([]any); len(inc) != 0 {
		t.Errorf("incomplete=%v; want empty", inc)
	}
	if m["counts"].(map[string]any)["runs"] != float64(1) {
		t.Errorf("counts=%v", m["counts"])
	}
}

// --- streaming + fail-closed ------------------------------------------

// The archive is pushed to Storage as it is produced, so a chunk that
// fails mid-build has to leave NOTHING behind. The old shape assembled
// the whole thing first, so this failure could not happen half-way; now
// it can, and the answer must still be a 500 with no artifact rather
// than a short-but-real zip carrying a signed URL.
func TestBuildArtifact_MidStreamUploadFailureLeavesNoArtifact(t *testing.T) {
	runs := make([]ExportRun, 400)
	for i := range runs {
		runs[i] = ExportRun{
			ID: fmt.Sprintf("run-%03d", i), UserID: "user-A",
			StartedAt: "2026-05-11T10:00:00Z", ActivityType: "run",
		}
	}
	be := &fakeBackend{
		runs:            runs,
		pageSize:        100,
		uploadErr:       errors.New("resumable: patch at offset 6291456 returned 500"),
		uploadFailAfter: 512,
	}
	if _, err := buildFor(t, be, "backup"); err == nil {
		t.Fatal("a dead upload must not report a finished archive")
	}
	if len(be.uploads) != 0 {
		t.Errorf("uploads=%v; a build that died half-way must leave no artifact", be.uploads)
	}
	if be.sink == nil || !be.sink.aborted {
		t.Error("the upload session must be aborted so Storage keeps no partial object")
	}
	if be.sink != nil && be.sink.finished {
		t.Error("a failed build must never finalise the object")
	}
}

// A tail chunk that fails is the upload's failure, not the build's, and
// the client is told so — the object still never materialises.
func TestBuildArtifact_FinishFailureIsReportedAsUploadFailed(t *testing.T) {
	be := &fakeBackend{
		runs:      []ExportRun{{ID: "run-1", UserID: "user-A", StartedAt: "2026-05-11T10:00:00Z"}},
		uploadErr: errors.New("resumable: finish short"),
	}
	_, err := buildFor(t, be, "csv")
	if err == nil {
		t.Fatal("a failed Finish must fail the build")
	}
	// ErrUpload is what main.go's adapter turns into `upload_failed`:
	// the archive build was fine, the write was not, and the two are
	// different operational facts.
	if !errors.Is(err, ErrUpload) {
		t.Fatalf("err=%v; want an ErrUpload", err)
	}
	if SectionOf(err) != "" {
		t.Errorf("a dead upload must not be blamed on a section (%q)", SectionOf(err))
	}
	if len(be.uploads) != 0 {
		t.Errorf("uploads=%v; nothing may be recorded when the upload failed", be.uploads)
	}
	if be.sink == nil || !be.sink.aborted {
		t.Error("the session must be aborted")
	}
}

// countingWriter stands in for the sink when the test cares about WHEN
// bytes arrive rather than what they are.
type countingWriter struct{ n int }

func (c *countingWriter) Write(p []byte) (int, error) {
	c.n += len(p)
	return len(p), nil
}

// The streaming property itself: bytes reach the sink while the walk is
// still going. A builder that assembled first and wrote once would pass
// every content assertion in this file and fail only this one.
func TestWriteCSV_BytesReachTheSinkBeforeTheWalkEnds(t *testing.T) {
	var w countingWriter
	page := make([]ExportRun, 500)
	for i := range page {
		page[i] = ExportRun{ID: fmt.Sprintf("r-%03d", i), UserID: "uid", StartedAt: "2026-05-11T10:00:00Z"}
	}
	atLastPage := -1
	src := RunSource(func(_ context.Context, emit func([]ExportRun) error) (ExportCompleteness, error) {
		for p := 0; p < 4; p++ {
			if p == 3 {
				atLastPage = w.n
			}
			if err := emit(page); err != nil {
				return ExportCompleteness{}, err
			}
		}
		return ExportCompleteness{Totals: map[string]int{"runs": 2000}}, nil
	})
	built, err := WriteCSV(context.Background(), &w, src)
	if err != nil {
		t.Fatal(err)
	}
	if built.Runs != 2000 {
		t.Fatalf("runs=%d; want 2000", built.Runs)
	}
	if atLastPage <= 0 {
		t.Fatal("nothing had reached the sink by the final page; the archive is being buffered")
	}
	if atLastPage >= w.n {
		t.Errorf("bytes at last page (%d) is the whole output (%d); the walk finished before anything was written", atLastPage, w.n)
	}
}

// The row ceiling is gone on this rail, so a history far past it has to
// come out whole and be reported as complete. 120,000 is the figure the
// Edge Function's own streaming suite uses against the same deleted
// 50,000-row bound.
func TestWriteBackupZip_HistoryFarPastTheDeletedCeilingStreamsWhole(t *testing.T) {
	const total = 120_000
	const pageSize = 1000
	biggestPage := 0
	src := RunSource(func(_ context.Context, emit func([]ExportRun) error) (ExportCompleteness, error) {
		page := make([]ExportRun, pageSize)
		for off := 0; off < total; off += pageSize {
			for i := range page {
				page[i] = ExportRun{
					ID: fmt.Sprintf("run-%06d", off+i), UserID: "uid",
					StartedAt: "2026-05-11T10:00:00Z", ActivityType: "run",
					DistanceM: 5000, DurationS: 1500, Source: "app",
				}
			}
			if len(page) > biggestPage {
				biggestPage = len(page)
			}
			if err := emit(page); err != nil {
				return ExportCompleteness{}, err
			}
		}
		return ExportCompleteness{Totals: map[string]int{"runs": total}}, nil
	})

	var buf bytes.Buffer
	built, err := WriteBackupZip(context.Background(), &buf, BuildBackupZipInput{
		Runs: src, Routes: routeSource(nil), ExtraTables: tableSource(nil),
		UserID: "uid", ExportedFrom: "test",
	}, BackupFetchers{})
	if err != nil {
		t.Fatalf("WriteBackupZip: %v", err)
	}
	if built.Runs != total {
		t.Fatalf("runs=%d; want all %d", built.Runs, total)
	}
	if biggestPage != pageSize {
		t.Errorf("biggest page=%d; the builder must never be handed the whole history", biggestPage)
	}

	zipped := buf.Bytes()
	zr, err := zip.NewReader(bytes.NewReader(zipped), int64(len(zipped)))
	if err != nil {
		t.Fatalf("the streamed archive does not open: %v", err)
	}
	var runsEntry *zip.File
	for _, f := range zr.File {
		if f.Name == "runs.json" {
			runsEntry = f
		}
	}
	if runsEntry == nil {
		t.Fatal("no runs.json in the archive")
	}
	rc, err := runsEntry.Open()
	if err != nil {
		t.Fatal(err)
	}
	defer rc.Close()
	dec := json.NewDecoder(rc)
	if _, err := dec.Token(); err != nil {
		t.Fatalf("runs.json is not a JSON array: %v", err)
	}
	rows := 0
	for dec.More() {
		var row map[string]interface{}
		if err := dec.Decode(&row); err != nil {
			t.Fatalf("row %d: %v", rows, err)
		}
		if _, ok := row["user_id"]; ok {
			t.Fatal("runs.json must stay re-homeable; user_id is stripped")
		}
		rows++
	}
	if rows != total {
		t.Fatalf("runs.json carries %d rows; want %d", rows, total)
	}

	m := manifestOf(t, zipped)
	if m["complete"] != true {
		t.Errorf("complete=%v; nothing was truncated", m["complete"])
	}
	if m["counts"].(map[string]any)["runs"] != float64(total) {
		t.Errorf("counts.runs=%v; want %d", m["counts"].(map[string]any)["runs"], total)
	}
}

// A section that failed to read must reach the RESPONSE's `complete`,
// not only manifest.json — both clients gate their truncation notice on
// an explicit `complete: false` (decisions §643).
func TestBuildArtifact_ShortSectionMakesTheBuildIncomplete(t *testing.T) {
	be := &fakeBackend{
		runs:       []ExportRun{{ID: "run-1", UserID: "user-A", StartedAt: "2026-05-11T10:00:00Z"}},
		runsComp:   ExportCompleteness{Totals: map[string]int{"runs": 1}},
		extrasComp: ExportCompleteness{Totals: map[string]int{"food_log": 40000}, Incomplete: []string{"food_log"}},
		extraTables: map[string][]map[string]interface{}{
			"food_log.json": {{"id": "f-1"}},
		},
	}
	built, err := buildFor(t, be, "backup")
	if err != nil {
		t.Fatal(err)
	}
	if built.Complete {
		t.Error("a section short of the database must be disclosed on the build, not only in manifest.json")
	}
}
