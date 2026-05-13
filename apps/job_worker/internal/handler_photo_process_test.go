package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"log/slog"
	"strings"
	"testing"
)

// decodableJPEG produces a real (decodable) JPEG of the requested
// pixel size with an APP1 (EXIF-like) segment injected after SOI.
// Real bytes are required because the handler's thumbnail step does
// jpeg.Decode → resize → encode; the marker-walker synthetic JPEGs
// from strip_test.go aren't decodable.
//
// The function: render an RGB gradient, jpeg.Encode it, then splice
// the APP1 segment into the encoded byte stream right after SOI.
func decodableJPEG(t *testing.T, w, h int, exifPayload []byte) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{
				R: uint8(x * 255 / w),
				G: uint8(y * 255 / h),
				B: 64,
				A: 255,
			})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90}); err != nil {
		t.Fatalf("encoding fixture: %v", err)
	}
	encoded := buf.Bytes()
	if len(exifPayload) == 0 {
		return encoded
	}
	// Splice APP1 after SOI. encoded[0:2] is SOI; insert
	// 0xFF 0xE1 <len-be> <payload> at position 2.
	var out bytes.Buffer
	out.Write(encoded[:2])
	out.Write([]byte{0xFF, 0xE1, byte((len(exifPayload) + 2) >> 8), byte((len(exifPayload) + 2) & 0xFF)})
	out.Write(exifPayload)
	out.Write(encoded[2:])
	return out.Bytes()
}

// decodableJPEGSmall returns a 100×80 real JPEG with an EXIF segment
// spliced in. Small enough that ThumbnailJPEG decides not to resize
// (≤512 longSide), so the original-strip path is exercised without
// also burning CPU on a 4032w resize during unit tests.
func decodableJPEGSmall(t *testing.T, exifPayload []byte) []byte {
	return decodableJPEG(t, 100, 80, exifPayload)
}

// decodableJPEGLarge returns a 1600×1200 real JPEG with an EXIF
// segment spliced in. Big enough that ThumbnailJPEG triggers a
// resize to 512w. Exercises the full strip + thumb + PATCH path.
func decodableJPEGLarge(t *testing.T, exifPayload []byte) []byte {
	return decodableJPEG(t, 1600, 1200, exifPayload)
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
	be.photoByPath[path] = decodableJPEGSmall(t, []byte(payloadStr))
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
		photoByPath:    map[string][]byte{"a/b.jpg": decodableJPEGSmall(t, []byte("Exif"))},
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
		photoByPath:      map[string][]byte{"a/b.jpg": decodableJPEGSmall(t, []byte("Exif"))},
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

func TestHandlePhotoProcess_GeneratesThumbnailAndPatchesRow(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	const path = "alice/photo123.jpg"
	be.photoByPath[path] = decodableJPEGLarge(t, []byte("Exif\x00\x00gps"))
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
	// Thumbnail uploaded at the expected convention path.
	thumbPath := "alice/photo123_512.jpg"
	if _, ok := be.photoByPath[thumbPath]; !ok {
		t.Errorf("thumbnail not uploaded at %q (uploaded paths: %v)",
			thumbPath, keysOf(be.photoByPath))
	}
	// Row PATCHed with that path.
	if be.photoThumbPaths["p1"] != thumbPath {
		t.Errorf("thumb_512_path PATCH = %q, want %q",
			be.photoThumbPaths["p1"], thumbPath)
	}
	// Thumbnail is meaningfully smaller than the (stripped) original.
	orig := be.photoByPath[path]
	thumb := be.photoByPath[thumbPath]
	if len(thumb) >= len(orig) {
		t.Errorf("thumbnail (%d bytes) is not smaller than original (%d)",
			len(thumb), len(orig))
	}
}

func TestHandlePhotoProcess_SkipsThumbnailForSmallPhotos(t *testing.T) {
	be := &fakeBackend{photoByPath: make(map[string][]byte)}
	be.photoByPath["a/b.jpg"] = decodableJPEGSmall(t, []byte("Exif"))

	w := newPhotoTestWorker(be)
	job := &Job{
		Kind:    "photo_process",
		Payload: mustJSON(PhotoProcessPayload{PhotoID: "p1", StoragePath: "a/b.jpg"}),
	}
	if err := w.handlePhotoProcess(context.Background(), job); err != nil {
		t.Fatalf("handlePhotoProcess: %v", err)
	}
	// No thumbnail file uploaded.
	if _, ok := be.photoByPath["a/b_512.jpg"]; ok {
		t.Error("thumbnail uploaded for an already-small photo")
	}
	// And no PATCH attempted — clients fall back to the original.
	if _, ok := be.photoThumbPaths["p1"]; ok {
		t.Error("row PATCHed even though no thumbnail was generated")
	}
}

func TestThumbnailPathDerivation(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"alice/photo123.jpg", "alice/photo123_512.jpg"},
		{"alice/photo123.JPEG", "alice/photo123_512.JPEG"},
		{"alice/photo123", "alice/photo123_512.jpg"},
		{"alice/sub.dir/photo.jpg", "alice/sub.dir/photo_512.jpg"},
		{"alice/no_extension_with_slash/", "alice/no_extension_with_slash/_512.jpg"},
	}
	for _, c := range cases {
		got := thumbnailPath(c.in)
		if got != c.want {
			t.Errorf("thumbnailPath(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func keysOf(m map[string][]byte) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func mustJSON(v any) json.RawMessage {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return b
}
