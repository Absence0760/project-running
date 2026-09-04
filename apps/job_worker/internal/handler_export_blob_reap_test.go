package internal

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

func reapBackend(objects ...StorageObject) *fakeBackend {
	return &fakeBackend{
		storageObjects: map[string][]StorageObject{schema.BucketExports: objects},
	}
}

func obj(path string, age time.Duration) StorageObject {
	return StorageObject{Path: path, CreatedAt: time.Now().Add(-age)}
}

func reapJob(t *testing.T, p ExportBlobReapPayload) *Job {
	t.Helper()
	b, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	return &Job{Kind: "export_blob_reap", Payload: b}
}

func TestExportBlobReap_ErasesOnlyObjectsPastTheWindow(t *testing.T) {
	be := reapBackend(
		obj("u1/exports/old.zip", 8*24*time.Hour),
		obj("u1/exports/fresh.zip", 1*time.Hour),
		obj("u2/exports/ancient.zip", 400*24*time.Hour),
	)
	w := newTestWorker(be, nil)

	if err := w.handleExportBlobReap(context.Background(), reapJob(t, ExportBlobReapPayload{})); err != nil {
		t.Fatalf("handleExportBlobReap: %v", err)
	}

	if len(be.storageDeleted) != 1 {
		t.Fatalf("DELETE calls = %d, want 1: %v", len(be.storageDeleted), be.storageDeleted)
	}
	got := be.storageDeleted[0]
	if len(got) != 2 || !slicesContains(got, "u1/exports/old.zip") || !slicesContains(got, "u2/exports/ancient.zip") {
		t.Fatalf("deleted %v, want the two objects past the 7-day window", got)
	}
	left := be.storageObjects[schema.BucketExports]
	if len(left) != 1 || left[0].Path != "u1/exports/fresh.zip" {
		t.Fatalf("bucket left holding %v, want only the fresh archive", left)
	}
}

// A row the sweep would delete and a byte the reaper would erase are the same
// window, so the default has to be the SQL sweep's. A reaper running long
// leaves the SQL half deleting rows for objects nothing erased, which is the
// state decisions § 1049 measured.
func TestExportBlobReap_DefaultWindowMatchesTheSqlSweep(t *testing.T) {
	if ExportReapRetentionDays != 7 {
		t.Fatalf("ExportReapRetentionDays = %d; cleanup_stale_export_blobs() sweeps at 7 days",
			ExportReapRetentionDays)
	}
	be := reapBackend(
		obj("u1/exports/just-inside.zip", 7*24*time.Hour-time.Minute),
		obj("u1/exports/just-outside.zip", 7*24*time.Hour+time.Minute),
	)
	w := newTestWorker(be, nil)
	if err := w.handleExportBlobReap(context.Background(), reapJob(t, ExportBlobReapPayload{})); err != nil {
		t.Fatalf("handleExportBlobReap: %v", err)
	}
	if len(be.storageDeleted) != 1 || len(be.storageDeleted[0]) != 1 ||
		be.storageDeleted[0][0] != "u1/exports/just-outside.zip" {
		t.Fatalf("deleted %v, want only the object past the boundary", be.storageDeleted)
	}
}

// A zero creation time is "the API did not say", not "very old". Reading it as
// an age deletes an Art 20 archive whose age was never established.
func TestExportBlobReap_SkipsAnObjectWithNoCreationTime(t *testing.T) {
	be := reapBackend(
		StorageObject{Path: "u1/exports/unknown-age.zip"},
		obj("u1/exports/old.zip", 30*24*time.Hour),
	)
	w := newTestWorker(be, nil)

	res, err := w.reapStorageObjectsBefore(context.Background(), schema.BucketExports, "", time.Now())
	if err != nil {
		t.Fatalf("reap: %v", err)
	}
	if res.Skipped != 1 || res.Deleted != 1 {
		t.Fatalf("res = %+v, want 1 skipped and 1 deleted", res)
	}
	if be.storageDeleted[0][0] != "u1/exports/old.zip" {
		t.Fatalf("deleted %v, want the dated object only", be.storageDeleted)
	}
}

// A payload that lost its retention field must not erase the whole bucket.
func TestExportBlobReap_NonPositiveRetentionFallsBackToTheDefault(t *testing.T) {
	for _, days := range []int{0, -1} {
		be := reapBackend(obj("u1/exports/fresh.zip", time.Hour))
		w := newTestWorker(be, nil)
		if err := w.handleExportBlobReap(context.Background(),
			reapJob(t, ExportBlobReapPayload{RetentionDays: days})); err != nil {
			t.Fatalf("retention_days=%d: %v", days, err)
		}
		if len(be.storageDeleted) != 0 {
			t.Fatalf("retention_days=%d erased %v; a missing window must not mean 'reap everything'",
				days, be.storageDeleted)
		}
	}
}

