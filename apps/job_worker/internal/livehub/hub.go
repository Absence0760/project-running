package livehub

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"time"
)

// MaxSubsPerRoom caps concurrent subscribers per run_id. Public-run
// share URLs are anon-reachable; without a cap a single bad actor can
// open thousands of WS connections to one room and force Publish's
// O(n) subscriber-snapshot copy on every 5s ping. 500 is comfortably
// above any plausible legitimate fanout (a popular running streamer's
// audience) while keeping the per-room memory bounded at < 1 MB of
// subscriber slots. /audit/livehub M3.
const MaxSubsPerRoom = 500

// ErrSubscriberCapReached is returned by Subscribe when the room's
// subscriber count is at MaxSubsPerRoom. The HTTP server maps it to
// a 503 with a Retry-After hint so spectators back off.
var ErrSubscriberCapReached = errors.New("livehub: room subscriber cap reached")

// IdleRoomTTL bounds how long a room with no subscribers and no
// recent pings can live in memory before GC. Matches the Redis path's
// 24h TTL on per-room last-known keys; the in-process hub previously
// pinned the room forever via a non-nil lastPing, growing RSS
// monotonically across runs. /audit/livehub C2 + M4.
const IdleRoomTTL = 24 * time.Hour

// GCInterval is how often the background sweeper walks the rooms map
// looking for expired entries. 5 minutes balances responsiveness
// against the lock contention of the sweep.
const GCInterval = 5 * time.Minute

// cacheRefreshTTLNanos bounds how long a cached (RunMeta, zones)
// entry stays valid before the next call re-fetches. 60 s is a slow
// rate vs the recorder's 5 s push cadence (≈12 pushes per refresh)
// but fast enough that toggling `runs.is_public = false` mid-run
// stops serving anon spectators within a minute. /audit/livehub
// H2 + M6. Atomic so tests can lower it concurrently with running
// HTTP handlers (snapshot / subscribe paths read it from multiple
// goroutines) when simulating mid-broadcast zone changes —
// TestServer_SnapshotReEvaluatesPrivacyZones drives this.
var cacheRefreshTTLNanos atomic.Int64

func init() {
	cacheRefreshTTLNanos.Store(int64(60 * time.Second))
}

// CacheRefreshTTL returns the current cache TTL. Production callers
// just read the result; tests use SetCacheRefreshTTL to lower it.
func CacheRefreshTTL() time.Duration {
	return time.Duration(cacheRefreshTTLNanos.Load())
}

// SetCacheRefreshTTL is the test hook for lowering the cache TTL.
// Restore the previous value via the returned closure (typically in
// t.Cleanup). Race-safe — the underlying store is atomic.
func SetCacheRefreshTTL(d time.Duration) func() {
	prev := cacheRefreshTTLNanos.Swap(int64(d))
	return func() {
		cacheRefreshTTLNanos.Store(prev)
	}
}

// Hub is the in-process pub/sub broker keyed by run_id.
//
// Concurrency model:
//   - Subscribe/Unsubscribe acquire the per-room mutex.
//   - Publish acquires it for the broadcast snapshot, then releases
//     it before sending to each subscriber's channel. A slow consumer
//     can therefore back up its own channel without blocking other
//     subscribers or the publisher; the channel is buffered (capacity
//     [subBufferSize]) so up to that many pings can queue per-subscriber
//     before [Publish] drops onto the floor for that one client. A
//     dropped ping just means the spectator misses one update — the
//     next ping arrives ≤5 s later (LiveBroadcaster throttle).
//
// Memory model:
//   - One [room] per run_id. Rooms are lazily created on first
//     subscribe-or-publish and garbage-collected when the last
//     subscriber unsubscribes AND the room has no buffered last
//     ping. The latter clause keeps the "last known position" alive
//     across short connection gaps (a spectator refreshing the page).
//   - LastPing is held under the room mutex; readers copy it into
//     their local buffer before sending so the room mutex doesn't
//     pin around a slow channel write.
//
// This is a stand-in for the eventual Upstash Redis pub/sub +
// per-run TTL key (24h) that the roadmap calls for. Both interfaces
// match the Publish/Subscribe shape used here, so the swap will be
// mechanical when the Redis credentials land.
type Hub struct {
	mu      sync.Mutex
	rooms   map[string]*room
	metrics *metricsAtomic
}

