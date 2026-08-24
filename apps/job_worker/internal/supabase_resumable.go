package internal

// Chunked (tus 1.0) Storage upload for the Art 20 export artifact.
//
// The export used to assemble the whole archive in one bytes.Buffer and
// POST it in a single shot. That one allocation is what forced every cap
// the manifest had to apologise for — 5000 runs, 50,000 rows per section
// — because a deep history's tracks alone run to hundreds of megabytes
// and the worker machine has 256 MB. A cap that exists to keep an
// allocation alive is not a data-minimisation decision; it is a subject
// not receiving their data.
//
// Supabase Storage speaks tus at `/storage/v1/upload/resumable`, so the
// archive can be pushed as it is produced and only one chunk is ever
// resident. This is the Go half of the sink decisions.md §703 built on
// the Edge Function rail; the wire contract is identical, deliberately.
//
// Two properties matter more than throughput:
//
//   - **Fail closed.** tus materialises the object only once the
//     declared length has been received. A creation, PATCH or offset
//     mismatch returns an error, and the caller aborts the session and
//     answers 500 with no artifact at all — so a build that died
//     half-way can never present a truncated archive as a complete one.
//     That is the whole reason the total length is declared on the FINAL
//     chunk rather than guessed up front.
//   - **The total length is not knowable up front.** A zip's size is
//     whatever the deflate stream turns out to be, so creation uses
//     tus's `Upload-Defer-Length` and the last PATCH declares the total.
//     An archive that fits in a single chunk skips the deferral entirely
//     (the length IS known by then), which keeps the overwhelmingly
//     common case on the plainest path the server offers.

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
	"github.com/Absence0760/project-running/apps/job_worker/internal/supakey"
)

const tusVersion = "1.0.0"

// TusChunkBytes is 6 MiB. Supabase Storage requires every non-final tus
// chunk to be exactly this size; it is a protocol constant, not a
// tuning knob.
const TusChunkBytes = 6 * 1024 * 1024

// ResumableUpload streams bytes into a Storage object through the tus
// resumable endpoint, holding at most one chunk. Not safe for
// concurrent use — the export builder writes it from one goroutine.
type ResumableUpload struct {
	client      *SupabaseClient
	ctx         context.Context
	bucket      string
	objectPath  string
	contentType string
	chunkBytes  int
	log         *slog.Logger

	buf      []byte
	uploaded int
	location string
	deferred bool
	finished bool
}

// OpenExportArtifact opens a chunked upload session for an export
// artifact in the `exports` bucket.
//
// The bucket matters as much as the chunking: `runs` carries
// `file_size_limit = 25 MB`, which on a full-history backup is a
// tighter ceiling than either cap this rail used to publish, and
// storage-api enforces it for service_role too — so the subject got a
// failed upload rather than a short archive. `exports` (migration
// 20270602_001) admits 5 GiB and carries no storage.objects policy, so
// the artifact stays reachable through its 10-minute signed URL and
// nothing else.
//
// The session is created lazily on the first flush so a single-chunk
// archive can declare its length at creation time.
func (c *SupabaseClient) OpenExportArtifact(ctx context.Context, path, contentType string) *ResumableUpload {
	return &ResumableUpload{
		client:      c,
		ctx:         ctx,
		bucket:      schema.BucketExports,
		objectPath:  path,
		contentType: contentType,
		chunkBytes:  TusChunkBytes,
		buf:         make([]byte, 0, TusChunkBytes),
	}
}

// Write buffers `p` and flushes whole chunks. Any transport or protocol
// failure is returned; the caller must abandon the export.
func (u *ResumableUpload) Write(p []byte) (int, error) {
	if u.finished {
		return 0, errors.New("resumable: write after finish")
	}
	written := 0
	for len(p) > 0 {
		// Fill the pending chunk straight from `p` rather than appending
		// all of it first: a STORE-method zip entry hands over a whole
		// photo in one Write, and appending would make the buffer as big
		// as the object it was meant to bound.
		space := u.chunkBytes - len(u.buf)
		if space > len(p) {
			space = len(p)
		}
		u.buf = append(u.buf, p[:space]...)
		p = p[space:]
		written += space
		// Strictly "more bytes in hand", not "buffer full": the tail
		// PATCH is what declares the total length, so the buffer must
		// never drain to empty while more bytes may still arrive.
		if len(p) > 0 {
			if err := u.patch(-1); err != nil {
				return written, err
			}
		}
	}
	return written, nil
}

// Finish flushes the tail, declares the total length, and finalises the
// object. Until it returns nil, no object exists.
func (u *ResumableUpload) Finish() error {
	if u.finished {
		return nil
	}
	u.finished = true
	total := u.uploaded + len(u.buf)
	if u.location == "" {
		if err := u.create(total); err != nil {
			return err
		}
	}
	if len(u.buf) > 0 {
		if err := u.patch(total); err != nil {
			return err
		}
	}
	if u.uploaded != total {
		return fmt.Errorf("resumable: finish short, %d of %d bytes", u.uploaded, total)
	}
	return nil
}

