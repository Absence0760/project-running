package exif

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"

	"golang.org/x/image/draw"
)

// ThumbnailJPEG decodes a JPEG, resizes it so the longer side is at
// most [maxLongSide] pixels (preserving aspect ratio), and re-encodes
// at [quality] (use 85 for the gallery-thumbnail sweet spot — visually
// indistinguishable from 95 at small sizes, ~30% smaller on wire).
// Returns (nil, false, nil) when the input is already smaller than
// the target — clients can fall back to the original in that case
// so we don't waste storage on a redundant copy.
//
// CatmullRom is used over ApproxBiLinear because the input is photo
// content (~4032×3024) being shrunk by ~8x. Bilinear gets blurry at
// that ratio; CatmullRom keeps edges crisp at maybe 3× the CPU.
// Worker latency for one 8MP JPEG → 512w resize is ~50ms on a
// commodity Fly.io shared-cpu-1x; well within the job-handler budget.
func ThumbnailJPEG(in []byte, maxLongSide int, quality int) ([]byte, bool, error) {
	if maxLongSide <= 0 {
		return nil, false, fmt.Errorf("exif: maxLongSide must be > 0")
	}
	src, err := jpeg.Decode(bytes.NewReader(in))
	if err != nil {
		return nil, false, fmt.Errorf("exif: jpeg decode: %w", err)
	}
	srcBounds := src.Bounds()
	srcW := srcBounds.Dx()
	srcH := srcBounds.Dy()
	longSide := srcW
	if srcH > srcW {
		longSide = srcH
	}
	if longSide <= maxLongSide {
		// Already small enough — nothing to do. Caller falls back to
		// the original on read.
		return nil, false, nil
	}
	// Preserve aspect ratio. Integer math drops the half-pixel, fine
	// at this scale — but it truncates to ZERO for an extreme aspect ratio
	// (a 4000x3 panorama gives dstH = 3*512/4000 = 0), and image.NewRGBA of a
	// zero-height rect encodes to a valid-looking 591-byte JPEG that decodes
	// 0x0. That was then uploaded and recorded as thumb_512_path, so clients
	// rendered a blank tile instead of taking the documented fallback to the
	// original. Clamp to one pixel: a 512x1 strip is a poor thumbnail but an
	// honest one.
	var dstW, dstH int
	if srcW >= srcH {
		dstW = maxLongSide
		dstH = max(1, srcH*maxLongSide/srcW)
	} else {
		dstH = maxLongSide
		dstW = max(1, srcW*maxLongSide/srcH)
	}
	dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))
	draw.CatmullRom.Scale(dst, dst.Bounds(), src, srcBounds, draw.Over, nil)

	var out bytes.Buffer
	if err := jpeg.Encode(&out, dst, &jpeg.Options{Quality: quality}); err != nil {
		return nil, false, fmt.Errorf("exif: jpeg encode: %w", err)
	}
	return out.Bytes(), true, nil
}
