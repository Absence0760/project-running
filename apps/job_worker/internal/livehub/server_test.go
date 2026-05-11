package livehub

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

// newTestServer spins up an httptest.Server backed by a fresh Hub +
// Server. Returns the http base URL and a teardown fn.
func newTestServer(t *testing.T, srv *Server) (string, func()) {
	t.Helper()
	hub := NewHub()
	srv.Hub = hub
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	return ts.URL, func() {
		ts.Close()
	}
}

func TestServer_PushReturns202AndPersists(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()

	body := strings.NewReader(`{"lat":51.5,"lng":-0.1,"distance_m":500,"elapsed_s":120}`)
	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json", body)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", resp.StatusCode)
	}

	// Snapshot should now return the pushed ping.
	snap, err := http.Get(base + "/v1/live/run-1/snapshot")
	if err != nil {
		t.Fatal(err)
	}
	defer snap.Body.Close()
	if snap.StatusCode != http.StatusOK {
		t.Fatalf("snapshot status = %d, want 200", snap.StatusCode)
	}
	var got Ping
	if err := json.NewDecoder(snap.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.DistanceM != 500 || got.Lat != 51.5 {
		t.Fatalf("snapshot = %+v, want lat=51.5 distance=500", got)
	}
}

func TestServer_SnapshotEmptyRunReturns204(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()

	resp, err := http.Get(base + "/v1/live/no-such-run/snapshot")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", resp.StatusCode)
	}
}

func TestServer_PushRejectsMalformedBody(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()
	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader("not json"))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

func TestServer_PushRejectsHugeBodies(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()
	// 8 KiB body — over the 4 KiB MaxBytesReader cap.
	big := bytes.Repeat([]byte(`{"lat":1,"lng":1,"distance_m":1,"elapsed_s":1,"junk":"x"} `), 200)
	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		bytes.NewReader(big))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (over cap)", resp.StatusCode)
	}
}

func TestServer_WrongMethodIs405(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()
	for _, c := range []struct {
		method, path string
	}{
		{"GET", "/v1/live/run-1/push"},
		{"POST", "/v1/live/run-1/snapshot"},
		{"POST", "/v1/live/run-1/subscribe"},
	} {
		req, _ := http.NewRequest(c.method, base+c.path, nil)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusMethodNotAllowed {
			t.Fatalf("%s %s → %d, want 405", c.method, c.path, resp.StatusCode)
		}
	}
}

func TestServer_BadRouteIs404(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()
	for _, path := range []string{
		"/v1/live/",                 // no run id
		"/v1/live/run-1/",           // no action
		"/v1/live/run-1/whatever",   // unknown action
	} {
		resp, err := http.Get(base + path)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("%s → %d, want 404", path, resp.StatusCode)
		}
	}
}

func TestServer_AuthorizerBlocksPush(t *testing.T) {
	srv := &Server{
		Authorizer: func(_ *http.Request, _ string, action AuthAction) error {
			if action == ActionPush {
				return errors.New("only the recorder may push")
			}
			return nil
		},
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":1,"lng":1,"distance_m":1,"elapsed_s":1}`))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", resp.StatusCode)
	}

	// Snapshot still permitted by the same authorizer (only push was denied).
	r2, err := http.Get(base + "/v1/live/run-1/snapshot")
	if err != nil {
		t.Fatal(err)
	}
	r2.Body.Close()
	if r2.StatusCode != http.StatusNoContent {
		t.Fatalf("snapshot status = %d, want 204 (room empty)", r2.StatusCode)
	}
}

func TestServer_WebSocketStreamsPushedPings(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()

	wsURL := strings.Replace(base, "http://", "ws://", 1) + "/v1/live/run-1/subscribe"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		t.Fatalf("ws dial: %v", err)
	}
	defer c.CloseNow()

	// Give the server a tick to register the subscriber.
	time.Sleep(20 * time.Millisecond)

	// Now publish via the HTTP push endpoint.
	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":51.5,"lng":-0.1,"distance_m":250,"elapsed_s":60}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()

	// The WS client should receive the same ping.
	readCtx, readCancel := context.WithTimeout(ctx, 2*time.Second)
	defer readCancel()
	var got Ping
	if err := wsjson.Read(readCtx, c, &got); err != nil {
		t.Fatalf("ws read: %v", err)
	}
	if got.DistanceM != 250 {
		t.Fatalf("got %+v, want DistanceM=250", got)
	}
}

