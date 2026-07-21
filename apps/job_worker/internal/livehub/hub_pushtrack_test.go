package livehub

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHub_MarkPushed_RecentlyPushed(t *testing.T) {
	h := NewHub()

	if h.RecentlyPushed("run-1", time.Minute) {
		t.Fatal("a never-pushed run must not read as recently pushed")
	}

	h.MarkPushed("run-1")
	if !h.RecentlyPushed("run-1", time.Minute) {
		t.Fatal("a just-marked run must read as recently pushed within a generous window")
	}
	// A different run is unaffected.
	if h.RecentlyPushed("run-2", time.Minute) {
		t.Fatal("run-2 was never pushed")
	}
	// A zero-length window means "nothing counts as recent" — the mark
	// is in the past by the time we check.
	if h.RecentlyPushed("run-1", 0) {
		t.Fatal("within=0 can never be recent")
	}
}

// TestHub_PushHandlerMarksRunNative wires a real Hub into a Server and
// confirms a successful /push stamps the run hub-native — the seam the
// Bridge's RecentlyPushed guard relies on to avoid double-delivery.
func TestHub_PushHandlerMarksRunNative(t *testing.T) {
	h := NewHub()
	srv := &Server{Hub: h} // permissive authorizer + no zones (dev shape)
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	defer ts.Close()

	if h.RecentlyPushed("run-9", time.Minute) {
		t.Fatal("precondition: run-9 not yet pushed")
	}

	resp, err := http.Post(ts.URL+"/v1/live/run-9/push", "application/json",
		strings.NewReader(`{"lat":51.5,"lng":-0.1,"distance_m":10,"elapsed_s":5}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("push status=%d, want 202", resp.StatusCode)
	}
	if !h.RecentlyPushed("run-9", time.Minute) {
		t.Fatal("a successful /push must mark the run hub-native")
	}
}
