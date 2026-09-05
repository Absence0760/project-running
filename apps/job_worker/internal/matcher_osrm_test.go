package internal

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// fakeOSRM stands in for an osrm-routed instance. Each test wires a
// handler that asserts on the path / query and writes a canned
// response. We can't import a real OSRM in unit tests — the engine
// needs a multi-GB pre-extracted graph.

func TestOSRMMatcher_AlgorithmAndVersion(t *testing.T) {
	m := NewOSRMMatcher("http://example/")
	if m.Algorithm() != "osrm" {
		t.Errorf("algorithm=%q", m.Algorithm())
	}
	if m.Version() != "v1" {
		t.Errorf("version=%q", m.Version())
	}
	// AlgVersion override survives.
	m.AlgVersion = "v2-foot-2026-04"
	if m.Version() != "v2-foot-2026-04" {
		t.Errorf("override ignored: %q", m.Version())
	}
}

func TestOSRMMatcher_TrimsTrailingSlash(t *testing.T) {
	m := NewOSRMMatcher("http://example/////")
	if m.BaseURL != "http://example" {
		t.Errorf("baseURL=%q, expected slash-stripped", m.BaseURL)
	}
}

func TestOSRMMatcher_SkipsLessThanTwoPoints(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("OSRM should not have been called for <2 points (path=%s)", r.URL.Path)
	}))
	defer srv.Close()
	m := NewOSRMMatcher(srv.URL)
	if out, err := m.Match(context.Background(), nil); err != nil || out != nil {
		t.Errorf("nil input: out=%v err=%v", out, err)
	}
	if out, err := m.Match(context.Background(), []TrackPoint{{Lat: 1, Lng: 2}}); err != nil || out != nil {
		t.Errorf("1 point: out=%v err=%v", out, err)
	}
}

func TestOSRMMatcher_HonoursContextCancellation(t *testing.T) {
	// A cancelled per-job context (job deadline hit / graceful shutdown)
	// must abort the OSRM call rather than run to the client timeout. The
	// handler signals once it has the request, then blocks; the test
	// cancels only after that so the request genuinely reaches the server
	// (cancelling earlier would abort before dial and never exercise the
	// in-flight path).
	gotRequest := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(gotRequest)
		<-r.Context().Done()
	}))
	defer srv.Close()

	m := NewOSRMMatcher(srv.URL)
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		<-gotRequest
		cancel()
	}()

	_, err := m.Match(ctx, []TrackPoint{
		{Lat: 51.5, Lng: -0.1}, {Lat: 51.51, Lng: -0.11},
	})
	if err == nil {
		t.Fatal("expected a cancellation error, got nil")
	}
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("error should wrap context.Canceled; got %v", err)
	}
}

