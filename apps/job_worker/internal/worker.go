package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"strings"
	"time"
)

// Backend is the subset of SupabaseClient methods the worker needs.
// Defining it as an interface here lets tests substitute a fake
// implementation without standing up a real Supabase stack.
type Backend interface {
	ClaimNextJob(ctx context.Context, workerID, kindFilter string) (*Job, error)
	FinishJob(ctx context.Context, jobID int64, resultStatus string, errMsg *string) error
	DeferJob(ctx context.Context, jobID int64, delaySeconds int, errMsg *string) error
	DownloadTrack(ctx context.Context, path string) ([]TrackPoint, error)
	UploadMatchedTrack(ctx context.Context, path string, points []TrackPoint) error
	UpdateMatchedTrackRow(ctx context.Context, runID string, expectedSourceTrackURL string, row MatchedTrackRow) error
	ReadRunTrackURL(ctx context.Context, runID string) (string, error)
	ReadRunForAutoLink(ctx context.Context, runID string) (RunLinkInfo, error)
	FindMatchingRoutes(ctx context.Context, userID string, track []TrackPoint, toleranceM float64, maxResults int) ([]RouteMatchCandidate, error)
	LinkRunToRoute(ctx context.Context, runID, routeID string) error
	// Token-refresh path — used by the kind='token_refresh' handler
	// that replaces apps/backend/supabase/functions/refresh-tokens.
	FetchExpiringStravaIntegrations(ctx context.Context, within time.Duration) ([]IntegrationRow, error)
	GetIntegrationTokens(ctx context.Context, userID, provider string) (*TokenPair, error)
	SetIntegrationTokens(ctx context.Context, userID, provider, accessToken, refreshToken string, tokenExpiry time.Time) error
	// Strava webhook ingest path — used by the kind='strava_event'
	// handler that replaces apps/backend/supabase/functions/strava-webhook.
	FindIntegrationUserByAthlete(ctx context.Context, provider string, athleteID int64) (string, error)
	IsStravaActivityImported(ctx context.Context, userID string, stravaActivityID int64) (bool, error)
	InsertStravaRun(ctx context.Context, userID string, act *StravaActivity) (*IngestedRunInfo, error)
	UpdateRunTrackURL(ctx context.Context, runID, trackURL string) error
	// Webhook dedupe — bound to the `webhook_events` table. Returned
	// `inserted == false` means the row already existed (Strava-side
	// retry); the caller treats that as "ack 200, skip ingest".
	InsertWebhookEvent(ctx context.Context, provider, eventID string) (inserted bool, err error)
	DeleteWebhookEvent(ctx context.Context, provider, eventID string) error
}

// StravaRefresher is the upstream OAuth call used by handleTokenRefresh.
// Production wires *StravaClient; tests substitute a fake to avoid
// hitting Strava during unit runs.
type StravaRefresher interface {
	Refresh(ctx context.Context, refreshToken string) (*StravaTokenResponse, error)
}

// StravaIngestor is the upstream interface used by handleStravaEvent
// for the per-event activity fetch + track-stream upload. Wider than
// StravaRefresher so the token-refresh handler doesn't carry these
// methods; production wires *StravaClient (which implements both).
type StravaIngestor interface {
	FetchActivity(ctx context.Context, accessToken string, activityID int64) (StravaActivityResult, error)
	FetchStreams(ctx context.Context, accessToken string, activityID int64) (map[string]StravaStream, error)
	Refresh(ctx context.Context, refreshToken string) (*StravaTokenResponse, error)
}

// Config bundles tunables. Defaults are conservative — short poll
// interval keeps latency low when the queue's busy, exponential
// backoff caps avoid hammering the matching upstream when it's down.
type Config struct {
	WorkerID       string
	PollInterval   time.Duration // sleep between empty claims
	HandleTimeout  time.Duration // per-job timeout
	TransientDelay int           // seconds; defer_job's delay_seconds
}

