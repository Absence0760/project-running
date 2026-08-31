package dataexport

// Fail-closed and authorisation properties of the queued Art 20 rail
// (decisions.md § 717 / § 724 / § 729).
//
// An export job belongs to exactly one subject and the archive behind it
// is the densest personal-data corpus this product holds, so the
// questions here are: whose job did the endpoint act on, and what does
// it hand over when the row does not say what it claims to.

import (
	"context"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/supajwt"
)

// recordingBackend notes WHOSE row each call asked for. The shared fake
// ignores the subject, which is right for the build tests and useless
// for these.
type recordingBackend struct {
	*fakeBackend
	statusReadsFor []string
	enqueuedFor    []string
	signedPaths    []string
	rowsBySubject  map[string]*ExportJobRow
}

func newRecordingBackend(be *fakeBackend) *recordingBackend {
	return &recordingBackend{fakeBackend: be}
}

func (r *recordingBackend) LatestDataExportJob(ctx context.Context, userID string) (*ExportJobRow, error) {
	r.statusReadsFor = append(r.statusReadsFor, userID)
	if r.rowsBySubject != nil {
		row, ok := r.rowsBySubject[userID]
		if !ok || row == nil {
			return nil, nil
		}
		copied := *row
		return &copied, nil
	}
	return r.fakeBackend.LatestDataExportJob(ctx, userID)
}

func (r *recordingBackend) EnqueueDataExport(ctx context.Context, userID, format string) (ExportJobRef, error) {
	r.enqueuedFor = append(r.enqueuedFor, userID)
	return r.fakeBackend.EnqueueDataExport(ctx, userID, format)
}

func (r *recordingBackend) CreateSignedURL(ctx context.Context, path string, ttl int) (string, error) {
	r.signedPaths = append(r.signedPaths, path)
	return r.fakeBackend.CreateSignedURL(ctx, path, ttl)
}

func recordingServer(t *testing.T, be *recordingBackend) (string, func()) {
	t.Helper()
	return newTestServer(t, &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be})
}

func readyRow(id, subject, objectPath string) *ExportJobRow {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	return &ExportJobRow{
		ID: id, UserID: subject, Status: "ready", Format: "backup",
		ObjectPath: objectPath, CreatedAt: now, UpdatedAt: now, FinishedAt: now,
	}
}

// ─────────────────── whose export is it ───────────────────

func TestJobs_EnqueueIsForTheTokenSubjectAndNothingInTheBody(t *testing.T) {
	be := newRecordingBackend(&fakeBackend{enqueueRef: ExportJobRef{ID: "exp-1", Status: "queued", Format: "csv"}})
	base, teardown := recordingServer(t, be)
	defer teardown()

	// A body naming somebody else must change nothing — and, because the
	// decoder disallows unknown fields, must not even be accepted.
	resp, _ := postJob(t, base, "user-A", `{"format":"csv","user_id":"user-B"}`)
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status=%d, want 400 — the body carries no identity to honour", resp.StatusCode)
	}
	if len(be.enqueuedFor) != 0 {
		t.Fatalf("a refused body must enqueue nothing, got %v", be.enqueuedFor)
	}

	postJob(t, base, "user-A", `{"format":"csv"}`)
	if len(be.enqueuedFor) != 1 || be.enqueuedFor[0] != "user-A" {
		t.Fatalf("enqueued for %v, want exactly the token subject", be.enqueuedFor)
	}
}

func TestJobs_StatusIsReadForTheTokenSubject(t *testing.T) {
	be := newRecordingBackend(&fakeBackend{})
	base, teardown := recordingServer(t, be)
	defer teardown()

	getLatest(t, base, "user-B")
	if len(be.statusReadsFor) != 1 || be.statusReadsFor[0] != "user-B" {
		t.Fatalf("status read for %v, want the token subject", be.statusReadsFor)
	}
}

func TestJobs_OneSubjectCannotSeeAnothersExport(t *testing.T) {
	be := newRecordingBackend(&fakeBackend{signedURL: "https://signed.example/a"})
	be.rowsBySubject = map[string]*ExportJobRow{
		"user-A": readyRow("exp-A", "user-A", "user-A/exports/a.zip"),
	}
	base, teardown := recordingServer(t, be)
	defer teardown()

	_, mine := getLatest(t, base, "user-A")
	if mine["job_id"] != "exp-A" || mine["url"] == nil {
		t.Fatalf("the owner must get their own archive: %v", mine)
	}
	_, theirs := getLatest(t, base, "user-B")
	if theirs["status"] != StatusNone {
		t.Fatalf("user-B sees %v, want %q — an export belongs to one subject",
			theirs, StatusNone)
	}
	if _, present := theirs["url"]; present {
		t.Fatal("a subject with no export was handed a download URL")
	}
	for _, p := range be.signedPaths {
		if !strings.HasPrefix(p, "user-A/") {
			t.Fatalf("signed %q for a caller who does not own it", p)
		}
	}
}

