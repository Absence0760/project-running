package dataexport

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

// The queued Art 20 rail (decisions.md § 717).
//
// `POST /v1/export/jobs` enqueues and answers immediately; the worker
// builds off the queue with no connection to lose, and
// `GET /v1/export/jobs/latest` reports the outcome and mints the signed
// URL at that moment.
//
// Why a status ENDPOINT rather than an RLS read of the job row: the
// subject cannot download an artifact from a Storage key. The `exports`
// bucket carries no `storage.objects` policies at all — § 703 made an
// export reachable through its signed URL and nothing else — and only
// the service role can mint one. So a row read under RLS would hand the
// subject a path they cannot use and still need this endpoint for the
// URL; the RLS surface would be a second way to learn the same status
// with no way to act on it. `data_export_jobs` therefore ships with RLS
// on and no policies, and this is the only reader.
//
// Why "latest" rather than a job id: a page that reloads mid-build must
// be able to say what is happening without having persisted anything.
// The subject can have at most one export in flight (the one-in-flight
// unique index), so "your most recent export" is unambiguous, and the
// client needs no local state that a cleared browser could lose.

const (
	// ExportJobStaleAfter bounds how long a queued or running row may go
	// untouched before the reader stops believing it. It is DERIVED, not
	// picked: the worker gives a data_export job ExportJobTimeout
	// (internal.ExportJobTimeout, 15 min) per attempt and the enqueue RPC
	// grants 2 attempts, so 30 minutes is the longest a live job can
	// legitimately be working, and the remaining 15 covers queue wait.
	// Past it the worker is gone — a crash between the claim and the
	// result write leaves a row saying `running` that nothing will ever
	// finish — and telling the subject their export is still building
	// forever is worse than telling them it failed.
	// internal's handler test pins the relation between the two numbers.
	ExportJobStaleAfter = 45 * time.Minute

	// StatusNone is what the reader says when the subject has never asked
	// for an export. A distinct value rather than a 404 so a page that
	// reloads has one shape to render.
	StatusNone = "none"
	// StatusStalled is reported for a row past ExportJobStaleAfter. It is
	// a read-time derivation and is never written to the row: the row
	// still says what the worker last said, and the reader says what that
	// is worth now.
	StatusStalled = "stalled"
)

// ExportJobRef is what `enqueue_data_export` answers with.
type ExportJobRef struct {
	ID        string `json:"id"`
	Status    string `json:"status"`
	Format    string `json:"format"`
	CreatedAt string `json:"created_at"`
	Reused    bool   `json:"reused"`
}

// ExportJobRow is the durable state of one export request.
type ExportJobRow struct {
	ID         string `json:"id"`
	UserID     string `json:"user_id"`
	Format     string `json:"format"`
	Status     string `json:"status"`
	ObjectPath string `json:"object_path"`
	RunCount   *int   `json:"run_count"`
	TotalRuns  *int   `json:"total_runs"`
	Complete   *bool  `json:"complete"`
	ErrorCode  string `json:"error_code"`
	StartedAt  string `json:"started_at"`
	FinishedAt string `json:"finished_at"`
	CreatedAt  string `json:"created_at"`
	UpdatedAt  string `json:"updated_at"`
}

// isStale reports whether an unfinished row has gone quiet for longer
// than any live worker could. `updated_at` is trigger-maintained, so a
// handler that stamps `running` refreshes it; a worker that died does
// not.
func (r *ExportJobRow) isStale(now time.Time) bool {
	if r.Status != "queued" && r.Status != "running" {
		return false
	}
	touched := r.UpdatedAt
	if touched == "" {
		touched = r.CreatedAt
	}
	t, err := time.Parse(time.RFC3339Nano, touched)
	if err != nil {
		// An unparseable timestamp is not evidence of staleness. Saying
		// "still building" about a row that is genuinely working is
		// recoverable; declaring a healthy export dead is not.
		return false
	}
	return now.Sub(t) > ExportJobStaleAfter
}

type exportJobRequest struct {
	Format string `json:"format"`
}

