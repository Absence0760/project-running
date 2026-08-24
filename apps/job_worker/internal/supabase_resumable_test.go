package internal

// Boundary conditions of the chunked (tus) export upload. The archive
// is now handed to Storage as it is produced, so the failure modes that
// matter are not "did the bytes arrive" but "can a build that died
// half-way leave an object behind" and "can a server that disagrees
// about the offset produce a corrupt archive that still finalised".
// Both would be silent in production and neither is reachable from the
// handler tests, so they are pinned here against a fake tus server that
// speaks the same protocol Supabase Storage does.

import (
	"archive/zip"
	"bytes"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

// tusServer is Supabase Storage's resumable endpoint, minus the storage:
// it accumulates PATCH bodies against a declared length and only
// "materialises" the object once the whole declared length has arrived —
// the property the export's fail-closed guarantee rests on.
type tusServer struct {
	mu sync.Mutex

	created   int
	deleted   int
	metadata  string
	upsert    string
	deferred  bool
	declared  int
	body      bytes.Buffer
	patches   []int
	finalised bool

	// locationOrigin, when set, is reported in the create response's
	// Location header instead of the origin the client called — the way
	// Storage's gateway reports its own internal host.
	locationOrigin string
	// failPatchAt makes the Nth PATCH (1-based) fail with 500.
	failPatchAt int
	// offsetLie, when non-zero, is reported as Upload-Offset on every
	// PATCH acknowledgement regardless of what actually arrived.
	offsetLie int
	// createStatus overrides the 201 on create.
	createStatus int
}

func (s *tusServer) handler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/storage/v1/upload/resumable":
			s.created++
			s.metadata = r.Header.Get("Upload-Metadata")
			s.upsert = r.Header.Get("x-upsert")
			s.deferred = r.Header.Get("Upload-Defer-Length") == "1"
			if v := r.Header.Get("Upload-Length"); v != "" {
				s.declared, _ = strconv.Atoi(v)
			}
			if s.createStatus != 0 && s.createStatus != http.StatusCreated {
				w.WriteHeader(s.createStatus)
				return
			}
			origin := s.locationOrigin
			if origin == "" {
				origin = "http://" + r.Host
			}
			w.Header().Set("Location", origin+"/storage/v1/upload/resumable/upload-id-1")
			w.WriteHeader(http.StatusCreated)
		case r.Method == http.MethodPatch && strings.HasPrefix(r.URL.Path, "/storage/v1/upload/resumable/"):
			s.patches = append(s.patches, 0)
			if s.failPatchAt == len(s.patches) {
				http.Error(w, `{"message":"chunk rejected"}`, http.StatusInternalServerError)
				return
			}
			if v := r.Header.Get("Upload-Length"); v != "" {
				s.declared, _ = strconv.Atoi(v)
			}
			body, _ := io.ReadAll(r.Body)
			s.patches[len(s.patches)-1] = len(body)
			s.body.Write(body)
			if s.offsetLie != 0 {
				w.Header().Set("Upload-Offset", strconv.Itoa(s.offsetLie))
			} else {
				w.Header().Set("Upload-Offset", strconv.Itoa(s.body.Len()))
			}
			// tus only materialises the object once the declared length
			// has been received; before that there is nothing to read.
			if s.declared > 0 && s.body.Len() >= s.declared {
				s.finalised = true
			}
			w.WriteHeader(http.StatusNoContent)
		case r.Method == http.MethodDelete && strings.HasPrefix(r.URL.Path, "/storage/v1/upload/resumable/"):
			s.deleted++
			s.finalised = false
			w.WriteHeader(http.StatusNoContent)
		default:
			http.Error(w, "unexpected", http.StatusNotFound)
		}
	}
}

// object is the bytes a reader would find in Storage: nothing at all
// until the upload finalised.
func (s *tusServer) object() []byte {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.finalised {
		return nil
	}
	return append([]byte(nil), s.body.Bytes()...)
}