func TestJobs_AReadyRowSignsExactlyItsOwnPathAndOnlyOnce(t *testing.T) {
	be := newRecordingBackend(&fakeBackend{signedURL: "https://signed.example/a"})
	be.rowsBySubject = map[string]*ExportJobRow{
		"user-A": readyRow("exp-A", "user-A", "user-A/exports/2026-08-25T10-00-00.000Z.zip"),
	}
	base, teardown := recordingServer(t, be)
	defer teardown()

	getLatest(t, base, "user-A")
	if len(be.signedPaths) != 1 {
		t.Fatalf("signed %d times, want 1", len(be.signedPaths))
	}
	if be.signedPaths[0] != "user-A/exports/2026-08-25T10-00-00.000Z.zip" {
		t.Fatalf("signed %q, want the row's own object_path verbatim", be.signedPaths[0])
	}
}

func TestJobs_TheUrlIsMintedFreshOnEveryRead(t *testing.T) {
	// § 717's whole answer to a queue meeting a 10-minute TTL: the row
	// stores a path, never a URL, so the clock starts when the subject
	// asks. Two reads therefore sign twice.
	be := newRecordingBackend(&fakeBackend{signedURL: "https://signed.example/a"})
	be.rowsBySubject = map[string]*ExportJobRow{
		"user-A": readyRow("exp-A", "user-A", "user-A/exports/a.zip"),
	}
	base, teardown := recordingServer(t, be)
	defer teardown()

	for i := 0; i < 3; i++ {
		_, body := getLatest(t, base, "user-A")
		if body["url"] == nil {
			t.Fatalf("read %d handed back no URL", i)
		}
		if body["expires_in"] != float64(SignedURLTTLSec) {
			t.Fatalf("read %d: expires_in=%v", i, body["expires_in"])
		}
	}
	if len(be.signedPaths) != 3 {
		t.Fatalf("signed %d times over 3 reads — a stored URL would sign once "+
			"and hand out an expiring link thereafter", len(be.signedPaths))
	}
}

// ─────────────────── what a row may claim ───────────────────

func TestJobs_ReadyWithNoObjectPathIsAFailureNotADeadDownloadButton(t *testing.T) {
	// A `ready` row asserts an artifact exists, and the object path is
	// the entirety of that assertion. Signing an empty path yields a URL
	// that 404s, which reaches the subject as a download button that
	// does nothing — the exact shape both clients refuse to render
	// (decisions.md § 724's `cloud_export_helpers` pair) and which the
	// server must not manufacture in the first place.
	be := newRecordingBackend(&fakeBackend{signedURL: "https://signed.example/nothing"})
	be.rowsBySubject = map[string]*ExportJobRow{
		"user-A": readyRow("exp-A", "user-A", ""),
	}
	base, teardown := recordingServer(t, be)
	defer teardown()

	resp, body := getLatest(t, base, "user-A")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status=%d, want 200 carrying an honest verdict", resp.StatusCode)
	}
	if _, present := body["url"]; present {
		t.Fatalf("body=%v — a row with no artifact path was presented as a download", body)
	}
	if body["status"] == "ready" {
		t.Fatalf("body=%v — a row with no artifact must not keep claiming to be ready", body)
	}
	if len(be.signedPaths) != 0 {
		t.Fatalf("signed %v, want nothing signed for an absent artifact", be.signedPaths)
	}
	if body["error_code"] == nil || body["error_code"] == "" {
		t.Fatalf("body=%v, want a machine token the client can render", body)
	}
}

