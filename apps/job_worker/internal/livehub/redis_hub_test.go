package livehub

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

// newRedisTestHub spins up an in-process miniredis, wires a real
// go-redis client at it, and returns a RedisHub + a teardown.
// Real-Redis semantics with zero external deps.
func newRedisTestHub(t *testing.T) (*RedisHub, *miniredis.Miniredis, func()) {
	t.Helper()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	hub := NewRedisHub(rdb)
	return hub, mr, func() {
		_ = rdb.Close()
		mr.Close()
	}
}

func TestRedisHub_PublishWritesLastKnown(t *testing.T) {
	hub, mr, teardown := newRedisTestHub(t)
	defer teardown()

	p := Ping{Lat: 51.5, Lng: -0.1, DistanceM: 1234}
	hub.Publish("run-A", p)

	// The :last key must be set with the JSON-marshalled ping.
	if !mr.Exists("live:run-A:last") {
		t.Fatalf("expected live:run-A:last to be set after Publish")
	}
	got := hub.LastKnown("run-A")
	if got == nil || got.DistanceM != 1234 {
		t.Fatalf("LastKnown=%+v", got)
	}
}

func TestRedisHub_LastKnownReturnsNilWhenAbsent(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()

	if got := hub.LastKnown("never-pushed"); got != nil {
		t.Fatalf("LastKnown for absent run must be nil; got %+v", got)
	}
}

func TestRedisHub_LastKnownExpires(t *testing.T) {
	hub, mr, teardown := newRedisTestHub(t)
	defer teardown()
	hub.LastKnownTTL = 5 * time.Minute

	hub.Publish("run-A", Ping{Lat: 1, Lng: 2})
	if got := hub.LastKnown("run-A"); got == nil {
		t.Fatal("LastKnown should be set immediately after Publish")
	}
	// Advance miniredis's clock past the TTL — verifies the EXPIRE
	// the hub set on the :last key actually took effect, so a stale
	// post-run spectator doesn't see day-old position data.
	mr.FastForward(6 * time.Minute)
	if got := hub.LastKnown("run-A"); got != nil {
		t.Fatalf("LastKnown must expire after TTL; got %+v", got)
	}
}

func TestRedisHub_SubscribeReceivesPublishedPings(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	ch, unsub, _ := hub.Subscribe(ctx, "run-A")
	defer unsub()

	// Give the pubsub goroutine a moment to subscribe before publishing
	// — pubsub on Redis is fire-and-forget; a publish before subscribe
	// lands gets dropped on the floor.
	time.Sleep(50 * time.Millisecond)

	want := Ping{Lat: 1, Lng: 2, DistanceM: 100}
	hub.Publish("run-A", want)

	select {
	case got := <-ch:
		if got.DistanceM != 100 {
			t.Errorf("got=%+v want=%+v", got, want)
		}
	case <-time.After(time.Second):
		t.Fatal("did not receive published ping within 1s")
	}
}

