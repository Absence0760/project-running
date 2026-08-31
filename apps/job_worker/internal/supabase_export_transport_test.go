package internal

// The two remaining bounds on a queued Art 20 export, at the transport
// (decisions.md § 703 / § 708 / § 717): the Storage object the archive
// becomes, and the signed URL the subject is handed for it.
//
// Both former row caps are gone, so a failure here is what a subject
// experiences instead of a truncated archive — which means the failures
// have to be honest. A short upload that finalises, an error body that
// carries the object key (and therefore the user id) into a log line,
// and a Storage outage reported as an expiry are each worse than the
// plain refusal they replace.

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// ─────────────────── the signed URL ───────────────────

func TestCreateSignedURL_SendsTheTtlAndTheExportsBucketPath(t *testing.T) {
	var path string
	var body map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &body)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"signedURL":"/object/sign/exports/u/x.zip?token=abc"}`))
	}))
	defer srv.Close()

	c := NewSupabaseClient(srv.URL, testServiceKey)
	if _, err := c.CreateSignedURL(context.Background(), "u/x.zip", 600); err != nil {
		t.Fatal(err)
	}
	if path != "/storage/v1/object/sign/exports/u/x.zip" {
		t.Fatalf("path=%q, want the exports bucket and the object key", path)
	}
	if body["expiresIn"] != float64(600) {
		t.Fatalf("body=%v, want the caller's TTL", body)
	}
}

func TestCreateSignedURL_A404IsAnHttpErrorTheAdapterCanRecognise(t *testing.T) {
	// main.go maps a 404 onto dataexport.ErrArtifactGone so the status
	// endpoint reports an expiry rather than an outage. That mapping is
	// an `errors.As` on *HTTPError with StatusCode 404, so this is the
	// half of the contract that lives here.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"error":"not_found"}`, http.StatusNotFound)
	}))
	defer srv.Close()

	c := NewSupabaseClient(srv.URL, testServiceKey)
	_, err := c.CreateSignedURL(context.Background(), "u/gone.zip", 600)
	if err == nil {
		t.Fatal("signing a vanished object must fail")
	}
	var hErr *HTTPError
	if !errors.As(err, &hErr) {
		t.Fatalf("err=%T (%v), want an *HTTPError the adapter can classify", err, err)
	}
	if hErr.StatusCode != http.StatusNotFound {
		t.Fatalf("status=%d, want 404", hErr.StatusCode)
	}
}

func TestCreateSignedURL_AnOutageIsNotA404(t *testing.T) {
	// The distinction is the whole reason the adapter matches on the
	// status: telling a subject their archive expired when Storage is
	// merely down sends them to start another export they did not need.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"error":"upstream"}`, http.StatusBadGateway)
	}))
	defer srv.Close()

	c := NewSupabaseClient(srv.URL, testServiceKey)
	_, err := c.CreateSignedURL(context.Background(), "u/x.zip", 600)
	var hErr *HTTPError
	if !errors.As(err, &hErr) || hErr.StatusCode == http.StatusNotFound {
		t.Fatalf("err=%v, want a non-404 HTTPError", err)
	}
}

func TestCreateSignedURL_AnEmptyUrlIsAnErrorNotADeadLink(t *testing.T) {
	// A 200 carrying no URL would otherwise reach the subject as a
	// download link to nowhere.
	for _, payload := range []string{`{}`, `{"signedURL":""}`, `{"signedURL":null}`} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(payload))
		}))
		c := NewSupabaseClient(srv.URL, testServiceKey)
		got, err := c.CreateSignedURL(context.Background(), "u/x.zip", 600)
		if err == nil {
			t.Errorf("payload %s produced %q rather than an error", payload, got)
		}
		srv.Close()
	}
}

func TestCreateSignedURL_AnAbsoluteUrlIsPassedThroughUntouched(t *testing.T) {
	// A deployment whose storage service answers with a full URL owns
	// that URL; rewriting it would break the download.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"signedURL":"https://cdn.example/object/sign/exports/u/x.zip?token=abc"}`))
	}))
	defer srv.Close()

	c := NewSupabaseClient(srv.URL, testServiceKey)
	got, err := c.CreateSignedURL(context.Background(), "u/x.zip", 600)
	if err != nil {
		t.Fatal(err)
	}
	if got != "https://cdn.example/object/sign/exports/u/x.zip?token=abc" {
		t.Fatalf("url=%q, want it verbatim", got)
	}
}

// ─────────────────── the upload's boundaries ───────────────────