func TestJobs_AnUnrecognisedStatusIsPassedThroughAndNeverSigned(t *testing.T) {
	// A status this build does not know is terminal on both clients. The
	// server's job is not to guess: report it verbatim, sign nothing,
	// promise nothing.
	now := time.Now().UTC().Format(time.RFC3339Nano)
	for _, status := range []string{"cancelled", "paused", "READY", "", "ready "} {
		be := newRecordingBackend(&fakeBackend{signedURL: "https://signed.example/a"})
		be.rowsBySubject = map[string]*ExportJobRow{
			"user-A": {
				ID: "exp-A", UserID: "user-A", Status: status, Format: "backup",
				ObjectPath: "user-A/exports/a.zip", CreatedAt: now, UpdatedAt: now,
			},
		}
		base, teardown := recordingServer(t, be)

		resp, body := getLatest(t, base, "user-A")
		if resp.StatusCode != http.StatusOK {
			t.Errorf("status=%q: http=%d, want 200", status, resp.StatusCode)
		}
		if body["status"] != status {
			t.Errorf("status=%q reported as %v, want it verbatim", status, body["status"])
		}
		if _, present := body["url"]; present {
			t.Errorf("status=%q was handed a download URL", status)
		}
		if len(be.signedPaths) != 0 {
			t.Errorf("status=%q signed %v", status, be.signedPaths)
		}
		teardown()
	}
}

func TestJobs_AnUnrecognisedInFlightStatusDoesNotBlockANewExport(t *testing.T) {
	// The reuse check and the one-in-flight unique index have to agree on
	// what "in flight" means. A status neither of them counts must leave
	// the subject able to ask again rather than wedged behind a row
	// nothing will ever finish.
	now := time.Now().UTC().Format(time.RFC3339Nano)
	be := newRecordingBackend(&fakeBackend{
		enqueueRef: ExportJobRef{ID: "exp-2", Status: "queued", Format: "csv"},
	})
	be.rowsBySubject = map[string]*ExportJobRow{
		"user-A": {ID: "exp-1", UserID: "user-A", Status: "cancelled", Format: "csv",
			CreatedAt: now, UpdatedAt: now},
	}
	base, teardown := recordingServer(t, be)
	defer teardown()

	_, body := postJob(t, base, "user-A", `{"format":"csv"}`)
	if body["job_id"] != "exp-2" || body["reused"] == true {
		t.Fatalf("body=%v, want a fresh enqueue past a status nothing recognises", body)
	}
}

func TestJobs_TheReuseSetIsTheOneTheUniqueIndexEnforces(t *testing.T) {
	// If the partial index covered a status the reuse check does not,
	// the handler would call the enqueue RPC and lose to the index; if
	// the reuse check covered one the index does not, two builds could
	// run for one subject at once and each would upload a whole archive.
	sql := asyncExportMigration(t)
	m := regexp.MustCompile(`(?is)create\s+unique\s+index\s+data_export_jobs_one_in_flight[\s\S]*?where\s+status\s+in\s*\(([^)]*)\)`).
		FindStringSubmatch(sql)
	if m == nil {
		t.Fatal("could not read the one-in-flight index predicate — this guard is asserting nothing")
	}
	var indexed []string
	for _, tok := range regexp.MustCompile(`'([^']*)'`).FindAllStringSubmatch(m[1], -1) {
		indexed = append(indexed, tok[1])
	}
	if len(indexed) == 0 {
		t.Fatal("the index predicate parsed to zero statuses")
	}

	now := time.Now().UTC().Format(time.RFC3339Nano)
	for _, status := range indexed {
		be := newRecordingBackend(&fakeBackend{
			rateErr: errors.New("a reuse must not consult the rate limiter"),
		})
		be.rowsBySubject = map[string]*ExportJobRow{
			"user-A": {ID: "exp-1", UserID: "user-A", Status: status, Format: "csv",
				CreatedAt: now, UpdatedAt: now},
		}
		base, teardown := recordingServer(t, be)
		_, body := postJob(t, base, "user-A", `{"format":"csv"}`)
		if body["reused"] != true {
			t.Errorf("status=%q is in-flight by the index but was not reused: %v", status, body)
		}
		if len(be.enqueuedFor) != 0 {
			t.Errorf("status=%q enqueued a second build", status)
		}
		teardown()
	}
}