// handleJobsCreate serves POST /v1/export/jobs.
func (s *Server) handleJobsCreate(w http.ResponseWriter, r *http.Request) {
	if !s.Verifier.Enabled() {
		s.log().Error("dataexport: JWT secret not configured; refusing")
		http.Error(w, `{"error":"export_not_configured"}`, http.StatusServiceUnavailable)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		http.Error(w, `{"error":"method_not_allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	userID, err := s.extractUserID(r)
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusUnauthorized)
		return
	}

	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, MaxBodyBytes))
	dec.DisallowUnknownFields()
	var req exportJobRequest
	if err := dec.Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, `{"error":"bad_body"}`, http.StatusBadRequest)
		return
	}
	format := req.Format
	if format == "" {
		format = "csv"
	}
	if !ValidFormat(format) {
		http.Error(w, `{"error":"format must be csv, gpx, or backup"}`, http.StatusBadRequest)
		return
	}

	// An export already in flight is the answer, and asking for it must
	// not cost a quota token: a client retrying through a flaky
	// connection would otherwise spend its whole hour's allowance
	// re-requesting the export it already has building. The enqueue RPC
	// reuses the in-flight row anyway, so the worst a race here can do is
	// spend one token and still not start a second build.
	if existing, err := s.Backend.LatestDataExportJob(r.Context(), userID); err == nil && existing != nil {
		if (existing.Status == "queued" || existing.Status == "running") && !existing.isStale(time.Now().UTC()) {
			writeJSON(w, http.StatusAccepted, map[string]any{
				"job_id": existing.ID,
				"status": existing.Status,
				"format": existing.Format,
				"reused": true,
			})
			return
		}
	}

	denied, retryAfter, rateErr := s.Backend.CheckRateLimitTiered(
		r.Context(), userID, "export-data",
		FreeQuotaPerHour, ProQuotaPerHour, 3600,
	)
	if rateErr != nil {
		s.log().Warn("dataexport: rate-limit RPC failed; throttling fail-closed",
			"err", rateErr, "user_id", userID)
		w.Header().Set("Retry-After", "60")
		http.Error(w, `{"error":"rate_limit_unavailable"}`, http.StatusTooManyRequests)
		return
	}
	if denied {
		if retryAfter > 0 {
			w.Header().Set("Retry-After", fmt.Sprintf("%d", retryAfter))
		}
		http.Error(w, `{"error":"rate_limited"}`, http.StatusTooManyRequests)
		return
	}

	ref, err := s.Backend.EnqueueDataExport(r.Context(), userID, format)
	if err != nil {
		s.log().Error("dataexport: enqueue failed", "err", err, "user_id", userID)
		http.Error(w, `{"error":"enqueue_failed"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"job_id": ref.ID,
		"status": ref.Status,
		"format": ref.Format,
		"reused": ref.Reused,
	})
}

// handleJobsLatest serves GET /v1/export/jobs/latest.
func (s *Server) handleJobsLatest(w http.ResponseWriter, r *http.Request) {
	if !s.Verifier.Enabled() {
		s.log().Error("dataexport: JWT secret not configured; refusing")
		http.Error(w, `{"error":"export_not_configured"}`, http.StatusServiceUnavailable)
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, `{"error":"method_not_allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	userID, err := s.extractUserID(r)
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusUnauthorized)
		return
	}

	row, err := s.Backend.LatestDataExportJob(r.Context(), userID)
	if err != nil {
		s.log().Error("dataexport: job status read failed", "err", err, "user_id", userID)
		http.Error(w, `{"error":"status_unavailable"}`, http.StatusInternalServerError)
		return
	}
	if row == nil {
		writeJSON(w, http.StatusOK, map[string]any{"status": StatusNone})
		return
	}

	body := map[string]any{
		"job_id":       row.ID,
		"status":       row.Status,
		"format":       row.Format,
		"requested_at": row.CreatedAt,
	}
	switch {
	case row.isStale(time.Now().UTC()):
		body["status"] = StatusStalled
	case row.Status == "failed":
		if row.ErrorCode != "" {
			body["error_code"] = row.ErrorCode
		}
	case row.Status == "ready":
		// The 10-minute clock starts HERE, not when the build finished.
		// A subject who closed the tab and came back an hour later gets
		// a fresh window rather than a URL that expired while the page
		// was shut.
		signed, err := s.Backend.CreateSignedURL(r.Context(), row.ObjectPath, SignedURLTTLSec)
		if err != nil {
			if errors.Is(err, ErrArtifactGone) {
				// The retention sweep collected it. The row's own
				// `expired` state is the usual account of this; reaching
				// it here means the object went first.
				body["status"] = "expired"
				break
			}
			s.log().Error("dataexport: signed URL failed", "err", err, "user_id", userID)
			http.Error(w, `{"error":"signed_url_failed"}`, http.StatusInternalServerError)
			return
		}
		body["url"] = signed
		body["expires_in"] = SignedURLTTLSec
		if row.RunCount != nil {
			body["count"] = *row.RunCount
		}
		if row.TotalRuns != nil {
			body["total"] = *row.TotalRuns
		}
		if row.Complete != nil {
			body["complete"] = *row.Complete
		}
	}
	writeJSON(w, http.StatusOK, body)
}
