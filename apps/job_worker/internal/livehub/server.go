package livehub

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

// Server wires the [Hub] to HTTP handlers. Routes registered:
//
//   - POST /v1/live/{run_id}/push     — recorder pushes a ping body
//   - GET  /v1/live/{run_id}/snapshot — JSON last-known position
//   - GET  /v1/live/{run_id}/subscribe — WebSocket stream of pings
//
// Path-param parsing is intentionally manual (strings.TrimPrefix +
// strings.Split) so this package doesn't pull a router dep. The
// route shapes are stable and there are only three of them.
//
// **Privacy zones** — on every push the server fetches (or reads
// from the room cache) the broadcaster's privacy zones via
// [Server.Zones] and drops the ping when the lat/lng falls inside
// any zone. Mirrors the `live_run_pings_drop_in_zone` BEFORE-INSERT
// trigger on the Supabase Realtime path. When [Server.Zones] is
// nil the hub falls through unclipped — useful for dev / unit
// tests; production MUST set it.
type Server struct {
	// Hub is the pub/sub broker. Production wires either an
	// in-process [Hub] (zero deps; single replica) or a Redis-backed
	// [RedisHub] (multi-replica fan-out). The interface is wide
	// enough to cover the Publish + Subscribe + snapshot + per-room
	// caches the routes touch; see `iface.go`.
	Hub LivePubSub
	Log *slog.Logger

	// Zones resolves the broadcaster's privacy zones for a run.
	// Wired in `main.go` to a [SupabaseZoneFetcher]. When nil the
	// hub publishes every ping unclipped — appropriate for local
	// dev where there's no Supabase service-role key available.
	// Production deploys MUST set this.
	Zones ZoneFetcher

	// Authorizer is called once per request after the run_id is
	// parsed. It returns a non-nil error to deny the request (the
	// error becomes the response body and a 403 is sent). The
	// default is a permissive no-op — production should plug in a
	// Supabase JWT verifier that:
	//
	//   - on /push, confirms the caller's user_id matches
	//     runs.user_id for the run_id (the recorder is the only
	//     legitimate publisher),
	//   - on /subscribe + /snapshot, allows anon when the run is
	//     `is_public=true` and otherwise verifies the caller is
	//     the owner.
	//
	// Kept as a callback rather than baked in so this Hub package
	// stays generic + unit-testable without a Supabase client.
	Authorizer func(r *http.Request, runID string, action AuthAction) error

	// AllowedOrigins controls which `Origin` headers the WS
	// upgrade accepts. Empty → no origin check (dev). Set to the
	// production web host(s) for any non-localhost build.
	AllowedOrigins []string

	// pushLimit is the per-room token bucket protecting against a
	// runaway / hostile recorder spamming /push at 100 Hz. Lazy-
	// initialised on first push so dev / tests don't need to wire
	// it. Audit/livehub H1.
	pushLimitOnce sync.Once
	pushLimitImpl *pushRateLimiter
}

// pushLimiter returns the lazily-initialised per-room token bucket.
// 12 pushes per 60s matches the LiveBroadcaster's 5s cadence plus
// a small burst budget. Tunable at compile time.
func (s *Server) pushLimiter() *pushRateLimiter {
	s.pushLimitOnce.Do(func() {
		s.pushLimitImpl = newPushRateLimiter(12, time.Minute)
	})
	return s.pushLimitImpl
}

// StartLimiterGC sweeps idle push-rate-limiter buckets on a ticker
// until [ctx] is done. Returns immediately. Mirrors [Hub.StartGC];
// main.go starts it alongside the room GC so the per-run buckets are
// reaped "alongside their rooms" (at the same IdleRoomTTL) instead of
// leaking for the process lifetime.
func (s *Server) StartLimiterGC(ctx context.Context, interval, maxIdle time.Duration) {
	go func() {
		t := time.NewTicker(interval)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				s.pushLimiter().reap(time.Now(), maxIdle)
			}
		}
	}()
}

// pushRateLimiter is a per-key token-bucket with a sync.Map of
// `*roomBucket` for the in-process Hub. Each bucket regenerates one
// token per `interval/rate` seconds and caps at [rate]. Concurrent-
// safe. Idle buckets are reaped by [Server.StartLimiterGC] (the map is
// keyed by runID and otherwise grows by one entry per distinct run that
// ever pushes — a process-lifetime leak, since the room GC only reaps
// rooms, not these sibling buckets).
type pushRateLimiter struct {
	rate     int
	interval time.Duration
	buckets  sync.Map // runID → *roomBucket
}

type roomBucket struct {
	mu       sync.Mutex
	tokens   float64
	lastFill time.Time
}

func newPushRateLimiter(rate int, interval time.Duration) *pushRateLimiter {
	return &pushRateLimiter{rate: rate, interval: interval}
}