func TestRedisHub_SubscribePreloadsLastKnown(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()

	// Publish before any spectator connects → late joiner should
	// still see the runner via the snapshot pre-load.
	hub.Publish("run-A", Ping{Lat: 1, Lng: 2, DistanceM: 500})

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	ch, unsub, _ := hub.Subscribe(ctx, "run-A")
	defer unsub()

	select {
	case got := <-ch:
		if got.DistanceM != 500 {
			t.Errorf("preload=%+v want DistanceM=500", got)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("late joiner should receive last-known immediately")
	}
}

func TestRedisHub_UnsubClosesChannel(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ch, unsub, _ := hub.Subscribe(ctx, "run-A")
	unsub()

	// Channel should close shortly after unsub. Read once — a closed
	// channel returns the zero value + ok=false.
	select {
	case _, ok := <-ch:
		if ok {
			t.Fatal("expected closed channel after unsub")
		}
	case <-time.After(time.Second):
		t.Fatal("channel didn't close within 1s of unsub")
	}
}

func TestRedisHub_TwoSubscribersBothReceive(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	ch1, u1, _ := hub.Subscribe(ctx, "run-A")
	defer u1()
	ch2, u2, _ := hub.Subscribe(ctx, "run-A")
	defer u2()
	time.Sleep(80 * time.Millisecond)

	hub.Publish("run-A", Ping{DistanceM: 42})

	for i, ch := range []<-chan Ping{ch1, ch2} {
		select {
		case got := <-ch:
			if got.DistanceM != 42 {
				t.Errorf("ch%d got=%+v", i+1, got)
			}
		case <-time.After(time.Second):
			t.Fatalf("ch%d didn't receive within 1s", i+1)
		}
	}
}

// fake fetchers — copied from server_test.go's pattern but tiny.
type fakeZoneFetcher struct {
	zones []PrivacyZone
	err   error
	calls int
}

func (f *fakeZoneFetcher) Zones(_ context.Context, _ string) ([]PrivacyZone, error) {
	f.calls++
	if f.err != nil {
		return nil, f.err
	}
	return f.zones, nil
}

// fakeRunMetaFetcher is reused from auth_test.go.

func TestRedisHub_LoadZonesCachesPerRoom(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	f := &fakeZoneFetcher{zones: []PrivacyZone{{Lat: 1, Lng: 2, RadiusM: 100}}}
	for i := 0; i < 10; i++ {
		zones, err := hub.LoadZones(context.Background(), "run-A", f)
		if err != nil {
			t.Fatal(err)
		}
		if len(zones) != 1 {
			t.Fatalf("expected 1 zone; got %d", len(zones))
		}
	}
	if f.calls != 1 {
		t.Fatalf("expected exactly 1 fetcher call; got %d", f.calls)
	}
}

func TestRedisHub_LoadZonesPropagatesError(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	want := errors.New("supabase down")
	f := &fakeZoneFetcher{err: want}
	_, err := hub.LoadZones(context.Background(), "run-A", f)
	if !errors.Is(err, want) {
		t.Fatalf("got=%v want=%v", err, want)
	}
}

func TestRedisHub_LoadRunMetaCachesPerRoom(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-A": {UserID: "user-1", IsPublic: true}}}
	for i := 0; i < 10; i++ {
		meta, err := hub.LoadRunMeta(context.Background(), "run-A", f)
		if err != nil {
			t.Fatal(err)
		}
		if meta == nil || meta.UserID != "user-1" {
			t.Fatalf("meta=%+v", meta)
		}
	}
	if f.calls != 1 {
		t.Fatalf("expected exactly 1 fetcher call; got %d", f.calls)
	}
}

func TestRedisHub_LoadRunMetaRefreshesAfterTTL(t *testing.T) {
	// Privacy contract: a mid-run is_public flip must stop being served
	// within CacheRefreshTTL. The old load-once cache never refreshed, so
	// anon spectators kept streaming a now-private run indefinitely.
	defer SetCacheRefreshTTL(10 * time.Millisecond)()
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-A": {UserID: "user-1", IsPublic: true}}}

	meta, err := hub.LoadRunMeta(context.Background(), "run-A", f)
	if err != nil || meta == nil || !meta.IsPublic {
		t.Fatalf("first load: meta=%+v err=%v", meta, err)
	}

	// Runner flips the run private; after the TTL elapses the cache must
	// re-fetch and surface the new value.
	f.rows["run-A"] = &RunMeta{UserID: "user-1", IsPublic: false}
	time.Sleep(20 * time.Millisecond)

	meta, err = hub.LoadRunMeta(context.Background(), "run-A", f)
	if err != nil {
		t.Fatal(err)
	}
	if meta == nil || meta.IsPublic {
		t.Fatalf("after TTL the flip to private must be visible; got %+v", meta)
	}
	if f.calls < 2 {
		t.Fatalf("expected a refresh fetch after the TTL; calls=%d", f.calls)
	}
}

func TestRedisHub_LoadZonesRefreshesAfterTTL(t *testing.T) {
	// A privacy zone added mid-run must start being honoured within the
	// TTL, matching the in-process Hub.
	defer SetCacheRefreshTTL(10 * time.Millisecond)()
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	f := &fakeZoneFetcher{zones: nil}

	if zones, err := hub.LoadZones(context.Background(), "run-A", f); err != nil || len(zones) != 0 {
		t.Fatalf("first load: zones=%v err=%v", zones, err)
	}

	f.zones = []PrivacyZone{{Lat: 1, Lng: 2, RadiusM: 100}}
	time.Sleep(20 * time.Millisecond)

	zones, err := hub.LoadZones(context.Background(), "run-A", f)
	if err != nil {
		t.Fatal(err)
	}
	if len(zones) != 1 {
		t.Fatalf("after TTL the new zone must be visible; got %d zones", len(zones))
	}
}

func TestRedisHub_LoadRunMetaCachesNilResult(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{}} // unknown run → nil
	for i := 0; i < 5; i++ {
		meta, err := hub.LoadRunMeta(context.Background(), "ghost", f)
		if err != nil {
			t.Fatal(err)
		}
		if meta != nil {
			t.Fatalf("unknown run should return nil; got %+v", meta)
		}
	}
	// Cache holds the negative result too — the JWTAuthorizer denies
	// on nil so we don't want to keep re-fetching for a non-existent run.
	if f.calls != 1 {
		t.Fatalf("expected exactly 1 fetcher call for negative result; got %d", f.calls)
	}
}