// Worker drains background jobs forever. Stops when ctx is
// cancelled. Each iteration claims at most one job, dispatches, and
// loops back — single-flight per worker keeps the per-job error
// surface simple. Run multiple processes for horizontal scale; the
// SQL `for update skip locked` in claim_next_job makes that safe.
//
// Drains any kind the dispatcher knows about. Today: `map_match`
// + `token_refresh`. Strava-webhook / data-export will land as
// additional cases — see `dispatch`.
type Worker struct {
	Backend Backend
	Matcher Matcher
	// Strava is the OAuth-refresh + activity-fetch upstream. Nil
	// disables both `token_refresh` and `strava_event` dispatch
	// paths; jobs of those kinds fall through to the
	// "Strava client not configured" failure branch.
	// Wired in main.go when STRAVA_CLIENT_ID + STRAVA_CLIENT_SECRET
	// are both set.
	Strava StravaIngestor
	Config Config
	Log    *slog.Logger
	// OnPollTick fires after every claim attempt (whether or not a job
	// was returned). Used by the /health server to distinguish "queue
	// empty" from "loop wedged" — see main.go. Safe to leave nil; the
	// loop calls only when the hook is set.
	OnPollTick func()
}

// Run is the worker loop. Returns nil on graceful shutdown (ctx
// cancelled), a non-nil error if a fatal pre-loop check fails.
func (w *Worker) Run(ctx context.Context) error {
	if w.Config.WorkerID == "" {
		return errors.New("worker: WorkerID is required")
	}
	if w.Config.PollInterval <= 0 {
		w.Config.PollInterval = 2 * time.Second
	}
	if w.Config.HandleTimeout <= 0 {
		w.Config.HandleTimeout = 5 * time.Minute
	}
	if w.Config.TransientDelay <= 0 {
		w.Config.TransientDelay = 30
	}
	w.Log.Info("worker started", "id", w.Config.WorkerID)

	for {
		if err := ctx.Err(); err != nil {
			w.Log.Info("worker shutting down", "reason", err)
			return nil
		}

		// Empty kind filter → drain any kind the dispatcher knows
		// about. Today: map_match + token_refresh. New kinds plug into
		// `dispatch` without touching this claim.
		job, err := w.Backend.ClaimNextJob(ctx, w.Config.WorkerID, "")
		// Heartbeat fires after the claim returns — including the
		// error and empty-queue paths. /health reads this; a stuck
		// claim (DB down, network gone) won't bump it and the
		// endpoint flips to 503 once the heartbeat ages past 5x
		// PollInterval.
		if w.OnPollTick != nil {
			w.OnPollTick()
		}
		if err != nil {
			// Claim failures are infrastructural — DB is down,
			// service key is wrong, etc. Log and back off rather
			// than spinning the CPU. Don't return: a transient
			// blip shouldn't kill the worker on Fly.io.
			w.Log.Error("claim_next_job failed", "err", err)
			sleep(ctx, w.Config.PollInterval)
			continue
		}
		if job == nil {
			sleep(ctx, w.Config.PollInterval)
			continue
		}

		w.handle(ctx, job)
	}
}

// handle wraps the per-job work with a timeout + result reporting.
// Always reports back to the queue: a panic-free error path is
// finish_job(failed, …); a transient one is defer_job(delay, …).
// Lost jobs (worker crashes mid-handle) are recovered on the next
// process start because attempts < max_attempts and locked_at can be
// reaped by an external watchdog (out of scope for v1).
func (w *Worker) handle(ctx context.Context, job *Job) {
	jobCtx, cancel := context.WithTimeout(ctx, w.Config.HandleTimeout)
	defer cancel()

	logger := w.Log.With("job_id", job.ID, "kind", job.Kind, "attempt", job.Attempts)
	logger.Info("handling job")

	err := w.dispatch(jobCtx, job)
	if err == nil {
		if ferr := w.Backend.FinishJob(ctx, job.ID, "done", nil); ferr != nil {
			logger.Error("finish_job(done) failed", "err", ferr)
		}
		logger.Info("job done")
		return
	}

	// Classify: transient errors get defer_job; everything else is
	// finish_job(failed). HTTP 5xx + network timeouts are transient;
	// 4xx (bad payload, missing run, RLS denial) is permanent. Same
	// shape as the watch's drain classifier.
	msg := err.Error()
	if isTransient(err) {
		if derr := w.Backend.DeferJob(ctx, job.ID, w.Config.TransientDelay, ptr(msg)); derr != nil {
			logger.Error("defer_job failed", "err", derr)
		}
		logger.Warn("job deferred", "delay_s", w.Config.TransientDelay, "err", err)
		return
	}
	if ferr := w.Backend.FinishJob(ctx, job.ID, "failed", ptr(msg)); ferr != nil {
		logger.Error("finish_job(failed) failed", "err", ferr)
	}
	logger.Error("job failed", "err", err)
}