// Abort terminates the tus session so no object is left behind. It runs
// on a path that is already failing, so it reports rather than returns.
func (u *ResumableUpload) Abort() {
	u.buf = u.buf[:0]
	if u.location == "" {
		return
	}
	// Detached from the build's context: the commonest reason to be
	// aborting is that context dying, and a DELETE that cannot be sent
	// leaves an orphaned tus session on the server. It can never become
	// an object — the declared length never arrives — but the server
	// should be told all the same.
	ctx, cancel := context.WithTimeout(context.WithoutCancel(u.ctx), 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, u.location, nil)
	if err != nil {
		u.logger().Warn("dataexport: resumable abort failed", "err", err)
		return
	}
	req.Header.Set("Tus-Resumable", tusVersion)
	resp, err := u.send(req)
	if err != nil {
		u.logger().Warn("dataexport: resumable abort failed", "err", err)
		return
	}
	resp.Body.Close()
}

// Uploaded reports the bytes the server has acknowledged.
func (u *ResumableUpload) Uploaded() int { return u.uploaded }

func (u *ResumableUpload) create(declaredLength int) error {
	createURL := strings.TrimRight(u.client.BaseURL, "/") + "/storage/v1/upload/resumable"
	req, err := http.NewRequestWithContext(u.ctx, http.MethodPost, createURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Tus-Resumable", tusVersion)
	req.Header.Set("Upload-Metadata", tusMetadata(map[string]string{
		"bucketName":   u.bucket,
		"objectName":   u.objectPath,
		"contentType":  u.contentType,
		"cacheControl": "3600",
	}))
	// The export path carries a fresh millisecond timestamp per call, so
	// a collision means a duplicate request, not a re-upload. Overwriting
	// would let a retry clobber an archive whose signed URL is already in
	// the caller's hands.
	req.Header.Set("x-upsert", "false")
	if declaredLength < 0 {
		req.Header.Set("Upload-Defer-Length", "1")
		u.deferred = true
	} else {
		req.Header.Set("Upload-Length", strconv.Itoa(declaredLength))
	}
	resp, err := u.send(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		// Status only: a Storage error body carries the object key, and
		// the key embeds the user id.
		return fmt.Errorf("resumable: create returned %d", resp.StatusCode)
	}
	loc := resp.Header.Get("Location")
	if loc == "" {
		return errors.New("resumable: create returned no Location")
	}
	base, err := url.Parse(createURL)
	if err != nil {
		return err
	}
	assigned, err := base.Parse(loc)
	if err != nil {
		return fmt.Errorf("resumable: unparseable Location")
	}
	// Keep the PATH the server assigned, but the ORIGIN we already
	// reached it on. Storage sits behind a gateway that reports its own
	// internal origin here (`http://kong:54321/...` on the local stack),
	// which is not routable from this container — so following the
	// Location verbatim fails every PATCH with ECONNREFUSED after a
	// create that returned 201.
	assigned.Scheme, assigned.Host = base.Scheme, base.Host
	u.location = assigned.String()
	return nil
}

// patch sends the whole pending buffer as one chunk. `declareTotal` is
// the archive's final length on the last chunk of a deferred-length
// upload, and -1 otherwise.
func (u *ResumableUpload) patch(declareTotal int) error {
	if u.location == "" {
		if err := u.create(-1); err != nil {
			return err
		}
	}
	chunk := u.buf
	req, err := http.NewRequestWithContext(u.ctx, http.MethodPatch, u.location, bytes.NewReader(chunk))
	if err != nil {
		return err
	}
	req.Header.Set("Tus-Resumable", tusVersion)
	req.Header.Set("Upload-Offset", strconv.Itoa(u.uploaded))
	req.Header.Set("Content-Type", "application/offset+octet-stream")
	req.ContentLength = int64(len(chunk))
	if declareTotal >= 0 && u.deferred {
		req.Header.Set("Upload-Length", strconv.Itoa(declareTotal))
	}
	resp, err := u.send(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		return fmt.Errorf("resumable: patch at offset %d returned %d", u.uploaded, resp.StatusCode)
	}
	expected := u.uploaded + len(chunk)
	// A server acknowledging a different offset has a different idea of
	// the object than we do. Continuing would splice bytes into the wrong
	// place and produce a corrupt archive that still finalised — the one
	// outcome worse than failing.
	if reported := resp.Header.Get("Upload-Offset"); reported != "" {
		n, err := strconv.Atoi(reported)
		if err != nil || n != expected {
			return fmt.Errorf("resumable: offset mismatch, sent %d, server %q", expected, reported)
		}
	}
	u.uploaded = expected
	u.buf = u.buf[:0]
	return nil
}

func (u *ResumableUpload) send(req *http.Request) (*http.Response, error) {
	supakey.SetAuthHeaders(req.Header, u.client.ServiceKey)
	return u.client.HTTP.Do(req)
}

func (u *ResumableUpload) logger() *slog.Logger {
	if u.log != nil {
		return u.log
	}
	return slog.Default()
}

// tusMetadata renders the `Upload-Metadata` header: space-separated
// key + base64 value, comma-separated pairs. Sorted so the header is
// deterministic.
func tusMetadata(pairs map[string]string) string {
	keys := []string{"bucketName", "objectName", "contentType", "cacheControl"}
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		v, ok := pairs[k]
		if !ok {
			continue
		}
		parts = append(parts, k+" "+base64.StdEncoding.EncodeToString([]byte(v)))
	}
	return strings.Join(parts, ",")
}