// Compile-time check that RedisHub satisfies the LivePubSub
// interface the Server + JWTAuthorizer take.
func TestRedisHub_SatisfiesLivePubSub(t *testing.T) {
	var _ LivePubSub = (*RedisHub)(nil)
}

func TestConfigureRedis_ParsesUrl(t *testing.T) {
	c, err := ConfigureRedis("redis://localhost:6379/0")
	if err != nil {
		t.Fatal(err)
	}
	if c == nil {
		t.Fatal("nil client")
	}
	// We don't actually connect; the parse path is what's exercised.
}

func TestConfigureRedis_RejectsEmpty(t *testing.T) {
	if _, err := ConfigureRedis(""); err == nil {
		t.Fatal("empty URL must error")
	}
}

func TestConfigureRedis_RejectsBad(t *testing.T) {
	if _, err := ConfigureRedis("not a url"); err == nil {
		t.Fatal("bogus URL must error")
	}
}

// The Redis path is what production runs, so its history retention must
// match the in-memory Hub's (TestHub_HistoryCoversLongUltra). Publish a
// full 24h/5s session and assert History returns it all, in order.
func TestRedisHub_HistoryCoversLongUltra(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	const dayPings = 24 * 60 * 60 / 5
	if dayPings != HistoryRingSize {
		t.Fatalf("expected ring (%d) to hold a 24h/5s session (%d pings)", HistoryRingSize, dayPings)
	}
	for i := 0; i < dayPings; i++ {
		hub.Publish("ultra", Ping{Lat: 1, Lng: 1, DistanceM: float64(i)})
	}
	got := hub.History("ultra", 0)
	if len(got) != dayPings {
		t.Fatalf("History len = %d, want %d (the full 24h session)", len(got), dayPings)
	}
	if got[0].DistanceM != 0 {
		t.Fatalf("oldest ping DistanceM = %v, want 0", got[0].DistanceM)
	}
	if got[len(got)-1].DistanceM != float64(dayPings-1) {
		t.Fatalf("newest ping DistanceM = %v, want %d", got[len(got)-1].DistanceM, dayPings-1)
	}
}