// dispatch picks the per-kind handler. New job types (strava-webhook,
// data-export per roadmap §214) plug in here.
func (w *Worker) dispatch(ctx context.Context, job *Job) error {
	switch job.Kind {
	case "map_match":
		return w.handleMapMatch(ctx, job)
	case "token_refresh":
		return w.handleTokenRefresh(ctx, job)
	case "strava_event":
		return w.handleStravaEvent(ctx, job)
	default:
		return fmt.Errorf("unknown job kind %q", job.Kind)
	}
}

// handleMapMatch is the production handler for map_match jobs. Reads
// the latest track_url at match time so a re-upload that changes the
// path is matched against the freshest data — the trigger's reset of
// run_matched_tracks pairs with this read so the worker never persists
// a result tagged against a stale track.
//
// Re-upload race handling: between reading track_url and writing the
// result, a runner can re-upload (replacing track_url). Without a
// recheck, the worker would persist a 'matched' state tagged against
// the OLD url over the trigger's pending reset. We re-read the url
// just before the write and discard the result if it changed — the
// newer job already queued by the trigger will produce the right one.
// A small TOCTOU window remains between recheck and PATCH; closing it
// fully needs a server-side CAS (e.g. a `source_track_url` column on
// run_matched_tracks), which is the upgrade path when a real engine
// lands. The recheck shrinks the race from O(match duration) to
// O(network round-trip), good enough for the stub matcher.
func (w *Worker) handleMapMatch(ctx context.Context, job *Job) error {
	var p MapMatchPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.RunID == "" || p.UserID == "" {
		return errors.New("payload missing run_id or user_id")
	}

	trackURL, err := w.Backend.ReadRunTrackURL(ctx, p.RunID)
	if err != nil {
		return fmt.Errorf("read track_url: %w", err)
	}

	raw, err := w.Backend.DownloadTrack(ctx, trackURL)
	if err != nil {
		return fmt.Errorf("download track: %w", err)
	}

	matched, err := w.Matcher.Match(raw)
	if err != nil {
		return fmt.Errorf("match: %w", err)
	}

	// Pre-write recheck. Skips the upload + PATCH when we already
	// know track_url has changed — saves wasted Storage writes.
	// Doesn't replace the source_track_url CAS below; the CAS is
	// what closes the residual TOCTOU window (re-upload between
	// recheck and PATCH).
	currentURL, err := w.Backend.ReadRunTrackURL(ctx, p.RunID)
	if err != nil {
		return fmt.Errorf("recheck track_url: %w", err)
	}
	if currentURL != trackURL {
		w.Log.Info(
			"track_url changed mid-match; discarding stale result",
			"run_id", p.RunID,
			"matched_against", trackURL,
			"current", currentURL,
		)
		return nil
	}

	// "Skipped" is a deliberate non-failure outcome — too few points
	// to align (indoor / no-GPS), or the matcher decided the noise
	// floor was too high. The status update lets the client tell
	// "matcher decided no" apart from "matcher hasn't run yet".
	//
	// Both write paths PATCH conditionally on source_track_url; an
	// ErrStaleSourceTrackURL means the trigger reset the row out
	// from under us between recheck and PATCH (the residual
	// TOCTOU window). Discard cleanly — the trigger already queued
	// a fresh job, no need to fail the current one.
	if len(matched) < 2 {
		err := w.Backend.UpdateMatchedTrackRow(ctx, p.RunID, trackURL, MatchedTrackRow{
			Status:           "skipped",
			MatchedTrackURL:  "",
			Algorithm:        w.Matcher.Algorithm(),
			AlgorithmVersion: w.Matcher.Version(),
		})
		if errors.Is(err, ErrStaleSourceTrackURL) {
			w.Log.Info("source_track_url changed before PATCH; discarding stale skip",
				"run_id", p.RunID)
			return nil
		}
		if err != nil {
			return err
		}
	} else {
		matchedPath := fmt.Sprintf("%s/%s.matched.json.gz", p.UserID, p.RunID)
		if err := w.Backend.UploadMatchedTrack(ctx, matchedPath, matched); err != nil {
			return fmt.Errorf("upload matched: %w", err)
		}
		now := time.Now().UTC()
		err := w.Backend.UpdateMatchedTrackRow(ctx, p.RunID, trackURL, MatchedTrackRow{
			Status:           "matched",
			MatchedTrackURL:  matchedPath,
			MatchedAt:        &now,
			Algorithm:        w.Matcher.Algorithm(),
			AlgorithmVersion: w.Matcher.Version(),
		})
		if errors.Is(err, ErrStaleSourceTrackURL) {
			w.Log.Info("source_track_url changed before PATCH; discarding stale match",
				"run_id", p.RunID,
				"orphaned_storage_path", matchedPath)
			return nil
		}
		if err != nil {
			return err
		}
	}

	// Auto-link is best-effort and independent of match status. Fires
	// for skipped runs too — the spatial overlap question doesn't
	// depend on the matcher's output. A failure here cannot fail the
	// job because the match is already persisted; log and move on.
	if err := w.maybeAutoLinkRoute(ctx, p, raw); err != nil {
		w.Log.Warn("auto-link skipped",
			"run_id", p.RunID,
			"err", err,
		)
	}
	return nil
}

