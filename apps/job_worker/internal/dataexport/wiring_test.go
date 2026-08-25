package dataexport

// Source-grep architecture guards for the export handler.
//
// The streaming invariants are structural — the archive must never be
// assembled in memory, a failed build must leave no artifact, and no cap
// may creep back in — and every one of them would regress silently under
// a refactor with a green suite. These pin them in source.
//
// Mirrors the source-grep pattern in the Edge Function's
// export-data/wiring.test.ts (decisions.md §703).

import (
	"os"
	"strings"
	"testing"
)

func readSource(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestWiring_ArchiveIsStreamedNeverBuffered(t *testing.T) {
	src := readSource(t, "server.go") + readSource(t, "build.go")
	if !strings.Contains(src, "OpenExportArtifact(ctx context.Context, path, contentType string) ArtifactSink") {
		t.Error("the archive must go out through a chunked upload session")
	}
	if strings.Contains(src, "bytes.Buffer") {
		t.Error("a bytes.Buffer accumulates the whole archive in memory — the exact " +
			"allocation the 5000-run and 50,000-row caps existed to protect")
	}
	if strings.Contains(src, "UploadExportArtifact") {
		t.Error("a single-shot Storage upload needs the whole body resident")
	}
	// Each builder writes into the caller's io.Writer, which is the sink.
	for _, sig := range []string{
		"func WriteCSV(ctx context.Context, w io.Writer, runs RunSource)",
		"func WriteGpxZip(ctx context.Context, w io.Writer, runs RunSource, trackFetcher TrackFetcher)",
		"func WriteBackupZip(ctx context.Context, w io.Writer, in BuildBackupZipInput, f BackupFetchers)",
	} {
		if !strings.Contains(src, sig) {
			t.Errorf("builder signature missing, so something else holds the archive: %s", sig)
		}
	}
}

func TestWiring_NoRunCapAndNoRowCeilingSurvive(t *testing.T) {
	src := readSource(t, "server.go")
	if strings.Contains(src, "MaxRunsPerExport") {
		t.Error("the 5000-run cap is gone; it was a memory bound")
	}
	client := readSource(t, "../supabase.go")
	if strings.Contains(client, "exportRowCeiling") {
		t.Error("the per-section row ceiling is gone")
	}
	// The reads hand pages over and drop them; collecting a whole section
	// is what the ceilings existed for.
	for _, walk := range []string{
		"func (c *SupabaseClient) StreamExportRuns(",
		"func (c *SupabaseClient) StreamExportRoutes(",
		"func (c *SupabaseClient) StreamExportPersonalDataTables(",
		"func walkExportPages[T any](",
	} {
		if !strings.Contains(client, walk) {
			t.Errorf("missing streaming read: %s", walk)
		}
	}
	if strings.Contains(client, "func fetchExportPages[") {
		t.Error("the collecting pager is what the row ceiling bounded; it must not come back")
	}
}

func TestWiring_FailedBuildAbortsBeforeAnswering(t *testing.T) {
	// The build and the signing sit in different files since the queued
	// rail landed (§ 717), so the invariant is pinned in two halves: the
	// builder yields a path only after the upload finalised, and neither
	// rail signs anything else.
	src := readSource(t, "build.go")
	if n := strings.Count(src, "sink.Abort()"); n < 2 {
		t.Errorf("every failure path out of the build must abort the upload session; found %d aborts", n)
	}
	finish := strings.Index(src, "sink.Finish()")
	ok := strings.Index(src, "ObjectPath: objectPath,")
	if finish == -1 || ok == -1 {
		t.Fatal("builder shape changed: expected a Finish and a success return carrying the object path")
	}
	if finish > ok {
		t.Error("the object path must only be returned after the upload finalises, or a caller signs a nonexistent object")
	}
	if strings.Contains(src, "CreateSignedURL") {
		t.Error("the builder must not mint the signed URL: on the queued rail its 10-minute " +
			"TTL would start whenever the worker happened to finish, not when the subject asks")
	}

	jobs := readSource(t, "jobs.go")
	ready := strings.Index(jobs, `case row.Status == "ready":`)
	jobSign := strings.Index(jobs, "CreateSignedURL(r.Context(), row.ObjectPath")
	if ready == -1 || jobSign == -1 || ready > jobSign {
		t.Error("the queued rail must sign only inside the ready arm: a queued, running, " +
			"failed or expired row has no artifact to hand over")
	}
}

func TestWiring_ResponseCompletenessFoldsInEverySection(t *testing.T) {
	if src := readSource(t, "build.go"); !strings.Contains(src, "Complete:   built.Completeness.IsComplete(),") {
		t.Error("a section that came up short must not be reported as a complete export")
	}
	if src := readSource(t, "jobs.go"); !strings.Contains(src, `body["complete"] = *row.Complete`) {
		t.Error("the status endpoint must carry the builder's own completeness verdict, or a " +
			"short archive is handed over as a whole one")
	}
}

// The synchronous rail is gone (decisions.md § 724), and it must not
// come back: it held the caller's connection open for the whole build,
// which on a phone is the ordinary way an export died. Mobile was the
// only reason it survived § 717.
func TestWiring_NoSynchronousExportRailSurvives(t *testing.T) {
	src := readSource(t, "server.go")
	if strings.Contains(src, `mux.HandleFunc("/v1/export"`) {
		t.Error("POST /v1/export must not be mounted: the queued rail is the only rail")
	}
	if strings.Contains(src, "BuildArtifact(") {
		t.Error("no HTTP handler may build the archive on the caller's connection")
	}
	if strings.Contains(src, "CreateSignedURL(r.Context()") {
		t.Error("server.go must mint no signed URL: signing happens in the status endpoint, " +
			"so the 10-minute clock starts when the subject asks")
	}
}

// The queued rail's own structural invariants (decisions.md § 717).
func TestWiring_QueuedRailHoldsNoConnectionAndStoresNoURL(t *testing.T) {
	jobs := readSource(t, "jobs.go")
	if strings.Contains(jobs, "BuildArtifact(") {
		t.Error("the enqueue endpoint must not build: holding the caller's connection for the " +
			"build is the whole thing the queued rail exists to stop")
	}
	// The state row carries a Storage key, never a live download credential.
	if strings.Contains(readSource(t, "../supabase_dataexport_jobs.go"), `"url"`) {
		t.Error("the export state row must store the object path, not a signed URL")
	}
	// Both endpoints authenticate before touching anything.
	for _, fn := range []string{"handleJobsCreate", "handleJobsLatest"} {
		start := strings.Index(jobs, "func (s *Server) "+fn)
		if start == -1 {
			t.Fatalf("%s not found", fn)
		}
		body := jobs[start:]
		auth := strings.Index(body, "s.extractUserID(r)")
		if auth == -1 {
			t.Errorf("%s must resolve the caller before doing anything", fn)
			continue
		}
		for _, call := range []string{"s.Backend.EnqueueDataExport(", "s.Backend.LatestDataExportJob(", "s.Backend.CheckRateLimitTiered("} {
			if at := strings.Index(body, call); at != -1 && at < auth {
				t.Errorf("%s calls %s before authenticating the caller", fn, call)
			}
		}
	}
}

func TestWiring_EveryPersonalDataSectionIsStillWired(t *testing.T) {
	// The streaming rewrite touched every builder, so the entry set is
	// re-pinned here rather than trusted.
	src := readSource(t, "server.go")
	for _, entry := range []string{
		`"runs.json"`,
		`"routes.json"`,
		`"profile.json"`,
		`"run_photos.json"`,
		`"manifest.json"`,
	} {
		if !strings.Contains(src, entry) {
			t.Errorf("%s is no longer written", entry)
		}
	}
	for _, prefix := range []string{`"tracks/`, `"hr/`, `"photos/`, `"avatar."`, `"storage/"`} {
		if !strings.Contains(src, prefix) {
			t.Errorf("the %s blob sweep is no longer wired", prefix)
		}
	}
	if !strings.Contains(src, "in.ExtraTables(ctx,") {
		t.Error("the per-table section set is no longer read")
	}
	if !strings.Contains(src, "f.ListObjects(ctx, wk.bucket, in.UserID)") {
		t.Error("the Storage orphan sweep is no longer wired")
	}
	// The jobs count-by-kind summary is a reduction the client owns.
	if !strings.Contains(readSource(t, "../supabase.go"), `emit("jobs_summary.json", summary)`) {
		t.Error("jobs_summary.json is no longer emitted")
	}
}

func TestWiring_ManifestIsStillTheLastEntryWritten(t *testing.T) {
	// It carries the counts, so anything added after it would not be
	// counted. Everything the backup builder adds must precede it.
	src := readSource(t, "server.go")
	start := strings.Index(src, "func WriteBackupZip(")
	if start == -1 {
		t.Fatal("WriteBackupZip not found")
	}
	body := src[start:]
	if end := strings.Index(body[1:], "\nfunc "); end != -1 {
		body = body[:end+1]
	}
	manifest := strings.Index(body, `writeJSONEntry(zw, "manifest.json"`)
	if manifest == -1 {
		t.Fatal("manifest.json is not written by WriteBackupZip")
	}
	after := body[manifest+len(`writeJSONEntry(zw, "manifest.json"`):]
	for _, call := range []string{"zw.Create(", "storeEntry(zw,", "writeJSONEntry(zw,", "in.ExtraTables("} {
		if strings.Contains(after, call) {
			t.Errorf("%s runs after manifest.json, so its entries are uncounted", call)
		}
	}
}

func TestWiring_TrackAndPhotoPathShapesStillGateTheDownloader(t *testing.T) {
	// RLS guarantees ownership; these keep a corrupt or legacy row from
	// feeding an unconstrained string to the service-role downloader.
	src := readSource(t, "server.go")
	for _, guard := range []string{"hasCanonicalTrack(r)", "hasCanonicalHr(r)", "isSafeStoragePath(sp)", "isSafeStoragePath(key)"} {
		if !strings.Contains(src, guard) {
			t.Errorf("path-shape assertion %s is gone", guard)
		}
	}
}

func TestWiring_ArtifactLandsInTheExportsBucket(t *testing.T) {
	// `file_size_limit` is per bucket. `runs` caps an object at 25 MB,
	// which on a full-history backup is a tighter ceiling than either cap
	// this change removed — and storage-api enforces it for service_role
	// too, so the subject got a failed upload rather than a short archive.
	if !strings.Contains(readSource(t, "../supabase_resumable.go"), "bucket:      schema.BucketExports") {
		t.Error("the upload must target the exports bucket")
	}
	if !strings.Contains(readSource(t, "../supabase.go"), `"/storage/v1/object/sign/" + schema.BucketExports`) {
		t.Error("the signed URL must be minted on the same bucket the artifact was written to")
	}
	// The orphan sweep must still skip the legacy in-`runs` export prefix,
	// or an export would archive a previous export.
	if !strings.Contains(readSource(t, "server.go"), `strings.HasPrefix(rel, "exports/")`) {
		t.Error("the orphan sweep must still skip prior export artifacts")
	}
}