// NewHub returns an empty Hub. Cheap — call once at process start.
func NewHub() *Hub {
	return &Hub{rooms: make(map[string]*room), metrics: &metricsAtomic{}}
}

// Per-subscriber buffer. 8 outstanding pings ≈ 40 s of slack at the
// LiveBroadcaster's 5 s throttle — generous enough that a brief
// network stutter on the spectator side doesn't lose data, tight
// enough that a stuck spectator doesn't grow unbounded memory.
const subBufferSize = 8

// Per-room history ring-buffer capacity. At a 5s mobile-recorder push
// cadence, 5000 pings covers the last ~7 hours of broadcast — enough
// for a crew rolling up at mile 60 of a 100-mile race to see the
// course traversed so far. Memory: 5000 × ~80 B = ~400 KB per room.
// A 50-hour ultra exceeds this and only the most recent ~7h are
// retained; that's the trade. Persona-hunt Round 3 finding Ultra #1.
const HistoryRingSize = 5000

type room struct {
	mu         sync.Mutex
	subs       map[*subscriber]struct{}
	lastPing   *Ping
	lastPingAt time.Time // stamped on every Publish — drives idle-room GC.
	// Ring buffer of recent pings for late-joiner replay. history is
	// a fixed-cap slice (cap = HistoryRingSize); `historyNext` is the
	// next write index. When the buffer is full, writes overwrite the
	// oldest entry, and reads start from historyNext and wrap. The
	// total ever-written count is tracked in `historyCount` so the
	// History reader can return the right chronological slice.
	history      []Ping
	historyNext  int
	historyCount uint64
	// Cached privacy zones for the broadcaster of this room. Loaded
	// lazily on the first push (or first read via [Hub.Zones]) and
	// refreshed every CacheRefreshTTL so a mid-run privacy-zone
	// edit takes effect within ~60 s instead of waiting for room
	// GC. `zonesAt` records the last successful fetch wall-clock;
	// callers compare against now() to decide whether to refetch.
	// nil zones + zonesAt non-zero → fetched, broadcaster has none.
	// /audit/livehub H2 + M6.
	zonesAt time.Time
	zones   []PrivacyZone
	// Cached run metadata (`user_id`, `is_public`) for the
	// authorizer. Same refresh semantics as zones — a flip of
	// `runs.is_public = false` mid-run stops serving anon
	// spectators within CacheRefreshTTL. `meta == nil` + non-zero
	// `runMetaAt` means the run row doesn't exist; the authorizer
	// denies in that case to prevent ghost broadcasts.
	runMetaAt time.Time
	runMeta   *RunMeta
}

type subscriber struct {
	mu     sync.Mutex // serialises send vs. close
	ch     chan Ping
	closed bool
}

// trySend is the only path that writes to [ch]. Holding [mu] across
// the non-blocking send keeps [close] and [Publish] from racing on
// the same channel write under -race. Returns whether the send
// landed; a `false` may mean either "buffer full" (publisher drops
// the ping) or "subscriber closed" (publisher skips). Both are
// indistinguishable from the publisher's perspective, which is what
// we want.
func (s *subscriber) trySend(p Ping) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return false
	}
	select {
	case s.ch <- p:
		return true
	default:
		return false
	}
}

// close is idempotent: a double call (caller's defer + the
// context-cancel goroutine both racing here) flips the flag once and
// closes the channel exactly once.
func (s *subscriber) close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return
	}
	s.closed = true
	close(s.ch)
}

// Publish stores [p] as the room's last-known ping and broadcasts to
// every current subscriber. Safe to call concurrently with itself
// and with [Subscribe]. Returns the number of subscribers that
// received the ping (i.e. didn't have a full buffer).
func (h *Hub) Publish(runID string, p Ping) int {
	h.metrics.publishCount.Add(1)
	r := h.roomFor(runID, true)
	r.mu.Lock()
	r.lastPing = &p
	r.lastPingAt = time.Now()
	// Record into the history ring. Allocate lazily on first publish
	// so empty rooms don't pay for the slab.
	if r.history == nil {
		r.history = make([]Ping, HistoryRingSize)
	}
	r.history[r.historyNext] = p
	r.historyNext = (r.historyNext + 1) % HistoryRingSize
	r.historyCount++
	// Snapshot subscribers so we don't hold the room mutex across
	// channel sends. A slow consumer can't deadlock the publisher.
	subs := make([]*subscriber, 0, len(r.subs))
	for s := range r.subs {
		subs = append(subs, s)
	}
	r.mu.Unlock()

	delivered := 0
	for _, s := range subs {
		// trySend internally serialises against close, so a sub that
		// gets unsubscribed mid-broadcast is safely skipped. A buffer-
		// full or closed sub counts as "not delivered" — the
		// publisher returns the count for ops metrics + tests.
		if s.trySend(p) {
			delivered++
		}
	}
	return delivered
}

