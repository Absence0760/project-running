// Package livehub is the in-process pub/sub hub the Go service uses
// to fan out live spectator pings.
//
// The pipeline:
//
//  1. Mobile recorder POSTs ping bodies to /v1/live/{run_id}/push
//     while a run is in flight (already implemented Dart-side via
//     LiveBroadcaster — currently writing to live_run_pings + Supabase
//     Realtime; the migration is to route through this hub instead).
//  2. Hub.Publish stores the latest position in an in-memory ring
//     buffer keyed by run_id and broadcasts to every subscriber.
//  3. Spectators WS-connect to /v1/live/{run_id}/subscribe. The hub
//     replays the last-known position on connect (so late joiners
//     see the runner immediately) then streams new pings.
//
// Today the buffer is either an in-process map (Hub) or Redis pub/
// sub (RedisHub) selected by main.go based on REDIS_URL. Both
// implement the LivePubSub interface in iface.go.
//
// Auth + private-run gating: server.go wires JWTAuthorizer from
// auth.go when SUPABASE_JWT_SECRET is set (production) and falls
// through to permissive mode when unset (dev only — prod startup
// refuses via LIVEHUB_REQUIRE_AUTH=1, see main.go). /audit/livehub
// May 2026 L1.
package livehub

import (
	"errors"
	"math"
)

// Ping is the wire shape published by the mobile recorder and
// streamed to spectators. Mirrors the columns on `live_run_pings`
// minus the run_id (which lives on the URL path) and the server-
// stamped `inserted_at`.
type Ping struct {
	Lat       float64  `json:"lat"`
	Lng       float64  `json:"lng"`
	DistanceM float64  `json:"distance_m"`
	ElapsedS  int      `json:"elapsed_s"`
	BPM       *int     `json:"bpm,omitempty"`
	Elevation *float64 `json:"ele,omitempty"`
	// SentAtMs is the recorder's local clock at the time of the ping
	// (Unix ms). The hub passes it through unchanged so a spectator
	// can compute end-to-end latency against their own clock.
	SentAtMs int64 `json:"sent_at_ms,omitempty"`
}

// Validate enforces a sane envelope on every field. Rejects NaN /
// Inf (which json.Decoder accepts when the body has `"NaN"`-ish
// literals in non-strict modes), out-of-range coordinates, negative
// counters, and absurd BPM / elevation. The cap on DistanceM is 1000
// km (longer than the longest known ultramarathons); ElapsedS at
// ~11.5 days catches the same shape from the other dimension.
// /audit/livehub M2.
func (p *Ping) Validate() error {
	if math.IsNaN(p.Lat) || math.IsInf(p.Lat, 0) || p.Lat < -90 || p.Lat > 90 {
		return errors.New("lat must be a finite number in [-90, 90]")
	}
	if math.IsNaN(p.Lng) || math.IsInf(p.Lng, 0) || p.Lng < -180 || p.Lng > 180 {
		return errors.New("lng must be a finite number in [-180, 180]")
	}
	if math.IsNaN(p.DistanceM) || math.IsInf(p.DistanceM, 0) || p.DistanceM < 0 || p.DistanceM > 1_000_000 {
		return errors.New("distance_m must be a finite number in [0, 1e6]")
	}
	if p.ElapsedS < 0 || p.ElapsedS > 1_000_000 {
		return errors.New("elapsed_s must be in [0, 1e6]")
	}
	if p.BPM != nil && (*p.BPM < 20 || *p.BPM > 350) {
		return errors.New("bpm must be in [20, 350]")
	}
	if p.Elevation != nil {
		v := *p.Elevation
		if math.IsNaN(v) || math.IsInf(v, 0) || v < -500 || v > 9000 {
			return errors.New("ele must be a finite number in [-500, 9000]")
		}
	}
	return nil
}