func newTusUpload(t *testing.T, srv *tusServer, chunkBytes int) *ResumableUpload {
	t.Helper()
	ts := httptest.NewServer(srv.handler())
	t.Cleanup(ts.Close)
	c := NewSupabaseClient(ts.URL, testServiceKey)
	u := c.OpenExportArtifact(t.Context(), "user-A/exports/2026-08-24T00-00-00.000Z.zip", "application/zip")
	u.chunkBytes = chunkBytes
	return u
}

// The archive that matters is a real zip pushed through a boundary it
// does not know about: the deflate stream is split at an arbitrary byte
// and reassembled by the server, and the result must still open.
func TestResumableUpload_RealZipSurvivesChunkBoundaries(t *testing.T) {
	srv := &tusServer{}
	u := newTusUpload(t, srv, 64)

	zw := zip.NewWriter(u)
	for i := 0; i < 40; i++ {
		fw, err := zw.Create(fmt.Sprintf("runs/run-%02d.gpx", i))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(fw, strings.Repeat(fmt.Sprintf("<trkpt n=%q/>", strconv.Itoa(i)), 20)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := u.Finish(); err != nil {
		t.Fatalf("Finish: %v", err)
	}

	body := srv.object()
	if len(body) == 0 {
		t.Fatal("upload finished but the object never materialised")
	}
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("the reassembled archive does not open: %v", err)
	}
	if len(zr.File) != 40 {
		t.Fatalf("entries=%d; want 40", len(zr.File))
	}
	first, err := zr.File[0].Open()
	if err != nil {
		t.Fatal(err)
	}
	content, _ := io.ReadAll(first)
	if !strings.Contains(string(content), `<trkpt n="0"/>`) {
		t.Errorf("entry content did not survive the boundary: %q", content[:min(40, len(content))])
	}
	if len(srv.patches) < 5 {
		t.Errorf("patches=%d; the archive must have crossed several chunk boundaries", len(srv.patches))
	}
	// Every chunk but the last is exactly the protocol's chunk size.
	for i, n := range srv.patches[:len(srv.patches)-1] {
		if n != 64 {
			t.Errorf("patch %d carried %d bytes; every non-final chunk must be exactly the chunk size", i, n)
		}
	}
	if !srv.deferred {
		t.Error("a multi-chunk archive must open with Upload-Defer-Length: a zip's size is not knowable up front")
	}
	if srv.declared != len(body) {
		t.Errorf("declared=%d, object=%d; the final PATCH must declare the true total", srv.declared, len(body))
	}
}

// The overwhelmingly common export fits in one chunk, and by then the
// length IS known — so it takes the plainest path the server offers.
func TestResumableUpload_SingleChunkDeclaresLengthAtCreate(t *testing.T) {
	srv := &tusServer{}
	u := newTusUpload(t, srv, 1024)

	payload := []byte(strings.Repeat("id,started_at\n", 10))
	if _, err := u.Write(payload); err != nil {
		t.Fatal(err)
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	if srv.deferred {
		t.Error("a single-chunk archive must not defer its length")
	}
	if srv.declared != len(payload) {
		t.Errorf("declared=%d; want %d", srv.declared, len(payload))
	}
	if len(srv.patches) != 1 {
		t.Errorf("patches=%d; want one", len(srv.patches))
	}
	if got := srv.object(); !bytes.Equal(got, payload) {
		t.Errorf("object=%q; want %q", got, payload)
	}
}

// The whole point of the sink: a chunk that fails mid-archive leaves
// NOTHING behind. The old single-shot upload could store a
// short-but-real archive and hand back a signed URL to it.
func TestResumableUpload_MidStreamChunkFailureLeavesNoArtifact(t *testing.T) {
	srv := &tusServer{failPatchAt: 3}
	u := newTusUpload(t, srv, 64)

	var writeErr error
	for i := 0; i < 20 && writeErr == nil; i++ {
		_, writeErr = u.Write([]byte(strings.Repeat("x", 64)))
	}
	if writeErr == nil {
		t.Fatal("a rejected chunk must surface to the caller, not be retried into silence")
	}
	u.Abort()

	if srv.object() != nil {
		t.Error("a build that died half-way left an object in Storage")
	}
	if srv.deleted != 1 {
		t.Errorf("abort issued %d DELETEs; the tus session must be terminated", srv.deleted)
	}
}

// Finishing is where the length is declared, so a failure there is also
// a failure to materialise — and must still be reported, never treated
// as a completed archive.
func TestResumableUpload_FinishFailureLeavesNoArtifact(t *testing.T) {
	srv := &tusServer{failPatchAt: 1}
	u := newTusUpload(t, srv, 1024)

	if _, err := u.Write([]byte("a short csv")); err != nil {
		t.Fatal(err)
	}
	if err := u.Finish(); err == nil {
		t.Fatal("Finish must report a rejected tail chunk")
	}
	u.Abort()
	if srv.object() != nil {
		t.Error("object materialised despite a failed finish")
	}
}

// A server acknowledging a different offset has a different idea of the
// object than we do. Continuing would splice bytes into the wrong place
// and produce a corrupt archive that still finalised.
func TestResumableUpload_OffsetMismatchAborts(t *testing.T) {
	srv := &tusServer{offsetLie: 999}
	u := newTusUpload(t, srv, 64)

	var err error
	for i := 0; i < 4 && err == nil; i++ {
		_, err = u.Write([]byte(strings.Repeat("y", 64)))
	}
	if err == nil {
		t.Fatal("an offset the server does not agree with must abort the upload")
	}
	if !strings.Contains(err.Error(), "offset mismatch") {
		t.Errorf("err=%v; want an offset mismatch", err)
	}
	u.Abort()
	if srv.object() != nil {
		t.Error("a spliced archive must never materialise")
	}
	// The failing chunk is not counted as uploaded, so a caller reading
	// Uploaded() can't be told bytes landed that did not.
	if u.Uploaded() != 0 {
		t.Errorf("uploaded=%d; a rejected chunk must not be counted", u.Uploaded())
	}
}

func TestResumableUpload_CreateFailureIsReportedAndLeavesNothing(t *testing.T) {
	srv := &tusServer{createStatus: http.StatusRequestEntityTooLarge}
	u := newTusUpload(t, srv, 64)

	_, err := u.Write([]byte(strings.Repeat("z", 200)))
	if err == nil {
		t.Fatal("a refused create must surface")
	}
	// Nothing to terminate, and abort must not invent a session.
	u.Abort()
	if srv.deleted != 0 {
		t.Errorf("deleted=%d; there was no session to terminate", srv.deleted)
	}
}

// Storage sits behind a gateway that reports its OWN origin in the
// create response's Location (`http://kong:54321/...` on the local
// stack), which is not routable from this container. The path is the
// server's to assign; the origin is ours to keep.
func TestResumableUpload_LocationKeepsOurOriginAndTheServerPath(t *testing.T) {
	srv := &tusServer{locationOrigin: "http://kong:54321"}
	u := newTusUpload(t, srv, 1024)

	if _, err := u.Write([]byte("body")); err != nil {
		t.Fatal(err)
	}
	if err := u.Finish(); err != nil {
		t.Fatalf("following the gateway's own origin breaks every PATCH: %v", err)
	}
	if !strings.HasSuffix(u.location, "/storage/v1/upload/resumable/upload-id-1") {
		t.Errorf("location=%q; the server-assigned path must be kept", u.location)
	}
	if strings.Contains(u.location, "kong") {
		t.Errorf("location=%q; the unroutable gateway origin must not be followed", u.location)
	}
}

func TestResumableUpload_CreateCarriesBucketMetadataAndRefusesUpsert(t *testing.T) {
	srv := &tusServer{}
	u := newTusUpload(t, srv, 1024)
	if _, err := u.Write([]byte("body")); err != nil {
		t.Fatal(err)
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	meta := map[string]string{}
	for _, pair := range strings.Split(srv.metadata, ",") {
		k, v, ok := strings.Cut(pair, " ")
		if !ok {
			continue
		}
		decoded, err := base64.StdEncoding.DecodeString(v)
		if err != nil {
			t.Fatalf("metadata value %q is not base64: %v", v, err)
		}
		meta[k] = string(decoded)
	}
	// `runs` caps an object at 25 MB, which on a full-history backup is
	// tighter than either cap this change removed, and storage-api
	// enforces it for service_role too.
	if meta["bucketName"] != schema.BucketExports {
		t.Errorf("bucketName=%q; the artifact must land in the exports bucket", meta["bucketName"])
	}
	if meta["objectName"] != "user-A/exports/2026-08-24T00-00-00.000Z.zip" {
		t.Errorf("objectName=%q", meta["objectName"])
	}
	if meta["contentType"] != "application/zip" {
		t.Errorf("contentType=%q", meta["contentType"])
	}
	// A collision means a duplicate request, not a re-upload: overwriting
	// would let a retry clobber an archive whose signed URL is already in
	// the caller's hands.
	if srv.upsert != "false" {
		t.Errorf("x-upsert=%q; want false", srv.upsert)
	}
}

// A blob handed over in one Write (a STORE-method photo entry) must not
// make the pending buffer as large as the blob — that is the allocation
// the whole change exists to remove.
func TestResumableUpload_OneBigWriteStillHoldsOnlyOneChunk(t *testing.T) {
	srv := &tusServer{}
	u := newTusUpload(t, srv, 64)

	if _, err := u.Write(bytes.Repeat([]byte("p"), 4096)); err != nil {
		t.Fatal(err)
	}
	if len(u.buf) > 64 {
		t.Errorf("pending buffer holds %d bytes after one 4096-byte write; want at most one chunk", len(u.buf))
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	if got := len(srv.object()); got != 4096 {
		t.Errorf("object=%d bytes; want 4096", got)
	}
}

func TestResumableUpload_WriteAfterFinishIsRefused(t *testing.T) {
	srv := &tusServer{}
	u := newTusUpload(t, srv, 1024)
	if _, err := u.Write([]byte("body")); err != nil {
		t.Fatal(err)
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	if _, err := u.Write([]byte("more")); err == nil {
		t.Error("writing past a declared length must be refused, not silently dropped")
	}
}

func TestResumableUpload_EmptyArchiveStillMaterialises(t *testing.T) {
	srv := &tusServer{}
	u := newTusUpload(t, srv, 1024)
	if err := u.Finish(); err != nil {
		t.Fatalf("Finish on an empty body: %v", err)
	}
	if srv.created != 1 {
		t.Errorf("created=%d; want one session", srv.created)
	}
	if srv.declared != 0 {
		t.Errorf("declared=%d; want 0", srv.declared)
	}
	if len(srv.patches) != 0 {
		t.Errorf("patches=%d; an empty body needs none", len(srv.patches))
	}
}

func TestResumableUpload_TransportFailureSurfaces(t *testing.T) {
	ts := httptest.NewServer((&tusServer{}).handler())
	c := NewSupabaseClient(ts.URL, testServiceKey)
	ts.Close()
	u := c.OpenExportArtifact(t.Context(), "user-A/exports/x.zip", "application/zip")
	u.chunkBytes = 16
	_, err := u.Write(bytes.Repeat([]byte("q"), 64))
	if err == nil {
		t.Fatal("a dead Storage endpoint must surface, not be swallowed")
	}
	var httpErr *HTTPError
	if errors.As(err, &httpErr) {
		t.Errorf("err=%v; a transport failure is not an HTTP status", err)
	}
}
