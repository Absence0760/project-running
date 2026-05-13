// Package exif strips identifying metadata from photo bytes without
// re-encoding. The goal is photo privacy on run_photos uploads: GPS
// coordinates, capture timestamp, camera serial, and ICC profiles
// stored in a photo's EXIF / XMP / IPTC blocks can identify the
// uploader's home address, device, and movements. Server-side
// stripping is what Strava + AllTrails do (the mobile clients can't
// be trusted; even when they try, image libraries on iOS and Android
// re-attach pieces of EXIF on resize).
//
// JPEG is the only format handled here today. Almost all camera-roll
// photos on iOS and Android are JPEG (iOS HEIC is transcoded to JPEG
// by the image_picker plugin before upload). PNG, WebP, and HEIC
// pass through unchanged — the caller's handler decides whether to
// re-upload a no-op result or skip. Adding PNG/WebP support is a
// small extension; HEIC is much bigger and worth deferring until
// it's a real surface.
package exif

import (
	"bytes"
	"encoding/binary"
	"errors"
)

// IsJPEG reports whether the byte slice begins with the JPEG
// Start-Of-Image marker (0xFF 0xD8). Cheap to call before
// dispatching to StripJPEG.
func IsJPEG(b []byte) bool {
	return len(b) >= 2 && b[0] == 0xFF && b[1] == 0xD8
}

// ErrNotJPEG is returned by StripJPEG when the input does not start
// with the JPEG SOI marker.
var ErrNotJPEG = errors.New("exif: not a JPEG (missing FFD8 SOI)")

// ErrTruncated is returned when the JPEG is malformed: a segment
// length runs past the end of the buffer, or SOI/EOI are missing.
// The handler treats this as a permanent failure on the upload —
// no point retrying a corrupt file.
var ErrTruncated = errors.New("exif: truncated JPEG")

// StripJPEG returns a copy of the input with every APP segment
// (FFE0–FFEF) removed and every COM (comment, FFFE) segment removed.
// The image data after SOS is passed through verbatim. The function
// does not re-encode the pixel data, so it's lossless and fast.
//
// What gets stripped:
//   - APP0 (JFIF / JFXX): version + density metadata. Some viewers
//     rely on JFIF; modern decoders all infer it. Stripping keeps the
//     image renderable everywhere we care about (Chrome, Safari,
//     Flutter image, Android ImageView, NSImage).
//   - APP1 (EXIF / XMP): the main payload — GPS, timestamp, camera.
//     This is the whole point.
//   - APP2 (ICC profile / FPXR / MPF): colour profile. Stripping
//     means viewers fall back to sRGB. Worth it: ICC profiles can
//     embed monitor serial numbers and printer calibration history.
//   - APP3–APP15: per-vendor metadata (Samsung tag, Nikon Capture,
//     Adobe Photoshop IRB, etc.). All identifying.
//   - COM (FFFE): free-text comments. Cameras rarely use these but
//     editors do — Photoshop writes its build number here.
//
// What stays:
//   - SOI / EOI / SOF / SOS / DQT / DHT / DRI / RST: everything the
//     decoder actually needs.
//
// Idempotent: running on an already-stripped JPEG produces identical
// output.
func StripJPEG(in []byte) ([]byte, error) {
	if !IsJPEG(in) {
		return nil, ErrNotJPEG
	}
	out := make([]byte, 0, len(in))
	// Always keep SOI.
	out = append(out, 0xFF, 0xD8)
	i := 2
	for i < len(in) {
		// Each segment starts with 0xFF, followed by a marker byte.
		// The decoder pads with extra 0xFF bytes if it wants — skip
		// them.
		if in[i] != 0xFF {
			return nil, ErrTruncated
		}
		for i < len(in) && in[i] == 0xFF {
			i++
		}
		if i >= len(in) {
			return nil, ErrTruncated
		}
		marker := in[i]
		i++

		switch {
		case marker == 0xD9:
			// EOI: end of image. Pass through and we're done.
			out = append(out, 0xFF, 0xD9)
			return out, nil
		case marker == 0xDA:
			// SOS: start of scan. Everything after SOS is entropy-coded
			// image data until EOI; pass it through verbatim. There are
			// no more parsed segments after SOS — the image data may
			// contain 0xFF bytes (they're escaped as 0xFF 0x00 inside
			// the stream), so we can't keep parsing the way we did
			// before. Just copy to EOI.
			sosLen, err := segmentLength(in, i)
			if err != nil {
				return nil, err
			}
			// Header for SOS = marker + length + length bytes.
			if i+sosLen > len(in) {
				return nil, ErrTruncated
			}
			out = append(out, 0xFF, 0xDA)
			out = append(out, in[i:i+sosLen]...)
			i += sosLen
			// Now stream copy until we hit FFD9 (EOI). 0xFF 0x00 stays
			// in the stream; only 0xFF followed by non-zero is a
			// marker. Find EOI by scanning.
			tail := in[i:]
			eoi := bytes.Index(tail, []byte{0xFF, 0xD9})
			if eoi < 0 {
				return nil, ErrTruncated
			}
			out = append(out, tail[:eoi+2]...)
			return out, nil
		case marker == 0x00, marker == 0xD0, marker == 0xD1, marker == 0xD2,
			marker == 0xD3, marker == 0xD4, marker == 0xD5, marker == 0xD6,
			marker == 0xD7, marker == 0xD8:
			// Standalone markers with no payload. RST0–RST7 + the
			// escaped 0xFF 0x00 inside the entropy stream (we don't
			// expect to see those outside SOS, but tolerate them).
			out = append(out, 0xFF, marker)
		case isAppMarker(marker) || marker == 0xFE:
			// APP0–APP15 + COM. Skip the whole segment.
			segLen, err := segmentLength(in, i)
			if err != nil {
				return nil, err
			}
			if i+segLen > len(in) {
				return nil, ErrTruncated
			}
			i += segLen
		default:
			// Keep: SOF, DHT, DQT, DRI, etc. — the decoder needs them.
			segLen, err := segmentLength(in, i)
			if err != nil {
				return nil, err
			}
			if i+segLen > len(in) {
				return nil, ErrTruncated
			}
			out = append(out, 0xFF, marker)
			out = append(out, in[i:i+segLen]...)
			i += segLen
		}
	}
	return nil, ErrTruncated
}

// isAppMarker reports whether a marker byte is in the APPn range
// 0xE0–0xEF. APPn segments hold all the identifying metadata —
// EXIF, XMP, ICC, JFIF, vendor-specific tags.
func isAppMarker(m byte) bool {
	return m >= 0xE0 && m <= 0xEF
}

// segmentLength reads the 2-byte big-endian length prefix that
// follows a JPEG marker byte. The length field is inclusive of its
// own two bytes per the JPEG spec.
func segmentLength(in []byte, off int) (int, error) {
	if off+2 > len(in) {
		return 0, ErrTruncated
	}
	return int(binary.BigEndian.Uint16(in[off : off+2])), nil
}
