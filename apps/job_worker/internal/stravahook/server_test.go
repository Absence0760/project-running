package stravahook

import (
	"context"
	"encoding/json"
	"fmt"
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef",
		VerifyToken:   "verify-tok",
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef&hub.mode=subscribe&hub.challenge=abc123&hub.verify_token=verify-tok")
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
	srv := &Server{WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok"}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Get(base + "/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef&hub.challenge=abc&hub.verify_token=wrong")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 403 {
		t.Fatalf("status=%d, want 403", resp.StatusCode)
	}
}

func TestServer_RejectsMissingUrlSecret(t *testing.T) {
	srv := &Server{WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok"}
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
	srv := &Server{WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok"}
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

func TestServer_AcceptsSecretFromHeader(t *testing.T) {
	// The header path exists so the secret stops riding in the query
	// string, where every request log line records it verbatim. Strava
	// itself can only be configured with a URL, so the query path stays
	// — but any other caller (and Strava, once re-registered) should use
	// the header.
	srv := &Server{WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok"}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, err := http.NewRequest(http.MethodGet, base+"/v1/strava/webhook?hub.challenge=abc123&hub.verify_token=verify-tok", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(WebhookSecretHeader, "url-secret-32-chars-long-deadbeef")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("status=%d, want 200", resp.StatusCode)
	}
	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body["hub.challenge"] != "abc123" {
		t.Fatalf("hub.challenge=%q, want abc123", body["hub.challenge"])
	}
}

func TestServer_WrongHeaderSecretDoesNotFallBackToQuery(t *testing.T) {
	// A caller that supplies the header gets ONE judgement on it. If a
	// wrong header fell through to the query param, an attacker who
	// learned the URL secret from a log could keep using it while
	// probing the header, and the header path would add nothing.
	srv := &Server{WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok"}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, err := http.NewRequest(http.MethodGet, base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef&hub.challenge=abc&hub.verify_token=verify-tok", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(WebhookSecretHeader, "wrong-secret")
	resp, err := http.DefaultClient.Do(req)
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef",
		VerifyToken:   "verify-tok",
		Enqueuer:      enqueuer,
		WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	body := `{"object_type":"activity","object_id":12345,"aspect_type":"create","owner_id":67890,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	// `object_type=athlete` is an event we don't care about. 200 fast
	// so Strava drops it; nothing enqueued.
	body := `{"object_type":"athlete","object_id":1,"aspect_type":"update","owner_id":67890,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	body := `{"object_type":"activity","object_id":12345,"aspect_type":"update","owner_id":67890,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
		FreshnessWindow: 1 * time.Hour,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	// Stamp event 25 hours ago — well past the 1h window we set.
	stale := time.Now().Add(-25 * time.Hour).Unix()
	body := `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":1,"event_time":` +
		jsonInt(stale) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	body := `{"object_type":"activity","object_id":12345,"aspect_type":"create","owner_id":67890,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`

	// First post — enqueues.
	resp1, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp1.Body.Close()
	// Second identical post — should be a no-op (dedupe wins).
	resp2, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	// Unknown field — DisallowUnknownFields rejects.
	body := `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":1,"event_time":1700000000,"extra":"oops"}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	// Missing event_time.
	body := `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":1}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status=%d, want 400", resp.StatusCode)
	}
}

func TestServer_MethodNotAllowed(t *testing.T) {
	srv := &Server{WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok"}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	req, _ := http.NewRequest(http.MethodPut, base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", nil)
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
		WebhookSecret: "url-secret-32-chars-long-deadbeef", VerifyToken: "verify-tok",
		Enqueuer: enqueuer, WebhookEvents: events,
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	body := `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":1,"event_time":` +
		jsonInt(time.Now().Unix()) + `}`
	resp, err := http.Post(base+"/v1/strava/webhook?secret=url-secret-32-chars-long-deadbeef", "application/json", strings.NewReader(body))
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
		WebhookSecret: "right-secret-32-chars-long-deadbf",
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
	r1, _ := http.NewRequest("GET", ts.URL+"/v1/strava/webhook?secret=right-secret-32-chars-long-deadbf&hub.mode=subscribe&hub.verify_token=verify&hub.challenge=x", nil)
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
	r2, _ := http.NewRequest("POST", ts.URL+"/v1/strava/webhook?secret=WRONG-still-32-chars-long-deadbeef", nil)
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
		WebhookSecret: "secret-32-chars-long-deadbeef-yyyy",
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
		r, _ := http.NewRequest("GET", ts.URL+"/v1/strava/webhook?secret=secret-32-chars-long-deadbeef-yyyy&hub.mode=subscribe&hub.verify_token=v&hub.challenge=c", nil)
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

// TestIPRateLimiterTableStaysBounded pins the limiter table's size. clientIP
// keys on caller-supplied forwarding headers and the throttle runs before the
// shared-secret compare, so an unauthenticated caller could mint one permanent
// bucket per fabricated header value — 500k of them retained ~88 MB for the
// process lifetime, in the process the job-drain loop runs in.
func TestIPRateLimiterTableStaysBounded(t *testing.T) {
	l := newIPRateLimiter(60, time.Hour)
	now := time.Unix(1_700_000_000, 0)
	for i := 0; i < 200_000; i++ {
		l.allow(fmt.Sprintf("10.%d.%d.%d", i>>16&255, i>>8&255, i&255), now)
	}
	l.mu.Lock()
	n := len(l.buckets)
	l.mu.Unlock()
	if n > maxIPBuckets {
		t.Fatalf("limiter retained %d buckets after 200k distinct keys, cap is %d", n, maxIPBuckets)
	}
}

// TestIPRateLimiterEvictsIdleButKeepsLiveThrottle pins that bounding the table
// didn't cost the throttle: a caller inside the window still gets cut off at
// the rate, and a bucket that has sat idle past the refill interval (and is
// therefore back at the full token cap) is dropped rather than kept forever.
func TestIPRateLimiterEvictsIdleButKeepsLiveThrottle(t *testing.T) {
	l := newIPRateLimiter(3, time.Hour)
	now := time.Unix(1_700_000_000, 0)

	for i := 0; i < 3; i++ {
		if !l.allow("1.2.3.4", now) {
			t.Fatalf("request %d inside the rate was throttled", i)
		}
	}
	if l.allow("1.2.3.4", now) {
		t.Fatal("4th request in the window should be throttled")
	}

	// Two hours on: the idle bucket has refilled to the cap, so it carries no
	// state and the next new key's eviction pass drops it.
	later := now.Add(2 * time.Hour)
	l.allow("5.6.7.8", later)
	l.mu.Lock()
	_, stillThere := l.buckets["1.2.3.4"]
	l.mu.Unlock()
	if stillThere {
		t.Fatal("bucket idle past the refill interval should have been evicted")
	}
}