// Subscribe registers a new subscriber for [runID] and returns the
// channel pings will arrive on. The caller MUST call [Unsubscribe]
// (typically via defer) when done — otherwise the hub leaks the
// subscriber record and the channel.
//
// On registration the subscriber receives the room's last-known
// ping (if any) so a late joiner sees the runner immediately
// instead of waiting up to 5 s for the next [Publish].
func (h *Hub) Subscribe(ctx context.Context, runID string) (<-chan Ping, func(), error) {
	return h.subscribe(ctx, runID, true)
}

// SubscribeNoReplay is identical to Subscribe but skips the late-
// joiner replay of `r.lastPing`. The HTTP /subscribe route uses this
// so server.go can re-run shouldDrop against the *current* privacy
// zones before manually pushing the cached ping to the WS — a zone
// added mid-broadcast would otherwise leak through the auto-replay
// because the cached lastPing was published before the zone existed.
// Persona-hunt finding Pro-Round2 #1.
func (h *Hub) SubscribeNoReplay(ctx context.Context, runID string) (<-chan Ping, func(), error) {
	return h.subscribe(ctx, runID, false)
}

func (h *Hub) subscribe(ctx context.Context, runID string, replay bool) (<-chan Ping, func(), error) {
	r := h.roomFor(runID, true)
	s := &subscriber{ch: make(chan Ping, subBufferSize)}

	r.mu.Lock()
	// Per-room subscriber cap. Audit/livehub M3: without this an anon-
	// reachable public-run URL is a memory amplification vector.
	if len(r.subs) >= MaxSubsPerRoom {
		r.mu.Unlock()
		h.metrics.subscribeRejectCap.Add(1)
		return nil, nil, ErrSubscriberCapReached
	}
	if replay && r.lastPing != nil {
		// Pre-load the buffer with the last known ping. Capacity is
		// >0, so this never blocks. If the caller drains slowly the
		// next Publish may drop, which is fine.
		s.ch <- *r.lastPing
	}
	if r.subs == nil {
		r.subs = make(map[*subscriber]struct{})
	}
	r.subs[s] = struct{}{}
	r.mu.Unlock()

	unsub := func() {
		h.removeSubscriber(runID, s)
	}

	// Best-effort cleanup if the caller's context is cancelled before
	// they get a chance to call unsub. The caller still SHOULD call
	// it explicitly via defer — this is a belt-and-suspenders.
	if ctx != nil && ctx.Done() != nil {
		go func() {
			<-ctx.Done()
			unsub()
		}()
	}

	return s.ch, unsub, nil
}

// RunGC walks the rooms map and drops any room whose subscriber count
// is zero AND whose last publish (lastPingAt) is older than [maxIdle],
// AND which has no buffered lastPing (legacy keep-alive behaviour for
// reconnecting spectators). Idempotent — call from a background
// goroutine on a ticker. /audit/livehub C2 + M4.
//
// Returns the number of rooms swept; useful for metrics + tests.
func (h *Hub) RunGC(maxIdle time.Duration) int {
	now := time.Now()
	dropped := 0
	h.mu.Lock()
	for id, r := range h.rooms {
		r.mu.Lock()
		stale := len(r.subs) == 0 && !r.lastPingAt.IsZero() && now.Sub(r.lastPingAt) > maxIdle
		r.mu.Unlock()
		if stale {
			delete(h.rooms, id)
			dropped++
		}
	}
	h.mu.Unlock()
	if dropped > 0 {
		h.metrics.roomGCDropped.Add(uint64(dropped))
	}
	return dropped
}

