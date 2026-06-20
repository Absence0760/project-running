package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

// These mirror handler_photo_process_test.go against the route handler.
// The route handler hits the route_photos backend methods; the fake
// delegates them onto the same storage map, so the assertions are the
// same shape. The JPEG fixtures + helpers (decodableJPEG*, mustJSON,
// keysOf, newPhotoTestWorker) live in handler_photo_process_test.go.

func TestHandleRoutePhotoProcess_StripsAPP1FromJPEG(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/route_photo.jpg"
	const payloadStr = "Exif\x00\x00THIS IS THE GPS PAYLOAD"
	be.photoByPath[path] = decodableJPEGSmall(t, []byte(payloadStr))
	be.photoContentType = "image/jpeg"

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind: "route_photo_process",
		Payload: mustJSON(PhotoProcessPayload{
			PhotoID:     "rp1",
			StoragePath: path,
			OwnerID:     "alice",
		}),
	}
	if err := w.handleRoutePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handleRoutePhotoProcess: %v", err)
	}
	got := be.photoByPath[path]
	if bytes.Contains(got, []byte(payloadStr)) {
		t.Error("stripped route photo still contains the EXIF payload")
	}
	if be.photoUploadedContentType != "image/jpeg" {
		t.Errorf("upload content-type = %q, want image/jpeg", be.photoUploadedContentType)
	}
	if !bytes.HasPrefix(got, []byte{0xFF, 0xD8}) {
		t.Error("stripped route photo lost its SOI")
	}
	if !bytes.HasSuffix(got, []byte{0xFF, 0xD9}) {
		t.Error("stripped route photo lost its EOI")
	}
}

func TestHandleRoutePhotoProcess_NonJPEGIsNoOp(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/screenshot.png"
	pngMagic := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
	be.photoByPath[path] = pngMagic
	be.photoContentType = "image/png"

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "route_photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: path}),
	}
	if err := w.handleRoutePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handleRoutePhotoProcess: %v", err)
	}
	if be.photoUploadedContentType != "" {
		t.Error("non-JPEG path should not re-upload")
	}
}

func TestHandleRoutePhotoProcess_BadPayloadIsPermanent(t *testing.T) {
	w := newPhotoTestWorker(&fakeBackend{})
	job := &Job{Kind: "route_photo_process", Payload: json.RawMessage(`not json`)}
	err := w.handleRoutePhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "bad payload") {
		t.Errorf("expected bad-payload error, got %v", err)
	}
}

func TestHandleRoutePhotoProcess_EmptyStoragePathIsPermanent(t *testing.T) {
	w := newPhotoTestWorker(&fakeBackend{})
	job := &Job{
		Kind: "route_photo_process",
		Payload: mustJSON(PhotoProcessPayload{
			PhotoID: "rp1", StoragePath: "", OwnerID: "alice",
		}),
	}
	err := w.handleRoutePhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "empty storage_path") {
		t.Errorf("expected empty-path error, got %v", err)
	}
}

func TestHandleRoutePhotoProcess_DownloadErrorBubblesUp(t *testing.T) {
	be := &fakeBackend{downloadPhotoErr: errors.New("storage 503")}
	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "route_photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: "a/b.jpg"}),
	}
	err := w.handleRoutePhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "storage 503") {
		t.Errorf("expected wrapped download error, got %v", err)
	}
}

func TestHandleRoutePhotoProcess_UploadErrorBubblesUp(t *testing.T) {
	be := &fakeBackend{
		photoByPath:    map[string][]byte{"a/b.jpg": decodableJPEGSmall(t, []byte("Exif"))},
		uploadPhotoErr: errors.New("storage 503"),
	}
	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "route_photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: "a/b.jpg"}),
	}
	err := w.handleRoutePhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "storage 503") {
		t.Errorf("expected wrapped upload error, got %v", err)
	}
}

func TestHandleRoutePhotoProcess_DefaultsContentTypeOnReupload(t *testing.T) {
	be := &fakeBackend{
		photoByPath:      map[string][]byte{"a/b.jpg": decodableJPEGSmall(t, []byte("Exif"))},
		photoContentType: "",
	}
	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "route_photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: "a/b.jpg"}),
	}
	if err := w.handleRoutePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handleRoutePhotoProcess: %v", err)
	}
	if be.photoUploadedContentType != "image/jpeg" {
		t.Errorf("upload content-type = %q, want image/jpeg fallback", be.photoUploadedContentType)
	}
}

func TestHandleRoutePhotoProcess_GeneratesThumbnailAndPatchesRow(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/route_photo.jpg"
	be.photoByPath[path] = decodableJPEGLarge(t, []byte("Exif\x00\x00gps"))
	be.photoContentType = "image/jpeg"

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind: "route_photo_process",
		Payload: mustJSON(PhotoProcessPayload{
			PhotoID:     "rp1",
			StoragePath: path,
			OwnerID:     "alice",
		}),
	}
	if err := w.handleRoutePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handleRoutePhotoProcess: %v", err)
	}
	thumbPath := "alice/route_photo_512.jpg"
	if _, ok := be.photoByPath[thumbPath]; !ok {
		t.Errorf("thumbnail not uploaded at %q (uploaded paths: %v)", thumbPath, keysOf(be.photoByPath))
	}
	if be.photoThumbPaths["rp1"] != thumbPath {
		t.Errorf("thumb_512_path PATCH = %q, want %q", be.photoThumbPaths["rp1"], thumbPath)
	}
	orig := be.photoByPath[path]
	thumb := be.photoByPath[thumbPath]
	if len(thumb) >= len(orig) {
		t.Errorf("thumbnail (%d bytes) is not smaller than original (%d)", len(thumb), len(orig))
	}
}

func TestHandleRoutePhotoProcess_SkipsThumbnailForSmallPhotos(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	be.photoByPath["a/b.jpg"] = decodableJPEGSmall(t, []byte("Exif"))

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "route_photo_process",
		Payload: mustJSON(PhotoProcessPayload{PhotoID: "rp1", StoragePath: "a/b.jpg"}),
	}
	if err := w.handleRoutePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handleRoutePhotoProcess: %v", err)
	}
	if _, ok := be.photoByPath["a/b_512.jpg"]; ok {
		t.Error("thumbnail uploaded for an already-small route photo")
	}
	if _, ok := be.photoThumbPaths["rp1"]; ok {
		t.Error("row PATCHed even though no thumbnail was generated")
	}
}
