package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

// These mirror handler_photo_process_test.go against the club handler.
// The club handler hits the club_photos backend methods; the fake
// delegates them onto the same storage map, so the assertions are the
// same shape. The JPEG fixtures + helpers (decodableJPEG*, mustJSON,
// newPhotoTestWorker) live in handler_photo_process_test.go.

func TestHandleClubPhotoProcess_StripsAPP1FromJPEG(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/club_photo.jpg"
	const payloadStr = "Exif\x00\x00THIS IS THE GPS PAYLOAD"
	be.photoByPath[path] = decodableJPEGSmall(t, []byte(payloadStr))
	be.photoContentType = "image/jpeg"

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind: "club_photo_process",
		Payload: mustJSON(PhotoProcessPayload{
			PhotoID:     "cp1",
			StoragePath: path,
			OwnerID:     "alice",
		}),
	}
	if err := w.handleClubPhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handleClubPhotoProcess: %v", err)
	}
	got := be.photoByPath[path]
	if bytes.Contains(got, []byte(payloadStr)) {
		t.Error("stripped club photo still contains the EXIF payload")
	}
	if be.photoUploadedContentType != "image/jpeg" {
		t.Errorf("upload content-type = %q, want image/jpeg", be.photoUploadedContentType)
	}
	if !bytes.HasPrefix(got, []byte{0xFF, 0xD8}) {
		t.Error("stripped club photo lost its SOI")
	}
	if !bytes.HasSuffix(got, []byte{0xFF, 0xD9}) {
		t.Error("stripped club photo lost its EOI")
	}
}

func TestHandleClubPhotoProcess_NonJPEGIsNoOp(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/screenshot.png"
	pngMagic := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
	be.photoByPath[path] = pngMagic
	be.photoContentType = "image/png"

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "club_photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: path}),
	}
	if err := w.handleClubPhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handleClubPhotoProcess: %v", err)
	}
	if be.photoUploadedContentType != "" {
		t.Error("non-JPEG path should not re-upload")
	}
}

func TestHandleClubPhotoProcess_BadPayloadIsPermanent(t *testing.T) {
	w := newPhotoTestWorker(&fakeBackend{})
	job := &Job{Kind: "club_photo_process", Payload: json.RawMessage(`not json`)}
	err := w.handleClubPhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "bad payload") {
		t.Errorf("expected bad-payload error, got %v", err)
	}
}

func TestHandleClubPhotoProcess_EmptyStoragePathIsPermanent(t *testing.T) {
	w := newPhotoTestWorker(&fakeBackend{})
	job := &Job{
		Kind: "club_photo_process",
		Payload: mustJSON(PhotoProcessPayload{
			PhotoID: "cp1", StoragePath: "", OwnerID: "alice",
		}),
	}
	err := w.handleClubPhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "empty storage_path") {
		t.Errorf("expected empty-path error, got %v", err)
	}
}

func TestHandleClubPhotoProcess_DownloadErrorBubblesUp(t *testing.T) {
	be := &fakeBackend{downloadPhotoErr: errors.New("storage 503")}
	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "club_photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: "a/b.jpg"}),
	}
	err := w.handleClubPhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "storage 503") {
		t.Errorf("expected wrapped download error, got %v", err)
	}
}

func TestHandleClubPhotoProcess_UploadErrorBubblesUp(t *testing.T) {
	be := &fakeBackend{
		photoByPath:    map[string][]byte{"a/b.jpg": decodableJPEGSmall(t, []byte("Exif"))},
		uploadPhotoErr: errors.New("storage 503"),
	}
	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "club_photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: "a/b.jpg"}),
	}
	err := w.handleClubPhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "storage 503") {
		t.Errorf("expected wrapped upload error, got %v", err)
	}
}

func TestHandleClubPhotoProcess_GeneratesThumbnail(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/big.jpg"
	be.photoByPath[path] = decodableJPEGLarge(t, []byte("Exif\x00\x00gps"))
	be.photoContentType = "image/jpeg"

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind: "club_photo_process",
		Payload: mustJSON(PhotoProcessPayload{
			PhotoID: "cp9", StoragePath: path, OwnerID: "alice",
		}),
	}
	if err := w.handleClubPhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handleClubPhotoProcess: %v", err)
	}
	const thumbPath = "alice/big_512.jpg"
	if _, ok := be.photoByPath[thumbPath]; !ok {
		t.Errorf("expected thumbnail at %s, have keys %v", thumbPath, keysOf(be.photoByPath))
	}
	if be.photoThumbPaths["cp9"] != thumbPath {
		t.Errorf("thumb_512_path PATCH = %q, want %q", be.photoThumbPaths["cp9"], thumbPath)
	}
}
