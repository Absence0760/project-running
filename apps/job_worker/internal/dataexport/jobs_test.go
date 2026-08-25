package dataexport

// The queued Art 20 rail (decisions.md § 717).
//
// The endpoint pair's whole job is to stop holding the caller's
// connection open for the build, so the properties worth pinning are
// about what it does NOT do: it does not build, it does not spend a
// quota token on a request that starts no build, it does not hand over a
// URL for an archive that does not exist, and it does not keep claiming
// an export is building after the worker that was building it is gone.

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/supajwt"
)

func postJob(t *testing.T, base, sub, body string) (*http.Response, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export/jobs", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, sub, 60))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp, out
}

func getLatest(t *testing.T, base, sub string) (*http.Response, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, base+"/v1/export/jobs/latest", nil)
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, sub, 60))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp, out
}

func TestJobs_PostEnqueuesAndAnswers202(t *testing.T) {
	be := &fakeBackend{enqueueRef: ExportJobRef{ID: "exp-1", Status: "queued", Format: "backup"}}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, body := postJob(t, base, "user-A", `{"format":"backup"}`)
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status=%d, want 202", resp.StatusCode)
	}
	if body["job_id"] != "exp-1" || body["status"] != "queued" || body["format"] != "backup" {
		t.Fatalf("body=%v", body)
	}
	// The point of the whole change: no archive was built on this call.
	if len(be.uploads) != 0 {
		t.Fatalf("the enqueue built an archive on the caller's connection: %d uploads", len(be.uploads))
	}
	if len(be.enqueued) != 1 {
		t.Fatalf("enqueued=%d, want 1", len(be.enqueued))
	}
}

func TestJobs_PostWhileOneIsInFlightReusesAndSpendsNoQuota(t *testing.T) {
	be := &fakeBackend{
		latestJob: &ExportJobRow{
			ID: "exp-1", Status: "running", Format: "backup",
			CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
			UpdatedAt: time.Now().UTC().Format(time.RFC3339Nano),
		},
		// Any rate-limit consultation at all would fail the request, which
		// is how the test proves none happened.
		rateErr: errors.New("rate limit must not be consulted for a reuse"),
	}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, body := postJob(t, base, "user-A", `{"format":"backup"}`)
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status=%d, want 202", resp.StatusCode)
	}
	if body["reused"] != true || body["job_id"] != "exp-1" {
		t.Fatalf("body=%v, want the in-flight job reported as a reuse", body)
	}
	if len(be.enqueued) != 0 {
		t.Fatalf("a reuse must enqueue nothing; enqueued=%d", len(be.enqueued))
	}
}

func TestJobs_PostAfterAStalledJobStartsAFreshOne(t *testing.T) {
	// A row still saying `running` an hour after anything touched it is
	// a worker that died mid-build. Treating it as in-flight would leave
	// the subject unable to ever ask again.
	stale := time.Now().UTC().Add(-2 * ExportJobStaleAfter).Format(time.RFC3339Nano)
	be := &fakeBackend{
		latestJob:  &ExportJobRow{ID: "exp-1", Status: "running", Format: "backup", CreatedAt: stale, UpdatedAt: stale},
		enqueueRef: ExportJobRef{ID: "exp-2", Status: "queued", Format: "backup"},
	}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	_, body := postJob(t, base, "user-A", `{"format":"backup"}`)
	if body["job_id"] != "exp-2" || body["reused"] == true {
		t.Fatalf("body=%v, want a fresh enqueue past a stalled row", body)
	}
}

func TestJobs_PostIsRateLimitedAndBadFormatIs400(t *testing.T) {
	be := &fakeBackend{denied: true, retryAfter: 42}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, _ := postJob(t, base, "user-A", `{"format":"backup"}`)
	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("status=%d, want 429", resp.StatusCode)
	}
	if got := resp.Header.Get("Retry-After"); got != "42" {
		t.Fatalf("Retry-After=%q, want 42", got)
	}
	if len(be.enqueued) != 0 {
		t.Fatalf("a throttled request must enqueue nothing")
	}

	resp, _ = postJob(t, base, "user-A", `{"format":"xml"}`)
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status=%d, want 400", resp.StatusCode)
	}
}