// reap deletes buckets whose last refill is older than maxIdle, judged
// at `now`, and returns the count dropped. A bucket idle longer than
// `interval` has already refilled to the full token cap, so dropping it
// loses no state — a later push just re-creates it at the same value.
// Safe for concurrent callers.
func (p *pushRateLimiter) reap(now time.Time, maxIdle time.Duration) int {
	dropped := 0
	p.buckets.Range(func(k, v any) bool {
		b := v.(*roomBucket)
		b.mu.Lock()
		idle := now.Sub(b.lastFill)
		b.mu.Unlock()
		if idle > maxIdle {
			p.buckets.Delete(k)
			dropped++
		}
		return true
	})
	return dropped
}

func (p *pushRateLimiter) allow(runID string) bool {
	now := time.Now()
	v, _ := p.buckets.LoadOrStore(runID, &roomBucket{
		tokens:   float64(p.rate),
		lastFill: now,
	})
	b := v.(*roomBucket)
	b.mu.Lock()
	defer b.mu.Unlock()
	elapsed := now.Sub(b.lastFill).Seconds()
	refill := elapsed * float64(p.rate) / p.interval.Seconds()
	if refill > 0 {
		b.tokens = minFloat(float64(p.rate), b.tokens+refill)
		b.lastFill = now
	}
	if b.tokens >= 1 {
		b.tokens -= 1
		return true
	}
	return false
}

// bumpDropZone + bumpAuthFail forward to the underlying Hub's
// atomic counters when the LivePubSub is the in-process *Hub. The
// Redis path doesn't expose the counters yet (those would live in
// Redis-side metrics like INCR keys); this is a best-effort
// instrumentation for the dev / single-replica case. /audit/livehub M1.
func (s *Server) bumpDropZone() {
	if h, ok := s.Hub.(*Hub); ok && h.metrics != nil {
		h.metrics.publishDropZone.Add(1)
	}
}

func (s *Server) bumpAuthFail() {
	if h, ok := s.Hub.(*Hub); ok && h.metrics != nil {
		h.metrics.authFailCount.Add(1)
	}
}

func minFloat(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

// AuthAction tags a request for the [Server.Authorizer] callback so
// a single function can branch on push vs subscribe vs snapshot.
type AuthAction string

const (
	ActionPush      AuthAction = "push"
	ActionSubscribe AuthAction = "subscribe"
	ActionSnapshot  AuthAction = "snapshot"
)

// RegisterRoutes mounts the three live-hub endpoints on [mux].
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/v1/live/", s.routeLive)
}

// routeLive dispatches /v1/live/{run_id}/{action}.
func (s *Server) routeLive(w http.ResponseWriter, r *http.Request) {
	trimmed := strings.TrimPrefix(r.URL.Path, "/v1/live/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		http.Error(w, "expected /v1/live/{run_id}/{push|snapshot|subscribe}", http.StatusNotFound)
		return
	}
	runID, action := parts[0], parts[1]
	switch action {
	case "push":
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		s.handlePush(w, r, runID)
	case "snapshot":
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", "GET")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		s.handleSnapshot(w, r, runID)
	case "subscribe":
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", "GET")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		s.handleSubscribe(w, r, runID)
	default:
		http.NotFound(w, r)
	}
}

func (s *Server) authorize(w http.ResponseWriter, r *http.Request, runID string, action AuthAction) bool {
	if s.Authorizer == nil {
		return true
	}
	if err := s.Authorizer(r, runID, action); err != nil {
		s.bumpAuthFail()
		http.Error(w, err.Error(), http.StatusForbidden)
		return false
	}
	return true
}

