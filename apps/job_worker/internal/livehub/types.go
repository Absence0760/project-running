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
// Today the buffer is an in-process map — it survives the process
// lifetime only. The roadmap calls for Upstash Redis as the durable
// ephemeral store with a 24h TTL, at which point this Hub becomes a
// thin shim over Redis pub/sub. The interface here is shaped to make
// that swap mechanical: Hub.Publish + Hub.Subscribe are the only
// touchpoints.
//
// Auth + private-run gating are out of scope for this slice — the
// HTTP layer (server.go) wires permissive auth by default with a
// TODO marker where a Supabase JWT verification call belongs.
package livehub

// Ping is the wire shape published by the mobile recorder and
// streamed to spectators. Mirrors the columns on `live_run_pings`
// minus the run_id (which lives on the URL path) and the server-
// stamped `inserted_at`.
type Ping struct {
	Lat        float64  `json:"lat"`
	Lng        float64  `json:"lng"`
	DistanceM  float64  `json:"distance_m"`
	ElapsedS   int      `json:"elapsed_s"`
	BPM        *int     `json:"bpm,omitempty"`
	Elevation  *float64 `json:"ele,omitempty"`
	// SentAtMs is the recorder's local clock at the time of the ping
	// (Unix ms). The hub passes it through unchanged so a spectator
	// can compute end-to-end latency against their own clock.
	SentAtMs int64 `json:"sent_at_ms,omitempty"`
}