func TestOSRMMatcher_SuccessfulMatch(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Path: /match/v1/foot/-0.100000,51.500000;-0.110000,51.510000
		if !strings.HasPrefix(r.URL.Path, "/match/v1/foot/") {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		if !strings.Contains(r.URL.Path, "-0.100000,51.500000") {
			t.Errorf("path missing first coordinate (lng,lat order): %s", r.URL.Path)
		}
		// The route geometry is not what this matcher reads any more, and
		// `tidy` drops input points — which is now a lost heart-rate
		// sample rather than a tidier line.
		if r.URL.Query().Get("overview") != "false" {
			t.Errorf("expected overview=false: %s", r.URL.RawQuery)
		}
		if r.URL.Query().Has("tidy") {
			t.Errorf("tidy must not be requested: %s", r.URL.RawQuery)
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, osrmSnapped([][2]float64{{-0.1001, 51.5001}, {-0.1101, 51.5101}}))
	}))
	defer srv.Close()

	m := NewOSRMMatcher(srv.URL)
	out, err := m.Match(context.Background(), []TrackPoint{
		{Lat: 51.5, Lng: -0.1},
		{Lat: 51.51, Lng: -0.11},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(out) != 2 {
		t.Fatalf("len out=%d want 2", len(out))
	}
	if out[0].Lat != 51.5001 || out[0].Lng != -0.1001 {
		t.Errorf("p0 = %+v", out[0])
	}
	if out[1].Lat != 51.5101 || out[1].Lng != -0.1101 {
		t.Errorf("p1 = %+v", out[1])
	}
}

// osrmSnapped renders a /match response that snaps each input coordinate to
// the matching entry of `locs`. A nil entry stands for OSRM's outlier signal.
func osrmSnapped(locs [][2]float64, null ...int) string {
	skip := map[int]bool{}
	for _, i := range null {
		skip[i] = true
	}
	var sb strings.Builder
	sb.WriteString(`{"code":"Ok","matchings":[{"confidence":1.0}],"tracepoints":[`)
	for i, c := range locs {
		if i > 0 {
			sb.WriteByte(',')
		}
		if skip[i] {
			sb.WriteString("null")
			continue
		}
		fmt.Fprintf(&sb, `{"location":[%.6f,%.6f]}`, c[0], c[1])
	}
	sb.WriteString(`]}`)
	return sb.String()
}

// The whole point of reading `tracepoints` rather than the route geometry:
// `ele`, `ts` and `bpm` are measurements belonging to a SAMPLE, and the
// geometry is road-network vertices belonging to none of them. Reading it is
// what emptied the elevation profile and the pace heatmap on /runs/[id] for
// every run recorded with altitude or a strap (decisions § 1171).
func TestOSRMMatcher_CarriesElevationTimestampAndBpmAcross(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, osrmSnapped([][2]float64{{-0.1001, 51.5001}, {-0.1101, 51.5101}}))
	}))
	defer srv.Close()

	ele := 42.5
	ts := time.Date(2026, 9, 5, 6, 30, 0, 0, time.UTC)
	bpm := 148
	in := []TrackPoint{
		{Lat: 51.5, Lng: -0.1, Elevation: &ele, Timestamp: &ts, Bpm: &bpm},
		{Lat: 51.51, Lng: -0.11},
	}
	out, err := NewOSRMMatcher(srv.URL).Match(context.Background(), in)
	if err != nil {
		t.Fatal(err)
	}
	if out[0].Elevation == nil || *out[0].Elevation != ele {
		t.Errorf("ele dropped: %+v", out[0])
	}
	if out[0].Timestamp == nil || !out[0].Timestamp.Equal(ts) {
		t.Errorf("ts dropped: %+v", out[0])
	}
	if out[0].Bpm == nil || *out[0].Bpm != bpm {
		t.Errorf("bpm dropped: %+v", out[0])
	}
	if out[0].Lat != 51.5001 || out[0].Lng != -0.1001 {
		t.Errorf("position not snapped: %+v", out[0])
	}
	if out[1].Elevation != nil || out[1].Timestamp != nil || out[1].Bpm != nil {
		t.Errorf("fields invented on a point that carried none: %+v", out[1])
	}
}

// A `null` tracepoint is OSRM calling that one sample an outlier. Dropping it
// would lose the measurement it carries, which is the defect this matcher was
// fixed for, one sample at a time — so it carries through raw and the output
// stays one point per input point.
func TestOSRMMatcher_NullTracepointCarriesThatSampleRaw(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, osrmSnapped([][2]float64{{-0.1001, 51.5001}, {0, 0}, {-0.1201, 51.5201}}, 1))
	}))
	defer srv.Close()

	bpm := 151
	in := []TrackPoint{
		{Lat: 51.5, Lng: -0.1},
		{Lat: 51.51, Lng: -0.11, Bpm: &bpm},
		{Lat: 51.52, Lng: -0.12},
	}
	out, err := NewOSRMMatcher(srv.URL).Match(context.Background(), in)
	if err != nil {
		t.Fatal(err)
	}
	if len(out) != 3 {
		t.Fatalf("len out=%d, want 3", len(out))
	}
	if out[1] != in[1] {
		t.Errorf("out[1]=%+v, want raw passthrough %+v", out[1], in[1])
	}
	if out[0].Lat != 51.5001 || out[2].Lat != 51.5201 {
		t.Errorf("neighbours should still be snapped: %+v %+v", out[0], out[2])
	}
}

// One tracepoint per input coordinate is what makes the pairing sound. A
// response of any other length indexes something else, and pairing against it
// would attach one sample's heart rate to another sample's position.
func TestOSRMMatcher_TracepointCountMismatchFallsBackToRaw(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, osrmSnapped([][2]float64{{-0.1001, 51.5001}}))
	}))
	defer srv.Close()

	in := []TrackPoint{
		{Lat: 51.5, Lng: -0.1},
		{Lat: 51.51, Lng: -0.11},
	}
	out, err := NewOSRMMatcher(srv.URL).Match(context.Background(), in)
	if err != nil {
		t.Fatal(err)
	}
	if len(out) != 2 || out[0] != in[0] || out[1] != in[1] {
		t.Errorf("out=%+v, want the raw input carried through", out)
	}
}

