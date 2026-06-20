package internal

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/Absence0760/project-running/apps/job_worker/internal/exif"
)

// handleRoutePhotoProcess is the route_photos sibling of handlePhotoProcess.
// Enqueued by the `route_photos` triggers (migration
// `20270224_001_route_photo_thumbnails.sql`) and dispatched by
// `Worker.dispatch`. Same contract as the run-photo handler, against the
// `route-photos` bucket + `route_photos` table:
//
//  1. Download the row's `storage_path` from the `route-photos` bucket.
//  2. If JPEG: strip every APP1 (EXIF) / COM segment — defence in depth.
//     The web + mobile clients already strip client-side before upload
//     (data.ts stripExifFromFile / mobile stripJpegExif), but a buggy or
//     hostile client could skip it, and a route's photos are visible to
//     non-owners when the route is public/club-shared.
//  3. Generate a 512w gallery thumbnail from the stripped bytes and upload
//     it alongside the original at `{owner}/{photo_id}_512.jpg`; PATCH the
//     route_photos row's thumb_512_path so clients prefer the smaller file.
//  4. Non-JPEG (PNG/WebP/HEIC): no-op + finish done, exactly like run photos.
//
// Error semantics match handlePhotoProcess: bad payload / empty path /
// JPEG parse error → permanent; storage 5xx → transient via the standard
// classifier. Idempotent — re-running on already-stripped bytes re-uploads
// identical bytes and re-PATCHes the same path.
func (w *Worker) handleRoutePhotoProcess(ctx context.Context, job *Job) error {
	var p PhotoProcessPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("route_photo_process: bad payload: %w", err)
	}
	if p.StoragePath == "" {
		return fmt.Errorf("route_photo_process: empty storage_path in payload")
	}

	body, contentType, err := w.Backend.DownloadRoutePhoto(ctx, p.StoragePath)
	if err != nil {
		return fmt.Errorf("route_photo_process: download %s: %w", p.StoragePath, err)
	}

	if !exif.IsJPEG(body) {
		return nil
	}

	stripped, err := exif.StripJPEG(body)
	if err != nil {
		return fmt.Errorf("route_photo_process: strip %s: %w", p.StoragePath, err)
	}

	if contentType == "" {
		contentType = "image/jpeg"
	}

	if err := w.Backend.UploadRoutePhoto(ctx, p.StoragePath, stripped, contentType); err != nil {
		return fmt.Errorf("route_photo_process: upload %s: %w", p.StoragePath, err)
	}

	thumb, resized, err := exif.ThumbnailJPEG(stripped, 512, 85)
	if err != nil {
		return fmt.Errorf("route_photo_process: thumbnail %s: %w", p.StoragePath, err)
	}
	if !resized {
		return nil
	}
	thumbPath := thumbnailPath(p.StoragePath)
	if err := w.Backend.UploadRoutePhoto(ctx, thumbPath, thumb, "image/jpeg"); err != nil {
		return fmt.Errorf("route_photo_process: upload thumb %s: %w", thumbPath, err)
	}
	if err := w.Backend.UpdateRoutePhotoThumb512Path(ctx, p.PhotoID, thumbPath); err != nil {
		return fmt.Errorf("route_photo_process: patch thumb_512_path %s: %w", p.PhotoID, err)
	}
	return nil
}
