package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
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
	UpdateMatchedTrackRow(ctx context.Context, runID string, row MatchedTrackRow) error
	ReadRunTrackURL(ctx context.Context, runID string) (string, error)
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

// Worker drains kind='map_match' jobs forever. Stops when ctx is
// cancelled. Each iteration claims at most one job, dispatches, and
// loops back — single-flight per worker keeps the per-job error
// surface simple. Run multiple processes for horizontal scale; the
// SQL `for update skip locked` in claim_next_job makes that safe.
type Worker struct {
	Backend Backend
	Matcher Matcher
	Config  Config
	Log     *slog.Logger
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

		job, err := w.Backend.ClaimNextJob(ctx, w.Config.WorkerID, "map_match")
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
// token-refresh, data-export per roadmap §214) plug in here.
func (w *Worker) dispatch(ctx context.Context, job *Job) error {
	switch job.Kind {
	case "map_match":
		return w.handleMapMatch(ctx, job)
	default:
		return fmt.Errorf("unknown job kind %q", job.Kind)
	}
}

// handleMapMatch is the production handler for map_match jobs. Reads
// the latest track_url at match time so a re-upload that changes the
// path is matched against the freshest data — the trigger's reset of
// run_matched_tracks pairs with this read so the worker never persists
// a result tagged against a stale track.
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

	// "Skipped" is a deliberate non-failure outcome — too few points
	// to align (indoor / no-GPS), or the matcher decided the noise
	// floor was too high. The status update lets the client tell
	// "matcher decided no" apart from "matcher hasn't run yet".
	if len(matched) < 2 {
		return w.Backend.UpdateMatchedTrackRow(ctx, p.RunID, MatchedTrackRow{
			Status:           "skipped",
			MatchedTrackURL:  "",
			Algorithm:        w.Matcher.Algorithm(),
			AlgorithmVersion: w.Matcher.Version(),
		})
	}

	matchedPath := fmt.Sprintf("%s/%s.matched.json.gz", p.UserID, p.RunID)
	if err := w.Backend.UploadMatchedTrack(ctx, matchedPath, matched); err != nil {
		return fmt.Errorf("upload matched: %w", err)
	}

	now := time.Now().UTC()
	return w.Backend.UpdateMatchedTrackRow(ctx, p.RunID, MatchedTrackRow{
		Status:           "matched",
		MatchedTrackURL:  matchedPath,
		MatchedAt:        &now,
		Algorithm:        w.Matcher.Algorithm(),
		AlgorithmVersion: w.Matcher.Version(),
	})
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