func TestJobs_PostWithoutBearerIs401AndGetTooIsUnauthenticated(t *testing.T) {
	be := &fakeBackend{}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Post(base+"/v1/export/jobs", "application/json", strings.NewReader(`{"format":"csv"}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401", resp.StatusCode)
	}
	resp, err = http.Get(base + "/v1/export/jobs/latest")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401", resp.StatusCode)
	}
	if len(be.enqueued) != 0 {
		t.Fatalf("an unauthenticated request must reach no backend work")
	}
}

func TestJobs_LatestReportsNoneRatherThan404(t *testing.T) {
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: &fakeBackend{}}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, body := getLatest(t, base, "user-A")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status=%d, want 200", resp.StatusCode)
	}
	if body["status"] != StatusNone {
		t.Fatalf("status=%v, want %q — a page that reloads needs one shape to render", body["status"], StatusNone)
	}
}

func TestJobs_LatestSignsOnlyAReadyRow(t *testing.T) {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	count, total, complete := 7412, 7412, true
	for _, tc := range []struct {
		status  string
		wantURL bool
	}{
		{"queued", false},
		{"running", false},
		{"failed", false},
		{"expired", false},
		{"ready", true},
	} {
		be := &fakeBackend{
			signedURL: "https://signed.example/exports/abc",
			latestJob: &ExportJobRow{
				ID: "exp-1", Status: tc.status, Format: "backup",
				ObjectPath: "user-A/exports/abc.zip",
				RunCount:   &count, TotalRuns: &total, Complete: &complete,
				CreatedAt: now, UpdatedAt: now, FinishedAt: now,
			},
		}
		srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
		base, teardown := newTestServer(t, srv)

		_, body := getLatest(t, base, "user-A")
		_, gotURL := body["url"]
		if gotURL != tc.wantURL {
			t.Errorf("status=%s: url present=%v, want %v", tc.status, gotURL, tc.wantURL)
		}
		if !tc.wantURL && be.signCalls != 0 {
			t.Errorf("status=%s: signed an artifact that does not exist", tc.status)
		}
		if tc.wantURL {
			if body["count"] != float64(count) || body["complete"] != true {
				t.Errorf("a ready export must carry its own completeness verdict: %v", body)
			}
			if body["expires_in"] != float64(SignedURLTTLSec) {
				t.Errorf("expires_in=%v, want %d", body["expires_in"], SignedURLTTLSec)
			}
		}
		teardown()
	}
}

func TestJobs_LatestReportsAGoneArtifactAsExpiredNotAsAnOutage(t *testing.T) {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	be := &fakeBackend{
		signURLErr: errors.Join(errors.New("storage 404"), ErrArtifactGone),
		latestJob: &ExportJobRow{
			ID: "exp-1", Status: "ready", Format: "backup",
			ObjectPath: "user-A/exports/abc.zip", CreatedAt: now, UpdatedAt: now, FinishedAt: now,
		},
	}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, body := getLatest(t, base, "user-A")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status=%d, want 200 — an expired export is a fact to state, not an error", resp.StatusCode)
	}
	if body["status"] != "expired" {
		t.Fatalf("status=%v, want expired", body["status"])
	}
	if _, ok := body["url"]; ok {
		t.Fatal("an expired export must hand over no URL")
	}

	// A Storage outage is NOT an expiry.
	be.signURLErr = errors.New("503 from storage")
	be.signCalls = 0
	resp2, _ := getLatest(t, base, "user-A")
	if resp2.StatusCode != http.StatusInternalServerError {
		t.Fatalf("status=%d, want 500 — an outage must not be dressed up as an expiry", resp2.StatusCode)
	}
}

func TestJobs_LatestReportsAStalledBuildRatherThanBuildingForever(t *testing.T) {
	stale := time.Now().UTC().Add(-2 * ExportJobStaleAfter).Format(time.RFC3339Nano)
	be := &fakeBackend{latestJob: &ExportJobRow{
		ID: "exp-1", Status: "running", Format: "backup", CreatedAt: stale, UpdatedAt: stale,
	}}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	_, body := getLatest(t, base, "user-A")
	if body["status"] != StatusStalled {
		t.Fatalf("status=%v, want %q", body["status"], StatusStalled)
	}
}

func TestJobs_LatestKeepsBelievingARowThatIsStillWarm(t *testing.T) {
	warm := time.Now().UTC().Add(-ExportJobStaleAfter / 2).Format(time.RFC3339Nano)
	be := &fakeBackend{latestJob: &ExportJobRow{
		ID: "exp-1", Status: "running", Format: "backup", CreatedAt: warm, UpdatedAt: warm,
	}}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	_, body := getLatest(t, base, "user-A")
	if body["status"] != "running" {
		t.Fatalf("status=%v, want running", body["status"])
	}
}

func TestJobs_LatestWithAnUnparseableTimestampDoesNotDeclareTheExportDead(t *testing.T) {
	// Saying "still building" about a healthy export is recoverable;
	// declaring a live one dead sends the subject to start another.
	be := &fakeBackend{latestJob: &ExportJobRow{
		ID: "exp-1", Status: "running", Format: "backup", CreatedAt: "not-a-time", UpdatedAt: "not-a-time",
	}}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	_, body := getLatest(t, base, "user-A")
	if body["status"] != "running" {
		t.Fatalf("status=%v, want running", body["status"])
	}
}

func TestJobs_LatestCarriesTheFailureCode(t *testing.T) {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	be := &fakeBackend{latestJob: &ExportJobRow{
		ID: "exp-1", Status: "failed", Format: "backup", ErrorCode: "food_log_fetch_failed",
		CreatedAt: now, UpdatedAt: now, FinishedAt: now,
	}}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	_, body := getLatest(t, base, "user-A")
	if body["status"] != "failed" || body["error_code"] != "food_log_fetch_failed" {
		t.Fatalf("body=%v", body)
	}
}

func TestJobs_MethodsAreConstrained(t *testing.T) {
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: &fakeBackend{}}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/export/jobs")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("GET /v1/export/jobs status=%d, want 405", resp.StatusCode)
	}
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export/jobs/latest", strings.NewReader(`{}`))
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("POST /v1/export/jobs/latest status=%d, want 405", resp.StatusCode)
	}
}

// The auth + configuration gates that used to be pinned on the
// synchronous POST /v1/export (deleted with decisions.md § 724). They
// are the queued rail's gates now, and they are the ones that matter:
// this endpoint is the only way to ask for an Art 20 archive.

func TestJobs_MissingJwtSecretIs503(t *testing.T) {
	srv := &Server{} // no verifier
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Post(base+"/v1/export/jobs", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("POST status=%d, want 503", resp.StatusCode)
	}
	resp, err = http.Get(base + "/v1/export/jobs/latest")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("GET status=%d, want 503", resp.StatusCode)
	}
}

func TestJobs_ExpiredTokenIsRejected(t *testing.T) {
	be := &fakeBackend{}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export/jobs",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", -600))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401", resp.StatusCode)
	}
	if len(be.enqueued) != 0 {
		t.Fatalf("an expired token must enqueue nothing")
	}
}

func TestJobs_TokenWithoutExpIsRejected(t *testing.T) {
	// A correctly-signed token with the right `sub` but NO `exp` claim
	// (signTestToken omits exp when expDelta == 0). Without
	// WithExpirationRequired such a token is valid forever — it must be
	// rejected on this security boundary, same as livehub.
	be := &fakeBackend{}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPost, base+"/v1/export/jobs",
		strings.NewReader(`{"format":"backup"}`))
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-A", 0))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401 (no immortal tokens)", resp.StatusCode)
	}
}

func TestJobs_RateLimitRpcErrorFailsClosed(t *testing.T) {
	// A wave of 429s under a DB blip is preferable to free multi-MB
	// archives during the outage.
	be := &fakeBackend{rateErr: errors.New("db down")}
	srv := &Server{Verifier: supajwt.New(testJWTSecret, "", nil), Backend: be}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, _ := postJob(t, base, "user-A", `{"format":"backup"}`)
	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("status=%d, want 429 (fail-closed)", resp.StatusCode)
	}
	if len(be.enqueued) != 0 {
		t.Fatalf("a fail-closed throttle must enqueue nothing")
	}
}
