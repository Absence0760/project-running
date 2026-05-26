package livehub

import "sync/atomic"

// HubMetrics is a lightweight atomic-counter set the hub bumps on
// every interesting event. Exposed as a snapshot via [Hub.Metrics]
// so an operator can wire it to Prometheus / CloudWatch / etc.
// without this package taking a dependency on a specific client lib.
//
// Counters are monotonic. Gauges (subscriber count, room count) are
// computed by walking the rooms map under the hub mutex when read.
//
// /audit/livehub M1.
type HubMetrics struct {
	// PublishCount tracks every successful Publish call (regardless
	// of whether any subscribers received it).
	PublishCount uint64
	// PublishDropCount tracks pings that were dropped before publish
	// — privacy-zone clip on the server side. Per-cause buckets are
	// stamped by the server.
	PublishDropZone uint64
	// SubscribeRejectCap tracks how often Subscribe returned
	// ErrSubscriberCapReached. A monotonically-rising value on a
	// public-run URL is the canonical M3 attack signature.
	SubscribeRejectCap uint64
	// AuthFailCount tracks every authorizer denial. Spike = stolen
	// JWT or a wrong-key replay.
	AuthFailCount uint64
	// RoomGCDropped tracks the cumulative count of rooms reaped by
	// the idle-room GC. A jump means a burst of stale rooms — fine
	// after a deploy with churn, suspicious if it climbs while
	// PublishCount is flat.
	RoomGCDropped uint64
}

// Snapshot returns a value-copy of the counters for export. Safe to
// call from any goroutine.
type metricsAtomic struct {
	publishCount       atomic.Uint64
	publishDropZone    atomic.Uint64
	subscribeRejectCap atomic.Uint64
	authFailCount      atomic.Uint64
	roomGCDropped      atomic.Uint64
}

func (m *metricsAtomic) snapshot() HubMetrics {
	if m == nil {
		return HubMetrics{}
	}
	return HubMetrics{
		PublishCount:       m.publishCount.Load(),
		PublishDropZone:    m.publishDropZone.Load(),
		SubscribeRejectCap: m.subscribeRejectCap.Load(),
		AuthFailCount:      m.authFailCount.Load(),
		RoomGCDropped:      m.roomGCDropped.Load(),
	}
}

// Metrics returns a value-copy of the hub's atomic counters plus
// the current room count gauge. Cheap to call (one mutex acquire
// for RoomCount + five atomic loads).
func (h *Hub) Metrics() HubMetrics {
	snap := h.metrics.snapshot()
	return snap
}