// StartGC spawns a background goroutine that runs RunGC every
// [interval] until [ctx] is done. Returns immediately. Pass
// `IdleRoomTTL` and `GCInterval` for the production defaults; tests
// can use tighter values.
func (h *Hub) StartGC(ctx context.Context, interval, maxIdle time.Duration) {
	if interval <= 0 || maxIdle <= 0 {
		return
	}
	go func() {
		t := time.NewTicker(interval)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				h.RunGC(maxIdle)
			}
		}
	}()
}

// LoadZones populates the room's privacy-zone cache (if not yet
// loaded) via the supplied [ZoneFetcher], then returns the cached
// list. Idempotent — a second call with a populated cache returns
// the existing slice. The fetcher is only invoked at most once per
// room. A fetcher error is returned verbatim; the caller (push
// path) is expected to fail-closed: drop the ping rather than risk
// publishing through a broken zone fetch.
//
// Returns (nil, nil) when zones are loaded and the broadcaster has
// none configured — the caller publishes the ping unclipped.
func (h *Hub) LoadZones(ctx context.Context, runID string, fetcher ZoneFetcher) ([]PrivacyZone, error) {
	r := h.roomFor(runID, true)
	r.mu.Lock()
	if !r.zonesAt.IsZero() && time.Since(r.zonesAt) < CacheRefreshTTL() {
		zones := append([]PrivacyZone(nil), r.zones...)
		r.mu.Unlock()
		return zones, nil
	}
	r.mu.Unlock()

	// Fetch outside the room mutex so a slow Supabase call doesn't
	// pin subscribers' close paths. We accept that a concurrent
	// publisher could call us twice — the loser of the race
	// overwrites with the same data, no correctness hit.
	zones, err := fetcher.Zones(ctx, runID)
	if err != nil {
		return nil, err
	}

	r.mu.Lock()
	r.zonesAt = time.Now()
	r.zones = zones
	out := append([]PrivacyZone(nil), r.zones...)
	r.mu.Unlock()
	return out, nil
}

// LoadRunMeta populates the room's run-metadata cache (if not yet
// loaded) via the supplied [RunMetaFetcher], then returns the cached
// value. Idempotent — a second call with a populated cache returns
// the existing pointer. The fetcher is only invoked at most once per
// room. A fetcher error is returned verbatim; the caller (authorizer
// path) is expected to deny on error.
//
// A nil return with nil error means the fetch succeeded but the run
// row doesn't exist — callers should treat this as "deny" to keep a
// caller from booking a room against a fictional run id.
func (h *Hub) LoadRunMeta(ctx context.Context, runID string, fetcher RunMetaFetcher) (*RunMeta, error) {
	r := h.roomFor(runID, true)
	r.mu.Lock()
	if !r.runMetaAt.IsZero() && time.Since(r.runMetaAt) < CacheRefreshTTL() {
		meta := r.runMeta
		r.mu.Unlock()
		return meta, nil
	}
	r.mu.Unlock()

	meta, err := fetcher.RunMeta(ctx, runID)
	if err != nil {
		return nil, err
	}

	r.mu.Lock()
	r.runMetaAt = time.Now()
	r.runMeta = meta
	out := r.runMeta
	r.mu.Unlock()
	return out, nil
}

// LastKnown returns the most recent ping the hub has seen for
// [runID], or nil when no ping has been published yet (or the run
// was never registered). Used by the HTTP handler to serve a
// "starting position" snapshot to spectators before they upgrade
// to a streaming connection.
func (h *Hub) LastKnown(runID string) *Ping {
	r := h.roomFor(runID, false)
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.lastPing == nil {
		return nil
	}
	p := *r.lastPing
	return &p
}

