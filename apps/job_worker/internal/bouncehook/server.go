// Package bouncehook is the HTTP receive-side for the email provider's
// bounce / complaint webhook. A hard bounce or a spam complaint must add the
// address to email_suppressions so no future bulk/engagement send (the weekly
// digest, later the lifecycle drip) ever re-mails it — the suppression row is
// the hard block the digest builder + handler consult independently of the
// recipient's opt-in pref. The doc's explicitly-outstanding piece for an
// enabled digest send: docs/features/email.md § Engagement.
//
// Architecture (mirrors internal/stravahook):
//
//   - One route, POST /v1/email/bounce, mounted on the worker's single mux
//     alongside /health, the live hub, the Strava hook, and the unsubscribe
//     endpoint.
//   - Auth is a shared URL secret (?secret=<EMAIL_BOUNCE_WEBHOOK_SECRET>),
//     timing-safe compared, behind a per-IP rate limit — the same posture the
//     Strava hook uses. Resend signs with a Svix header and SES wraps SNS;
//     rather than carry two verifier crypto stacks, we gate on the shared
//     secret embedded in the registered callback URL (every provider preserves
//     the configured URL's query string). A short secret (<32 chars) is
//     refused at request time so a brute-force can't clear the space.
//   - The body is parsed permissively across the two provider shapes we may
//     deploy behind (Resend event JSON / SES-over-SNS notification JSON). A
//     hard bounce or a complaint yields one suppression insert per affected
//     address (reason 'bounce' | 'complaint'); a soft bounce / delivery / open
//     is a fast 200 no-op (a transient soft bounce must NOT permanently block
//     an address). InsertEmailSuppression is idempotent on the email PK, so a
//     provider retry of the same event is harmless.
//
// Synchronous by design: the only work is one (or few) idempotent suppression
// inserts — there's no slow upstream fetch to push off the request path the
// way the Strava hook enqueues a job. We ack after the inserts land so the
// provider doesn't retry a write we already committed.
package bouncehook

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Backend is the suppression surface the endpoint exercises. Leaf interface so
// the package tests without importing `internal`. *SupabaseClient satisfies it
// directly (InsertEmailSuppression already exists for the unsubscribe path).
type Backend interface {
	// InsertEmailSuppression adds the address to email_suppressions with the
	// given reason. Idempotent on the email primary key.
	InsertEmailSuppression(ctx context.Context, email, reason string) error
}

// Server wires the bounce/complaint webhook. Mounted from main.go.
type Server struct {
	// Secret is the shared secret embedded in the registered callback URL's
	// `?secret=` query param. Empty → every request is refused (503); a
	// secret shorter than 32 chars is also refused (brute-force floor). This
	// matches the Strava hook's posture.
	Secret  string
	Backend Backend
	Log     *slog.Logger

	ipLimitOnce sync.Once
	ipLimitImpl *ipRateLimiter
}

// RegisterRoutes mounts the bounce/complaint endpoint.
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/v1/email/bounce", s.handle)
}

