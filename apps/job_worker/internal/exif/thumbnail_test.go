package exif

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"testing"
)

// realJPEG synthesises a small RGB rectangle and encodes it as JPEG
// at the requested width × height. Used as the input to thumbnail
// tests — the synthetic-marker JPEGs in strip_test.go aren't
// decodable since they have no real image data.
func realJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	// Simple gradient so the encoder isn't fed a uniform colour
	// (which JPEG compresses absurdly small and isn't a faithful
	// stand-in for a real photo).
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{
				R: uint8((x * 255) / w),
				G: uint8((y * 255) / h),
				B: 128,
				A: 255,
			})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 85}); err != nil {
		t.Fatalf("encoding fixture: %v", err)
	}
	return buf.Bytes()
}

func TestThumbnailJPEG_ResizesLandscape(t *testing.T) {
	in := realJPEG(t, 4032, 3024)
	out, resized, err := ThumbnailJPEG(in, 512, 85)
	if err != nil {
		t.Fatalf("ThumbnailJPEG: %v", err)
	}
	if !resized {
		t.Fatal("expected resized=true for an oversized input")
	}
	img, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatalf("output isn't a decodable JPEG: %v", err)
	}
	b := img.Bounds()
	if b.Dx() != 512 {
		t.Errorf("landscape long side = %d, want 512", b.Dx())
	}
	// Height should preserve aspect ratio: 3024 * 512 / 4032 = 384.
	if b.Dy() != 384 {
		t.Errorf("landscape short side = %d, want 384", b.Dy())
	}
	if len(out) >= len(in) {
		t.Errorf("thumbnail %d bytes is not smaller than original %d", len(out), len(in))
	}
}

func TestThumbnailJPEG_ResizesPortrait(t *testing.T) {
	in := realJPEG(t, 3024, 4032)
	out, resized, err := ThumbnailJPEG(in, 512, 85)
	if err != nil {
		t.Fatalf("ThumbnailJPEG: %v", err)
	}
	if !resized {
		t.Fatal("expected resized=true for an oversized input")
	}
	img, _ := jpeg.Decode(bytes.NewReader(out))
	b := img.Bounds()
	if b.Dy() != 512 {
		t.Errorf("portrait long side = %d, want 512", b.Dy())
	}
	if b.Dx() != 384 {
		t.Errorf("portrait short side = %d, want 384", b.Dx())
	}
}

func TestThumbnailJPEG_SkipsAlreadySmallImage(t *testing.T) {
	in := realJPEG(t, 200, 150)
	out, resized, err := ThumbnailJPEG(in, 512, 85)
	if err != nil {
		t.Fatalf("ThumbnailJPEG: %v", err)
	}
	if resized {
		t.Error("expected resized=false when input already smaller than target")
	}
	if out != nil {
		t.Error("expected out=nil when no thumbnail was generated")
	}
}

func TestThumbnailJPEG_RejectsNonJPEG(t *testing.T) {
	if _, _, err := ThumbnailJPEG([]byte{0x89, 0x50, 0x4E, 0x47}, 512, 85); err == nil {
		t.Error("expected error decoding non-JPEG input, got nil")
	}
}

func TestThumbnailJPEG_RejectsBadMaxLongSide(t *testing.T) {
	in := realJPEG(t, 100, 100)
	if _, _, err := ThumbnailJPEG(in, 0, 85); err == nil {
		t.Error("expected error for maxLongSide=0")
	}
	if _, _, err := ThumbnailJPEG(in, -10, 85); err == nil {
		t.Error("expected error for negative maxLongSide")
	}
}

func TestThumbnailJPEG_SquareInput(t *testing.T) {
	in := realJPEG(t, 1024, 1024)
	out, resized, err := ThumbnailJPEG(in, 512, 85)
	if err != nil {
		t.Fatalf("ThumbnailJPEG: %v", err)
	}
	if !resized {
		t.Fatal("expected resized=true")
	}
	img, _ := jpeg.Decode(bytes.NewReader(out))
	b := img.Bounds()
	if b.Dx() != 512 || b.Dy() != 512 {
		t.Errorf("square thumbnail = %d×%d, want 512×512", b.Dx(), b.Dy())
	}
}
