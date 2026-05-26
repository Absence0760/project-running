package stravahook

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeEnqueuer records every enqueue call. The default `id` is 1;
// scripted errors return without recording.
type fakeEnqueuer struct {
	mu    sync.Mutex
	calls []StravaEventPayload
	err   error
}

func (f *fakeEnqueuer) EnqueueStravaEvent(_ context.Context, p StravaEventPayload) (int64, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return 0, f.err
	}
	f.calls = append(f.calls, p)
	return int64(len(f.calls)), nil
}

type fakeWebhookEvents struct {
	mu    sync.Mutex
	seen  map[string]bool
	err   error
}

func newFakeWebhookEvents() *fakeWebhookEvents {
	return &fakeWebhookEvents{seen: map[string]bool{}}
}

func (f *fakeWebhookEvents) InsertWebhookEvent(_ context.Context, provider, eventID string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return false, f.err
	}
	key := provider + ":" + eventID
	if f.seen[key] {
		return false, nil
	}
	f.seen[key] = true
	return true, nil
}

func newTestServer(t *testing.T, srv *Server) (string, func()) {
	t.Helper()
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	return ts.URL, ts.Close
}

func TestServer_GetHandshakeEchoesChallenge(t *testing.T) {
	srv := &Server{
		WebhookSecret: "url-secret",
		VerifyToken:   "verify-tok",
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/strava/webhook?secret=url-secret&hub.mode=subscribe&hub.challenge=abc123&hub.verify_token=verify-tok")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("status=%d, want 200", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	if !strings.Contains(string(body), `"hub.challenge":"abc123"`) {
		t.Errorf("body=%s, expected challenge echo", body)
	}
}

func TestServer_GetRejectsBadVerifyToken(t *testing.T) {
	srv := &Server{WebhookSecret: "url-secret", VerifyToken: "verify-tok"}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/strava/webhook?secret=url-secret&hub.challenge=abc&hub.verify_token=wrong")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 403 {
		t.Fatalf("status=%d, want 403", resp.StatusCode)
	}
}

func TestServer_RejectsMissingUrlSecret(t *testing.T) {
	srv := &Server{WebhookSecret: "url-secret", VerifyToken: "verify-tok"}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/strava/webhook?hub.challenge=abc&hub.verify_token=verify-tok")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 403 {
		t.Fatalf("status=%d, want 403", resp.StatusCode)
	}
}

func TestServer_RejectsWrongUrlSecret(t *testing.T) {
	srv := &Server{WebhookSecret: "url-secret", VerifyToken: "verify-tok"}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/strava/webhook?secret=wrong-secret")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 403 {
		t.Fatalf("status=%d, want 403", resp.StatusCode)
	}
}

func TestServer_MissingSecretConfigReturnsServiceUnavailable(t *testing.T) {
	// Operator misconfiguration — the env var didn't land on the
	// deploy. Refuse rather than silently accept unauthenticated
	// traffic.
	srv := &Server{} // no WebhookSecret
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/strava/webhook?secret=anything")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 503 {
		t.Fatalf("status=%d, want 503", resp.StatusCode)
	}
}