func TestServer_WebSocketReplaysLastKnownOnConnect(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()

	// Push first so the room has a lastPing.
	_, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":1,"lng":1,"distance_m":111,"elapsed_s":11}`))
	if err != nil {
		t.Fatal(err)
	}

	wsURL := strings.Replace(base, "http://", "ws://", 1) + "/v1/live/run-1/subscribe"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.CloseNow()

	readCtx, readCancel := context.WithTimeout(ctx, 2*time.Second)
	defer readCancel()
	var got Ping
	if err := wsjson.Read(readCtx, c, &got); err != nil {
		t.Fatalf("ws read: %v", err)
	}
	if got.DistanceM != 111 {
		t.Fatalf("late joiner received %+v, want lastPing replay", got)
	}
}

func TestServer_WebSocketCleansUpOnDisconnect(t *testing.T) {
	hub := NewHub()
	srv := &Server{Hub: hub}
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	defer ts.Close()

	wsURL := strings.Replace(ts.URL, "http://", "ws://", 1) + "/v1/live/run-1/subscribe"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		t.Fatal(err)
	}

	// Wait for the server-side subscriber to register.
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if hub.SubscriberCount("run-1") == 1 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if c := hub.SubscriberCount("run-1"); c != 1 {
		t.Fatalf("SubscriberCount before close = %d, want 1", c)
	}

	// Close the WS connection — server should drop its subscriber.
	_ = c.Close(websocket.StatusNormalClosure, "bye")

	deadline = time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if hub.SubscriberCount("run-1") == 0 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if c := hub.SubscriberCount("run-1"); c != 0 {
		t.Fatalf("SubscriberCount after close = %d, want 0 (leak)", c)
	}
}

// --- Privacy zones ---

// stubZoneFetcher returns a fixed zone list for one run; everything
// else gets nil. Counts calls so tests can assert the per-room
// cache.
type stubZoneFetcher struct {
	matchRunID string
	zones      []PrivacyZone
	calls      int
	failNext   bool
}

func (s *stubZoneFetcher) Zones(_ context.Context, runID string) ([]PrivacyZone, error) {
	s.calls++
	if s.failNext {
		s.failNext = false
		return nil, errors.New("zone fetch failed")
	}
	if runID != s.matchRunID {
		return nil, nil
	}
	return s.zones, nil
}

