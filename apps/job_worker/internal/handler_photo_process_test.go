package internal

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"testing"
)

// minimalJPEG synthesises a JPEG byte stream with the requested
// segments. Mirrors exif/strip_test.go's helper. Pulled here too so
// the handler test stays self-contained — depending on a test helper
// across packages would be cleaner but adds a build tag dance.
func minimalJPEG(appPayload []byte) []byte {
	var buf bytes.Buffer
	buf.Write([]byte{0xFF, 0xD8})    // SOI
	// APP1 (EXIF) carrying the payload we expect the handler to strip.
	buf.Write([]byte{0xFF, 0xE1})
	lenBuf := make([]byte, 2)
	binary.BigEndian.PutUint16(lenBuf, uint16(len(appPayload)+2))
	buf.Write(lenBuf)
	buf.Write(appPayload)
	// SOF + DQT + DHT + SOS — enough to be a valid skeleton.
	for _, marker := range []byte{0xC0, 0xDB, 0xC4, 0xDA} {
		buf.Write([]byte{0xFF, marker})
		binary.BigEndian.PutUint16(lenBuf, uint16(2+1))
		buf.Write(lenBuf)
		buf.WriteByte(0x00)
	}
	buf.Write([]byte{0x11, 0x22})    // a couple of entropy bytes
	buf.Write([]byte{0xFF, 0xD9})    // EOI
	return buf.Bytes()
}

func newPhotoTestWorker(be *fakeBackend) *Worker {
	return &Worker{
		Backend: be,
		Log:     slog.New(slog.NewTextHandler(nullWriter{}, nil)),
	}
}

type nullWriter struct{}

func (nullWriter) Write(p []byte) (int, error) { return len(p), nil }

func TestHandlePhotoProcess_StripsAPP1FromJPEG(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/photo123.jpg"
	const payloadStr = "Exif\x00\x00THIS IS THE GPS PAYLOAD"
	be.photoByPath[path] = minimalJPEG([]byte(payloadStr))
	be.photoContentType = "image/jpeg"

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind: "photo_process",
		Payload: mustJSON(PhotoProcessPayload{
			PhotoID:     "p1",
			StoragePath: path,
			OwnerID:     "alice",
		}),
	}
	if err := w.handlePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handlePhotoProcess: %v", err)
	}
	got := be.photoByPath[path]
	if bytes.Contains(got, []byte(payloadStr)) {
		t.Error("stripped photo still contains the EXIF payload")
	}
	// Content-type preserved on re-upload.
	if be.photoUploadedContentType != "image/jpeg" {
		t.Errorf("upload content-type = %q, want image/jpeg",
			be.photoUploadedContentType)
	}
	// Still a valid JPEG — SOI + EOI bookends survive.
	if !bytes.HasPrefix(got, []byte{0xFF, 0xD8}) {
		t.Error("stripped photo lost its SOI")
	}
	if !bytes.HasSuffix(got, []byte{0xFF, 0xD9}) {
		t.Error("stripped photo lost its EOI")
	}
}

func TestHandlePhotoProcess_NonJPEGIsNoOp(t *testing.T) {
	// PNG bytes — handler must finish_job(done) without touching
	// the upload path. Re-encoding a PNG via the JPEG stripper
	// would corrupt it; the no-op check is what protects us.
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/screenshot.png"
	pngMagic := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
	be.photoByPath[path] = pngMagic
	be.photoContentType = "image/png"

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: path}),
	}
	if err := w.handlePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handlePhotoProcess: %v", err)
	}
	// The fake records the most-recent uploaded content type; staying
	// empty proves UploadPhoto was never called.
	if be.photoUploadedContentType != "" {
		t.Error("non-JPEG path should not re-upload")
	}
}

func TestHandlePhotoProcess_BadPayloadIsPermanent(t *testing.T) {
	w := newPhotoTestWorker(&fakeBackend{})
	job := &Job{Kind: "photo_process", Payload: json.RawMessage(`not json`)}
	err := w.handlePhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "bad payload") {
		t.Errorf("expected bad-payload error, got %v", err)
	}
}

func TestHandlePhotoProcess_EmptyStoragePathIsPermanent(t *testing.T) {
	w := newPhotoTestWorker(&fakeBackend{})
	job := &Job{
		Kind: "photo_process",
		Payload: mustJSON(PhotoProcessPayload{
			PhotoID: "p1", StoragePath: "", OwnerID: "alice",
		}),
	}
	err := w.handlePhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "empty storage_path") {
		t.Errorf("expected empty-path error, got %v", err)
	}
}

func TestHandlePhotoProcess_DownloadErrorBubblesUp(t *testing.T) {
	be := &fakeBackend{downloadPhotoErr: errors.New("storage 503")}
	w := newPhotoTestWorker(be)
	job := &Job{
		Kind: "photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: "a/b.jpg"}),
	}
	err := w.handlePhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "storage 503") {
		t.Errorf("expected wrapped download error, got %v", err)
	}
}

func TestHandlePhotoProcess_UploadErrorBubblesUp(t *testing.T) {
	be := &fakeBackend{
		photoByPath:    map[string][]byte{"a/b.jpg": minimalJPEG([]byte("Exif"))},
		uploadPhotoErr: errors.New("storage 503"),
	}
	w := newPhotoTestWorker(be)
	job := &Job{
		Kind: "photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: "a/b.jpg"}),
	}
	err := w.handlePhotoProcess(context.Background(), job)
	if err == nil || !strings.Contains(err.Error(), "storage 503") {
		t.Errorf("expected wrapped upload error, got %v", err)
	}
}

func TestHandlePhotoProcess_DefaultsContentTypeOnReupload(t *testing.T) {
	be := &fakeBackend{
		photoByPath:      map[string][]byte{"a/b.jpg": minimalJPEG([]byte("Exif"))},
		photoContentType: "", // Storage forgot to send Content-Type
	}
	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "photo_process",
		Payload: mustJSON(PhotoProcessPayload{StoragePath: "a/b.jpg"}),
	}
	if err := w.handlePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handlePhotoProcess: %v", err)
	}
	if be.photoUploadedContentType != "image/jpeg" {
		t.Errorf("upload content-type = %q, want image/jpeg fallback",
			be.photoUploadedContentType)
	}
}

func mustJSON(v any) json.RawMessage {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return b
}
