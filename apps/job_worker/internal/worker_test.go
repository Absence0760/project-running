package internal

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeBackend records every call so tests can pin the worker's
// finish/defer/upload behaviour without a real Supabase. Pure data —
// no network, no goroutines — so tests run in milliseconds.
type fakeBackend struct {
	mu sync.Mutex

	// Inputs
	jobs        []*Job // queued in order; ClaimNextJob pops from the front
	trackByPath map[string][]TrackPoint
	trackURL    string

	// Errors to inject — return on the next call to that method.
	claimErr      error
	downloadErr   error
	uploadErr     error
	updateRowErr  error
	readURLErr    error
	matcherErr    error // not on the backend, but threaded through
	finishErr     error
	deferErr      error

	// Outputs
	finished []finishCall
	deferred []deferCall
	uploaded map[string][]TrackPoint
	rowSets  []rowSet
}

type finishCall struct {
	JobID    int64
	Status   string
	ErrorMsg *string
}

type deferCall struct {
	JobID   int64
	DelayS  int
	ErrMsg  *string
}

type rowSet struct {
	RunID string
	Row   MatchedTrackRow
}

func newFakeBackend() *fakeBackend {
	return &fakeBackend{
		trackByPath: map[string][]TrackPoint{},
		uploaded:    map[string][]TrackPoint{},
	}
}

func (f *fakeBackend) ClaimNextJob(_ context.Context, _, _ string) (*Job, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.claimErr != nil {
		err := f.claimErr
		f.claimErr = nil
		return nil, err
	}
	if len(f.jobs) == 0 {
		return nil, nil
	}
	job := f.jobs[0]
	f.jobs = f.jobs[1:]
	return job, nil
}

func (f *fakeBackend) FinishJob(_ context.Context, jobID int64, status string, msg *string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.finishErr != nil {
		err := f.finishErr
		f.finishErr = nil
		return err
	}
	f.finished = append(f.finished, finishCall{JobID: jobID, Status: status, ErrorMsg: msg})
	return nil
}

func (f *fakeBackend) DeferJob(_ context.Context, jobID int64, delay int, msg *string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.deferErr != nil {
		err := f.deferErr
		f.deferErr = nil
		return err
	}
	f.deferred = append(f.deferred, deferCall{JobID: jobID, DelayS: delay, ErrMsg: msg})
	return nil
}

func (f *fakeBackend) DownloadTrack(_ context.Context, path string) ([]TrackPoint, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.downloadErr != nil {
		err := f.downloadErr
		f.downloadErr = nil
		return nil, err
	}
	pts, ok := f.trackByPath[path]
	if !ok {
		return nil, errors.New("track not found in fake backend: " + path)
	}
	return pts, nil
}

func (f *fakeBackend) UploadMatchedTrack(_ context.Context, path string, pts []TrackPoint) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.uploadErr != nil {
		err := f.uploadErr
		f.uploadErr = nil
		return err
	}
	f.uploaded[path] = pts
	return nil
}

func (f *fakeBackend) UpdateMatchedTrackRow(_ context.Context, runID string, row MatchedTrackRow) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.updateRowErr != nil {
		err := f.updateRowErr
		f.updateRowErr = nil
		return err
	}
	f.rowSets = append(f.rowSets, rowSet{RunID: runID, Row: row})
	return nil
}

func (f *fakeBackend) ReadRunTrackURL(_ context.Context, _ string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.readURLErr != nil {
		err := f.readURLErr
		f.readURLErr = nil
		return "", err
	}
	return f.trackURL, nil
}

// nopMatcher returns whatever it's told to, with the ability to inject
// an error. Used to drive Match success / failure / skip paths without
// touching the production passthrough.
type nopMatcher struct {
	err error
}

func (nopMatcher) Algorithm() string { return "test" }
func (nopMatcher) Version() string   { return "v1" }
func (m nopMatcher) Match(pts []TrackPoint) ([]TrackPoint, error) {
	if m.err != nil {
		return nil, m.err
	}
	return pts, nil
}