func TestJobs_AReuseAnswersWithTheRunningExportNotTheRequestedFormat(t *testing.T) {
	// Asking for a csv while a backup is building must not start a
	// second archive; the honest answer is the job already in flight.
	now := time.Now().UTC().Format(time.RFC3339Nano)
	be := newRecordingBackend(&fakeBackend{})
	be.rowsBySubject = map[string]*ExportJobRow{
		"user-A": {ID: "exp-1", UserID: "user-A", Status: "running", Format: "backup",
			CreatedAt: now, UpdatedAt: now},
	}
	base, teardown := recordingServer(t, be)
	defer teardown()

	_, body := postJob(t, base, "user-A", `{"format":"csv"}`)
	if body["format"] != "backup" || body["reused"] != true {
		t.Fatalf("body=%v, want the in-flight backup reported as-is", body)
	}
	if len(be.enqueuedFor) != 0 {
		t.Fatal("a reuse must start no second build")
	}
}

// ─────────────────── staleness ───────────────────

func TestJobs_StalenessCoversBothInFlightStatusesAndNoTerminalOne(t *testing.T) {
	ancient := time.Now().UTC().Add(-10 * ExportJobStaleAfter).Format(time.RFC3339Nano)
	for _, tc := range []struct {
		status string
		stale  bool
	}{
		{"queued", true},
		{"running", true},
		{"ready", false},
		{"failed", false},
		{"expired", false},
	} {
		be := newRecordingBackend(&fakeBackend{signedURL: "https://signed.example/a"})
		be.rowsBySubject = map[string]*ExportJobRow{
			"user-A": {ID: "exp-1", UserID: "user-A", Status: tc.status, Format: "csv",
				ObjectPath: "user-A/exports/a.zip", CreatedAt: ancient, UpdatedAt: ancient,
				FinishedAt: ancient},
		}
		base, teardown := recordingServer(t, be)
		_, body := getLatest(t, base, "user-A")
		got := body["status"] == StatusStalled
		if got != tc.stale {
			t.Errorf("an ancient %q row reported %v, stalled=%v want %v",
				tc.status, body["status"], got, tc.stale)
		}
		teardown()
	}
}

func TestJobs_StalenessMeasuresCreatedAtWhenNothingHasUpdatedTheRow(t *testing.T) {
	// `updated_at` is trigger-maintained but a freshly-inserted row that
	// nothing has claimed has never been updated in the sense that
	// matters. An empty value must not read as the zero time and declare
	// every new export dead on arrival.
	fresh := time.Now().UTC().Format(time.RFC3339Nano)
	ancient := time.Now().UTC().Add(-10 * ExportJobStaleAfter).Format(time.RFC3339Nano)
	for _, tc := range []struct {
		name      string
		createdAt string
		wantStale bool
	}{
		{"just enqueued", fresh, false},
		{"enqueued long ago and never claimed", ancient, true},
	} {
		be := newRecordingBackend(&fakeBackend{})
		be.rowsBySubject = map[string]*ExportJobRow{
			"user-A": {ID: "exp-1", UserID: "user-A", Status: "queued", Format: "csv",
				CreatedAt: tc.createdAt},
		}
		base, teardown := recordingServer(t, be)
		_, body := getLatest(t, base, "user-A")
		if got := body["status"] == StatusStalled; got != tc.wantStale {
			t.Errorf("%s: status=%v, stalled=%v want %v", tc.name, body["status"], got, tc.wantStale)
		}
		teardown()
	}
}

func TestJobs_AJustInsideTheWindowRowIsStillBelieved(t *testing.T) {
	// The boundary is what the derivation is FOR: a job on its second
	// attempt has legitimately been quiet for most of this window.
	for _, tc := range []struct {
		name      string
		age       time.Duration
		wantStale bool
	}{
		{"one second inside the window", ExportJobStaleAfter - time.Second, false},
		{"one second past it", ExportJobStaleAfter + time.Second, true},
	} {
		touched := time.Now().UTC().Add(-tc.age).Format(time.RFC3339Nano)
		be := newRecordingBackend(&fakeBackend{})
		be.rowsBySubject = map[string]*ExportJobRow{
			"user-A": {ID: "exp-1", UserID: "user-A", Status: "running", Format: "csv",
				CreatedAt: touched, UpdatedAt: touched},
		}
		base, teardown := recordingServer(t, be)
		_, body := getLatest(t, base, "user-A")
		if got := body["status"] == StatusStalled; got != tc.wantStale {
			t.Errorf("%s: status=%v, want stalled=%v", tc.name, body["status"], tc.wantStale)
		}
		teardown()
	}
}