func TestResumableUpload_AnArchiveExactlyOneChunkLongTakesTheSingleShotPath(t *testing.T) {
	// The deferral exists because a zip's length is not knowable up
	// front. An archive that fits in one chunk knows its length by the
	// time anything is sent, so it declares it at create and stays on
	// the plainest path the server offers.
	srv := &tusServer{}
	u := newTusUpload(t, srv, 64)
	if _, err := u.Write(bytes.Repeat([]byte("a"), 64)); err != nil {
		t.Fatal(err)
	}
	if srv.created != 0 {
		t.Fatal("a buffer that exactly fills must not flush early — the tail PATCH is what declares the length")
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	if srv.deferred {
		t.Error("a single-chunk archive must not defer its length")
	}
	if srv.declared != 64 {
		t.Errorf("declared=%d, want 64", srv.declared)
	}
	if got := srv.object(); len(got) != 64 {
		t.Errorf("object is %d bytes, want 64", len(got))
	}
}

func TestResumableUpload_AMultiChunkArchiveDeclaresItsLengthOnTheTail(t *testing.T) {
	srv := &tusServer{}
	u := newTusUpload(t, srv, 64)
	payload := bytes.Repeat([]byte("b"), 200)
	if _, err := u.Write(payload); err != nil {
		t.Fatal(err)
	}
	if !srv.deferred {
		t.Fatal("a length that is not yet known must be deferred at create")
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	if srv.declared != len(payload) {
		t.Errorf("declared=%d, want %d", srv.declared, len(payload))
	}
	if !bytes.Equal(srv.object(), payload) {
		t.Errorf("object is %d bytes, want %d", len(srv.object()), len(payload))
	}
	if u.Uploaded() != len(payload) {
		t.Errorf("Uploaded()=%d, want %d", u.Uploaded(), len(payload))
	}
}

func TestResumableUpload_EveryNonFinalChunkIsExactlyTheChunkSize(t *testing.T) {
	// Supabase Storage rejects a short non-final chunk. This is a
	// protocol constant, not a tuning knob.
	srv := &tusServer{}
	u := newTusUpload(t, srv, 64)
	for i := 0; i < 10; i++ {
		if _, err := u.Write(bytes.Repeat([]byte("c"), 33)); err != nil {
			t.Fatal(err)
		}
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	if len(srv.patches) < 2 {
		t.Fatalf("patches=%v, want a multi-chunk upload", srv.patches)
	}
	for i, n := range srv.patches[:len(srv.patches)-1] {
		if n != 64 {
			t.Errorf("non-final chunk %d is %d bytes, want 64", i, n)
		}
	}
	if total := 10 * 33; u.Uploaded() != total {
		t.Errorf("Uploaded()=%d, want %d", u.Uploaded(), total)
	}
}

func TestResumableUpload_ACreateFailureLeaksNoObjectKeyIntoTheError(t *testing.T) {
	// The key embeds the subject's user id, and a Storage error body
	// repeats it. This error is logged, so it carries the status and
	// nothing else.
	srv := &tusServer{createStatus: http.StatusForbidden}
	u := newTusUpload(t, srv, 64)
	_, werr := u.Write(bytes.Repeat([]byte("d"), 200))
	err := werr
	if err == nil {
		err = u.Finish()
	}
	if err == nil {
		t.Fatal("a refused create must fail the upload")
	}
	if strings.Contains(err.Error(), "user-A") || strings.Contains(err.Error(), "exports/") {
		t.Fatalf("err=%q carries the object key, which embeds the user id", err)
	}
	if !strings.Contains(err.Error(), "403") {
		t.Fatalf("err=%q, want the status", err)
	}
	if srv.object() != nil {
		t.Fatal("a refused create must materialise nothing")
	}
}

func TestResumableUpload_ATruncatedArchiveNeverMaterialises(t *testing.T) {
	// The declared length is what makes this true: the server has bytes
	// but no length, so there is no object for anyone to sign, and the
	// subject gets an error rather than a short archive presented as
	// whole.
	srv := &tusServer{failPatchAt: 2}
	u := newTusUpload(t, srv, 64)
	_, err := u.Write(bytes.Repeat([]byte("e"), 500))
	if err == nil {
		err = u.Finish()
	}
	if err == nil {
		t.Fatal("a rejected chunk must fail the upload")
	}
	if srv.object() != nil {
		t.Fatalf("Storage holds a %d-byte object for a build that died", len(srv.object()))
	}
	u.Abort()
	if srv.deleted == 0 {
		t.Error("the session must be deleted so the server keeps no half-upload")
	}
}

func TestResumableUpload_AbortReachesTheServerEvenWhenTheBuildsContextIsDead(t *testing.T) {
	// The commonest reason to be aborting IS that context dying — the
	// per-attempt clock expiring mid-build. A DELETE that could not be
	// sent would leave an orphaned tus session behind every timeout.
	srv := &tusServer{}
	ts := httptest.NewServer(srv.handler())
	defer ts.Close()
	c := NewSupabaseClient(ts.URL, testServiceKey)

	ctx, cancel := context.WithCancel(context.Background())
	u := c.OpenExportArtifact(ctx, "user-A/exports/x.zip", "application/zip")
	u.chunkBytes = 64
	if _, err := u.Write(bytes.Repeat([]byte("f"), 200)); err != nil {
		t.Fatal(err)
	}
	cancel()
	u.Abort()
	if srv.deleted != 1 {
		t.Fatalf("deletes=%d, want the session torn down despite the dead context", srv.deleted)
	}
}

func TestResumableUpload_AbortWithNoSessionTalksToNobody(t *testing.T) {
	// A build that failed before the first flush has nothing to abort.
	// Sending a DELETE to a session that was never created would be a
	// request against a URL we do not have.
	srv := &tusServer{}
	u := newTusUpload(t, srv, 64)
	u.Abort()
	if srv.created != 0 || srv.deleted != 0 {
		t.Fatalf("created=%d deleted=%d, want no traffic at all", srv.created, srv.deleted)
	}
}

func TestResumableUpload_IrregularWritesReassembleByteForByte(t *testing.T) {
	// The zip writer hands over whatever the deflate stream produces —
	// a header here, a whole STORE-method photo there — so the chunker
	// splits at arbitrary points. A byte dropped or duplicated at a
	// boundary would still finalise, and the subject would receive an
	// archive that no longer opens.
	payload := make([]byte, 0, 4000)
	x := uint64(12345)
	for len(payload) < 4000 {
		x ^= x << 13
		x ^= x >> 7
		x ^= x << 17
		payload = append(payload, byte(x))
	}
	srv := &tusServer{}
	u := newTusUpload(t, srv, 64)

	off := 0
	for i := 0; off < len(payload); i++ {
		n := 1 + (i*37)%200
		if off+n > len(payload) {
			n = len(payload) - off
		}
		if _, err := u.Write(payload[off : off+n]); err != nil {
			t.Fatal(err)
		}
		off += n
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(srv.object(), payload) {
		t.Fatalf("object is %d bytes and does not match the %d written", len(srv.object()), len(payload))
	}
	sum := 0
	for _, n := range srv.patches {
		sum += n
	}
	if sum != len(payload) {
		t.Fatalf("chunks total %d bytes, want %d — a boundary dropped or duplicated bytes", sum, len(payload))
	}
	if u.Uploaded() != len(payload) {
		t.Fatalf("Uploaded()=%d, want %d", u.Uploaded(), len(payload))
	}
}

func TestResumableUpload_AServerThatAcknowledgesTheWrongOffsetIsRefused(t *testing.T) {
	// Splicing bytes into the wrong place would produce a corrupt
	// archive that still finalised — the one outcome worse than failing.
	srv := &tusServer{offsetLie: 7}
	u := newTusUpload(t, srv, 64)
	_, err := u.Write(bytes.Repeat([]byte("h"), 200))
	if err == nil {
		err = u.Finish()
	}
	if err == nil {
		t.Fatal("an offset the server does not agree with must abort the upload")
	}
	if !strings.Contains(err.Error(), "offset mismatch") {
		t.Fatalf("err=%q, want the mismatch named", err)
	}
	if srv.object() != nil {
		t.Fatal("nothing may materialise after an offset disagreement")
	}
}

func TestResumableUpload_TheCreateNamesTheExportsBucketAndTheObject(t *testing.T) {
	srv := &tusServer{}
	u := newTusUpload(t, srv, 64)
	if _, err := u.Write([]byte("i")); err != nil {
		t.Fatal(err)
	}
	if err := u.Finish(); err != nil {
		t.Fatal(err)
	}
	meta := srv.metadata
	for _, want := range []string{"bucketName ", "objectName ", "contentType ", "cacheControl "} {
		if !strings.Contains(meta, want) {
			t.Errorf("Upload-Metadata %q is missing %q", meta, want)
		}
	}
	// An overwrite would let a retry clobber an archive whose signed URL
	// is already in a subject's hands.
	if srv.upsert != "false" {
		t.Errorf("x-upsert=%q, want false", srv.upsert)
	}
}
