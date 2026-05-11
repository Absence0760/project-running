package livehub

import (
	"context"
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
	ch, unsub := h.Subscribe(context.Background(), "run-1")
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
	ch, unsub := h.Subscribe(context.Background(), "run-1")
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
		chans[i], unsubs[i] = h.Subscribe(context.Background(), "run-1")
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
	ch, unsub := h.Subscribe(context.Background(), "run-1")
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
	_, unsub := h.Subscribe(context.Background(), "ephemeral-run")
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
	_, unsub := h.Subscribe(context.Background(), "run-1")
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
	ch, _ := h.Subscribe(ctx, "run-1")
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
	_, unsub := h.Subscribe(context.Background(), "run-1")
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
			ch, unsub := h.Subscribe(ctx, "run-shared")
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