func TestExportBlobReap_BatchesTheDelete(t *testing.T) {
	var objects []StorageObject
	for i := 0; i < ExportReapBatchSize+5; i++ {
		objects = append(objects, obj("u1/exports/"+strings.Repeat("a", i+1)+".zip", 30*24*time.Hour))
	}
	be := reapBackend(objects...)
	w := newTestWorker(be, nil)

	if err := w.handleExportBlobReap(context.Background(), reapJob(t, ExportBlobReapPayload{})); err != nil {
		t.Fatalf("handleExportBlobReap: %v", err)
	}
	if len(be.storageDeleted) != 2 {
		t.Fatalf("DELETE calls = %d, want 2 for %d objects at a batch of %d",
			len(be.storageDeleted), len(objects), ExportReapBatchSize)
	}
	if len(be.storageDeleted[0]) != ExportReapBatchSize || len(be.storageDeleted[1]) != 5 {
		t.Fatalf("batch sizes = %d, %d", len(be.storageDeleted[0]), len(be.storageDeleted[1]))
	}
}

// A failed batch keeps the erasures already made and says how many they were.
// Reporting a whole failed night would hide the ones that did land, and the
// next attempt re-lists so it cannot repeat them.
func TestExportBlobReap_ReportsPartialProgressOnADeleteFailure(t *testing.T) {
	var objects []StorageObject
	for i := 0; i < ExportReapBatchSize+5; i++ {
		objects = append(objects, obj("u1/exports/"+strings.Repeat("a", i+1)+".zip", 30*24*time.Hour))
	}
	be := reapBackend(objects...)
	be.storageDeleteErrAfter = 1
	w := newTestWorker(be, nil)

	res, err := w.reapStorageObjectsBefore(context.Background(), schema.BucketExports, "", time.Now())
	if err == nil {
		t.Fatal("a refused DELETE must fail the job")
	}
	if res.Deleted != ExportReapBatchSize {
		t.Fatalf("res.Deleted = %d, want the first batch", res.Deleted)
	}
	if !strings.Contains(err.Error(), "already erased") {
		t.Fatalf("error does not report the progress made: %v", err)
	}
}

func TestExportBlobReap_ListFailureFailsTheJob(t *testing.T) {
	be := reapBackend()
	be.storageListErr = context.DeadlineExceeded
	w := newTestWorker(be, nil)
	if err := w.handleExportBlobReap(context.Background(), reapJob(t, ExportBlobReapPayload{})); err == nil {
		t.Fatal("a list failure must fail the job rather than report an empty sweep")
	}
}

func TestExportBlobReap_BadPayloadFails(t *testing.T) {
	w := newTestWorker(reapBackend(), nil)
	err := w.handleExportBlobReap(context.Background(), &Job{Kind: "export_blob_reap", Payload: []byte("~")})
	if err == nil || !strings.Contains(err.Error(), "bad payload") {
		t.Fatalf("err = %v, want a bad-payload failure", err)
	}
}

// An empty payload is what a nightly schedule enqueues, and it must mean the
// exports bucket at the default window rather than nothing at all.
func TestExportBlobReap_EmptyPayloadReapsTheExportsBucket(t *testing.T) {
	be := reapBackend(obj("u1/exports/old.zip", 30*24*time.Hour))
	w := newTestWorker(be, nil)
	if err := w.handleExportBlobReap(context.Background(),
		&Job{Kind: "export_blob_reap", Payload: nil}); err != nil {
		t.Fatalf("handleExportBlobReap: %v", err)
	}
	if len(be.storageDeleted) != 1 {
		t.Fatalf("an empty payload swept nothing: %v", be.storageDeleted)
	}
}

// Re-running the sweep is a no-op, which is what makes a retried job safe.
func TestExportBlobReap_IsIdempotent(t *testing.T) {
	be := reapBackend(obj("u1/exports/old.zip", 30*24*time.Hour))
	w := newTestWorker(be, nil)
	for i := 0; i < 2; i++ {
		if err := w.handleExportBlobReap(context.Background(), reapJob(t, ExportBlobReapPayload{})); err != nil {
			t.Fatalf("pass %d: %v", i, err)
		}
	}
	if len(be.storageDeleted) != 1 {
		t.Fatalf("the second pass re-deleted: %v", be.storageDeleted)
	}
}

