package livehub

import "context"

// LivePubSub is the surface the HTTP routes + JWTAuthorizer use to
// publish, subscribe, snapshot, and read the per-room caches. Two
// implementations:
//
//   - *Hub — the original in-process broker (lazy rooms, channel-
//     per-subscriber, per-room zone + run-meta caches).
//   - *RedisHub — Redis pub/sub-backed variant for multi-process
//     deploys. Same Publish + Subscribe semantics; per-process
//     in-memory zone + run-meta caches (each process makes at most
//     one Supabase round-trip per run, same as the in-process Hub).
//
// `main.go` picks one based on REDIS_URL. The roadmap moves the
// in-process map onto Redis pub/sub with a per-run 24 h TTL for
// horizontal-scale deploys; the in-process Hub stays as the dev /
// single-replica path because it has zero external dependencies.
type LivePubSub interface {
	// Publish stores the ping as the room's last-known and
	// broadcasts to every active subscriber. Returns the number of
	// subscribers that received the ping (i.e. didn't have a full
	// buffer). The in-process Hub counts process-local subscribers;
	// RedisHub returns the receiver count Redis reports.
	Publish(runID string, p Ping) int

	// Subscribe registers a streaming consumer. The returned channel
	// receives every subsequent ping plus (when a last-known is
	// available) one pre-load ping so a late joiner sees the
	// runner immediately. The caller MUST invoke the returned
	// unsub func when done — leaving it dangling leaks a Redis
	// pubsub connection or an in-process subscriber record.
	//
	// Returns [ErrSubscriberCapReached] when the room's subscriber
	// count is at [MaxSubsPerRoom] — the HTTP layer maps this to a
	// 503 so spectators back off without DoSing the server.
	Subscribe(ctx context.Context, runID string) (<-chan Ping, func(), error)

	// SubscribeWithHistory atomically registers a no-replay subscriber
	// AND snapshots the room's recent history (up to [maxHistory]; 0 →
	// the implementation default cap) at the same instant. The contract
	// is a clean partition: every ping in the returned `history` slice
	// was recorded strictly before the subscriber was registered, and
	// every ping the returned channel will deliver was published
	// strictly after — so replaying `history` then streaming `ch`
	// reconstructs the full ordered sequence with no ping seen twice
	// and none dropped in the registration window.
	//
	// The HTTP `/subscribe` route uses this instead of a separate
	// SubscribeNoReplay + History pair, which left a window where a
	// ping landing between the register and the snapshot was either
	// delivered on both paths (a duplicate dot on the spectator's map)
	// or, when a slow replay let the live channel fill, dropped from
	// the live stream by trySend's buffer-full path.
	SubscribeWithHistory(ctx context.Context, runID string, maxHistory int) (history []Ping, ch <-chan Ping, unsub func(), err error)

	// LastKnown returns the most recent ping or nil. Used by the
	// HTTP `/snapshot` route.
	LastKnown(runID string) *Ping

	// History returns up to [max] most-recent pings in chronological
	// order (oldest first) so a late-joining spectator can render
	// the historical track instead of a single dot. Empty when no
	// pings have been published. The implementation caps to a sane
	// per-room ceiling; callers can pass max=0 to request the
	// implementation's default cap. Persona-hunt Round 3 finding
	// Ultra #1 — closes the gap between this transport and the
	// Supabase Realtime path, which serves the full `live_run_pings`
	// backlog on late-join.
	History(runID string, max int) []Ping

	// LoadZones populates the per-room privacy-zone cache (lazily,
	// once per room per process). Same fail-closed contract for
	// fetcher errors — the push path drops the ping rather than
	// risk leaking a home coordinate.
	LoadZones(ctx context.Context, runID string, fetcher ZoneFetcher) ([]PrivacyZone, error)

	// LoadRunMeta populates the per-room (user_id, is_public)
	// cache for the JWTAuthorizer. nil + nil means "the run row
	// doesn't exist" — caller denies.
	LoadRunMeta(ctx context.Context, runID string, fetcher RunMetaFetcher) (*RunMeta, error)
}

// Compile-time assertion: the in-process Hub already implements the
// interface; adding it here is the typing handshake that lets
// `main.go` write `var p LivePubSub = NewHub()` without a wrapper.
var _ LivePubSub = (*Hub)(nil)