func TestJobs_AFutureTimestampIsNotStale(t *testing.T) {
	// Clock skew between the database and the worker must not be able to
	// declare a live export dead.
	future := time.Now().UTC().Add(time.Hour).Format(time.RFC3339Nano)
	be := newRecordingBackend(&fakeBackend{})
	be.rowsBySubject = map[string]*ExportJobRow{
		"user-A": {ID: "exp-1", UserID: "user-A", Status: "running", Format: "csv",
			CreatedAt: future, UpdatedAt: future},
	}
	base, teardown := recordingServer(t, be)
	defer teardown()

	_, body := getLatest(t, base, "user-A")
	if body["status"] != "running" {
		t.Fatalf("status=%v, want the row believed", body["status"])
	}
}

// ─────────────────── backend outages ───────────────────

func TestJobs_AStatusReadOutageIs500AndSignsNothing(t *testing.T) {
	be := newRecordingBackend(&fakeBackend{latestJobErr: errors.New("db down")})
	base, teardown := recordingServer(t, be)
	defer teardown()

	resp, body := getLatest(t, base, "user-A")
	if resp.StatusCode != http.StatusInternalServerError {
		t.Fatalf("status=%d, want 500 — reporting `none` would tell a subject "+
			"the export they are waiting for never existed", resp.StatusCode)
	}
	if _, present := body["url"]; present {
		t.Fatal("a failed status read handed over a URL")
	}
	if len(be.signedPaths) != 0 {
		t.Fatalf("signed %v during an outage", be.signedPaths)
	}
}

func TestJobs_AReuseCheckOutageStillLetsTheSubjectAsk(t *testing.T) {
	// The reuse check is an optimisation over an RPC that already
	// de-duplicates. Refusing the enqueue because the check could not run
	// would deny an Art 20 request over a transient read.
	be := newRecordingBackend(&fakeBackend{
		latestJobErr: errors.New("db blip"),
		enqueueRef:   ExportJobRef{ID: "exp-1", Status: "queued", Format: "csv"},
	})
	base, teardown := recordingServer(t, be)
	defer teardown()

	resp, body := postJob(t, base, "user-A", `{"format":"csv"}`)
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status=%d, want 202", resp.StatusCode)
	}
	if body["job_id"] != "exp-1" {
		t.Fatalf("body=%v", body)
	}
}

func TestJobs_AnEnqueueFailureIs500AndBuildsNothing(t *testing.T) {
	be := newRecordingBackend(&fakeBackend{enqueueErr: errors.New("rpc down")})
	base, teardown := recordingServer(t, be)
	defer teardown()

	resp, body := postJob(t, base, "user-A", `{"format":"csv"}`)
	if resp.StatusCode != http.StatusInternalServerError {
		t.Fatalf("status=%d, want 500", resp.StatusCode)
	}
	if body["job_id"] != nil {
		t.Fatalf("body=%v, want no job id for a job that was not queued", body)
	}
	if len(be.uploads) != 0 {
		t.Fatal("the endpoint built an archive")
	}
}

func TestJobs_ASigningOutageIs500RatherThanADressedUpExpiry(t *testing.T) {
	// Only ErrArtifactGone means "the retention sweep took it". A plain
	// Storage failure reported as an expiry would tell a subject their
	// week-old archive is gone when it is sitting there.
	be := newRecordingBackend(&fakeBackend{signURLErr: errors.New("storage 503")})
	be.rowsBySubject = map[string]*ExportJobRow{
		"user-A": readyRow("exp-A", "user-A", "user-A/exports/a.zip"),
	}
	base, teardown := recordingServer(t, be)
	defer teardown()

	resp, body := getLatest(t, base, "user-A")
	if resp.StatusCode != http.StatusInternalServerError {
		t.Fatalf("status=%d, want 500", resp.StatusCode)
	}
	if body["status"] == "expired" {
		t.Fatal("a Storage outage was reported as an expiry")
	}
}

// ─────────────────── request shape ───────────────────