// Past the cap the oldest LPUSH/LTRIM entries roll off but order + the
// newest tail are preserved — mirrors TestHub_HistoryRollsOffPastCap on
// the Redis transport.
func TestRedisHub_HistoryRollsOffPastCap(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()
	const extra = 100
	for i := 0; i < HistoryRingSize+extra; i++ {
		hub.Publish("ultra", Ping{Lat: 1, Lng: 1, DistanceM: float64(i)})
	}
	got := hub.History("ultra", 0)
	if len(got) != HistoryRingSize {
		t.Fatalf("History len = %d, want %d (capped)", len(got), HistoryRingSize)
	}
	if got[0].DistanceM != float64(extra) {
		t.Fatalf("oldest retained DistanceM = %v, want %d", got[0].DistanceM, extra)
	}
	if got[len(got)-1].DistanceM != float64(HistoryRingSize+extra-1) {
		t.Fatalf("newest DistanceM = %v, want %d", got[len(got)-1].DistanceM, HistoryRingSize+extra-1)
	}
}

// SubscribeWithHistory returns the recent history snapshot AND a live
// channel that streams subsequent publishes — the Redis transport's
// half of the no-drop/no-duplicate late-joiner contract.
func TestRedisHub_SubscribeWithHistoryReplaysThenStreams(t *testing.T) {
	hub, _, teardown := newRedisTestHub(t)
	defer teardown()

	for i := 0; i < 3; i++ {
		hub.Publish("run-A", Ping{Lat: 1, Lng: 1, DistanceM: float64(i)})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	history, ch, unsub, err := hub.SubscribeWithHistory(ctx, "run-A", 0)
	if err != nil {
		t.Fatalf("SubscribeWithHistory err = %v", err)
	}
	defer unsub()

	if len(history) != 3 {
		t.Fatalf("history len = %d, want 3", len(history))
	}
	for i, p := range history {
		if p.DistanceM != float64(i) {
			t.Fatalf("history[%d].DistanceM = %v, want %d", i, p.DistanceM, i)
		}
	}

	// A publish after the subscribe streams live and is not duplicated
	// into the already-returned history snapshot.
	hub.Publish("run-A", Ping{Lat: 1, Lng: 1, DistanceM: 3})
	select {
	case got := <-ch:
		if got.DistanceM != 3 {
			t.Fatalf("live ping DistanceM = %v, want 3", got.DistanceM)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for the live ping")
	}
	for _, p := range history {
		if p.DistanceM == 3 {
			t.Fatal("ping #3 appeared in both history and the live channel (duplicate)")
		}
	}
}

// dedupHistoryTail trims the boundary overlap so a ping straddling the
// subscribe/snapshot window (present in both the history snapshot and
// the live buffer) is replayed once, not twice. pingEqual compares by
// value so the dedup survives the pointer-field round-trip through JSON.
func TestRedisHub_DedupHistoryTail(t *testing.T) {
	bpm := func(v int) *int { return &v }
	mk := func(d float64, b *int) Ping { return Ping{DistanceM: d, BPM: b} }

	hist := []Ping{mk(0, nil), mk(1, bpm(120)), mk(2, bpm(130))}
	// The live buffer caught the last two history pings (boundary
	// overlap) plus a genuinely-new one. Distinct pointers, equal values.
	live := []Ping{mk(1, bpm(120)), mk(2, bpm(130)), mk(3, bpm(140))}

	got := dedupHistoryTail(hist, live)
	if len(got) != 1 || got[0].DistanceM != 0 {
		t.Fatalf("dedupHistoryTail = %v, want only the non-overlapping head [0]", distances(got))
	}

	// No overlap → history returned untouched.
	if got := dedupHistoryTail(hist, []Ping{mk(9, nil)}); len(got) != len(hist) {
		t.Fatalf("dedupHistoryTail with no overlap len = %d, want %d", len(got), len(hist))
	}
	// Differing BPM at the same distance is NOT an overlap.
	if got := dedupHistoryTail([]Ping{mk(2, bpm(130))}, []Ping{mk(2, bpm(131))}); len(got) != 1 {
		t.Fatalf("dedupHistoryTail must compare BPM by value; trimmed a non-matching ping")
	}
}
