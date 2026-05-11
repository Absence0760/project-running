package livehub

import (
	"context"
	"sync"
)

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
	mu    sync.Mutex
	rooms map[string]*room
}

// NewHub returns an empty Hub. Cheap — call once at process start.
func NewHub() *Hub {
	return &Hub{rooms: make(map[string]*room)}
}

// Per-subscriber buffer. 8 outstanding pings ≈ 40 s of slack at the
// LiveBroadcaster's 5 s throttle — generous enough that a brief
// network stutter on the spectator side doesn't lose data, tight
// enough that a stuck spectator doesn't grow unbounded memory.
const subBufferSize = 8

type room struct {
	mu       sync.Mutex
	subs     map[*subscriber]struct{}
	lastPing *Ping
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
	r := h.roomFor(runID, true)
	r.mu.Lock()
	r.lastPing = &p
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
func (h *Hub) Subscribe(ctx context.Context, runID string) (<-chan Ping, func()) {
	r := h.roomFor(runID, true)
	s := &subscriber{ch: make(chan Ping, subBufferSize)}

	r.mu.Lock()
	if r.lastPing != nil {
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

	return s.ch, unsub
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
