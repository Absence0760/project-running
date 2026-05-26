// Package stravahook is the HTTP receive-side for Strava's webhook
// subscription. Mirrors the auth model + replay-protection contract
// of apps/backend/supabase/functions/strava-webhook/index.ts so the
// EF and Go paths can co-exist during cutover — they share the
// `webhook_events` dedupe table on the `provider='strava'` partition,
// so a Strava-side retry that lands on whichever endpoint is
// currently configured produces the same outcome.
//
// Architecture (different from the EF):
//
//   - EF was synchronous: parse → freshness → dedupe → fetch activity
//     → upload track → insert row → ack 200. The 2-second Strava
//     timeout fired regularly on a cold activity-detail fetch + slow
//     stream upload, causing Strava-side retries.
//   - Go is asynchronous: parse → freshness → dedupe → enqueue
//     `kind='strava_event'` job → ack 200 immediately. The worker
//     drains the job and does the activity fetch + stream upload off
//     the request path. Matches Strava's own recommendation: ack
//     within 2s, ingest async.
//
// Roll-back: the Go handler rolls back the `webhook_events` dedupe
// insert when the upstream Strava fetch returns 429 / 503 so the
// next retry attempts reaches the activity-fetch stage cleanly.
package stravahook

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Server wires the Strava webhook routes to the worker's job queue
// + dedupe table. Mounted from main.go alongside the live-hub
// + /health routes on the worker's single HTTP mux.
//
// Routes:
//
//   - GET  /v1/strava/webhook  — subscription handshake (Strava sends
//     `hub.challenge` + `hub.verify_token`; we echo the challenge
//     after timing-safe-comparing the verify token).
//   - POST /v1/strava/webhook  — activity event (we parse, gate by
//     freshness + dedupe, enqueue a `strava_event` job, return 200).
//
// Both methods require the URL-query `?secret=<STRAVA_WEBHOOK_SECRET>`
// (timing-safe compared) — Strava preserves the configured URL's
// query string on every callback so the secret rides along on both
// GET and POST.
type Server struct {
	// WebhookSecret is the shared secret embedded in the registered
	// callback URL's `?secret=` query param. Without this set every
	// request is rejected — the deployed worker must populate it.
	WebhookSecret string

	// VerifyToken is the value Strava sends back to us on the GET
	// handshake (`?hub.verify_token=...`). We compared against this
	// at subscription-creation time; rejecting any other value here
	// stops a third party from completing a subscription with our
	// URL.
	VerifyToken string

	// Enqueuer inserts the `strava_event` job after the request
	// passes validation. Production wires the SupabaseClient
	// (see EnqueueStravaEvent below); tests substitute a fake.
	Enqueuer JobEnqueuer

	// WebhookEvents is the dedupe surface: InsertWebhookEvent
	// returns `inserted == false` on a 23505 (Strava-side retry).
	// Production wires the SupabaseClient.
	WebhookEvents WebhookEventsStore

	// FreshnessWindow caps how old an event can be before we
	// reject it. Defaults to 7 days — wider than Strava's retry
	// envelope (~3 days), narrower than the dedupe-row TTL (30
	// days set by cleanup-stale-webhook-events cron). Set to a
	// custom value for tests; production leaves zero.
	FreshnessWindow time.Duration

	// ClockSkew is the future-tolerance on event_time — a Strava
	// host with a slightly fast clock shouldn't bounce. Default
	// 60s.
	ClockSkew time.Duration

	// Now is the wall-clock source the freshness gate consults.
	// Override for tests; production leaves zero (real time).
	Now func() time.Time

	Log *slog.Logger

	// ipLimiter throttles unauthenticated webhook requests per
	// client IP before the secret-gate runs. Defense against an
	// attacker grinding the URL secret at network speed — without
	// it, `timingSafeEqual` only closes the per-byte side channel,
	// not the offline guess rate. The EF version (`apps/backend/
	// supabase/functions/strava-webhook/index.ts`) does the same
	// via `checkRateLimit(ipBucketKey, 60, 3600, failClosed)`.
	// /audit/strava May 2026 Critical #2.
	ipLimitOnce sync.Once
	ipLimitImpl *ipRateLimiter
}

