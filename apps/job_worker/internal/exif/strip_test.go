package exif

import (
	"bytes"
	"encoding/binary"
	"testing"
)

// buildJPEG synthesises a minimal-but-valid JPEG byte stream with the
// markers passed in `segments`. Each segment is a (marker, payload)
// pair; the helper writes the 2-byte length prefix automatically.
// SOI is prepended, EOI is appended. SOS payload is followed by raw
// entropy-coded bytes plus EOI.
//
// The point is to exercise StripJPEG against a bytes-exact input
// without depending on a real photo fixture (which would either be
// huge, or non-deterministic, or both).
func buildJPEG(segments []seg, entropy []byte) []byte {
	var buf bytes.Buffer
	buf.Write([]byte{0xFF, 0xD8}) // SOI
	for _, s := range segments {
		buf.Write([]byte{0xFF, s.marker})
		// length includes its own 2 bytes
		lenBuf := make([]byte, 2)
		binary.BigEndian.PutUint16(lenBuf, uint16(len(s.payload)+2))
		buf.Write(lenBuf)
		buf.Write(s.payload)
	}
	if entropy != nil {
		buf.Write(entropy)
	}
	buf.Write([]byte{0xFF, 0xD9}) // EOI
	return buf.Bytes()
}

type seg struct {
	marker  byte
	payload []byte
}

func TestStripJPEG_NotJPEG(t *testing.T) {
	cases := [][]byte{
		nil,
		{},
		{0xFF},
		{0x89, 0x50, 0x4E, 0x47}, // PNG magic
		{0x00, 0x00},
	}
	for _, in := range cases {
		_, err := StripJPEG(in)
		if err != ErrNotJPEG {
			t.Errorf("StripJPEG(%x): expected ErrNotJPEG, got %v", in, err)
		}
	}
}

func TestStripJPEG_RemovesAPP1_EXIF(t *testing.T) {
	// EXIF carries the GPS / timestamp payload that this whole feature
	// exists to remove. APP1's payload conventionally begins with
	// "Exif\x00\x00" + TIFF header; the marker walker doesn't care
	// about that — it just deletes the whole APPn segment.
	const sosMarker = 0xDA
	const sofMarker = 0xC0
	in := buildJPEG([]seg{
		{marker: 0xE0, payload: []byte("JFIF\x00\x01\x01")}, // APP0 JFIF
		{marker: 0xE1, payload: append([]byte("Exif\x00\x00"), bytes.Repeat([]byte{0xAB}, 256)...)},
		{marker: sofMarker, payload: bytes.Repeat([]byte{0x11}, 14)},
		{marker: sosMarker, payload: bytes.Repeat([]byte{0x22}, 10)},
	}, []byte{0x33, 0x44, 0x55})

	out, err := StripJPEG(in)
	if err != nil {
		t.Fatalf("StripJPEG: %v", err)
	}
	// APP0 ("JFIF") and APP1 ("Exif") must both be gone.
	if bytes.Contains(out, []byte("Exif")) {
		t.Error("output still contains EXIF payload")
	}
	if bytes.Contains(out, []byte("JFIF")) {
		t.Error("output still contains JFIF payload")
	}
	// SOF + SOS + entropy must survive.
	if !bytes.Contains(out, []byte{0xFF, sofMarker}) {
		t.Error("output is missing SOF marker")
	}
	if !bytes.Contains(out, []byte{0xFF, sosMarker}) {
		t.Error("output is missing SOS marker")
	}
	if !bytes.Contains(out, []byte{0x33, 0x44, 0x55}) {
		t.Error("output is missing entropy-coded image data")
	}
	// SOI + EOI bookends must remain.
	if !bytes.HasPrefix(out, []byte{0xFF, 0xD8}) {
		t.Error("output is missing SOI")
	}
	if !bytes.HasSuffix(out, []byte{0xFF, 0xD9}) {
		t.Error("output is missing EOI")
	}
}

