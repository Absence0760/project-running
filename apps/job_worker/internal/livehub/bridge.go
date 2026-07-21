package livehub

import (
	"context"
	"log/slog"
	"time"
)

// The live-ping Bridge closes the transport gap during the migration
// from Supabase Realtime to this hub.
//
// Two transports carry "share my live location": the legacy path
// (recorder INSERTs into `live_run_pings`, spectator reads it over
// Supabase Realtime) and this hub (recorder POSTs /push, spectator
// streams the WebSocket). A client picks its transport at build time,
// so during the gradual mobile rollover the two coexist — and a hub
// spectator watching a runner still on the legacy recorder would see
// an empty map, because the runner's pings land in `live_run_pings`,
// never in a hub room.
//
// The Bridge is the "Realtime → hub" half of the fix: it polls
// `live_run_pings` for new rows and republishes them into the matching
// hub room, so a hub spectator sees a legacy-transport run. It forwards
// only rows for runs that (a) have at least one hub subscriber — no
// point materialising rooms for runs nobody is watching here — and
// (b) are NOT hub-native (a run currently receiving direct /push already
// fans out, and re-forwarding its rows would double-deliver; the
// [Hub.RecentlyPushed] guard skips those). In-zone SAR "coarse" rows are
// skipped, matching the hub push path, which drops in-zone pings outright.
//
// The "hub → Realtime" half (a hub /push also persisting to
// `live_run_pings` so a legacy spectator sees a hub-transport run) is a
// separate follow-up, needed only once recorders begin pushing to the
// hub — i.e. at the mobile cutover, after the web cutover this half
// unblocks.
//
// Single-replica only: it holds the concrete in-process [Hub] (for
// SubscriberCount + the hub-native guard) and an in-memory cursor. A
// multi-replica (Redis) deploy would move the cursor + hub-native state
// into Redis; not built (REDIS_URL is unset today).

// PersistedPing is one `live_run_pings` row as the Bridge reads it.
type PersistedPing struct {
	ID        int64
	RunID     string
	Lat       float64
	Lng       float64
	Ele       *float64
	ElapsedS  *int
	DistanceM *float64
	BPM       *int
	Coarse    bool
}

// PingReader fetches `live_run_pings` rows for the Bridge. Implemented
// by the worker's SupabaseClient; stubbed in tests.
type PingReader interface {
	// MaxLivePingID returns the current highest row id (0 when the
	// table is empty) so the Bridge can start its cursor at "now" and
	// forward only new rows rather than replaying all history.
	MaxLivePingID(ctx context.Context) (int64, error)
	// ReadLivePingsSince returns rows with id > afterID, ascending by
	// id, capped at limit.
	ReadLivePingsSince(ctx context.Context, afterID int64, limit int) ([]PersistedPing, error)
}

// bridgeHub is the slice of the in-process Hub the Bridge needs. Kept
// narrow so tests can drive the Bridge with a fake.
type bridgeHub interface {
	Publish(runID string, p Ping) int
	SubscriberCount(runID string) int
	RecentlyPushed(runID string, within time.Duration) bool
}

var _ bridgeHub = (*Hub)(nil)

// Bridge polls live_run_pings and republishes legacy-transport pings
// into hub rooms. Construct via [NewBridge] and drive with [Run].
type Bridge struct {
	hub    bridgeHub
	reader PingReader
	log    *slog.Logger

	// interval between polls. Matched to the recorder's ~5s push
	// cadence — a live spectator tolerates a couple of seconds of
	// bridge lag on the legacy path (Supabase Realtime itself is not
	// instant either).
	interval time.Duration
	// batch caps rows per poll; a full batch triggers an immediate
	// follow-up poll (catch-up) up to catchupRounds.
	batch int
	// hubNativeWindow: a run pushed within this window is treated as
	// hub-native and skipped. Comfortably longer than one push cadence
	// so a brief gap between pushes doesn't flip a run to Realtime-native.
	hubNativeWindow time.Duration

	cursor int64
}

const (
	bridgeInterval        = 2 * time.Second
	bridgeBatch           = 500
	bridgeHubNativeWindow = 30 * time.Second
	bridgeCatchupRounds   = 20
)

// NewBridge wires a Bridge. hub is the in-process Hub; reader is the
// Supabase-backed live_run_pings reader.
func NewBridge(hub bridgeHub, reader PingReader, log *slog.Logger) *Bridge {
	if log == nil {
		log = slog.Default()
	}
	return &Bridge{
		hub:             hub,
		reader:          reader,
		log:             log,
		interval:        bridgeInterval,
		batch:           bridgeBatch,
		hubNativeWindow: bridgeHubNativeWindow,
	}
}

// Run blocks until ctx is cancelled, polling on the configured
// interval. It first advances the cursor to the current max id so a
// fresh process forwards only pings recorded from now on — a
// late-joining spectator's backlog is served by the hub's own history
// replay + snapshot, not by the Bridge.
func (b *Bridge) Run(ctx context.Context) {
	if max, err := b.reader.MaxLivePingID(ctx); err != nil {
		// Non-fatal: start the cursor at 0 and let the first poll set
		// it. Worst case a single catch-up scan; the subscriber gate
		// keeps it from forwarding anything to empty rooms anyway.
		b.log.Warn("bridge: initial MaxLivePingID failed; starting cursor at 0", "err", err)
	} else {
		b.cursor = max
		b.log.Info("live-ping bridge: started", "cursor", max, "interval", b.interval.String())
	}

	t := time.NewTicker(b.interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			b.pollOnce(ctx)
		}
	}
}

// pollOnce drains new rows, forwarding the eligible ones. Catches up
// across a burst by re-polling while batches come back full, bounded
// so a firehose can't starve ctx cancellation.
func (b *Bridge) pollOnce(ctx context.Context) {
	for round := 0; round < bridgeCatchupRounds; round++ {
		rows, err := b.reader.ReadLivePingsSince(ctx, b.cursor, b.batch)
		if err != nil {
			b.log.Warn("bridge: read failed", "err", err, "cursor", b.cursor)
			return
		}
		if len(rows) == 0 {
			return
		}
		for _, row := range rows {
			if row.ID > b.cursor {
				b.cursor = row.ID
			}
			b.forward(row)
		}
		if len(rows) < b.batch {
			return
		}
	}
}

// forward republishes one row into its hub room, subject to the
// subscriber gate, the hub-native guard, and the coarse-ping skip.
func (b *Bridge) forward(row PersistedPing) {
	if row.Coarse {
		// In-zone SAR last-seen. The hub push path drops in-zone pings
		// outright, so hub spectators never see a coarse point on a
		// hub-transport run; skipping it here keeps hub-transport
		// behaviour uniform regardless of the recorder's transport.
		return
	}
	if b.hub.SubscriberCount(row.RunID) == 0 {
		return
	}
	if b.hub.RecentlyPushed(row.RunID, b.hubNativeWindow) {
		return
	}
	b.hub.Publish(row.RunID, Ping{
		Lat:       row.Lat,
		Lng:       row.Lng,
		DistanceM: derefF(row.DistanceM),
		ElapsedS:  derefI(row.ElapsedS),
		BPM:       row.BPM,
		Elevation: row.Ele,
		// SentAtMs deliberately 0: the recorder's original send clock
		// wasn't persisted, and the row's server `at` is a different
		// clock. A bridged ping simply carries no end-to-end latency
		// number, which the spectator renders fine (sent_at_ms is
		// optional on the wire).
	})
}

func derefF(p *float64) float64 {
	if p == nil {
		return 0
	}
	return *p
}

func derefI(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}
