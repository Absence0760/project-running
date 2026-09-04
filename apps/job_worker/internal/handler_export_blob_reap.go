package internal

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

// The Art 20 export retention reaper (kind='export_blob_reap').
//
// `cleanup_stale_export_blobs()` deletes rows from `storage.objects`, and
// decisions § 1049 measured what that buys: the archive stops being listable
// and the bytes stay on the backend with a matching sha256. The SQL tier
// cannot buy more than that — a row delete is not an object delete, which is
// why storage-api ships a trigger refusing one. Only the Storage API erases,
// and the worker is the tier that already holds the service key and already
// writes these archives through it.
//
// The reaper derives its own worklist rather than being handed one. That is
// the ordering problem § 1049 named: once the row is gone nothing in the
// database knows the object exists, so a reaper fed by the SQL sweep must run
// inside the same transaction and BEFORE the delete, and one that runs after
// is reaping a list nobody can produce. Listing the bucket needs neither — the
// list API reads the same rows, so running the reap first makes the row delete
// redundant rather than load-bearing.
//
// What it does NOT recover: objects whose rows a previous sweep already
// deleted. Those are unreachable through the Storage API by construction
// (list reads `storage.objects`), and need a bucket lifecycle rule or direct
// backend access instead.

const (
	// ExportReapRetentionDays mirrors the window `cleanup_stale_export_blobs()`
	// sweeps on. The two must agree: a reaper with a LONGER window leaves the
	// SQL sweep deleting rows for objects it has not erased, which is the
	// state § 1049 measured.
	ExportReapRetentionDays = 7

	// ExportReapBatchSize bounds one DELETE body. The multi-object form takes
	// a list, and an unbounded one turns a backlog into a single request whose
	// failure loses the whole night's progress.
	ExportReapBatchSize = 100
)

// ExportBlobReapPayload is what the enqueue writes. Every field is optional:
// an empty payload reaps the `exports` bucket at the default window, which is
// what a nightly schedule wants to say.
type ExportBlobReapPayload struct {
	// Bucket defaults to the exports bucket, and may only name a bucket
	// that holds export artifacts. See isExportArtifact.
	Bucket string `json:"bucket"`
	// Prefix scopes the walk. Empty walks the whole bucket.
	Prefix string `json:"prefix"`
	// RetentionDays defaults to ExportReapRetentionDays. Zero or negative is
	// read as absent rather than as "reap everything": a payload that lost a
	// field must not erase every archive in the bucket.
	RetentionDays int `json:"retention_days"`
}

// ExportReapResult reports what one sweep did, so the caller can log a fact.
type ExportReapResult struct {
	Listed    int
	NotExport int
	Expired   int
	Deleted   int
	Skipped   int
}

// handleExportBlobReap erases export archives past the retention window.
func (w *Worker) handleExportBlobReap(ctx context.Context, job *Job) error {
	var p ExportBlobReapPayload
	if len(job.Payload) > 0 {
		if err := json.Unmarshal(job.Payload, &p); err != nil {
			return fmt.Errorf("export_blob_reap: bad payload: %w", err)
		}
	}
	bucket := p.Bucket
	if bucket == "" {
		bucket = schema.BucketExports
	}
	days := p.RetentionDays
	if days <= 0 {
		days = ExportReapRetentionDays
	}
	cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour)

	res, err := w.reapStorageObjectsBefore(ctx, bucket, p.Prefix, cutoff)
	if err != nil {
		return err
	}
	w.Log.Info("export blob reap",
		"bucket", bucket,
		"prefix", p.Prefix,
		"cutoff", cutoff.UTC().Format(time.RFC3339),
		"listed", res.Listed,
		"not_an_export", res.NotExport,
		"expired", res.Expired,
		"deleted", res.Deleted,
		"skipped_unknown_age", res.Skipped)
	return nil
}

// reapStorageObjectsBefore lists a bucket, selects the objects created before
// `cutoff`, and deletes them in bounded batches.
//
// An object whose creation time the list API did not report is SKIPPED, not
// deleted. A zero time compares as older than every cutoff, so reading it as
// an age would erase an archive whose age was never established — a Art 20
// artifact the subject may still be waiting to download.
func (w *Worker) reapStorageObjectsBefore(ctx context.Context, bucket, prefix string, cutoff time.Time) (ExportReapResult, error) {
	var res ExportReapResult
	if bucket != schema.BucketExports && bucket != schema.BucketRuns {
		return res, fmt.Errorf("export_blob_reap: %q holds no export artifacts", bucket)
	}
	entries, err := w.Backend.ListStorageObjectsWithMeta(ctx, bucket, prefix)
	if err != nil {
		return res, fmt.Errorf("export_blob_reap: list %s: %w", bucket, err)
	}
	res.Listed = len(entries)

	var stale []string
	for _, e := range entries {
		if !isExportArtifact(bucket, e.Path) {
			res.NotExport++
			continue
		}
		if e.CreatedAt.IsZero() {
			res.Skipped++
			continue
		}
		if e.CreatedAt.Before(cutoff) {
			stale = append(stale, e.Path)
		}
	}
	res.Expired = len(stale)

	for start := 0; start < len(stale); start += ExportReapBatchSize {
		end := start + ExportReapBatchSize
		if end > len(stale) {
			end = len(stale)
		}
		batch := stale[start:end]
		if err := w.Backend.DeleteStorageObjects(ctx, bucket, batch); err != nil {
			// Partial progress is kept deliberately: the deletes already
			// applied are erasures, and a retry re-lists so it cannot repeat
			// them. Returning the count with the error lets the caller say how
			// far it got rather than reporting a whole failed night.
			return res, fmt.Errorf("export_blob_reap: delete %d object(s) from %s (%d already erased): %w",
				len(batch), bucket, res.Deleted, err)
		}
		res.Deleted += len(batch)
	}
	return res, nil
}

// isExportArtifact mirrors `cleanup_stale_export_blobs()`'s own predicate,
// `(bucket_id = 'runs' and name like '%/exports/%') or bucket_id = 'exports'`.
//
// It is what stands between this job and the rest of Storage. The reaper
// selects on AGE alone, and every bucket holds objects older than a week: a
// payload naming `runs` without it erases every GPS track the runner has, and
// the byte is gone in the sense § 1049 spent a round establishing the SQL
// sweep could not manage. The `exports` bucket is Art 20 archives by
// construction (20270602_001 created it for them and nothing else writes
// there), so it needs no path test; `runs` holds tracks alongside the legacy
// `{uid}/exports/<ts>.zip` leg, so it needs the same one the SQL has.
func isExportArtifact(bucket, path string) bool {
	switch bucket {
	case schema.BucketExports:
		return true
	case schema.BucketRuns:
		return strings.Contains(path, "/exports/")
	default:
		return false
	}
}
