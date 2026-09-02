package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"strings"
	"testing"
	"time"
)

// panicMatcher panics inside Match — the shape a real engine failure takes
// (an OSRM response the decoder indexes past the end of, a nil map write).
// It stands in for "any handler on any kind panics"; the barrier under test
// wraps dispatch, not this one path.
type panicMatcher struct{ value any }

func (panicMatcher) Algorithm() string { return "panic" }
func (panicMatcher) Version() string   { return "v1" }

func (m panicMatcher) Match(_ context.Context, _ []TrackPoint) ([]TrackPoint, error) {
	panic(m.value)
}

func panickingWorker(t *testing.T, value any) (*Worker, *fakeBackend, *bytes.Buffer) {
	t.Helper()
	b := newFakeBackend()
	b.trackURL = "u1/r1.json.gz"
	b.trackByPath["u1/r1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2},
		{Lat: 1.001, Lng: 2.001},
	}
	b.jobs = []*Job{{
		ID:      7,
		Kind:    "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "r1", UserID: "u1"}),
	}}
	w := newTestWorker(b, panicMatcher{value: value})
	var logBuf bytes.Buffer
	w.Log = slog.New(slog.NewTextHandler(&logBuf, &slog.HandlerOptions{Level: slog.LevelError}))
	return w, b, &logBuf
}

// A panicking handler must not end the process. Before the barrier the worker
// loop ran in main's own goroutine alongside the live-spectator hub and the
// export endpoints, so one bad payload took live tracking down for everyone.
func TestWorker_PanickingHandlerDoesNotKillTheLoop(t *testing.T) {
	w, b, _ := panickingWorker(t, "boom")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	done := make(chan struct{})
	go func() {
		defer close(done)
		// A panic that escapes dispatch unwinds this goroutine, so Run never
		// returns and `done` never closes.
		_ = w.Run(ctx)
	}()

	// Stop the loop as soon as the panicking job has reported back, so the
	// test measures the barrier rather than a timeout.
	deadline := time.Now().Add(3 * time.Second)
	for {
		b.mu.Lock()
		reported := len(b.finished) + len(b.deferred)
		b.mu.Unlock()
		if reported > 0 || time.Now().After(deadline) {
			break
		}
		time.Sleep(time.Millisecond)
	}
	cancel()

	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("Run did not return: the panic escaped the barrier")
	}

	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.finished) != 1 {
		t.Fatalf("finished = %d calls, want 1 (the panicking job must still report back)", len(b.finished))
	}
	if got := b.finished[0].Status; got != "failed" {
		t.Fatalf("finish status = %q, want %q", got, "failed")
	}
	if b.finished[0].ErrorMsg == nil || !strings.Contains(*b.finished[0].ErrorMsg, "panic in job handler") {
		t.Fatalf("error message = %v, want it to name the panic", b.finished[0].ErrorMsg)
	}
	if len(b.deferred) != 0 {
		t.Fatalf("deferred = %d calls, want 0: a panic is a bug, not a retryable blip", len(b.deferred))
	}
}

// The row must be stamped `failed`, not left claimed. claim_next_job only ever
// selects status='queued' and nothing moves a row back out of 'running', so a
// deferral is the only alternative that keeps the job reachable — and a panic
// is not a condition that clears on its own.
func TestWorker_PanicIsPermanentEvenWhenItsMessageLooksTransient(t *testing.T) {
	// "i/o timeout" is one of isTransient's substring markers. A panic
	// carrying it must still be permanent.
	w, b, _ := panickingWorker(t, "read tcp 10.0.0.1:443: i/o timeout")

	job := b.jobs[0]
	b.jobs = nil
	w.handle(context.Background(), job)

	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.deferred) != 0 {
		t.Fatalf("deferred = %d, want 0: a panic whose text mentions a timeout is still a bug", len(b.deferred))
	}
	if len(b.finished) != 1 || b.finished[0].Status != "failed" {
		t.Fatalf("finished = %+v, want one failed", b.finished)
	}
}

// The operator needs the stack: a job id and "panic" alone does not locate the
// bug, and the process no longer dies printing one.
func TestWorker_PanicLogsTheStack(t *testing.T) {
	w, b, logBuf := panickingWorker(t, "boom")

	job := b.jobs[0]
	b.jobs = nil
	w.handle(context.Background(), job)

	out := logBuf.String()
	if !strings.Contains(out, "job handler panicked") {
		t.Fatalf("log does not name the panic:\n%s", out)
	}
	if !strings.Contains(out, "panicMatcher") {
		t.Fatalf("log does not carry a stack naming the panicking frame:\n%s", out)
	}
}

// A nil-pointer dereference is the panic shape a real handler bug takes; the
// barrier must catch a runtime error, not only an explicit panic() value.
func TestWorker_RuntimePanicIsCaught(t *testing.T) {
	b := newFakeBackend()
	b.jobs = nil
	w := newTestWorker(b, PassthroughMatcher{})
	var logBuf bytes.Buffer
	w.Log = slog.New(slog.NewTextHandler(&logBuf, &slog.HandlerOptions{Level: slog.LevelError}))

	// A data_export job with DataExport left nil would return an error, not
	// panic, so reach a runtime panic through the matcher instead.
	w.Matcher = nilDerefMatcher{}
	b.trackURL = "u1/r1.json.gz"
	b.trackByPath["u1/r1.json.gz"] = []TrackPoint{{Lat: 1, Lng: 2}}

	w.handle(context.Background(), &Job{
		ID:      9,
		Kind:    "map_match",
		Payload: json.RawMessage(`{"run_id":"r1","user_id":"u1"}`),
	})

	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.finished) != 1 || b.finished[0].Status != "failed" {
		t.Fatalf("finished = %+v, want one failed", b.finished)
	}
	if b.finished[0].ErrorMsg == nil || !strings.Contains(*b.finished[0].ErrorMsg, "nil pointer") {
		t.Fatalf("error message = %v, want it to carry the runtime error", b.finished[0].ErrorMsg)
	}
}

type nilDerefMatcher struct{}

func (nilDerefMatcher) Algorithm() string { return "nilderef" }
func (nilDerefMatcher) Version() string   { return "v1" }

func (nilDerefMatcher) Match(_ context.Context, _ []TrackPoint) ([]TrackPoint, error) {
	var p *TrackPoint
	return []TrackPoint{*p}, nil
}