// The legacy path put archives under runs/<uid>/exports/, which the SQL sweep
// also names. The bucket is a payload field so an operator can reach it.
func TestExportBlobReap_ReapsTheLegacyRunsExportsPrefix(t *testing.T) {
	be := &fakeBackend{storageObjects: map[string][]StorageObject{
		schema.BucketRuns: {
			obj("u1/exports/old.zip", 30*24*time.Hour),
			obj("u1/tracks/old.json.gz", 30*24*time.Hour),
		},
	}}
	w := newTestWorker(be, nil)
	err := w.handleExportBlobReap(context.Background(),
		reapJob(t, ExportBlobReapPayload{Bucket: schema.BucketRuns, Prefix: "u1/exports/"}))
	if err != nil {
		t.Fatalf("handleExportBlobReap: %v", err)
	}
	if len(be.storageDeleted) != 1 || len(be.storageDeleted[0]) != 1 ||
		be.storageDeleted[0][0] != "u1/exports/old.zip" {
		t.Fatalf("deleted %v, want only the export archive — a track is not an export",
			be.storageDeleted)
	}
}

// The selection is on AGE, and every bucket holds objects older than a week.
// Without the artifact predicate a `runs` payload erases the runner's whole
// track history — and unlike the SQL sweep it erases the BYTES, which is the
// entire point of moving the reap to this tier. The prefix is not the guard:
// an operator who omits it, or a schedule that reaps the legacy leg
// bucket-wide rather than per user, must still lose nothing.
func TestExportBlobReap_NeverErasesANonExportObject(t *testing.T) {
	be := &fakeBackend{storageObjects: map[string][]StorageObject{
		schema.BucketRuns: {
			obj("u1/exports/old.zip", 30*24*time.Hour),
			obj("u1/2026-01-01.json.gz", 30*24*time.Hour),
			obj("u2/2025-06-06.json.gz", 400*24*time.Hour),
		},
	}}
	w := newTestWorker(be, nil)

	res, err := w.reapStorageObjectsBefore(context.Background(), schema.BucketRuns, "", time.Now())
	if err != nil {
		t.Fatalf("reap: %v", err)
	}
	if res.NotExport != 2 || res.Deleted != 1 {
		t.Fatalf("res = %+v, want the two tracks passed over and only the archive erased", res)
	}
	if len(be.storageDeleted) != 1 || len(be.storageDeleted[0]) != 1 ||
		be.storageDeleted[0][0] != "u1/exports/old.zip" {
		t.Fatalf("deleted %v — a GPS track is not an export artifact", be.storageDeleted)
	}
}

// A bucket that holds no export artifacts is refused rather than walked. The
// predicate above would already erase nothing there, but a job that lists
// every avatar in the project and reports a successful sweep is a silent
// no-op; the honest answer is that the payload is wrong.
func TestExportBlobReap_RefusesABucketThatHoldsNoExports(t *testing.T) {
	for _, bucket := range []string{schema.BucketRunPhotos, schema.BucketAvatars, ""} {
		be := &fakeBackend{storageObjects: map[string][]StorageObject{
			bucket: {obj("u1/anything.jpg", 400*24*time.Hour)},
		}}
		w := newTestWorker(be, nil)
		_, err := w.reapStorageObjectsBefore(context.Background(), bucket, "", time.Now())
		if err == nil {
			t.Fatalf("bucket %q was walked; it holds no export artifacts", bucket)
		}
		if len(be.storageDeleted) != 0 {
			t.Fatalf("bucket %q: erased %v", bucket, be.storageDeleted)
		}
	}
}

// The predicate is the SQL sweep's, and the two have to name the same set or
// the sweep deletes a row for an object the reaper passed over — which is the
// orphaned-byte state § 1049 measured, reintroduced one bucket over.
func TestExportBlobReap_ArtifactPredicateMatchesTheSqlSweep(t *testing.T) {
	for _, tc := range []struct {
		bucket, path string
		want         bool
	}{
		{schema.BucketExports, "u1/exports/a.zip", true},
		{schema.BucketExports, "anything-at-all", true},
		{schema.BucketRuns, "u1/exports/a.zip", true},
		{schema.BucketRuns, "u1/exports/nested/a.zip", true},
		{schema.BucketRuns, "u1/2026-01-01.json.gz", false},
		{schema.BucketRuns, "exports/a.zip", false},
		{schema.BucketRunPhotos, "u1/exports/a.jpg", false},
	} {
		if got := isExportArtifact(tc.bucket, tc.path); got != tc.want {
			t.Errorf("isExportArtifact(%q, %q) = %v, want %v", tc.bucket, tc.path, got, tc.want)
		}
	}
}