func TestServer_PostHappyPathEnqueuesJob(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	events := newFakeWebhookEvents()
	srv := &Server{
		WebhookSecret: "url-secret",
		VerifyToken:   "verify-tok",
		Enqueuer:      enqueuer,
		WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	body := `{"object_type":"activity","object_id":12345,"aspect_type":"create","owner_id":67890,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("status=%d, want 200", resp.StatusCode)
	}
	if len(enqueuer.calls) != 1 {
		t.Fatalf("expected 1 enqueue; got %d", len(enqueuer.calls))
	}
	got := enqueuer.calls[0]
	if got.ObjectID != 12345 || got.OwnerID != 67890 || got.AspectType != "create" {
		t.Errorf("enqueued payload wrong: %+v", got)
	}
}

func TestServer_PostSkipsNonActivity(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	events := newFakeWebhookEvents()
	srv := &Server{
		WebhookSecret: "url-secret", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	// `object_type=athlete` is an event we don't care about. 200 fast
	// so Strava drops it; nothing enqueued.
	body := `{"object_type":"athlete","object_id":1,"aspect_type":"update","owner_id":67890,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("status=%d, want 200", resp.StatusCode)
	}
	if len(enqueuer.calls) != 0 {
		t.Errorf("non-activity must not enqueue; got %d", len(enqueuer.calls))
	}
}

func TestServer_PostSkipsNonCreate(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	events := newFakeWebhookEvents()
	srv := &Server{
		WebhookSecret: "url-secret", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	body := `{"object_type":"activity","object_id":12345,"aspect_type":"update","owner_id":67890,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("status=%d, want 200", resp.StatusCode)
	}
	if len(enqueuer.calls) != 0 {
		t.Errorf("non-create must not enqueue; got %d", len(enqueuer.calls))
	}
	if len(events.seen) != 0 {
		t.Errorf("non-create must not burn a dedupe row")
	}
}

func TestServer_PostRejectsStaleEvent(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	events := newFakeWebhookEvents()
	srv := &Server{
		WebhookSecret: "url-secret", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
		FreshnessWindow: 1 * time.Hour,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	// Stamp event 25 hours ago — well past the 1h window we set.
	stale := time.Now().Add(-25 * time.Hour).Unix()
	body := `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":1,"event_time":` +
		jsonInt(stale) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status=%d, want 400 (freshness)", resp.StatusCode)
	}
	if len(enqueuer.calls) != 0 {
		t.Errorf("stale event must not enqueue")
	}
}

func TestServer_PostDedupesOnSecondInsert(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	events := newFakeWebhookEvents()
	srv := &Server{
		WebhookSecret: "url-secret", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	body := `{"object_type":"activity","object_id":12345,"aspect_type":"create","owner_id":67890,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`

	// First post — enqueues.
	resp1, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp1.Body.Close()
	// Second identical post — should be a no-op (dedupe wins).
	resp2, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp2.Body.Close()
	if resp2.StatusCode != 200 {
		t.Fatalf("dedupe second post should still 200; got %d", resp2.StatusCode)
	}
	if len(enqueuer.calls) != 1 {
		t.Fatalf("dedupe should keep enqueue count at 1; got %d", len(enqueuer.calls))
	}
	respBody, _ := io.ReadAll(resp2.Body)
	if !strings.Contains(string(respBody), "duplicate_event") {
		t.Errorf("dedupe response should flag duplicate_event; got %s", respBody)
	}
}

func TestServer_PostBadBodyReturns400(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	events := newFakeWebhookEvents()
	srv := &Server{
		WebhookSecret: "url-secret", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	// Unknown field — DisallowUnknownFields rejects.
	body := `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":1,"event_time":1700000000,"extra":"oops"}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status=%d, want 400", resp.StatusCode)
	}
}

func TestServer_PostMissingFieldsReturns400(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	events := newFakeWebhookEvents()
	srv := &Server{
		WebhookSecret: "url-secret", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	// Missing event_time.
	body := `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":1}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status=%d, want 400", resp.StatusCode)
	}
}

func TestServer_MethodNotAllowed(t *testing.T) {
	srv := &Server{WebhookSecret: "url-secret", VerifyToken: "verify-tok"}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPut, base+"/v1/strava/webhook?secret=url-secret", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 405 {
		t.Fatalf("status=%d, want 405", resp.StatusCode)
	}
	if resp.Header.Get("Allow") != "GET, POST" {
		t.Errorf("Allow header=%q, want 'GET, POST'", resp.Header.Get("Allow"))
	}
}

func TestServer_PostEnqueueErrorReturns500(t *testing.T) {
	enqueuer := &fakeEnqueuer{err: errFake}
	events := newFakeWebhookEvents()
	srv := &Server{
		WebhookSecret: "url-secret", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	body := `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":1,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 500 {
		t.Fatalf("status=%d, want 500 (Strava retries)", resp.StatusCode)
	}
}

// errFake is a sentinel used by the enqueue-error test.
type fakeErr struct{}

func (fakeErr) Error() string { return "fake" }

var errFake error = fakeErr{}

// jsonInt formats an int64 for inline JSON construction in tests.
func jsonInt(n int64) string {
	b, _ := json.Marshal(n)
	return string(b)
}

// audit/strava Critical #2 — per-IP throttle BEFORE the secret-gate.
func TestServer_IPRateLimitFiresBeforeSecretCompare(t *testing.T) {
	srv := &Server{
		WebhookSecret: "right-secret",
		VerifyToken:   "verify",
		Enqueuer:      &fakeEnqueuer{},
		WebhookEvents: &fakeWebhookEvents{},
	}
	// Force the limiter into "no tokens left" by pre-allocating a
	// custom one at rate=1/h and burning the first slot. The next
	// call (from the SAME IP) must 429 — and crucially it must NOT
	// fall through to the secret compare (which would 403 with a
	// wrong secret).
	srv.ipLimitImpl = newIPRateLimiter(1, time.Hour)
	srv.ipLimitOnce.Do(func() {})

	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)

	// First request burns the token.
	r1, _ := http.NewRequest("GET", ts.URL+"/v1/strava/webhook?secret=right-secret&hub.mode=subscribe&hub.verify_token=verify&hub.challenge=x", nil)
	r1.Header.Set("cf-connecting-ip", "1.2.3.4")
	resp, err := http.DefaultClient.Do(r1)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("first call should pass, got %d", resp.StatusCode)
	}

	// Second from same IP with the WRONG secret. A bypass of the
	// limiter would land at the secret-compare → 403; correct
	// behaviour is 429 (limiter fires first).
	r2, _ := http.NewRequest("POST", ts.URL+"/v1/strava/webhook?secret=WRONG", nil)
	r2.Header.Set("cf-connecting-ip", "1.2.3.4")
	resp2, err := http.DefaultClient.Do(r2)
	if err != nil {
		t.Fatal(err)
	}
	resp2.Body.Close()
	if resp2.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("expected 429 (rate-limit before secret), got %d", resp2.StatusCode)
	}
	if ra := resp2.Header.Get("Retry-After"); ra == "" {
		t.Fatal("Retry-After header should be set on 429")
	}
}

func TestServer_IPRateLimitPerKey(t *testing.T) {
	// Different IPs maintain independent buckets.
	srv := &Server{
		WebhookSecret: "secret",
		VerifyToken:   "v",
		Enqueuer:      &fakeEnqueuer{},
		WebhookEvents: &fakeWebhookEvents{},
	}
	srv.ipLimitImpl = newIPRateLimiter(1, time.Hour)
	srv.ipLimitOnce.Do(func() {})

	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)

	for _, ip := range []string{"1.1.1.1", "2.2.2.2", "3.3.3.3"} {
		r, _ := http.NewRequest("GET", ts.URL+"/v1/strava/webhook?secret=secret&hub.mode=subscribe&hub.verify_token=v&hub.challenge=c", nil)
		r.Header.Set("cf-connecting-ip", ip)
		resp, err := http.DefaultClient.Do(r)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("ip %s first call should pass, got %d", ip, resp.StatusCode)
		}
	}
}