func TestOSRMMatcher_NoMatchCarriesRawPointsThrough(t *testing.T) {
	// OSRM signals "I couldn't align this" by replying 200 with
	// code != "Ok" (NoMatch / NoSegment / TooBig). Rather than drop the
	// chunk — which would silently truncate the run under a 'matched'
	// label — the matcher carries the chunk's raw input points through,
	// so the output covers the whole input with raw geometry.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"code":"NoMatch","message":"Could not match the trace."}`)
	}))
	defer srv.Close()
	m := NewOSRMMatcher(srv.URL)
	in := []TrackPoint{
		{Lat: 51.5, Lng: -0.1},
		{Lat: 51.51, Lng: -0.11},
	}
	out, err := m.Match(context.Background(), in)
	if err != nil {
		t.Fatalf("NoMatch should not surface as error: %v", err)
	}
	if len(out) != len(in) {
		t.Fatalf("NoMatch should carry raw points through: len out=%d want %d", len(out), len(in))
	}
	for i := range in {
		if out[i] != in[i] {
			t.Errorf("out[%d]=%+v, want raw %+v", i, out[i], in[i])
		}
	}
}

func TestOSRMMatcher_HTTPErrorSurfaced(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprint(w, `{"code":"Error","message":"upstream is down"}`)
	}))
	defer srv.Close()
	m := NewOSRMMatcher(srv.URL)
	_, err := m.Match(context.Background(), []TrackPoint{
		{Lat: 51.5, Lng: -0.1},
		{Lat: 51.51, Lng: -0.11},
	})
	if err == nil {
		t.Fatal("expected error on 502")
	}
	var httpErr *HTTPError
	if !errors.As(err, &httpErr) {
		t.Fatalf("expected *HTTPError, got %T: %v", err, err)
	}
	if httpErr.StatusCode != http.StatusBadGateway {
		t.Errorf("status=%d", httpErr.StatusCode)
	}
}

func TestOSRMMatcher_ChunksLongTracks(t *testing.T) {
	// Build 250 points; chunk size 100 → 3 calls (100, 100, 50).
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		coords := r.URL.Path[len("/match/v1/foot/"):]
		n := strings.Count(coords, ";") + 1
		// Fabricate a matched line of n points, just nudged.
		w.Header().Set("Content-Type", "application/json")
		locs := make([][2]float64, n)
		for i := range locs {
			locs[i] = [2]float64{-0.1 + float64(i)*0.0001, 51.5 + float64(i)*0.0001}
		}
		fmt.Fprint(w, osrmSnapped(locs))
	}))
	defer srv.Close()

	in := make([]TrackPoint, 250)
	for i := range in {
		in[i] = TrackPoint{Lat: 51.5 + float64(i)*0.0001, Lng: -0.1 + float64(i)*0.0001}
	}
	m := NewOSRMMatcher(srv.URL)
	out, err := m.Match(context.Background(), in)
	if err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 3 {
		t.Errorf("expected 3 OSRM calls, got %d", calls.Load())
	}
	if len(out) != 250 {
		t.Errorf("len out=%d, want 250 (chunks stitched back together)", len(out))
	}
}

func TestOSRMMatcher_TailChunkOfOnePassedThrough(t *testing.T) {
	// 101 points with chunk size 100 → first call gets 100, then a
	// 1-point tail. /match needs 2+ points; the matcher should carry
	// the 1-point tail through without calling OSRM for it so the
	// matched line ends where the raw line ends.
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		coords := r.URL.Path[len("/match/v1/foot/"):]
		n := strings.Count(coords, ";") + 1
		if n < 2 {
			t.Errorf("OSRM called with %d points (must be >= 2)", n)
		}
		locs := make([][2]float64, n)
		for i := range locs {
			locs[i] = [2]float64{-0.1, 51.5}
		}
		fmt.Fprint(w, osrmSnapped(locs))
	}))
	defer srv.Close()

	in := make([]TrackPoint, 101)
	for i := range in {
		in[i] = TrackPoint{Lat: 51.5, Lng: -0.1}
	}
	m := NewOSRMMatcher(srv.URL)
	out, err := m.Match(context.Background(), in)
	if err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 1 {
		t.Errorf("expected 1 OSRM call (tail of 1 carries through), got %d", calls.Load())
	}
	if len(out) != 101 {
		t.Errorf("len out=%d, want 101", len(out))
	}
}

