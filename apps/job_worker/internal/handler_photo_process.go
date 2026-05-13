package internal

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/Absence0760/project-running/apps/job_worker/internal/exif"
)

// handlePhotoProcess strips identifying metadata from a newly-uploaded
// run photo. Enqueued by the `run_photos` AFTER INSERT trigger
// (migration `20260825_001_jobs_kind_allowlist_photo_process.sql`)
// and dispatched by `Worker.dispatch`. Mirrors what Strava and
// AllTrails do server-side to keep GPS coordinates, capture
// timestamps, and camera serials out of photos shared on public
// runs.
//
// Steady-state flow:
//
//  1. Read the row's `storage_path` from the payload.
//  2. Download the bytes from the `run-photos` Storage bucket.
//  3. If the bytes are JPEG: walk the marker stream and drop every
//     APPn (0xE0–0xEF) + COM (0xFE) segment, keeping SOI / SOFn /
//     DHT / DQT / DRI / SOS / EOI verbatim. Re-upload to the same
//     path with `x-upsert: true`. Idempotent — re-running on an
//     already-stripped JPEG produces identical bytes.
//  4. If the bytes are anything else (PNG, WebP, HEIC, …): no-op
//     and finish_job(done). PNG / WebP rarely carry GPS in practice;
//     HEIC is a larger surface that warrants its own implementation.
//
// Error semantics:
//
//   - Missing payload, malformed JSON, empty storage_path → permanent
//     failure. The trigger is the only writer and it always sends
//     these fields; a bad payload is a bug.
//   - Storage download 4xx (e.g. the user deleted the photo between
//     upload and the worker claim) → permanent. No point retrying.
//   - Storage download 5xx / connection error → transient via the
//     standard classifier; defer + retry.
//   - JPEG parse error (ErrTruncated) → permanent. The bytes are
//     corrupt and re-uploading wouldn't help.
//   - Strip-then-upload 5xx → transient.
func (w *Worker) handlePhotoProcess(ctx context.Context, job *Job) error {
	var p PhotoProcessPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("photo_process: bad payload: %w", err)
	}
	if p.StoragePath == "" {
		return fmt.Errorf("photo_process: empty storage_path in payload")
	}

	body, contentType, err := w.Backend.DownloadPhoto(ctx, p.StoragePath)
	if err != nil {
		return fmt.Errorf("photo_process: download %s: %w", p.StoragePath, err)
	}

	// JPEG-only for v1. Non-JPEG paths exit cleanly; the trigger
	// fires on every insert, and we'd rather no-op fast than carry
	// half-built code for formats we haven't tested.
	if !exif.IsJPEG(body) {
		return nil
	}

	stripped, err := exif.StripJPEG(body)
	if err != nil {
		return fmt.Errorf("photo_process: strip %s: %w", p.StoragePath, err)
	}

	// Default the content-type when Storage omits it. The original
	// upload from the mobile client sets it, but a re-uploaded blob
	// could lose the header — fall back to image/jpeg since IsJPEG
	// just confirmed the magic.
	if contentType == "" {
		contentType = "image/jpeg"
	}

	if err := w.Backend.UploadPhoto(ctx, p.StoragePath, stripped, contentType); err != nil {
		return fmt.Errorf("photo_process: upload %s: %w", p.StoragePath, err)
	}
	return nil
}
