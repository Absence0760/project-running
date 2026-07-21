package livehub

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// capturedInsert records one InsertLivePing call.
type capturedInsert struct {
	runID  string
	userID string
	ping   Ping
}

// fakePersister signals each InsertLivePing on a channel so a test can
// wait for the detached persist goroutine deterministically.
type fakePersister struct {
	ch  chan capturedInsert
	err error
}

func newFakePersister() *fakePersister {
	return &fakePersister{ch: make(chan capturedInsert, 4)}
}

func (f *fakePersister) InsertLivePing(_ context.Context, runID, userID string, p Ping) error {
	f.ch <- capturedInsert{runID: runID, userID: userID, ping: p}
	return f.err
}

// pushOK POSTs a ping and asserts a 202. Returns nothing; fatals on
// mismatch.
func pushOK(t *testing.T, base, runID, body string) {
	t.Helper()
	resp, err := http.Post(base+"/v1/live/"+runID+"/push", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("push status=%d, want 202", resp.StatusCode)
	}
}

func newPersistServer(t *testing.T, srv *Server) (string, func()) {
	t.Helper()
	if srv.Hub == nil {
		srv.Hub = NewHub()
	}
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	return ts.URL, ts.Close
}

func TestPersist_MirrorsAcceptedPushToLiveRunPings(t *testing.T) {
	persister := newFakePersister()
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-1": {UserID: "user-A", IsPublic: true}}}
	base, teardown := newPersistServer(t, &Server{Persister: persister, RunMeta: meta})
	defer teardown()

	pushOK(t, base, "run-1", `{"lat":51.5,"lng":-0.1,"distance_m":500,"elapsed_s":120,"bpm":150,"ele":42.5}`)

	select {
	case got := <-persister.ch:
		if got.runID != "run-1" || got.userID != "user-A" {
			t.Fatalf("insert run/user = %q/%q, want run-1/user-A", got.runID, got.userID)
		}
		if got.ping.Lat != 51.5 || got.ping.Lng != -0.1 || got.ping.DistanceM != 500 || got.ping.ElapsedS != 120 {
			t.Fatalf("ping core fields not carried: %+v", got.ping)
		}
		if got.ping.BPM == nil || *got.ping.BPM != 150 || got.ping.Elevation == nil || *got.ping.Elevation != 42.5 {
			t.Fatalf("ping optional fields not carried: %+v", got.ping)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("push did not trigger a live_run_pings persist within the deadline")
	}
}

func TestPersist_SkippedWhenNotWired(t *testing.T) {
	// No Persister / RunMeta — the hub stays fan-out-only (pre-bridge
	// behaviour). A push still succeeds and, importantly, doesn't panic
	// on the nil persist path.
	base, teardown := newPersistServer(t, &Server{})
	defer teardown()
	pushOK(t, base, "run-1", `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0}`)
	// Snapshot confirms the fan-out path still worked.
	resp, err := http.Get(base + "/v1/live/run-1/snapshot")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("snapshot status=%d, want 200 (fan-out unaffected)", resp.StatusCode)
	}
}

func TestPersist_InsertErrorDoesNotFailPush(t *testing.T) {
	persister := newFakePersister()
	persister.err = errors.New("supabase down")
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-1": {UserID: "user-A"}}}
	base, teardown := newPersistServer(t, &Server{Persister: persister, RunMeta: meta})
	defer teardown()

	// The push must still be 202 — the mirror is best-effort.
	pushOK(t, base, "run-1", `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0}`)
	// And the insert was still attempted (error swallowed in the goroutine).
	select {
	case got := <-persister.ch:
		if got.userID != "user-A" {
			t.Fatalf("insert userID=%q, want user-A", got.userID)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("insert was not attempted")
	}
}

func TestPersist_SkippedWhenRunRowMissing(t *testing.T) {
	// RunMeta returns nil (run row gone) → nothing to persist, no
	// insert with an empty user_id (which would violate NOT NULL).
	persister := newFakePersister()
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{}} // no row for run-1
	base, teardown := newPersistServer(t, &Server{Persister: persister, RunMeta: meta})
	defer teardown()

	pushOK(t, base, "run-1", `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0}`)
	select {
	case got := <-persister.ch:
		t.Fatalf("insert attempted with missing run row: %+v", got)
	case <-time.After(300 * time.Millisecond):
		// Expected: no insert.
	}
}