func TestOSRMMatcher_PartialMatchCoversWholeRunWithRawFallback(t *testing.T) {
	// 250 points / chunk size 100 → 3 chunks (100, 100, 50). The middle
	// chunk runs through a tunnel and OSRM returns code != "Ok" for it.
	// The previous behaviour dropped that chunk and continued, silently
	// truncating the run to chunks 1 + 3 (150 points) under a 'matched'
	// label. The fix carries the failed chunk's raw input through so the
	// output covers ALL 250 input points.
	var call atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := strings.Count(r.URL.Path[len("/match/v1/foot/"):], ";") + 1
		idx := call.Add(1)
		w.Header().Set("Content-Type", "application/json")
		if idx == 2 {
			// Tunnel: engine can't align this chunk.
			fmt.Fprint(w, `{"code":"NoMatch","message":"Could not match the trace."}`)
			return
		}
		locs := make([][2]float64, n)
		for i := range locs {
			locs[i] = [2]float64{-0.1 + float64(i)*0.0001, 51.5 + float64(i)*0.0001}
		}
		fmt.Fprint(w, osrmSnapped(locs))
	}))
	defer srv.Close()

	in := make([]TrackPoint, 250)
	for i := range in {
		in[i] = TrackPoint{Lat: 51.5 + float64(i)*0.001, Lng: -0.1 + float64(i)*0.001}
	}
	m := NewOSRMMatcher(srv.URL)
	out, err := m.Match(context.Background(), in)
	if err != nil {
		t.Fatal(err)
	}
	if len(out) != 250 {
		t.Fatalf("partial match should cover the whole run: len out=%d, want 250", len(out))
	}
	// The failed middle chunk (input indices 100..199) must appear as the
	// VERBATIM raw input, not snapped — that's the coverage we'd otherwise
	// silently lose.
	for i := 100; i < 200; i++ {
		if out[i] != in[i] {
			t.Fatalf("out[%d]=%+v, want raw passthrough %+v", i, out[i], in[i])
		}
	}
}

func TestOSRMMatcher_DegenerateOkCarriesRawPointsThrough(t *testing.T) {
	// OSRM can reply code="Ok" with nothing usable — an empty matchings list,
	// or a tracepoints array that is absent altogether. Neither is a signal
	// about the samples, so the chunk carries through raw and the matched
	// track still covers the whole run. It used to return empty here, which
	// handleMapMatch wrote as status='skipped'.
	for _, body := range []string{
		`{"code":"Ok","matchings":[]}`,
		`{"code":"Ok","matchings":[{"confidence":0.0}]}`,
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, body)
		}))
		in := []TrackPoint{
			{Lat: 51.5, Lng: -0.1},
			{Lat: 51.51, Lng: -0.11},
		}
		out, err := NewOSRMMatcher(srv.URL).Match(context.Background(), in)
		srv.Close()
		if err != nil {
			t.Fatalf("%s: %v", body, err)
		}
		if len(out) != 2 || out[0] != in[0] || out[1] != in[1] {
			t.Errorf("%s: out=%+v, want the raw input carried through", body, out)
		}
	}
}

// The property every consumer of a matched track now gets to rely on, stated
// once rather than inferred from the cases above: one output point per input
// point, in order, whatever the engine said. It is what lets a caller index
// the matched track against the raw one.
func TestOSRMMatcher_IsLengthPreserving(t *testing.T) {
	var call atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := strings.Count(r.URL.Path[len("/match/v1/foot/"):], ";") + 1
		w.Header().Set("Content-Type", "application/json")
		switch call.Add(1) % 3 {
		case 0:
			fmt.Fprint(w, `{"code":"NoMatch","message":"Could not match the trace."}`)
		case 1:
			locs := make([][2]float64, n)
			for i := range locs {
				locs[i] = [2]float64{-0.1, 51.5}
			}
			fmt.Fprint(w, osrmSnapped(locs, 0, n-1))
		default:
			fmt.Fprint(w, `{"code":"Ok","matchings":[{"confidence":0.1}],"tracepoints":[]}`)
		}
	}))
	defer srv.Close()

	for _, n := range []int{2, 99, 100, 101, 250} {
		in := make([]TrackPoint, n)
		for i := range in {
			in[i] = TrackPoint{Lat: 51.5 + float64(i)*0.001, Lng: -0.1 + float64(i)*0.001}
		}
		out, err := NewOSRMMatcher(srv.URL).Match(context.Background(), in)
		if err != nil {
			t.Fatalf("n=%d: %v", n, err)
		}
		if len(out) != n {
			t.Errorf("n=%d: len out=%d", n, len(out))
		}
	}
}

func TestOSRMMatcher_MalformedJSONIsError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `not json at all`)
	}))
	defer srv.Close()
	m := NewOSRMMatcher(srv.URL)
	_, err := m.Match(context.Background(), []TrackPoint{
		{Lat: 51.5, Lng: -0.1}, {Lat: 51.51, Lng: -0.11},
	})
	if err == nil {
		t.Fatal("expected decode error")
	}
	if !strings.Contains(err.Error(), "decode osrm response") {
		t.Errorf("err=%v, expected wrapper", err)
	}
}
