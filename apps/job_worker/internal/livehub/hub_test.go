package livehub

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

func TestHub_PublishWithoutSubscribers(t *testing.T) {
	h := NewHub()
	// Publishing into a room with no subscribers is harmless — the
	// room is created, the ping is stashed as lastPing, no panic.
	got := h.Publish("run-1", Ping{Lat: 47.37, Lng: 8.54})
	if got != 0 {
		t.Fatalf("delivered = %d, want 0", got)
	}
	last := h.LastKnown("run-1")
	if last == nil || last.Lat != 47.37 {
		t.Fatalf("LastKnown = %+v, want lat=47.37", last)
	}
}

func TestHub_SubscribeReceivesPublishedPings(t *testing.T) {
	h := NewHub()
	ch, unsub, _ := h.Subscribe(context.Background(), "run-1")
	defer unsub()

	h.Publish("run-1", Ping{Lat: 1, Lng: 1, DistanceM: 100, ElapsedS: 10})
	select {
	case got := <-ch:
		if got.DistanceM != 100 {
			t.Fatalf("got %+v, want DistanceM=100", got)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for ping")
	}
}

func TestHub_LateJoinerReceivesLastKnown(t *testing.T) {
	h := NewHub()
	// Publish before anyone subscribes.
	h.Publish("run-1", Ping{Lat: 51.5, Lng: -0.1, DistanceM: 500})

	// Now a spectator joins — they should pick up the last position
	// immediately, not wait for the next push.
	ch, unsub, _ := h.Subscribe(context.Background(), "run-1")
	defer unsub()
	select {
	case got := <-ch:
		if got.DistanceM != 500 || got.Lat != 51.5 {
			t.Fatalf("got %+v, want late-joiner replay of last known", got)
		}
	case <-time.After(time.Second):
		t.Fatal("late joiner didn't receive last-known ping")
	}
}

func TestHub_PublishFansOutToEverySubscriber(t *testing.T) {
	h := NewHub()
	const n = 5
	chans := make([]<-chan Ping, n)
	unsubs := make([]func(), n)
	for i := 0; i < n; i++ {
		ch, u, err := h.Subscribe(context.Background(), "run-1")
		if err != nil {
			t.Fatalf("Subscribe[%d] err = %v", i, err)
		}
		chans[i], unsubs[i] = ch, u
	}
	defer func() {
		for _, u := range unsubs {
			u()
		}
	}()

	if c := h.SubscriberCount("run-1"); c != n {
		t.Fatalf("SubscriberCount = %d, want %d", c, n)
	}

	h.Publish("run-1", Ping{DistanceM: 42})

	for i, ch := range chans {
		select {
		case got := <-ch:
			if got.DistanceM != 42 {
				t.Fatalf("sub %d got %+v, want DistanceM=42", i, got)
			}
		case <-time.After(time.Second):
			t.Fatalf("sub %d timed out", i)
		}
	}
}

func TestHub_UnsubscribeStopsDelivery(t *testing.T) {
	h := NewHub()
	ch, unsub, _ := h.Subscribe(context.Background(), "run-1")
	unsub()

	// Channel should be closed; reads return the zero value with ok=false.
	select {
	case _, ok := <-ch:
		if ok {
			t.Fatal("expected channel closed after unsubscribe")
		}
	case <-time.After(time.Second):
		t.Fatal("channel didn't close")
	}

	// Publishing after unsub doesn't reopen anything.
	h.Publish("run-1", Ping{DistanceM: 1})
}

func TestHub_RoomGCAfterLastUnsubscribe(t *testing.T) {
	h := NewHub()
	_, unsub, _ := h.Subscribe(context.Background(), "ephemeral-run")
	if c := h.RoomCount(); c != 1 {
		t.Fatalf("RoomCount after subscribe = %d, want 1", c)
	}
	unsub()
	// No lastPing was ever published — the room should be gone.
	if c := h.RoomCount(); c != 0 {
		t.Fatalf("RoomCount after last unsubscribe = %d, want 0", c)
	}
}

func TestHub_RoomKeptForLateRefresh(t *testing.T) {
	h := NewHub()
	// Publish first so the room has a lastPing.
	h.Publish("run-1", Ping{DistanceM: 100})
	_, unsub, _ := h.Subscribe(context.Background(), "run-1")
	unsub()
	// lastPing held → room must survive so a refresh sees the
	// starting position.
	if c := h.RoomCount(); c != 1 {
		t.Fatalf("RoomCount with lastPing = %d, want 1 (room must persist for late refresh)", c)
	}
	if last := h.LastKnown("run-1"); last == nil {
		t.Fatal("LastKnown lost across unsubscribe")
	}
}

func TestHub_ContextCancelUnsubscribes(t *testing.T) {
	h := NewHub()
	ctx, cancel := context.WithCancel(context.Background())
	ch, _, _ := h.Subscribe(ctx, "run-1")
	if c := h.SubscriberCount("run-1"); c != 1 {
		t.Fatalf("SubscriberCount = %d, want 1", c)
	}
	cancel()

	// The context-cancel goroutine inside Subscribe asynchronously
	// removes the subscriber. Poll up to 1 s for it to land.
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if h.SubscriberCount("run-1") == 0 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if c := h.SubscriberCount("run-1"); c != 0 {
		t.Fatalf("SubscriberCount after cancel = %d, want 0", c)
	}
	// Channel must be closed too.
	select {
	case _, ok := <-ch:
		if ok {
			t.Fatal("channel still receives after context cancel")
		}
	case <-time.After(200 * time.Millisecond):
		t.Fatal("channel didn't close after context cancel")
	}
}

func TestHub_SlowConsumerDoesntBlockPublisher(t *testing.T) {
	h := NewHub()
	_, unsub, _ := h.Subscribe(context.Background(), "run-1")
	defer unsub()
	// Don't drain the channel. Publish more than the buffer holds —
	// excess pings drop for this consumer but Publish must return
	// without blocking.
	done := make(chan struct{})
	go func() {
		for i := 0; i < subBufferSize*4; i++ {
			h.Publish("run-1", Ping{DistanceM: float64(i)})
		}
		close(done)
	}()
	select {
	case <-done:
		// pass
	case <-time.After(time.Second):
		t.Fatal("Publish blocked on a stuck consumer")
	}
}

func TestHub_PublishesAreSerialAcrossGoroutines(t *testing.T) {
	// Smoke-test that concurrent Publish + Subscribe + Unsubscribe
	// from many goroutines doesn't trip the race detector. Run with
	// `go test -race ./...` to actually exercise the detector.
	h := NewHub()
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
			defer cancel()
			ch, unsub, _ := h.Subscribe(ctx, "run-shared")
			defer unsub()
			for j := 0; j < 50; j++ {
				h.Publish("run-shared", Ping{DistanceM: float64(j)})
				select {
				case <-ch:
				default:
				}
			}
		}(i)
	}
	wg.Wait()
	// After everything finishes the SubscriberCount should be 0.
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if h.SubscriberCount("run-shared") == 0 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if c := h.SubscriberCount("run-shared"); c != 0 {
		t.Fatalf("subscribers leaked: %d", c)
	}
}