func newTestWorker(b Backend, m Matcher) *Worker {
	return &Worker{
		Backend: b,
		Matcher: m,
		Config: Config{
			WorkerID:       "test",
			PollInterval:   1 * time.Millisecond,
			HandleTimeout:  1 * time.Second,
			TransientDelay: 5,
		},
		Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
}

func mustPayload(t *testing.T, p MapMatchPayload) json.RawMessage {
	t.Helper()
	b, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// ---- happy path -------------------------------------------------------

func TestWorker_HappyPath(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	be.jobs = []*Job{{
		ID: 7, Kind: "map_match", Attempts: 1,
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})

	// Drain one job, then cancel.
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got, want := len(be.finished), 1; got != want {
		t.Fatalf("finished count=%d, want %d", got, want)
	}
	if be.finished[0].Status != "done" {
		t.Errorf("finish status=%q, want done", be.finished[0].Status)
	}

	if got, want := len(be.uploaded), 1; got != want {
		t.Fatalf("uploaded count=%d, want %d", got, want)
	}
	matchedPath := "user-1/run-1.matched.json.gz"
	if _, ok := be.uploaded[matchedPath]; !ok {
		t.Errorf("expected upload at %s, got %v", matchedPath, keys(be.uploaded))
	}

	if got, want := len(be.rowSets), 1; got != want {
		t.Fatalf("row sets=%d, want %d", got, want)
	}
	row := be.rowSets[0]
	if row.RunID != "run-1" || row.Row.Status != "matched" {
		t.Errorf("rowSet=%+v, want run-1/matched", row)
	}
	if row.Row.MatchedTrackURL != matchedPath {
		t.Errorf("matched_track_url=%q, want %q", row.Row.MatchedTrackURL, matchedPath)
	}
}

// ---- skipped path -----------------------------------------------------

func TestWorker_SkipsTooFewPoints(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	// One point. Matcher's passthrough returns 1; worker writes
	// 'skipped' rather than uploading a 1-point line.
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{{Lat: 1, Lng: 2}}
	be.jobs = []*Job{{
		ID: 9, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.uploaded) != 0 {
		t.Errorf("uploads on skip path: %v", keys(be.uploaded))
	}
	if len(be.rowSets) != 1 || be.rowSets[0].Row.Status != "skipped" {
		t.Errorf("rowSets=%+v, want one skipped row", be.rowSets)
	}
	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want done", be.finished)
	}
}

// ---- transient retry path ---------------------------------------------

func TestWorker_TransientErrorDefers(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.downloadErr = &HTTPError{StatusCode: 503, Body: "upstream down"}
	be.jobs = []*Job{{
		ID: 11, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 0 {
		t.Errorf("transient error finished the job: %+v", be.finished)
	}
	if len(be.deferred) != 1 {
		t.Fatalf("deferred count=%d, want 1", len(be.deferred))
	}
	if be.deferred[0].DelayS != 5 {
		t.Errorf("delay_s=%d, want 5", be.deferred[0].DelayS)
	}
}

// ---- permanent failure path -------------------------------------------

func TestWorker_PermanentErrorFinishesFailed(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.downloadErr = &HTTPError{StatusCode: 404, Body: "not found"}
	be.jobs = []*Job{{
		ID: 13, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.deferred) != 0 {
		t.Errorf("404 was deferred (should be permanent): %+v", be.deferred)
	}
	if len(be.finished) != 1 || be.finished[0].Status != "failed" {
		t.Fatalf("finish=%+v, want one failed", be.finished)
	}
	if be.finished[0].ErrorMsg == nil || !strings.Contains(*be.finished[0].ErrorMsg, "404") {
		t.Errorf("expected error message to carry 404, got %v", be.finished[0].ErrorMsg)
	}
}

// ---- malformed payload -------------------------------------------------

func TestWorker_BadPayloadFails(t *testing.T) {
	be := newFakeBackend()
	be.jobs = []*Job{{
		ID: 15, Kind: "map_match",
		Payload: json.RawMessage(`{"run_id":""}`),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "failed" {
		t.Errorf("finish=%+v, want failed", be.finished)
	}
}

// ---- unknown kind ------------------------------------------------------

func TestWorker_UnknownKindFails(t *testing.T) {
	be := newFakeBackend()
	be.jobs = []*Job{{
		ID: 17, Kind: "send_carrier_pigeon",
		Payload: json.RawMessage(`{}`),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "failed" {
		t.Errorf("finish=%+v, want failed", be.finished)
	}
	if be.finished[0].ErrorMsg == nil || !strings.Contains(*be.finished[0].ErrorMsg, "unknown job kind") {
		t.Errorf("expected error mentioning unknown kind, got %v", be.finished[0].ErrorMsg)
	}
}

// ---- isTransient classifier -------------------------------------------

func TestIsTransient(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"5xx", &HTTPError{StatusCode: 503}, true},
		{"4xx", &HTTPError{StatusCode: 404}, false},
		{"timeout substring", errors.New("dial tcp: i/o timeout"), true},
		{"connection refused", errors.New("connection refused"), true},
		{"deadline exceeded", context.DeadlineExceeded, true},
		{"plain error", errors.New("payload missing run_id"), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isTransient(tc.err); got != tc.want {
				t.Errorf("isTransient(%v) = %v, want %v", tc.err, got, tc.want)
			}
		})
	}
}

// ---- helpers -----------------------------------------------------------

func keys[K comparable, V any](m map[K]V) []K {
	out := make([]K, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
