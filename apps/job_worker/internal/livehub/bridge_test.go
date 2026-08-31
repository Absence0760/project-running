package livehub

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeBridgeHub records Publish calls and lets a test script the
// subscriber gate + hub-native guard.
type fakeBridgeHub struct {
	mu        sync.Mutex
	published []struct {
		runID string
		ping  Ping
	}
	subCount    map[string]int
	pushedNativ map[string]bool
}

func newFakeBridgeHub() *fakeBridgeHub {
	return &fakeBridgeHub{subCount: map[string]int{}, pushedNativ: map[string]bool{}}
}

func (f *fakeBridgeHub) Publish(runID string, p Ping) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.published = append(f.published, struct {
		runID string
		ping  Ping
	}{runID, p})
	return 1
}
func (f *fakeBridgeHub) SubscriberCount(runID string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.subCount[runID]
}
func (f *fakeBridgeHub) RecentlyPushed(runID string, _ time.Duration) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.pushedNativ[runID]
}
func (f *fakeBridgeHub) publishedRuns() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]string, len(f.published))
	for i, p := range f.published {
		out[i] = p.runID
	}
	return out
}

// fakeReader serves rows with id > afterID from a fixed, id-sorted set.
type fakeReader struct {
	mu      sync.Mutex
	rows    []PersistedPing
	maxErr  error
	readErr error
	reads   int
}

func (r *fakeReader) MaxLivePingID(context.Context) (int64, error) {
	if r.maxErr != nil {
		return 0, r.maxErr
	}
	var max int64
	for _, p := range r.rows {
		if p.ID > max {
			max = p.ID
		}
	}
	return max, nil
}
func (r *fakeReader) ReadLivePingsSince(_ context.Context, afterID int64, limit int) ([]PersistedPing, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.reads++
	if r.readErr != nil {
		return nil, r.readErr
	}
	var out []PersistedPing
	for _, p := range r.rows {
		if p.ID > afterID {
			out = append(out, p)
			if len(out) == limit {
				break
			}
		}
	}
	return out, nil
}

func newTestBridge(hub bridgeHub, reader PingReader) *Bridge {
	b := NewBridge(hub, reader, nil)
	b.interval = 5 * time.Millisecond // fast tick for Run() tests
	return b
}

func TestBridge_ForwardsRealtimePingToSubscribedRoom(t *testing.T) {
	hub := newFakeBridgeHub()
	hub.subCount["run-1"] = 1
	b := newTestBridge(hub, &fakeReader{})
	ele := 12.5
	dist := 100.0
	el := 60
	bpm := 150
	b.forward(PersistedPing{ID: 1, RunID: "run-1", Lat: 51.5, Lng: -0.1, Ele: &ele, DistanceM: &dist, ElapsedS: &el, BPM: &bpm})

	if got := hub.publishedRuns(); len(got) != 1 || got[0] != "run-1" {
		t.Fatalf("published=%v, want one publish to run-1", got)
	}
	p := hub.published[0].ping
	if p.Lat != 51.5 || p.Lng != -0.1 || p.DistanceM != 100.0 || p.ElapsedS != 60 || p.Elevation == nil || *p.Elevation != 12.5 || p.BPM == nil || *p.BPM != 150 {
		t.Fatalf("ping fields not carried through: %+v", p)
	}
	if p.SentAtMs != 0 {
		t.Errorf("SentAtMs=%d, want 0 for a bridged ping", p.SentAtMs)
	}
}

func TestBridge_SkipsRunWithNoSubscribers(t *testing.T) {
	hub := newFakeBridgeHub() // subCount defaults to 0
	b := newTestBridge(hub, &fakeReader{})
	b.forward(PersistedPing{ID: 1, RunID: "run-1", Lat: 1, Lng: 2})
	if got := hub.publishedRuns(); len(got) != 0 {
		t.Fatalf("published=%v, want none (no subscribers)", got)
	}
}

func TestBridge_SkipsHubNativeRun(t *testing.T) {
	hub := newFakeBridgeHub()
	hub.subCount["run-1"] = 3
	hub.pushedNativ["run-1"] = true // recorder is pushing to the hub directly
	b := newTestBridge(hub, &fakeReader{})
	b.forward(PersistedPing{ID: 1, RunID: "run-1", Lat: 1, Lng: 2})
	if got := hub.publishedRuns(); len(got) != 0 {
		t.Fatalf("published=%v, want none (hub-native run — direct fan-out already delivered)", got)
	}
}

func TestBridge_SkipsCoarsePing(t *testing.T) {
	hub := newFakeBridgeHub()
	hub.subCount["run-1"] = 1
	b := newTestBridge(hub, &fakeReader{})
	b.forward(PersistedPing{ID: 1, RunID: "run-1", Lat: 1, Lng: 2, Coarse: true})
	if got := hub.publishedRuns(); len(got) != 0 {
		t.Fatalf("published=%v, want none (coarse SAR ping — hub path drops in-zone)", got)
	}
}