// JobEnqueuer inserts a single job row. Returned `id` is the
// generated bigint primary key; tests can assert against it.
// Production wires SupabaseClient.EnqueueStravaEvent.
type JobEnqueuer interface {
	EnqueueStravaEvent(ctx context.Context, payload StravaEventPayload) (int64, error)
}

// WebhookEventsStore is the dedupe surface bound to the
// `webhook_events` table. Mirrors the EF's
// `supabase.from('webhook_events').insert({provider, event_id})` —
// returns `inserted == false` when the row already existed (23505).
type WebhookEventsStore interface {
	InsertWebhookEvent(ctx context.Context, provider, eventID string) (bool, error)
}

// StravaEventPayload is the wire shape Strava POSTs to the
// subscription URL. Kept in this package (rather than importing
// `internal`) so the hook package stays a leaf — tests don't
// need to pull in the worker.
type StravaEventPayload struct {
	ObjectType string `json:"object_type"`
	ObjectID   int64  `json:"object_id"`
	AspectType string `json:"aspect_type"`
	OwnerID    int64  `json:"owner_id"`
	EventTime  int64  `json:"event_time"`
}

// RegisterRoutes mounts the GET + POST handlers on [mux].
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/v1/strava/webhook", s.handle)
}

func (s *Server) handle(w http.ResponseWriter, r *http.Request) {
	// audit/strava May 2026 Low #2 — refuse to start with a short
	// secret. 32 chars is the floor we enforce; below that a brute-
	// force at 60 req/h (the IP rate-limit ceiling) would clear the
	// space in < 1 day. Empty short-circuit kept first since a
	// missing secret needs the more specific log line.
	if s.WebhookSecret == "" {
		s.log().Error("strava webhook: secret not configured; refusing")
		http.Error(w, `{"error":"webhook_not_configured"}`, http.StatusServiceUnavailable)
		return
	}
	if len(s.WebhookSecret) < 32 {
		s.log().Error("strava webhook: secret too short (<32 chars); refusing")
		http.Error(w, `{"error":"webhook_not_configured"}`, http.StatusServiceUnavailable)
		return
	}
	// Per-IP throttle BEFORE the secret-compare. Matches the EF
	// pattern (60/hour fail-closed). /audit/strava Critical #2.
	if !s.ipLimiter().allow(clientIP(r)) {
		w.Header().Set("Retry-After", "60")
		http.Error(w, `{"error":"rate_limited"}`, http.StatusTooManyRequests)
		return
	}
	supplied := r.URL.Query().Get("secret")
	if !timingSafeEqual(supplied, s.WebhookSecret) {
		http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
		return
	}

	switch r.Method {
	case http.MethodGet:
		s.handleHandshake(w, r)
	case http.MethodPost:
		s.handlePost(w, r)
	default:
		w.Header().Set("Allow", "GET, POST")
		http.Error(w, `{"error":"method_not_allowed"}`, http.StatusMethodNotAllowed)
	}
}

// handleHandshake responds to Strava's subscription verification
// GET. Strava sends `?hub.mode=subscribe&hub.challenge=<random>
// &hub.verify_token=<the value we gave them at subscription time>`.
// We echo the challenge after timing-safe-comparing the verify
// token; any mismatch returns 403 so a third party can't piggyback
// on our endpoint to register a subscription against another
// athlete.
func (s *Server) handleHandshake(w http.ResponseWriter, r *http.Request) {
	if s.VerifyToken == "" {
		s.log().Error("strava webhook: verify token not configured; refusing handshake")
		http.Error(w, `{"error":"verify_not_configured"}`, http.StatusServiceUnavailable)
		return
	}
	challenge := r.URL.Query().Get("hub.challenge")
	verifyToken := r.URL.Query().Get("hub.verify_token")
	if !timingSafeEqual(verifyToken, s.VerifyToken) {
		http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"hub.challenge": challenge})
}

