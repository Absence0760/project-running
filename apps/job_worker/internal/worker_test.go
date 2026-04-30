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
	// Optional override: when non-nil, ReadRunTrackURL returns
	// trackURLs[i] on the i-th call (clamped to the last entry).
	// Lets tests simulate a re-upload mid-match — the worker reads
	// trackURL at start, then re-reads before writing, and the
	// second read returns the new URL.
	trackURLs []string
	// Auto-link inputs
	autoLinkInfo    RunLinkInfo
	autoLinkInfoErr error
	routeCandidates []RouteMatchCandidate
	findRoutesErr   error
	linkErr         error
	// Auto-link outputs
	links []linkCall

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

type linkCall struct {
	RunID   string
	RouteID string
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

func (f *fakeBackend) ReadRunForAutoLink(_ context.Context, _ string) (RunLinkInfo, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.autoLinkInfoErr != nil {
		err := f.autoLinkInfoErr
		f.autoLinkInfoErr = nil
		return RunLinkInfo{}, err
	}
	return f.autoLinkInfo, nil
}

func (f *fakeBackend) FindMatchingRoutes(
	_ context.Context, _ string, _ []TrackPoint, _ float64, _ int,
) ([]RouteMatchCandidate, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.findRoutesErr != nil {
		err := f.findRoutesErr
		f.findRoutesErr = nil
		return nil, err
	}
	return f.routeCandidates, nil
}

func (f *fakeBackend) LinkRunToRoute(_ context.Context, runID, routeID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.linkErr != nil {
		err := f.linkErr
		f.linkErr = nil
		return err
	}
	f.links = append(f.links, linkCall{RunID: runID, RouteID: routeID})
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
	if len(f.trackURLs) > 0 {
		// Return the next scripted URL, sticking on the last entry
		// once the script runs out (extra reads behave like the
		// final state).
		url := f.trackURLs[0]
		if len(f.trackURLs) > 1 {
			f.trackURLs = f.trackURLs[1:]
		}
		return url, nil
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

// ---- re-upload race ---------------------------------------------------

// If track_url changes between the start of the match and the write
// back, the worker should discard its result and finish_job(done) so
// the OLD job exits cleanly. The trigger has already enqueued a new
// job for the fresh track; that one will produce the right result.
func TestWorker_ReuploadDuringMatchDiscardsResult(t *testing.T) {
	be := newFakeBackend()
	be.trackURLs = []string{
		"user-1/run-1.json.gz",      // first read (download)
		"user-1/run-1.v2.json.gz",   // second read (recheck): re-upload landed
	}
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	be.jobs = []*Job{{
		ID: 21, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.uploaded); got != 0 {
		t.Errorf("uploaded count=%d, want 0 (stale result discarded)", got)
	}
	if got := len(be.rowSets); got != 0 {
		t.Errorf("row writes=%d, want 0 (stale result discarded)", got)
	}
	if got := len(be.finished); got != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want one done", be.finished)
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

// ---- auto-link --------------------------------------------------------

// Confident match: endpoints close, length ratio under 20%. The
// worker should PATCH runs.route_id and the auto-link write happens
// once.
func TestWorker_AutoLinksWhenConfident(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 51.5074, Lng: -0.1278},
		{Lat: 51.5165, Lng: -0.1278},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "", DistanceM: 1000}
	be.routeCandidates = []RouteMatchCandidate{{
		ID:           "route-1",
		Name:         "morning loop",
		DistanceM:    1010, // 1% off the run's stored distance
		StartOffsetM: 5,
		EndOffsetM:   5,
	}}
	be.jobs = []*Job{{
		ID: 31, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.links) != 1 {
		t.Fatalf("links=%d, want 1", len(be.links))
	}
	if be.links[0].RunID != "run-1" || be.links[0].RouteID != "route-1" {
		t.Errorf("link=%+v, want run-1->route-1", be.links[0])
	}
	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want done", be.finished)
	}
}

// Already-linked: route_id is non-empty, so the worker must NOT call
// FindMatchingRoutes / LinkRunToRoute. Idempotent on re-runs.
func TestWorker_NoAutoLinkWhenAlreadyLinked(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "already-linked", DistanceM: 1000}
	// Even if a candidate is on the table, we shouldn't query for it.
	be.routeCandidates = []RouteMatchCandidate{{
		ID: "ignored", StartOffsetM: 0, EndOffsetM: 0, DistanceM: 100,
	}}
	be.jobs = []*Job{{
		ID: 33, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.links) != 0 {
		t.Errorf("links=%+v, want 0 (already linked)", be.links)
	}
}

// Length mismatch: candidate's distance is 50% off the track length.
// Even though endpoints are spot-on, the worker must NOT auto-link —
// this is the "run was a sub-section / superset" case the
// length-ratio check exists to catch.
func TestWorker_NoAutoLinkOnLengthMismatch(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 51.5074, Lng: -0.1278},
		{Lat: 51.5165, Lng: -0.1278},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "", DistanceM: 1000}
	be.routeCandidates = []RouteMatchCandidate{{
		ID:           "route-2",
		Name:         "5k loop",
		DistanceM:    5000, // 5x the run's distance — sub-section case
		StartOffsetM: 0,
		EndOffsetM:   0,
	}}
	be.jobs = []*Job{{
		ID: 35, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.links) != 0 {
		t.Errorf("links=%+v, want 0 (length mismatch)", be.links)
	}
}

// Endpoint mismatch: lengths match but the start/end of the run is
// 500 m from the route's endpoints. Same neighbourhood, different
// run.
func TestWorker_NoAutoLinkOnEndpointMismatch(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 51.5074, Lng: -0.1278},
		{Lat: 51.5165, Lng: -0.1278},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "", DistanceM: 1000}
	be.routeCandidates = []RouteMatchCandidate{{
		ID:           "route-3",
		DistanceM:    1010,
		StartOffsetM: 250,
		EndOffsetM:   300, // sum = 550, > 200 m threshold
	}}
	be.jobs = []*Job{{
		ID: 37, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.links) != 0 {
		t.Errorf("links=%+v, want 0 (endpoints too far)", be.links)
	}
}

// Auto-link failure must NOT fail the job — the match itself
// succeeded, the auto-link is best-effort. Worker logs and returns.
func TestWorker_AutoLinkFailureDoesNotFailJob(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "", DistanceM: 1000}
	be.findRoutesErr = errors.New("rpc unavailable")
	be.jobs = []*Job{{
		ID: 39, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want done despite auto-link failure", be.finished)
	}
	if len(be.rowSets) != 1 || be.rowSets[0].Row.Status != "matched" {
		t.Errorf("rowSets=%+v, want one matched", be.rowSets)
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