// audit/livehub M3 — per-room subscriber cap.
func TestHub_SubscriberCapRejects(t *testing.T) {
	h := NewHub()
	// Burn MaxSubsPerRoom slots first — all must succeed.
	cleanups := make([]func(), 0, MaxSubsPerRoom)
	t.Cleanup(func() {
		for _, u := range cleanups {
			u()
		}
	})
	for i := 0; i < MaxSubsPerRoom; i++ {
		_, u, err := h.Subscribe(context.Background(), "run-cap")
		if err != nil {
			t.Fatalf("Subscribe[%d] should have succeeded under cap, got %v", i, err)
		}
		cleanups = append(cleanups, u)
	}
	// The next subscribe must reject with the documented error.
	if _, _, err := h.Subscribe(context.Background(), "run-cap"); !errors.Is(err, ErrSubscriberCapReached) {
		t.Fatalf("Subscribe at cap = %v, want ErrSubscriberCapReached", err)
	}
}

// Persona round-5 runner-ultra — the history ring must cover a full
// 24h ultra at the 5s push cadence so a crew joining late replays the
// whole traversed course, not just the most recent few hours.
func TestHub_HistoryCoversLongUltra(t *testing.T) {
	h := NewHub()
	// 24h at one push per 5s = 17280 pings, exactly the ring size.
	const dayPings = 24 * 60 * 60 / 5
	if dayPings != HistoryRingSize {
		t.Fatalf("expected ring (%d) to hold a 24h/5s session (%d pings)", HistoryRingSize, dayPings)
	}
	for i := 0; i < dayPings; i++ {
		h.Publish("ultra", Ping{Lat: 1, Lng: 1, DistanceM: float64(i)})
	}
	got := h.History("ultra", 0)
	if len(got) != dayPings {
		t.Fatalf("History len = %d, want %d (the full 24h session)", len(got), dayPings)
	}
	// Chronological order, oldest first — the first ping of the run is
	// still present (not rolled off) and the last is the most recent.
	if got[0].DistanceM != 0 {
		t.Fatalf("oldest ping DistanceM = %v, want 0", got[0].DistanceM)
	}
	if got[len(got)-1].DistanceM != float64(dayPings-1) {
		t.Fatalf("newest ping DistanceM = %v, want %d", got[len(got)-1].DistanceM, dayPings-1)
	}
}