// History returns up to [max] most-recent pings for [runID] in
// chronological order (oldest first). Used by the HTTP /subscribe
// route to replay the historical track to a late-joining spectator
// — a crew rolling up at mile 60 needs to see the runner's traversed
// course, not a single dot. Persona-hunt Round 3 finding Ultra #1.
//
// max=0 → defaults to HistoryRingSize (the per-room ceiling).
// Larger values are clamped to HistoryRingSize.
func (h *Hub) History(runID string, max int) []Ping {
	r := h.roomFor(runID, false)
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.historyCount == 0 || len(r.history) == 0 {
		return nil
	}
	if max <= 0 || max > HistoryRingSize {
		max = HistoryRingSize
	}
	// Total pings ever published. The ring buffer holds at most
	// min(historyCount, HistoryRingSize) of the most recent.
	total := int(r.historyCount)
	if total > HistoryRingSize {
		total = HistoryRingSize
	}
	if max > total {
		max = total
	}
	// The oldest still-buffered ping lives at historyNext when the
	// buffer wrapped, or at index 0 when it hasn't. Read `max` from
	// the END (most-recent) backwards to find the start index.
	startOffsetFromEnd := max
	out := make([]Ping, max)
	// historyNext points at the next WRITE position, so historyNext-1
	// is the most-recent write. Step backward `startOffsetFromEnd`
	// places, wrap with HistoryRingSize.
	start := (r.historyNext - startOffsetFromEnd + HistoryRingSize*2) % HistoryRingSize
	if total < HistoryRingSize {
		// Buffer hasn't wrapped — start cleanly at index 0.
		start = total - max
	}
	for i := 0; i < max; i++ {
		out[i] = r.history[(start+i)%HistoryRingSize]
	}
	return out
}

// SubscriberCount returns the number of active subscribers for
// [runID]. Used by tests and by future ops metrics — a steady
// >0 count after a run finishes would surface a leak.
func (h *Hub) SubscriberCount(runID string) int {
	r := h.roomFor(runID, false)
	if r == nil {
		return 0
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.subs)
}

// roomFor looks up the per-room state for [runID]. When
// [createIfMissing] is true a fresh room is registered; otherwise
// the lookup returns nil for unknown rooms (cheap path for
// `SubscriberCount` / `LastKnown` queries the WS server makes on
// every connect to decide whether to serve a snapshot).
func (h *Hub) roomFor(runID string, createIfMissing bool) *room {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[runID]
	if !ok {
		if !createIfMissing {
			return nil
		}
		r = &room{subs: make(map[*subscriber]struct{})}
		h.rooms[runID] = r
	}
	return r
}

// removeSubscriber unregisters one subscriber from a room. The lock
// dance is:
//
//  1. h.roomFor(false): read-locks the hub map, returns nil if the
//     room is gone (a concurrent unsub already swept it).
//  2. r.mu: protects subs[] + lastPing. We delete the subscriber
//     under it and decide whether the room is now empty.
//  3. s.close(): closes the channel OUTSIDE the room lock so a
//     slow WS reader can't pin the room lock.
//  4. h.mu (only when empty): re-check under the hub lock that
//     nobody resurrected the room between our `empty` decision and
//     now, then delete from the map.
//
// The double hub-lock pattern is deliberate — taking it on the
// inner branch avoids serialising every unsubscribe through the
// global hub mutex. /audit/livehub L4.
func (h *Hub) removeSubscriber(runID string, s *subscriber) {
	r := h.roomFor(runID, false)
	if r == nil {
		return
	}
	r.mu.Lock()
	_, present := r.subs[s]
	delete(r.subs, s)
	empty := len(r.subs) == 0 && r.lastPing == nil
	r.mu.Unlock()

	// Close the channel after the room lock is released — a closed
	// channel guarantees the WS server's reader loop drains and exits
	// rather than hanging on the cancelled connection. The subscriber's
	// own sync.Once makes close idempotent so a double-unsub (caller's
	// defer + context-cancel goroutine both racing here) is safe.
	if present {
		s.close()
	} else {
		// Already removed by another path — don't try to re-GC the room.
		return
	}

	// GC empty rooms so a flaky run that connects, disconnects, and
	// never publishes doesn't leak per-run state. Rooms with a
	// lastPing stay so a refresh sees the runner's last known spot.
	if empty {
		h.mu.Lock()
		// Re-check under the hub mutex: another goroutine may have
		// resurrected the room with a Publish or Subscribe between
		// our `empty` decision and now.
		if cur, ok := h.rooms[runID]; ok && cur == r {
			cur.mu.Lock()
			stillEmpty := len(cur.subs) == 0 && cur.lastPing == nil
			cur.mu.Unlock()
			if stillEmpty {
				delete(h.rooms, runID)
			}
		}
		h.mu.Unlock()
	}
}

// RoomCount returns the number of rooms currently held in memory.
// Test- and metrics-facing — the production deploy should expose
// this as a Prometheus gauge so a leak surfaces in dashboards.
func (h *Hub) RoomCount() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.rooms)
}
