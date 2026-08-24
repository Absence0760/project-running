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
	src := readSource(t, "server.go")
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
	src := readSource(t, "server.go")
	abort := strings.Index(src, "sink.Abort()")
	sign := strings.Index(src, "CreateSignedURL(r.Context()")
	if abort == -1 {
		t.Fatal("the failure path must abort the upload session")
	}
	if sign == -1 {
		t.Fatal("signed-URL call not found")
	}
	if abort > sign {
		t.Error("the abort must precede the signing path: an archive that stopped " +
			"half-way must not exist, let alone be handed to the caller")
	}
	finish := strings.Index(src, "sink.Finish()")
	if finish == -1 || finish > sign {
		t.Error("the signed URL must only be minted after the upload finalises, or it signs a nonexistent object")
	}
}

func TestWiring_ResponseCompletenessFoldsInEverySection(t *testing.T) {
	src := readSource(t, "server.go")
	if !strings.Contains(src, `"complete":   built.Completeness.IsComplete()`) {
		t.Error("a section that came up short must not be reported as a complete export")
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