// Past the 24h ceiling the oldest pings roll off but order + the
// newest tail are preserved — the ring is a bounded most-recent
// window, not unbounded growth.
func TestHub_HistoryRollsOffPastCap(t *testing.T) {
	h := NewHub()
	const extra = 100
	for i := 0; i < HistoryRingSize+extra; i++ {
		h.Publish("ultra", Ping{Lat: 1, Lng: 1, DistanceM: float64(i)})
	}
	got := h.History("ultra", 0)
	if len(got) != HistoryRingSize {
		t.Fatalf("History len = %d, want %d (capped)", len(got), HistoryRingSize)
	}
	// The first `extra` pings rolled off; oldest retained is #extra.
	if got[0].DistanceM != float64(extra) {
		t.Fatalf("oldest retained DistanceM = %v, want %d", got[0].DistanceM, extra)
	}
	if got[len(got)-1].DistanceM != float64(HistoryRingSize+extra-1) {
		t.Fatalf("newest DistanceM = %v, want %d", got[len(got)-1].DistanceM, HistoryRingSize+extra-1)
	}
}

// audit/livehub C2 + M4 — idle-room GC drops stale rooms.
func TestHub_RunGCDropsIdleRoom(t *testing.T) {
	h := NewHub()
	// Publish once to a room with no subscribers; lastPingAt is now.
	h.Publish("idle-run", Ping{Lat: 1, Lng: 1})
	if c := h.RoomCount(); c != 1 {
		t.Fatalf("RoomCount after publish = %d, want 1", c)
	}
	// Sweep with maxIdle=0 reaps immediately (publish was ≥0s ago).
	// Use a 1ns max-idle to guarantee the room is treated as stale.
	time.Sleep(2 * time.Millisecond)
	if dropped := h.RunGC(time.Nanosecond); dropped != 1 {
		t.Fatalf("RunGC dropped = %d, want 1", dropped)
	}
	if c := h.RoomCount(); c != 0 {
		t.Fatalf("RoomCount after GC = %d, want 0", c)
	}
}

// Rooms with active subscribers must NOT be GC'd even if stale.
func TestHub_RunGCKeepsRoomsWithSubscribers(t *testing.T) {
	h := NewHub()
	h.Publish("live-run", Ping{Lat: 1, Lng: 1})
	_, unsub, err := h.Subscribe(context.Background(), "live-run")
	if err != nil {
		t.Fatalf("Subscribe err = %v", err)
	}
	defer unsub()
	time.Sleep(2 * time.Millisecond)
	if dropped := h.RunGC(time.Nanosecond); dropped != 0 {
		t.Fatalf("RunGC dropped = %d, want 0 (active subscriber)", dropped)
	}
	if c := h.RoomCount(); c != 1 {
		t.Fatalf("RoomCount = %d, want 1", c)
	}
}

