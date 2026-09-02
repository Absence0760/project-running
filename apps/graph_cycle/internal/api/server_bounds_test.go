package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func doCtx(t *testing.T, s *Server, ctx context.Context, method, target, body string) *httptest.ResponseRecorder {
	t.Helper()
	mux := http.NewServeMux()
	s.RegisterRoutes(mux)
	req := httptest.NewRequest(method, target, strings.NewReader(body)).WithContext(ctx)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

// A body past maxBodyBytes is a 400, not a 200 off a half-read stream. The cap
// is enforced by MaxBytesReader; nothing exercised it.
func TestCycleRejectsAnOversizeBody(t *testing.T) {
	s, cLat, cLng := testServer(t)
	// Valid JSON whose leading whitespace alone blows the 4 KiB cap.
	body := strings.Repeat(" ", maxBodyBytes+1) +
		`{"start":{"lat":` + ftoa(cLat) + `,"lng":` + ftoa(cLng) + `},"targetDistanceM":800}`
	rec := do(t, s, http.MethodPost, "/cycle", body)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body=%s)", rec.Code, rec.Body.String())
	}
}

// json.Decoder stops at the first value, so a stream carrying a second one used
// to be accepted with the tail silently discarded — the same laxness
// DisallowUnknownFields exists to refuse.
func TestBodiesWithTrailingDataAreRejected(t *testing.T) {
	s, cLat, cLng := testServer(t)
	cycle := `{"start":{"lat":` + ftoa(cLat) + `,"lng":` + ftoa(cLng) + `},"targetDistanceM":800}`
	for _, tail := range []string{`{"targetDistanceM":1}`, `[1,2]`, `garbage`} {
		rec := do(t, s, http.MethodPost, "/cycle", cycle+tail)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("tail %q: status = %d, want 400", tail, rec.Code)
		}
	}
	// The same body without a tail still succeeds, so the check is not just
	// rejecting everything.
	if rec := do(t, s, http.MethodPost, "/cycle", cycle); rec.Code != http.StatusOK {
		t.Fatalf("clean body status = %d, want 200", rec.Code)
	}
}

// The search is bounded on the SERVER's clock. Before this the only bound was
// the caller's: main.go's WriteTimeout does not cancel the handler context, so
// a search running past it burned a core on a response nobody could receive.
func TestCycleRefusesRatherThanRunningPastItsDeadline(t *testing.T) {
	s, cLat, cLng := testServer(t)
	s.SearchTimeout = time.Nanosecond
	body := `{"start":{"lat":` + ftoa(cLat) + `,"lng":` + ftoa(cLng) + `},"targetDistanceM":800}`
	rec := do(t, s, http.MethodPost, "/cycle", body)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503 (body=%s)", rec.Code, rec.Body.String())
	}
	// Crucially NOT a fabricated loop-poor answer: "no loop here" is a product
	// claim the client turns into "the best loop near you is ~X km", and a
	// search that ran out of clock has established nothing about the region.
	if strings.Contains(rec.Body.String(), `"found"`) {
		t.Fatalf("a timed-out search answered with a found flag: %s", rec.Body.String())
	}
}

func TestRouteRefusesRatherThanRunningPastItsDeadline(t *testing.T) {
	s, _, _ := testServer(t)
	s.SearchTimeout = time.Nanosecond
	rec := do(t, s, http.MethodPost, "/route",
		`{"from":{"lat":40.0,"lng":-77.0},"to":{"lat":40.003592,"lng":-77.004692}}`)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
}

// A caller who went away gets no fabricated answer either — and a different
// code from the deadline, because the two mean opposite things to an operator.
func TestCycleAnsweringACallerWhoLeftIsNotLoopPoor(t *testing.T) {
	s, cLat, cLng := testServer(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	body := `{"start":{"lat":` + ftoa(cLat) + `,"lng":` + ftoa(cLng) + `},"targetDistanceM":800}`
	rec := doCtx(t, s, ctx, http.MethodPost, "/cycle", body)
	if rec.Code != 499 {
		t.Fatalf("status = %d, want 499", rec.Code)
	}
	if strings.Contains(rec.Body.String(), `"found"`) {
		t.Fatalf("an abandoned search answered with a found flag: %s", rec.Body.String())
	}
}

// strconv.ParseFloat accepts "NaN" and "Inf", so /nearest's own finite check is
// the only thing between a hostile query and a NaN reaching the grid.
func TestNearestRejectsNonFiniteQueryCoordinates(t *testing.T) {
	s, _, _ := testServer(t)
	for _, q := range []string{
		"lat=NaN&lng=-77.0",
		"lat=40.0&lng=Inf",
		"lat=-Inf&lng=+Inf",
	} {
		rec := do(t, s, http.MethodGet, "/nearest?"+q, "")
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400", q, rec.Code)
		}
	}
}

// The graph's own doc says "immutable after Build. All routing reads it
// concurrently without locking" — a claim nothing exercised. Under -race this
// is the test that would find a lazily-built cache or a shared scratch buffer.
func TestHandlersAreSafeUnderConcurrentRequests(t *testing.T) {
	s, cLat, cLng := testServer(t)
	cycle := `{"start":{"lat":` + ftoa(cLat) + `,"lng":` + ftoa(cLng) + `},"targetDistanceM":800}`
	route := `{"from":{"lat":40.0,"lng":-77.0},"to":{"lat":40.003592,"lng":-77.004692}}`

	mux := http.NewServeMux()
	s.RegisterRoutes(mux)

	var wg sync.WaitGroup
	codes := make([]int, 24)
	for i := range codes {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			var req *http.Request
			switch i % 3 {
			case 0:
				req = httptest.NewRequest(http.MethodPost, "/cycle", strings.NewReader(cycle))
			case 1:
				req = httptest.NewRequest(http.MethodPost, "/route", strings.NewReader(route))
			default:
				req = httptest.NewRequest(http.MethodGet, "/nearest?lat=40.0&lng=-77.0", nil)
			}
			rec := httptest.NewRecorder()
			mux.ServeHTTP(rec, req)
			codes[i] = rec.Code
		}(i)
	}
	wg.Wait()
	for i, c := range codes {
		if c != http.StatusOK {
			t.Fatalf("request %d: status = %d, want 200", i, c)
		}
	}
}

// Every concurrent /cycle over one graph must agree — a shared mutable
// scratch buffer would show up as differing geometry, which -race cannot see
// when the writes happen to be word-sized.
func TestConcurrentCycleSearchesAgree(t *testing.T) {
	s, cLat, cLng := testServer(t)
	body := `{"start":{"lat":` + ftoa(cLat) + `,"lng":` + ftoa(cLng) + `},"targetDistanceM":800}`
	want := do(t, s, http.MethodPost, "/cycle", body).Body.String()

	var wg sync.WaitGroup
	got := make([]string, 16)
	for i := range got {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			mux := http.NewServeMux()
			s.RegisterRoutes(mux)
			req := httptest.NewRequest(http.MethodPost, "/cycle", strings.NewReader(body))
			rec := httptest.NewRecorder()
			mux.ServeHTTP(rec, req)
			got[i] = rec.Body.String()
		}(i)
	}
	wg.Wait()
	var wantJSON any
	if err := json.Unmarshal([]byte(want), &wantJSON); err != nil {
		t.Fatal(err)
	}
	for i, g := range got {
		if g != want {
			t.Fatalf("concurrent request %d disagreed with the serial answer", i)
		}
	}
}
