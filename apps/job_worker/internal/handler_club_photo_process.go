package internal

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/Absence0760/project-running/apps/job_worker/internal/exif"
)

// handleClubPhotoProcess is the club_photos sibling of handlePhotoProcess.
// Enqueued by the `club_photos` triggers (migration
// `20270301_001_club_photos.sql`) and dispatched by `Worker.dispatch`. Same
// contract as the run-photo handler, against the `club-photos` bucket +
// `club_photos` table:
//
//  1. Download the row's `storage_path` from the `club-photos` bucket.
//  2. If JPEG: strip every APP1 (EXIF) / COM segment — defence in depth.
//     The web + mobile clients already strip client-side before upload
//     (exif_strip.ts stripExifFromFile / exif_strip.dart stripJpegExif),
//     but a buggy or hostile client could skip it, and a club's photos are
//     visible to non-members when the club is public.
//  3. Generate a 512w gallery thumbnail from the stripped bytes and upload
//     it alongside the original at `{owner}/{photo_id}_512.jpg`; PATCH the
//     club_photos row's thumb_512_path so clients prefer the smaller file.
//  4. Non-JPEG (PNG/WebP/HEIC): no-op + finish done, exactly like run photos.
//
// Error semantics match handlePhotoProcess: bad payload / empty path /
// JPEG parse error → permanent; storage 5xx → transient via the standard
// classifier. Idempotent — re-running on already-stripped bytes re-uploads
// identical bytes and re-PATCHes the same path.
func (w *Worker) handleClubPhotoProcess(ctx context.Context, job *Job) error {
	var p PhotoProcessPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("club_photo_process: bad payload: %w", err)
	}
	if p.StoragePath == "" {
		return fmt.Errorf("club_photo_process: empty storage_path in payload")
	}

	body, contentType, err := w.Backend.DownloadClubPhoto(ctx, p.StoragePath)
	if err != nil {
		return fmt.Errorf("club_photo_process: download %s: %w", p.StoragePath, err)
	}

	if !exif.IsJPEG(body) {
		return nil
	}

	stripped, err := exif.StripJPEG(body)
	if err != nil {
		return fmt.Errorf("club_photo_process: strip %s: %w", p.StoragePath, err)
	}

	if contentType == "" {
		contentType = "image/jpeg"
	}

	if err := w.Backend.UploadClubPhoto(ctx, p.StoragePath, stripped, contentType); err != nil {
		return fmt.Errorf("club_photo_process: upload %s: %w", p.StoragePath, err)
	}

	thumb, resized, err := exif.ThumbnailJPEG(stripped, 512, 85)
	if err != nil {
		return fmt.Errorf("club_photo_process: thumbnail %s: %w", p.StoragePath, err)
	}
	if !resized {
		return nil
	}
	thumbPath := thumbnailPath(p.StoragePath)
	if err := w.Backend.UploadClubPhoto(ctx, thumbPath, thumb, "image/jpeg"); err != nil {
		return fmt.Errorf("club_photo_process: upload thumb %s: %w", thumbPath, err)
	}
	if err := w.Backend.UpdateClubPhotoThumb512Path(ctx, p.PhotoID, thumbPath); err != nil {
		return fmt.Errorf("club_photo_process: patch thumb_512_path %s: %w", p.PhotoID, err)
	}
	return nil
}