func (s *Server) handlePush(w http.ResponseWriter, r *http.Request, runID string) {
	if !s.authorize(w, r, runID, ActionPush) {
		return
	}
	// Per-room push rate-limit. Recorder cadence is one push per ~5 s
	// (LiveBroadcaster throttle); a token bucket of 12 / 60 s lets a
	// recorder catch up after a brief network stutter while capping
	// the abuse case where a stolen recorder JWT spams at 100 Hz.
	// Per-(user, run_id) would be ideal but every legitimate room is
	// already 1:1 user:run; per-runID catches the same abuse with no
	// JWT re-parse. Audit/livehub H1.
	if !s.pushLimiter().allow(runID) {
		w.Header().Set("Retry-After", "5")
		http.Error(w, "push rate exceeded", http.StatusTooManyRequests)
		return
	}
	// MaxBytesReader caps the request body at 4 KiB. DisallowUnknownFields
	// rejects payloads that smuggle in fields outside the Ping schema —
	// a defence-in-depth gate complementing the size cap. Both are
	// needed: size stops huge bodies at the transport layer; the
	// unknown-fields check stops shape abuse from blowing past the
	// policy with crafted JSON inside the limit. /audit/livehub L2.
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	dec.DisallowUnknownFields()
	var p Ping
	if err := dec.Decode(&p); err != nil {
		http.Error(w, "bad ping body: "+err.Error(), http.StatusBadRequest)
		return
	}
	// Envelope validation — audit/livehub M2. Catches NaN / out-of-
	// range coordinates / absurd BPM before the publish path.
	if err := p.Validate(); err != nil {
		http.Error(w, "invalid ping: "+err.Error(), http.StatusBadRequest)
		return
	}
	// Privacy-zone clip — fail-closed: if the zone fetch errors we
	// drop the ping rather than risk publishing through a broken
	// fetch. A persistent fetch failure surfaces in logs; a runner's
	// home address must never leak as a side effect of a Supabase
	// outage.
	clipped, err := s.shouldDrop(r.Context(), runID, p)
	if err != nil {
		s.log().Warn("zone fetch failed; dropping ping",
			"err", err, "run_id", runID)
		s.bumpDropZone()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ok":      false,
			"clipped": true,
			"reason":  "zone fetch failed",
		})
		return
	}
	if clipped {
		s.bumpDropZone()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ok":               true,
			"clipped":          true,
			"subscribers_sent": 0,
		})
		return
	}
	delivered := s.Hub.Publish(runID, p)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"ok":               true,
		"subscribers_sent": delivered,
	})
}

// shouldDrop checks the ping against the broadcaster's cached
// privacy zones. Returns (true, nil) when the ping must be dropped,
// (false, nil) when it can be published, or (_, err) when the zone
// fetch itself failed (caller drops fail-closed).
//
// Skips the check entirely when [Server.Zones] is nil — the dev
// path. The 100% safe production wiring sets a real fetcher in
// main.go.
func (s *Server) shouldDrop(ctx context.Context, runID string, p Ping) (bool, error) {
	if s.Zones == nil {
		return false, nil
	}
	zones, err := s.Hub.LoadZones(ctx, runID, s.Zones)
	if err != nil {
		return false, err
	}
	// Log at debug so an operator can distinguish "no zones
	// configured" from "zones configured but ping out of zone" in
	// the drop-rate metric. /audit/livehub L3.
	if len(zones) == 0 {
		s.log().Debug("zone check: broadcaster has no zones", "run_id", runID)
		return false, nil
	}
	drop := IsInAnyZone(p.Lat, p.Lng, zones)
	if drop {
		s.log().Debug("zone check: ping in zone, dropping", "run_id", runID, "zone_count", len(zones))
	}
	return drop, nil
}

