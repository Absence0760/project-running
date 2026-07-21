package internal

// HTTP-level coverage for UploadMatchedTrack. The runs bucket carries
// an allowed_mime_types list (application/gzip, application/octet-stream,
// text/csv, application/zip) — an upload declaring application/json is
// rejected with invalid_mime_type, which perma-failed every map_match
// job on the first production deploy. These tests pin the wire shape:
// application/gzip, no Content-Encoding (consumers gunzip explicitly),
// x-upsert for re-matches, and a body that actually gunzips to the
// points JSON.

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"
)

func TestUploadMatchedTrack_WireShape(t *testing.T) {
	var capturedPath, capturedContentType, capturedContentEncoding, capturedUpsert string
	var capturedBody []byte
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path
		capturedContentType = r.Header.Get("Content-Type")
		capturedContentEncoding = r.Header.Get("Content-Encoding")
		capturedUpsert = r.Header.Get("x-upsert")
		capturedBody, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"Key":"runs/user-1/run-1.matched.json.gz"}`))
	})

	points := []TrackPoint{{Lat: 47.37, Lng: 8.54}, {Lat: 47.371, Lng: 8.541}}
	if err := client.UploadMatchedTrack(context.Background(), "user-1/run-1.matched.json.gz", points); err != nil {
		t.Fatalf("UploadMatchedTrack: %v", err)
	}

	if want := "/storage/v1/object/runs/user-1/run-1.matched.json.gz"; capturedPath != want {
		t.Errorf("path=%q, want %q", capturedPath, want)
	}
	if capturedContentType != "application/gzip" {
		t.Errorf("Content-Type=%q, want application/gzip (bucket allowed_mime_types rejects application/json)", capturedContentType)
	}
	if capturedContentEncoding != "" {
		t.Errorf("Content-Encoding=%q, want unset — intermediaries would transparently decompress a body consumers gunzip explicitly", capturedContentEncoding)
	}
	if capturedUpsert != "true" {
		t.Errorf("x-upsert=%q, want true", capturedUpsert)
	}

	zr, err := gzip.NewReader(bytes.NewReader(capturedBody))
	if err != nil {
		t.Fatalf("body is not gzip: %v", err)
	}
	var decoded []TrackPoint
	if err := json.NewDecoder(zr).Decode(&decoded); err != nil {
		t.Fatalf("gunzipped body is not the points JSON: %v", err)
	}
	if len(decoded) != 2 || decoded[0].Lat != 47.37 {
		t.Errorf("decoded points=%+v, want the 2 input points", decoded)
	}
}