func (s *Server) handle(w http.ResponseWriter, r *http.Request) {
	if s.Secret == "" {
		s.log().Error("bouncehook: secret not configured; refusing")
		http.Error(w, `{"error":"webhook_not_configured"}`, http.StatusServiceUnavailable)
		return
	}
	if len(s.Secret) < 32 {
		s.log().Error("bouncehook: secret too short (<32 chars); refusing")
		http.Error(w, `{"error":"webhook_not_configured"}`, http.StatusServiceUnavailable)
		return
	}
	if s.Backend == nil {
		s.log().Error("bouncehook: backend missing; refusing POST")
		http.Error(w, `{"error":"misconfigured"}`, http.StatusServiceUnavailable)
		return
	}
	if !s.ipLimiter().allow(clientIP(r)) {
		w.Header().Set("Retry-After", "60")
		http.Error(w, `{"error":"rate_limited"}`, http.StatusTooManyRequests)
		return
	}
	if !timingSafeEqual(r.URL.Query().Get("secret"), s.Secret) {
		http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		http.Error(w, `{"error":"method_not_allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	// 64 KiB cap — an SES-over-SNS complaint notification carries the full
	// message headers and can be a few KiB; 64 KiB is generous without
	// inviting a payload-flood. No DisallowUnknownFields here (unlike the
	// Strava hook): provider event bodies carry many fields we ignore, and we
	// only read the handful that classify the event.
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64*1024))
	var raw json.RawMessage
	if err := dec.Decode(&raw); err != nil {
		http.Error(w, `{"error":"bad_payload"}`, http.StatusBadRequest)
		return
	}

	addrs := classify(raw)
	if len(addrs) == 0 {
		// Soft bounce / delivery / open / unrecognised shape → fast 200 no-op.
		// A soft bounce must NOT permanently suppress; only hard bounce +
		// complaint reach here with addresses.
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "suppressed": 0})
		return
	}

	suppressed := 0
	for _, a := range addrs {
		if err := s.Backend.InsertEmailSuppression(r.Context(), a.email, a.reason); err != nil {
			// A write failure must surface as 500 so the provider retries —
			// dropping a bounce silently would let us keep mailing a dead /
			// complaining address. The insert is idempotent, so a retry that
			// partially succeeded before is safe.
			s.log().Error("bouncehook: suppression insert failed", "err", err, "reason", a.reason)
			http.Error(w, `{"error":"suppression_insert_failed"}`, http.StatusInternalServerError)
			return
		}
		suppressed++
	}
	s.log().Info("bouncehook: suppressed addresses", "count", suppressed)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "suppressed": suppressed})
}

func (s *Server) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}

// suppression is one address to hard-block with the reason that classified it.
type suppression struct {
	email  string
	reason string // 'bounce' | 'complaint'
}

// classify reads a provider event body and returns the addresses to suppress.
// It understands two shapes:
//
//   - Resend event JSON: `{"type":"email.bounced"|"email.complained",
//     "data":{"to":["a@x"], ... ,"bounce":{"type":"Permanent"}}}`. Resend's
//     bounce event carries `data.bounce.type`; only a Permanent bounce
//     suppresses (a Transient soft bounce is a no-op). A complaint always
//     suppresses.
//   - SES-over-SNS JSON: the SNS envelope's `Message` is itself a JSON string
//     holding `{"notificationType":"Bounce"|"Complaint", "bounce":{
//     "bounceType":"Permanent", "bouncedRecipients":[{"emailAddress":...}]},
//     "complaint":{"complainedRecipients":[{"emailAddress":...}]}}`. Only a
//     Permanent bounce suppresses.
//
// Unknown shapes / soft bounces / delivery / open events return nil → 200 no-op.
func classify(raw json.RawMessage) []suppression {
	if out := classifyResend(raw); len(out) > 0 {
		return out
	}
	return classifySES(raw)
}

func classifyResend(raw json.RawMessage) []suppression {
	var ev struct {
		Type string `json:"type"`
		Data struct {
			To     []string `json:"to"`
			Email  string   `json:"email"`
			Bounce struct {
				Type string `json:"type"`
			} `json:"bounce"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &ev); err != nil {
		return nil
	}
	var reason string
	switch ev.Type {
	case "email.bounced":
		// Only a permanent (hard) bounce suppresses. An absent bounce.type is
		// treated as permanent — Resend emits the bounced event for hard
		// bounces; a missing subtype shouldn't let a dead address through.
		if t := strings.ToLower(ev.Data.Bounce.Type); t == "transient" || t == "soft" {
			return nil
		}
		reason = "bounce"
	case "email.complained":
		reason = "complaint"
	default:
		return nil
	}
	return dedupeAddrs(append(ev.Data.To, ev.Data.Email), reason)
}

func classifySES(raw json.RawMessage) []suppression {
	// The SNS envelope carries the SES notification as a JSON string in
	// `Message`. Some test/manual posts send the SES notification directly
	// (no SNS wrapper), so fall back to parsing `raw` itself.
	var envelope struct {
		Message string `json:"Message"`
	}
	body := raw
	if err := json.Unmarshal(raw, &envelope); err == nil && envelope.Message != "" {
		body = json.RawMessage(envelope.Message)
	}

	var note struct {
		NotificationType string `json:"notificationType"`
		Bounce           struct {
			BounceType        string `json:"bounceType"`
			BouncedRecipients []struct {
				EmailAddress string `json:"emailAddress"`
			} `json:"bouncedRecipients"`
		} `json:"bounce"`
		Complaint struct {
			ComplainedRecipients []struct {
				EmailAddress string `json:"emailAddress"`
			} `json:"complainedRecipients"`
		} `json:"complaint"`
	}
	if err := json.Unmarshal(body, &note); err != nil {
		return nil
	}

	switch note.NotificationType {
	case "Bounce":
		// SES bounceType: Permanent | Transient | Undetermined. Only Permanent
		// suppresses; a Transient soft bounce is retried by SES and must not
		// permanently block. Undetermined is treated as transient (don't block
		// on ambiguity).
		if !strings.EqualFold(note.Bounce.BounceType, "Permanent") {
			return nil
		}
		emails := make([]string, 0, len(note.Bounce.BouncedRecipients))
		for _, r := range note.Bounce.BouncedRecipients {
			emails = append(emails, r.EmailAddress)
		}
		return dedupeAddrs(emails, "bounce")
	case "Complaint":
		emails := make([]string, 0, len(note.Complaint.ComplainedRecipients))
		for _, r := range note.Complaint.ComplainedRecipients {
			emails = append(emails, r.EmailAddress)
		}
		return dedupeAddrs(emails, "complaint")
	default:
		return nil
	}
}

// dedupeAddrs lowercases, trims, drops empties, and de-duplicates the address
// list, pairing each with the reason. Addresses are normalised lower-case so a
// later send-side lookup (which keys on the address as stored) matches
// regardless of the casing the provider reported.
func dedupeAddrs(emails []string, reason string) []suppression {
	seen := map[string]struct{}{}
	out := make([]suppression, 0, len(emails))
	for _, e := range emails {
		e = strings.ToLower(strings.TrimSpace(e))
		if e == "" {
			continue
		}
		if _, dup := seen[e]; dup {
			continue
		}
		seen[e] = struct{}{}
		out = append(out, suppression{email: e, reason: reason})
	}
	return out
}

// timingSafeEqual compares without short-circuiting on content. Length
// mismatch is the only fast-fail (both inputs are fixed-length URL secrets in
// production). Same helper shape as stravahook.
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

// clientIP returns the best-effort caller IP for rate-limit keying. Honours
// the reverse-proxy headers Fly's edge sets, falling back to RemoteAddr. Same
// shape as stravahook.clientIP.
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
		if colon := strings.LastIndex(host, ":"); colon >= 0 {
			return host[:colon]
		}
		return host
	}
	return "unknown"
}

func (s *Server) ipLimiter() *ipRateLimiter {
	s.ipLimitOnce.Do(func() {
		s.ipLimitImpl = newIPRateLimiter(120, time.Hour)
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
	v, _ := l.buckets.LoadOrStore(ip, &ipBucket{tokens: float64(l.rate), lastFill: now})
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