func (s *Server) handleSnapshot(w http.ResponseWriter, r *http.Request, runID string) {
	if !s.authorize(w, r, runID, ActionSnapshot) {
		return
	}
	last := s.Hub.LastKnown(runID)
	w.Header().Set("Content-Type", "application/json")
	if last == nil {
		// 204 No Content rather than 404 — the room is just empty,
		// which is a fine state (no pings yet, or run hasn't started).
		// Spectators can poll snapshot or open the subscribe stream.
		w.WriteHeader(http.StatusNoContent)
		return
	}
	// Re-evaluate privacy zones against the cached ping. shouldDrop
	// runs against the CURRENT zones — a zone added mid-broadcast (or
	// loaded after the cache TTL refresh) would catch a coord the
	// cached ping was published before. Fail-closed on fetch error
	// matches the /push path's contract. Persona-hunt Pro-Round2 #1.
	drop, err := s.shouldDrop(r.Context(), runID, *last)
	if err != nil {
		s.log().Warn("snapshot zone check failed; dropping", "err", err, "run_id", runID)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if drop {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	_ = json.NewEncoder(w).Encode(last)
}

func (s *Server) handleSubscribe(w http.ResponseWriter, r *http.Request, runID string) {
	if !s.authorize(w, r, runID, ActionSubscribe) {
		return
	}
	acceptOpts := &websocket.AcceptOptions{
		OriginPatterns: s.AllowedOrigins,
	}
	if len(s.AllowedOrigins) == 0 {
		// Empty list → CHIP origin check skipped. Acceptable for dev /
		// the LAN-only smoke test; production should always set at
		// least one origin.
		acceptOpts.InsecureSkipVerify = true
	}
	c, err := websocket.Accept(w, r, acceptOpts)
	if err != nil {
		s.log().Warn("ws accept failed", "err", err, "run_id", runID)
		return
	}
	defer c.CloseNow()

	// Bound inbound message size before CloseRead starts draining
	// frames. The WS is server-streaming-only — clients have no
	// legitimate reason to send anything larger than a control frame.
	// 1 KiB is a comfortable cap for the close handshake + any
	// reasonable client-side ping. Audit/livehub M7.
	c.SetReadLimit(1024)

	// CloseRead spawns a reader goroutine that drains incoming frames
	// (we ignore them — the WS is server-streaming-only) and returns
	// a context that's cancelled when the peer closes or the read
	// errors. Without this we wouldn't notice a half-closed client
	// until the 25s ping cycle, leaking the subscriber in the
	// meantime — which the cleanup test pins in place.
	ctx := c.CloseRead(r.Context())

	// SubscribeWithHistory atomically snapshots the late-joiner history
	// AND registers the (no-replay) subscriber under one lock, so the
	// replay slice and the live `ch` partition the ping stream with no
	// gap and no overlap. The earlier SubscribeNoReplay + separate
	// History pair left a window: a ping landing between the register
	// and the snapshot was either replayed AND streamed (a duplicate
	// dot) or, if a long replay let the 8-slot live buffer fill, dropped
	// from the live stream. No-replay (not the auto-lastPing replay) so
	// server.go can still re-evaluate each replayed ping against CURRENT
	// privacy zones — a zone added mid-broadcast must be honoured by the
	// late-joiner replay, not just by future /push calls. Persona-hunt
	// Pro-Round2 #1 + the dedup race.
	history, ch, unsub, subErr := s.Hub.SubscribeWithHistory(ctx, runID, 0)
	if subErr != nil {
		// Per-room subscriber cap reached. Audit/livehub M3. Close
		// with `1013 Try Again Later` (StatusTryAgainLater) so well-
		// behaved clients back off rather than reconnect-loop. Also
		// log so the operator metric on "cap hits per minute" has a
		// signal even before Prometheus is wired.
		s.log().Warn("subscribe rejected (cap reached)", "run_id", runID, "err", subErr)
		_ = c.Close(websocket.StatusTryAgainLater, "subscriber cap reached")
		return
	}
	defer unsub()

	// Late-joiner replay. Persona-hunt Round 3 finding Ultra #1 —
	// pre-fix we only sent the last ping, so a crew rolling up at
	// mile 60 of a 100-mile race saw a single dot with no historical
	// course. We replay up to HistoryRingSize recent pings (snapshotted
	// atomically above), re-evaluating each against current privacy
	// zones. The live stream then picks up from the next Publish via
	// `ch`.
	if len(history) == 0 {
		// Backstop: pre-rollout rooms (or RedisHub instances without
		// a history list) still expose LastKnown. Use it so a
		// freshly-deployed hub doesn't regress the dot-only behaviour.
		if last := s.Hub.LastKnown(runID); last != nil {
			history = []Ping{*last}
		}
	}
	for _, p := range history {
		drop, err := s.shouldDrop(ctx, runID, p)
		if err != nil {
			s.log().Warn("subscribe zone check failed; suppressing replay", "err", err, "run_id", runID)
			break
		}
		if drop {
			continue
		}
		writeCtx, writeCancel := context.WithTimeout(ctx, 10*time.Second)
		werr := wsjson.Write(writeCtx, c, p)
		writeCancel()
		if werr != nil {
			if !errors.Is(werr, context.Canceled) {
				s.log().Debug("ws late-joiner write failed", "err", werr, "run_id", runID)
			}
			return
		}
	}

	// Ping every 25 s so an intermediate proxy doesn't idle-timeout
	// the connection. CloudFront's default idle is 60 s; 25 s leaves
	// generous slack. The peer pong is verified by coder/websocket
	// internally — a stuck client is detected within ~30 s.
	pingCtx, cancelPing := context.WithCancel(ctx)
	defer cancelPing()
	go func() {
		t := time.NewTicker(25 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-pingCtx.Done():
				return
			case <-t.C:
				pctx, pc := context.WithTimeout(pingCtx, 10*time.Second)
				if err := c.Ping(pctx); err != nil {
					pc()
					_ = c.Close(websocket.StatusGoingAway, "ping timeout")
					return
				}
				pc()
			}
		}
	}()

	for {
		select {
		case <-ctx.Done():
			_ = c.Close(websocket.StatusNormalClosure, "client gone")
			return
		case p, ok := <-ch:
			if !ok {
				// Hub closed the subscriber (e.g. server shutdown).
				_ = c.Close(websocket.StatusGoingAway, "hub closed")
				return
			}
			writeCtx, writeCancel := context.WithTimeout(ctx, 10*time.Second)
			err := wsjson.Write(writeCtx, c, p)
			writeCancel()
			if err != nil {
				if !errors.Is(err, context.Canceled) {
					s.log().Debug("ws write failed", "err", err, "run_id", runID)
				}
				return
			}
		}
	}
}

func (s *Server) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}