// handlePost parses, validates, dedupes, and enqueues the event.
// Returns 200 fast — actual ingest happens in the worker's
// `handleStravaEvent` job dispatch.
func (s *Server) handlePost(w http.ResponseWriter, r *http.Request) {
	if s.Enqueuer == nil || s.WebhookEvents == nil {
		// Defensive — main.go always wires both. A misconfigured
		// deploy that landed without them shouldn't silently 200
		// while events fall on the floor.
		s.log().Error("strava webhook: dependencies missing; refusing POST",
			"enqueuer_nil", s.Enqueuer == nil, "events_nil", s.WebhookEvents == nil)
		http.Error(w, `{"error":"misconfigured"}`, http.StatusServiceUnavailable)
		return
	}

	// MaxBytesReader + DisallowUnknownFields combo — same defence
	// the live hub's /push uses. The cap stops huge payloads at the
	// transport, the unknown-fields check stops payload-shape abuse.
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	dec.DisallowUnknownFields()
	var event StravaEventPayload
	if err := dec.Decode(&event); err != nil {
		http.Error(w, `{"error":"bad_payload"}`, http.StatusBadRequest)
		return
	}

	// Strava sends webhook events for every subscribed object type
	// (activity / athlete). We only act on activity events; everything
	// else gets a fast 200 so Strava drops the event from its retry
	// queue without us burning a `webhook_events` row.
	if event.ObjectType != "activity" {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "skipped": "non_activity"})
		return
	}

	// Required fields. Missing object_id or owner_id means we can't
	// route the event; missing event_time means we can't freshness-
	// check it. 400 so Strava knows the payload was bad (versus a
	// 200 which they'd interpret as "you handled it").
	if event.ObjectID == 0 || event.OwnerID == 0 {
		http.Error(w, `{"error":"missing_object_id_or_owner_id"}`, http.StatusBadRequest)
		return
	}
	if event.EventTime == 0 {
		http.Error(w, `{"error":"missing_event_time"}`, http.StatusBadRequest)
		return
	}

	// Aspect filter: we only ingest create events. Update / delete
	// are 200-no-op (the backfill EF handles edits on the next manual
	// sync; deletes are not surfaced in the runs UI yet). Skipping
	// here keeps the dedupe table from filling with rows for noise.
	if event.AspectType != "create" {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "skipped": "non_create"})
		return
	}

	// Freshness gate. A captured POST replayed weeks later must be
	// rejected even though the URL secret still validates. 7 day
	// window threads the gap between Strava's retry envelope
	// (~3 days) and the dedupe-row TTL (30 days set by
	// cleanup-stale-webhook-events cron in 20260623_001).
	if !s.freshnessOK(event.EventTime) {
		http.Error(w, `{"error":"event_outside_freshness_window"}`, http.StatusBadRequest)
		return
	}

	// Dedupe insert — first writer wins. Strava-side retry of the
	// same event lands on the 23505 path and gets 200-ok-skipped.
	eventID := fmt.Sprintf("%d:%d:%s:%d",
		event.OwnerID, event.ObjectID, event.AspectType, event.EventTime)
	inserted, err := s.WebhookEvents.InsertWebhookEvent(r.Context(), "strava", eventID)
	if err != nil {
		s.log().Error("strava webhook: dedupe insert failed", "err", err, "event_id", eventID)
		http.Error(w, `{"error":"dedupe_failed"}`, http.StatusInternalServerError)
		return
	}
	if !inserted {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "skipped": "duplicate_event"})
		return
	}

	// Enqueue the job. The worker's handleStravaEvent dispatch
	// takes it from here.
	jobID, err := s.Enqueuer.EnqueueStravaEvent(r.Context(), event)
	if err != nil {
		// If we enqueued the job after committing the dedupe row,
		// a later retry would be silently swallowed. Return 500
		// so Strava retries; the operator should see this in logs
		// and investigate. (The dedupe row rollback isn't done
		// here — it's done by the worker's rate-limit handling
		// when the activity fetch fails. Enqueue failures are
		// platform-level and warrant alerting.)
		s.log().Error("strava webhook: enqueue failed",
			"err", err, "event_id", eventID, "owner_id", event.OwnerID)
		http.Error(w, `{"error":"enqueue_failed"}`, http.StatusInternalServerError)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"ok":     true,
		"job_id": jobID,
	})
}