func TestJobs_BodyHandling(t *testing.T) {
	for _, tc := range []struct {
		name       string
		body       string
		wantStatus int
		wantFormat string
	}{
		{"absent format defaults to csv", `{}`, http.StatusAccepted, "csv"},
		{"empty body defaults to csv", ``, http.StatusAccepted, "csv"},
		{"explicit empty format defaults to csv", `{"format":""}`, http.StatusAccepted, "csv"},
		{"gpx", `{"format":"gpx"}`, http.StatusAccepted, "gpx"},
		{"backup", `{"format":"backup"}`, http.StatusAccepted, "backup"},
		{"unknown format", `{"format":"tar"}`, http.StatusBadRequest, ""},
		{"case is not folded", `{"format":"CSV"}`, http.StatusBadRequest, ""},
		{"unknown field", `{"format":"csv","admin":true}`, http.StatusBadRequest, ""},
		{"not json", `nonsense`, http.StatusBadRequest, ""},
		{"oversize body", `{"format":"csv","x":"` + strings.Repeat("a", MaxBodyBytes*2) + `"}`, http.StatusBadRequest, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			be := newRecordingBackend(&fakeBackend{})
			base, teardown := recordingServer(t, be)
			defer teardown()

			resp, body := postJob(t, base, "user-A", tc.body)
			if resp.StatusCode != tc.wantStatus {
				t.Fatalf("status=%d, want %d (%v)", resp.StatusCode, tc.wantStatus, body)
			}
			if tc.wantStatus != http.StatusAccepted {
				if len(be.enqueuedFor) != 0 {
					t.Fatal("a refused request must enqueue nothing")
				}
				return
			}
			if body["format"] != tc.wantFormat {
				t.Fatalf("format=%v, want %q", body["format"], tc.wantFormat)
			}
		})
	}
}

// ─────────────────── CORS ───────────────────

func TestJobs_AnUnlistedOriginGetsVaryButNoAllowHeader(t *testing.T) {
	// `Vary: Origin` is unconditional: without it a shared cache can
	// serve the allowed origin's response — allow header and all — to
	// somebody else.
	be := newRecordingBackend(&fakeBackend{enqueueRef: ExportJobRef{ID: "exp-1", Status: "queued", Format: "csv"}})
	base, teardown := newTestServer(t, &Server{
		Verifier:       supajwt.New(testJWTSecret, "", nil),
		Backend:        be,
		AllowedOrigins: []string{"https://threkir.com"},
	})
	defer teardown()

	for _, path := range []string{"/v1/export/jobs", "/v1/export/jobs/latest"} {
		method := http.MethodPost
		var bodyReader *strings.Reader = strings.NewReader(`{"format":"csv"}`)
		if strings.HasSuffix(path, "latest") {
			method, bodyReader = http.MethodGet, strings.NewReader("")
		}
		req, _ := http.NewRequest(method, base+path, bodyReader)
		req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Origin", "https://evil.example")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "" {
			t.Errorf("%s: allow-origin=%q for an unlisted origin", path, got)
		}
		if got := resp.Header.Get("Vary"); !strings.Contains(got, "Origin") {
			t.Errorf("%s: vary=%q, want Origin even on a refusal", path, got)
		}
	}
}

func TestJobs_PreflightIsAnsweredBeforeTheConfigurationGate(t *testing.T) {
	// An OPTIONS probe carries no credentials, so refusing it 503 when
	// the JWT secret is unset would hide a misconfiguration behind a
	// browser-level failure that names neither.
	srv := &Server{AllowedOrigins: []string{"https://threkir.com"}} // no verifier
	base, teardown := newTestServer(t, srv)
	defer teardown()

	for _, path := range []string{"/v1/export/jobs", "/v1/export/jobs/latest"} {
		req, _ := http.NewRequest(http.MethodOptions, base+path, nil)
		req.Header.Set("Origin", "https://threkir.com")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusNoContent {
			t.Errorf("%s: status=%d, want 204 even with no verifier", path, resp.StatusCode)
		}
	}
}

func TestJobs_NoAllowlistMeansNoCorsHeadersAtAll(t *testing.T) {
	// The server-to-server default. Fail-closed for a browser deployment
	// that forgot to set the variable, rather than open by accident.
	be := newRecordingBackend(&fakeBackend{enqueueRef: ExportJobRef{ID: "exp-1", Status: "queued", Format: "csv"}})
	base, teardown := recordingServer(t, be)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export/jobs", strings.NewReader(`{"format":"csv"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 60))
	req.Header.Set("Origin", "https://threkir.com")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("allow-origin=%q with an empty allowlist", got)
	}
}

// asyncExportMigration reads the queued rail's migration so a guard can
// compare the SQL against the Go rather than against a copy of it.
func asyncExportMigration(t *testing.T) string {
	t.Helper()
	path := filepath.Join("..", "..", "..", "backend", "supabase", "migrations",
		"20270603_001_async_data_export.sql")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Skipf("migration not readable at %s (%v) — run from apps/job_worker", path, err)
	}
	return string(raw)
}
