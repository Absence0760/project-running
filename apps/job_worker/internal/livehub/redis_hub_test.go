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

	ch, unsub := hub.Subscribe(ctx, "run-A")
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
	ch, unsub := hub.Subscribe(ctx, "run-A")
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
	ch, unsub := hub.Subscribe(ctx, "run-A")
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

	ch1, u1 := hub.Subscribe(ctx, "run-A")
	defer u1()
	ch2, u2 := hub.Subscribe(ctx, "run-A")
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