// SubscribeWithHistory must partition the ping stream: everything
// published before the subscribe is in the history snapshot, everything
// after is on the channel, with no ping appearing on both. This pins
// the late-joiner replay against the register-then-snapshot race that
// otherwise duplicated a ping landing in the window. The followup:
// "Live pings during a late-joiner's history replay can be dropped or
// duplicated."
func TestHub_SubscribeWithHistoryPartitionsStream(t *testing.T) {
	h := NewHub()
	for i := 0; i < 5; i++ {
		h.Publish("run-1", Ping{Lat: 1, Lng: 1, DistanceM: float64(i)})
	}

	history, ch, unsub, err := h.SubscribeWithHistory(context.Background(), "run-1", 0)
	if err != nil {
		t.Fatalf("SubscribeWithHistory err = %v", err)
	}
	defer unsub()

	if len(history) != 5 {
		t.Fatalf("history len = %d, want 5 (the pre-subscribe pings)", len(history))
	}
	for i, p := range history {
		if p.DistanceM != float64(i) {
			t.Fatalf("history[%d].DistanceM = %v, want %d", i, p.DistanceM, i)
		}
	}

	// A ping published AFTER the atomic subscribe lands on the live
	// channel and must NOT also be in the history snapshot we already
	// hold (it isn't — that slice was captured under the same lock the
	// register took, so the publish below could only have come after).
	h.Publish("run-1", Ping{Lat: 1, Lng: 1, DistanceM: 5})
	select {
	case got := <-ch:
		if got.DistanceM != 5 {
			t.Fatalf("live ping DistanceM = %v, want 5", got.DistanceM)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for the live ping")
	}
	for _, p := range history {
		if p.DistanceM == 5 {
			t.Fatal("ping #5 appeared in BOTH history and the live channel (duplicate)")
		}
	}
}

// A ping that arrives concurrently with the subscribe is delivered
// EXACTLY ONCE — either replayed via history or streamed on the
// channel, never both, never neither — and the reconstructed sequence
// (history ++ channel) stays strictly ordered. Run many iterations so
// the race detector exercises the publish/subscribe interleave at the
// boundary the lock now guards.
func TestHub_SubscribeWithHistoryExactlyOnceDuringReplay(t *testing.T) {
	for iter := 0; iter < 500; iter++ {
		h := NewHub()
		const pre = 4
		for i := 0; i < pre; i++ {
			h.Publish("run-x", Ping{Lat: 1, Lng: 1, DistanceM: float64(i)})
		}

		// Fire a publish concurrently with the subscribe so the ping
		// races the register/snapshot boundary.
		const racer = float64(pre)
		var wg sync.WaitGroup
		wg.Add(1)
		started := make(chan struct{})
		go func() {
			defer wg.Done()
			<-started
			h.Publish("run-x", Ping{Lat: 1, Lng: 1, DistanceM: racer})
		}()

		close(started)
		history, ch, unsub, err := h.SubscribeWithHistory(context.Background(), "run-x", 0)
		if err != nil {
			unsubIf(unsub)
			t.Fatalf("iter %d: SubscribeWithHistory err = %v", iter, err)
		}
		wg.Wait()

		// The racing publish has returned, so its trySend (if the ping
		// went live rather than into history) has already landed in the
		// channel buffer. Drain non-blockingly.
		var live []Ping
	drain:
		for {
			select {
			case p := <-ch:
				live = append(live, p)
			default:
				break drain
			}
		}
		unsub()

		// Reconstruct the full ordered sequence the spectator saw.
		seen := make(map[float64]int)
		seq := append(append([]Ping{}, history...), live...)
		last := -1.0
		for _, p := range seq {
			seen[p.DistanceM]++
			if p.DistanceM < last {
				t.Fatalf("iter %d: out-of-order: %v after %v in %v",
					iter, p.DistanceM, last, distances(seq))
			}
			last = p.DistanceM
		}
		// Every pre-subscribe ping plus the racer must appear exactly
		// once across history+live — no drop, no duplicate.
		for i := 0; i <= pre; i++ {
			if seen[float64(i)] != 1 {
				t.Fatalf("iter %d: ping %d seen %d times, want exactly 1 (seq=%v)",
					iter, i, seen[float64(i)], distances(seq))
			}
		}
	}
}

func unsubIf(unsub func()) {
	if unsub != nil {
		unsub()
	}
}

func distances(ps []Ping) []float64 {
	out := make([]float64, len(ps))
	for i, p := range ps {
		out[i] = p.DistanceM
	}
	return out
}