// maybeAutoLinkRoute looks for a saved route the run's track lies on
// and PATCHes runs.route_id when one passes the confidence threshold.
// Same scoring policy as web/mobile: combined endpoint offset under
// 200 m AND length ratio under 0.20. Either dimension alone produces
// false positives — a run that shares one endpoint with a route, or a
// run that's a sub-section of a longer route. The conjunction is
// trustworthy.
//
// Length comparison uses runs.distance_m (the canonical recorder
// figure) rather than a worker-side haversine of the track. The
// recorder applies movement-quality filters (sub-2m / >100m deltas
// dropped) that the worker can't replay; the stored value is closer
// to truth and matches what web/mobile use.
//
// No-ops when run.route_id is already set (the runner picked one
// at start, or a previous match auto-linked it).
func (w *Worker) maybeAutoLinkRoute(
	ctx context.Context, p MapMatchPayload, raw []TrackPoint,
) error {
	if len(raw) < 2 {
		return nil
	}
	info, err := w.Backend.ReadRunForAutoLink(ctx, p.RunID)
	if err != nil {
		return fmt.Errorf("read run for auto-link: %w", err)
	}
	if info.RouteID != "" {
		return nil
	}
	if info.DistanceM <= 0 {
		// Manual-entry run with no recorded distance, or a pathological
		// row. Nothing to compare against — bail rather than guess.
		return nil
	}
	candidates, err := w.Backend.FindMatchingRoutes(ctx, p.UserID, raw, 100, 5)
	if err != nil {
		return fmt.Errorf("find matching routes: %w", err)
	}
	if len(candidates) == 0 {
		return nil
	}
	best := candidates[0]
	lengthRatio := math.Abs(best.DistanceM-info.DistanceM) / info.DistanceM
	if best.StartOffsetM+best.EndOffsetM >= 200 || lengthRatio >= 0.20 {
		return nil
	}
	if err := w.Backend.LinkRunToRoute(ctx, p.RunID, best.ID); err != nil {
		return fmt.Errorf("link run to route: %w", err)
	}
	w.Log.Info(
		"auto-linked run to route",
		"run_id", p.RunID,
		"route_id", best.ID,
		"route_name", best.Name,
		"start_offset_m", best.StartOffsetM,
		"end_offset_m", best.EndOffsetM,
		"length_ratio", lengthRatio,
	)
	return nil
}

// isTransient classifies an error as worth-retrying. Network blips,
// 5xx upstream, request timeouts → defer + retry. 4xx, malformed
// payload, missing run, RLS denial → permanent.
func isTransient(err error) bool {
	var hErr *HTTPError
	if errors.As(err, &hErr) {
		return hErr.StatusCode >= 500 && hErr.StatusCode < 600
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	msg := strings.ToLower(err.Error())
	for _, marker := range []string{"timeout", "connection refused", "connection reset", "no such host", "i/o timeout"} {
		if strings.Contains(msg, marker) {
			return true
		}
	}
	return false
}

func sleep(ctx context.Context, d time.Duration) {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}

func ptr[T any](v T) *T { return &v }