func TestStripJPEG_Idempotent(t *testing.T) {
	in := buildJPEG([]seg{
		{marker: 0xE0, payload: []byte("JFIF\x00\x01\x01")},
		{marker: 0xE1, payload: []byte("Exif payload")},
		{marker: 0xC0, payload: []byte{0x11, 0x22, 0x33}},
		{marker: 0xDA, payload: []byte{0x44}},
	}, []byte{0x55, 0x66})

	first, err := StripJPEG(in)
	if err != nil {
		t.Fatalf("first strip: %v", err)
	}
	second, err := StripJPEG(first)
	if err != nil {
		t.Fatalf("second strip: %v", err)
	}
	if !bytes.Equal(first, second) {
		t.Error("StripJPEG is not idempotent — running twice produced different bytes")
	}
}

func TestStripJPEG_KeepsAllNonAPPSegments(t *testing.T) {
	// SOF0, DHT, DQT, DRI are the "real" segments the decoder needs.
	// None of them carry identifying metadata; all must survive.
	const dht = 0xC4
	const dqt = 0xDB
	const dri = 0xDD
	const sof = 0xC0
	in := buildJPEG([]seg{
		{marker: dqt, payload: bytes.Repeat([]byte{0x10}, 64)},
		{marker: dht, payload: bytes.Repeat([]byte{0x20}, 32)},
		{marker: dri, payload: []byte{0x00, 0x08}},
		{marker: sof, payload: bytes.Repeat([]byte{0x30}, 14)},
		{marker: 0xDA, payload: bytes.Repeat([]byte{0x40}, 10)},
	}, []byte{0xFF, 0x00, 0xAB}) // 0xFF 0x00 is a stuffed-byte; must pass through

	out, err := StripJPEG(in)
	if err != nil {
		t.Fatalf("StripJPEG: %v", err)
	}
	for _, m := range []byte{dqt, dht, dri, sof} {
		if !bytes.Contains(out, []byte{0xFF, m}) {
			t.Errorf("output is missing marker 0xFF%02X", m)
		}
	}
	// Stuffed FF00 must round-trip — without it a viewer would decode
	// an FF as a marker prefix and reject the image.
	if !bytes.Contains(out, []byte{0xFF, 0x00, 0xAB}) {
		t.Error("output dropped the FF00 stuffed byte from the entropy stream")
	}
}

func TestStripJPEG_RemovesAllAPPn(t *testing.T) {
	// One segment per APPn marker plus a COM. Every one of them is
	// known to carry vendor or user metadata.
	var segs []seg
	for m := byte(0xE0); m <= 0xEF; m++ {
		segs = append(segs, seg{marker: m, payload: []byte{byte(m), 0xAA, 0xBB}})
	}
	segs = append(segs, seg{marker: 0xFE, payload: []byte("Photoshop CS6")})
	segs = append(segs,
		seg{marker: 0xC0, payload: []byte{0x11}},
		seg{marker: 0xDA, payload: []byte{0x22}},
	)
	in := buildJPEG(segs, []byte{0x33})

	out, err := StripJPEG(in)
	if err != nil {
		t.Fatalf("StripJPEG: %v", err)
	}
	for m := byte(0xE0); m <= 0xEF; m++ {
		if bytes.Contains(out, []byte{0xFF, m}) {
			t.Errorf("output still contains APPn marker 0xFF%02X", m)
		}
	}
	if bytes.Contains(out, []byte{0xFF, 0xFE}) {
		t.Error("output still contains COM marker")
	}
	if bytes.Contains(out, []byte("Photoshop")) {
		t.Error("output still contains COM payload (Photoshop signature)")
	}
}

func TestStripJPEG_Truncated(t *testing.T) {
	// JPEG that starts but never has SOS or EOI.
	in := []byte{0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0xFF}
	if _, err := StripJPEG(in); err == nil {
		t.Error("expected ErrTruncated on segment-length overflow, got nil")
	}
	// JPEG missing EOI entirely.
	in = []byte{0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x04, 0x11, 0x22}
	if _, err := StripJPEG(in); err == nil {
		t.Error("expected ErrTruncated when EOI is missing, got nil")
	}
}

func TestIsJPEG(t *testing.T) {
	if IsJPEG(nil) {
		t.Error("nil should not be JPEG")
	}
	if !IsJPEG([]byte{0xFF, 0xD8, 0xFF, 0xE0}) {
		t.Error("FFD8FFE0 should be detected as JPEG")
	}
	if IsJPEG([]byte{0x89, 0x50, 0x4E, 0x47}) {
		t.Error("PNG magic should not be detected as JPEG")
	}
}
