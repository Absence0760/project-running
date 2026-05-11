package livehub

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
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
	Hub *Hub
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
		http.Error(w, err.Error(), http.StatusForbidden)
		return false
	}
	return true
}

func (s *Server) handlePush(w http.ResponseWriter, r *http.Request, runID string) {
	if !s.authorize(w, r, runID, ActionPush) {
		return
	}
	// MaxBytesReader caps the body; json.Decoder.DisallowUnknownFields
	// keeps a fat-finger-attacker from smuggling 4 KB of unknown keys
	// into a "valid" object that's still small enough to decode. Both
	// gates are needed: the cap stops huge payloads at the transport
	// layer, the unknown-fields check stops payload-shape abuse from
	// blowing past the policy.
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	dec.DisallowUnknownFields()
	var p Ping
	if err := dec.Decode(&p); err != nil {
		http.Error(w, "bad ping body: "+err.Error(), http.StatusBadRequest)
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
	if len(zones) == 0 {
		return false, nil
	}
	return IsInAnyZone(p.Lat, p.Lng, zones), nil
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

	// CloseRead spawns a reader goroutine that drains incoming frames
	// (we ignore them — the WS is server-streaming-only) and returns
	// a context that's cancelled when the peer closes or the read
	// errors. Without this we wouldn't notice a half-closed client
	// until the 25s ping cycle, leaking the subscriber in the
	// meantime — which the cleanup test pins in place.
	ctx := c.CloseRead(r.Context())

	ch, unsub := s.Hub.Subscribe(ctx, runID)
	defer unsub()

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