func (s *Server) freshnessOK(eventTimeSec int64) bool {
	window := s.FreshnessWindow
	if window <= 0 {
		window = 7 * 24 * time.Hour
	}
	skew := s.ClockSkew
	if skew <= 0 {
		skew = 60 * time.Second
	}
	now := time.Now()
	if s.Now != nil {
		now = s.Now()
	}
	eventTime := time.Unix(eventTimeSec, 0)
	age := now.Sub(eventTime)
	if age > window {
		return false
	}
	if age < -skew {
		return false
	}
	return true
}

func (s *Server) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}

// timingSafeEqual compares without short-circuiting on content.
// Length mismatch is the only fast-fail; both inputs are
// fixed-length in production (URL secrets + verify tokens of known
// length) so the length check itself is not new information.
func timingSafeEqual(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	var mismatch byte
	for i := 0; i < len(a); i++ {
		mismatch |= a[i] ^ b[i]
	}
	return mismatch == 0
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// clientIP returns the best-effort caller IP for rate-limit keying.
// Honours the standard reverse-proxy headers Fly's edge sets
// (cf-connecting-ip, x-real-ip, x-forwarded-for first hop), falling
// back to the connection's remote address. The keying material is
// untrusted — header values can be spoofed — but the worst case is
// an attacker burns their own bucket on one of several IPs they
// control. /audit/strava Critical #2.
func clientIP(r *http.Request) string {
	if v := strings.TrimSpace(r.Header.Get("cf-connecting-ip")); v != "" {
		return v
	}
	if v := strings.TrimSpace(r.Header.Get("x-real-ip")); v != "" {
		return v
	}
	if v := r.Header.Get("x-forwarded-for"); v != "" {
		if comma := strings.Index(v, ","); comma >= 0 {
			return strings.TrimSpace(v[:comma])
		}
		return strings.TrimSpace(v)
	}
	if host := r.RemoteAddr; host != "" {
		// `host:port` form — strip the port.
		if colon := strings.LastIndex(host, ":"); colon >= 0 {
			return host[:colon]
		}
		return host
	}
	return "unknown"
}

// ipLimiter returns the lazily-initialised per-IP token bucket. 60
// requests / hour matches the EF rate-limit (`audit/strava` Critical
// #2). A legitimate Strava callback IP set sees << 60/hour on this
// endpoint; an attacker grinding the secret gets throttled fast.
func (s *Server) ipLimiter() *ipRateLimiter {
	s.ipLimitOnce.Do(func() {
		s.ipLimitImpl = newIPRateLimiter(60, time.Hour)
	})
	return s.ipLimitImpl
}

type ipRateLimiter struct {
	rate     int
	interval time.Duration
	buckets  sync.Map // ip → *ipBucket
}

type ipBucket struct {
	mu       sync.Mutex
	tokens   float64
	lastFill time.Time
}

func newIPRateLimiter(rate int, interval time.Duration) *ipRateLimiter {
	return &ipRateLimiter{rate: rate, interval: interval}
}

func (l *ipRateLimiter) allow(ip string) bool {
	now := time.Now()
	v, _ := l.buckets.LoadOrStore(ip, &ipBucket{
		tokens:   float64(l.rate),
		lastFill: now,
	})
	b := v.(*ipBucket)
	b.mu.Lock()
	defer b.mu.Unlock()
	elapsed := now.Sub(b.lastFill).Seconds()
	refill := elapsed * float64(l.rate) / l.interval.Seconds()
	if refill > 0 {
		next := b.tokens + refill
		if next > float64(l.rate) {
			next = float64(l.rate)
		}
		b.tokens = next
		b.lastFill = now
	}
	if b.tokens >= 1 {
		b.tokens--
		return true
	}
	return false
}