func TestBridge_PollAdvancesCursorAndDoesNotReforward(t *testing.T) {
	hub := newFakeBridgeHub()
	hub.subCount["run-1"] = 1
	reader := &fakeReader{rows: []PersistedPing{
		{ID: 10, RunID: "run-1", Lat: 1, Lng: 1},
		{ID: 11, RunID: "run-1", Lat: 2, Lng: 2},
	}}
	b := newTestBridge(hub, reader)

	b.pollOnce(context.Background())
	if got := len(hub.publishedRuns()); got != 2 {
		t.Fatalf("first poll published %d, want 2", got)
	}
	if b.cursor != 11 {
		t.Fatalf("cursor=%d, want 11", b.cursor)
	}
	// A second poll with no new rows forwards nothing.
	b.pollOnce(context.Background())
	if got := len(hub.publishedRuns()); got != 2 {
		t.Fatalf("after empty poll published %d, want still 2 (no re-forward)", got)
	}
}

func TestBridge_PollCatchesUpAcrossFullBatches(t *testing.T) {
	hub := newFakeBridgeHub()
	hub.subCount["run-1"] = 1
	// 3 rows with a batch of 2 forces a second read in the same poll.
	reader := &fakeReader{rows: []PersistedPing{
		{ID: 1, RunID: "run-1", Lat: 1, Lng: 1},
		{ID: 2, RunID: "run-1", Lat: 2, Lng: 2},
		{ID: 3, RunID: "run-1", Lat: 3, Lng: 3},
	}}
	b := newTestBridge(hub, reader)
	b.batch = 2

	b.pollOnce(context.Background())
	if got := len(hub.publishedRuns()); got != 3 {
		t.Fatalf("catch-up published %d, want 3", got)
	}
	if b.cursor != 3 {
		t.Fatalf("cursor=%d, want 3", b.cursor)
	}
	if reader.reads < 2 {
		t.Fatalf("reads=%d, want ≥2 (a full batch triggers a follow-up read)", reader.reads)
	}
}

func TestBridge_ReadErrorDoesNotAdvanceCursor(t *testing.T) {
	hub := newFakeBridgeHub()
	hub.subCount["run-1"] = 1
	reader := &fakeReader{readErr: errors.New("boom")}
	b := newTestBridge(hub, reader)
	b.cursor = 42
	b.pollOnce(context.Background())
	if b.cursor != 42 {
		t.Fatalf("cursor=%d, want unchanged 42 on read error", b.cursor)
	}
	if got := len(hub.publishedRuns()); got != 0 {
		t.Fatalf("published=%d, want 0 on read error", got)
	}
}

func TestBridge_RunStartsCursorAtMaxAndForwardsOnlyNew(t *testing.T) {
	hub := newFakeBridgeHub()
	hub.subCount["run-1"] = 1
	reader := &fakeReader{rows: []PersistedPing{
		{ID: 100, RunID: "run-1", Lat: 1, Lng: 1}, // pre-existing → must NOT be forwarded
	}}
	b := newTestBridge(hub, reader)

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { b.Run(ctx); close(done) }()

	// Let a few ticks pass with only the pre-existing row present.
	time.Sleep(40 * time.Millisecond)
	if got := len(hub.publishedRuns()); got != 0 {
		cancel()
		<-done
		t.Fatalf("forwarded %d pre-existing rows, want 0 (cursor should start at max)", got)
	}

	// A new row lands → it should be forwarded.
	reader.mu.Lock()
	reader.rows = append(reader.rows, PersistedPing{ID: 101, RunID: "run-1", Lat: 2, Lng: 2})
	reader.mu.Unlock()

	deadline := time.After(2 * time.Second)
	for {
		if len(hub.publishedRuns()) == 1 {
			break
		}
		select {
		case <-deadline:
			cancel()
			<-done
			t.Fatal("new row was not forwarded within the deadline")
		case <-time.After(5 * time.Millisecond):
		}
	}
	cancel()
	<-done
}

// decisions.md § 756. The Redis branch dropped the Bridge silently — no log
// line, no metric, and the population it strands is the one the transport
// rollover exists for. Whether the Bridge runs is now a stated answer.
func TestBridgeSkipReasonNamesTheRedisDrop(t *testing.T) {
	if got := BridgeSkipReason(NewHub(), "service-key"); got != "" {
		t.Fatalf("an in-process hub with a service key runs the bridge; got %q", got)
	}
	if got := BridgeSkipReason(NewHub(), ""); got == "" {
		t.Fatal("no service key means no live_run_pings read, which must be stated")
	} else if !strings.Contains(got, "service key") {
		t.Fatalf("the reason must name the missing service key; got %q", got)
	}

	redis := &RedisHub{}
	got := BridgeSkipReason(redis, "service-key")
	if got == "" {
		t.Fatal("a Redis-backed hub runs no bridge, and saying nothing is the § 756 defect")
	}
	for _, want := range []string{"REDIS_URL", "legacy", "Realtime"} {
		if !strings.Contains(got, want) {
			t.Fatalf("the reason must name %q so a reader can act on it; got %q", want, got)
		}
	}
	// A service key does not rescue the Redis case: the missing half is
	// per-process state, not credentials.
	if BridgeSkipReason(redis, "") == "" {
		t.Fatal("a Redis hub with no service key still runs no bridge")
	}
}