func TestServer_PingInsideZoneIsDropped(t *testing.T) {
	stub := &stubZoneFetcher{
		matchRunID: "run-1",
		zones: []PrivacyZone{
			{Lat: 47.37, Lng: 8.54, RadiusM: 200},
		},
	}
	base, teardown := newTestServer(t, &Server{Zones: stub})
	defer teardown()

	// Subscribe so we can assert nothing arrives on the wire.
	wsURL := strings.Replace(base, "http://", "ws://", 1) + "/v1/live/run-1/subscribe"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		t.Fatalf("ws dial: %v", err)
	}
	defer c.CloseNow()

	// Push a ping inside the zone (dead-centre).
	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":47.37,"lng":8.54,"distance_m":1,"elapsed_s":1}`))
	if err != nil {
		t.Fatal(err)
	}
	var body struct {
		OK              bool `json:"ok"`
		Clipped         bool `json:"clipped"`
		SubscribersSent int  `json:"subscribers_sent"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", resp.StatusCode)
	}
	if !body.Clipped {
		t.Fatal("clipped flag missing on in-zone ping response")
	}
	if body.SubscribersSent != 0 {
		t.Fatalf("subscribers_sent = %d, want 0 (clip suppresses fan-out)", body.SubscribersSent)
	}

	// Read attempts on the WS should time out — no ping arrived.
	readCtx, readCancel := context.WithTimeout(ctx, 300*time.Millisecond)
	defer readCancel()
	var got Ping
	if err := wsjson.Read(readCtx, c, &got); err == nil {
		t.Fatalf("ws received in-zone ping %+v that should have been clipped", got)
	}
}

func TestServer_PingOutsideZoneFlowsThrough(t *testing.T) {
	stub := &stubZoneFetcher{
		matchRunID: "run-1",
		zones: []PrivacyZone{
			{Lat: 47.37, Lng: 8.54, RadiusM: 200},
		},
	}
	base, teardown := newTestServer(t, &Server{Zones: stub})
	defer teardown()

	wsURL := strings.Replace(base, "http://", "ws://", 1) + "/v1/live/run-1/subscribe"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		t.Fatalf("ws dial: %v", err)
	}
	defer c.CloseNow()
	time.Sleep(20 * time.Millisecond)

	// 1 km east — well outside the 200 m zone.
	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":47.37,"lng":8.555,"distance_m":1000,"elapsed_s":300}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", resp.StatusCode)
	}

	readCtx, readCancel := context.WithTimeout(ctx, 2*time.Second)
	defer readCancel()
	var got Ping
	if err := wsjson.Read(readCtx, c, &got); err != nil {
		t.Fatalf("ws read: %v", err)
	}
	if got.DistanceM != 1000 {
		t.Fatalf("got %+v, want DistanceM=1000", got)
	}
}

func TestServer_ZoneFetchCachedPerRoom(t *testing.T) {
	stub := &stubZoneFetcher{
		matchRunID: "run-1",
		zones: []PrivacyZone{
			{Lat: 47.37, Lng: 8.54, RadiusM: 200},
		},
	}
	base, teardown := newTestServer(t, &Server{Zones: stub})
	defer teardown()

	// Three pushes — only the first should trigger a zone fetch.
	for i := 0; i < 3; i++ {
		resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
			strings.NewReader(`{"lat":48,"lng":9,"distance_m":1,"elapsed_s":1}`))
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
	}
	if stub.calls != 1 {
		t.Fatalf("zone fetcher calls = %d, want 1 (cached per room)", stub.calls)
	}
}

func TestServer_ZoneFetchFailureDropsFailClosed(t *testing.T) {
	stub := &stubZoneFetcher{
		matchRunID: "run-1",
		zones: []PrivacyZone{
			{Lat: 47.37, Lng: 8.54, RadiusM: 200},
		},
		failNext: true,
	}
	base, teardown := newTestServer(t, &Server{Zones: stub})
	defer teardown()

	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":48,"lng":9,"distance_m":1,"elapsed_s":1}`))
	if err != nil {
		t.Fatal(err)
	}
	var body struct {
		OK      bool   `json:"ok"`
		Clipped bool   `json:"clipped"`
		Reason  string `json:"reason"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&body)
	resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", resp.StatusCode)
	}
	if !body.Clipped {
		t.Fatal("zone-fetch failure must drop the ping (fail-closed)")
	}
	if body.Reason != "zone fetch failed" {
		t.Fatalf("reason = %q, want zone fetch failed", body.Reason)
	}
}

func TestServer_NoZoneFetcherSkipsCheckEntirely(t *testing.T) {
	// Server.Zones = nil → unclipped fall-through (dev / unit-test
	// path). The legacy tests at the top of this file rely on this
	// behaviour — keep one explicit test so a future refactor that
	// drops the nil-guard surfaces it immediately.
	base, teardown := newTestServer(t, &Server{Zones: nil})
	defer teardown()

	resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":0,"lng":0,"distance_m":1,"elapsed_s":1}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", resp.StatusCode)
	}
	// Snapshot path confirms the push landed unclipped.
	snap, _ := http.Get(base + "/v1/live/run-1/snapshot")
	if snap.StatusCode != http.StatusOK {
		t.Fatalf("snapshot = %d, want 200 (push was published)", snap.StatusCode)
	}
	snap.Body.Close()
}

// Smoke-test the path-parsing on an edge case: run_id with hyphens
// + uuid-shaped — the trim-and-split logic must round-trip these.
func TestServer_RunIDWithHyphens(t *testing.T) {
	base, teardown := newTestServer(t, &Server{})
	defer teardown()
	id := "f4a3c5d8-1234-5678-9abc-def012345678"
	resp, err := http.Post(fmt.Sprintf("%s/v1/live/%s/push", base, id),
		"application/json",
		strings.NewReader(`{"lat":1,"lng":1,"distance_m":1,"elapsed_s":1}`))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("uuid run_id push status = %d, want 202", resp.StatusCode)
	}
}
