package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"
)

// The queued Art 20 export (kind='data_export', migration 20270603_001,
// decisions.md § 717).
//
// The build used to run on the caller's own connection: they POSTed
// /v1/export and waited while every section was walked and every 6 MiB
// chunk pushed, so their timeout, a disconnect, or a backgrounded mobile
// app could end an export that would otherwise have completed. It runs
// here now, with nothing to lose, and that endpoint is gone
// (decisions.md § 724).

const (
	// ExportJobTimeout is the per-attempt clock for one export build.
	// The generic 5-minute HandleTimeout is right for a push or an email
	// and wrong for a deep-history archive: the export's cost is
	// dominated by per-object Storage fetches, and killing it at five
	// minutes would make the queued rail worse than the synchronous one
	// it replaced, which had no clock at all.
	ExportJobTimeout = 15 * time.Minute

	// ExportJobMaxAttempts mirrors the `max_attempts` the enqueue RPC
	// stamps on the queue row. The handler needs it to know when it is
	// on the last attempt and must tell the subject the export failed
	// rather than leave the row saying `running` forever. Two, not the
	// table default of five, because every attempt that reaches the tus
	// Finish uploads a whole archive.
	ExportJobMaxAttempts = 2
)

// DataExportPayload is the payload `enqueue_data_export` writes.
type DataExportPayload struct {
	ExportJobID string `json:"export_job_id"`
	UserID      string `json:"user_id"`
	Format      string `json:"format"`
}

// ExportArtifact is where a finished archive landed and what it claims
// about itself. Mirrors dataexport.ArtifactBuild; main.go's adapter
// translates, same leaf-package rule as ExportRun / ExportCompleteness.
type ExportArtifact struct {
	ObjectPath string
	Runs       int
	TotalRuns  int
	Complete   bool
}

// DataExportBuilder streams one Art 20 archive into Storage. Nil
// disables the dispatch path. Production wires an adapter over
// `dataexport.BuildArtifact`, so the queued rail and the deprecated
// synchronous endpoint build byte-identical archives.
type DataExportBuilder interface {
	BuildExportArtifact(ctx context.Context, userID, format string) (ExportArtifact, error)
}

// ExportBuildError carries the machine token the subject's client
// renders beside the failure. Wrapping rather than replacing keeps
// `isTransient` able to see the cause underneath.
type ExportBuildError struct {
	Code string
	Err  error
}

func (e *ExportBuildError) Error() string { return e.Code + ": " + e.Err.Error() }
func (e *ExportBuildError) Unwrap() error { return e.Err }

// exportErrorCode picks the token to record against a failed build.
func exportErrorCode(err error) string {
	var be *ExportBuildError
	if errors.As(err, &be) && be.Code != "" {
		return be.Code
	}
	return "build_failed"
}

func (w *Worker) handleDataExport(ctx context.Context, job *Job) error {
	var p DataExportPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.ExportJobID == "" || p.UserID == "" || p.Format == "" {
		return errors.New("payload missing export_job_id, user_id or format")
	}

	logger := w.Log.With("export_job_id", p.ExportJobID, "user_id", p.UserID, "format", p.Format)

	if w.DataExport == nil {
		// Every other optional transport finishes its job `done` and
		// leaves the underlying row for a later configured deploy. An
		// export cannot: the subject is waiting on a status that would
		// then say `queued` for ever. Tell them it failed.
		w.recordExportFailure(ctx, p.ExportJobID, "not_configured", logger)
		return errors.New("data export builder not configured")
	}

	row, err := w.Backend.GetDataExportJob(ctx, p.ExportJobID)
	if err != nil {
		if errors.Is(err, ErrExportJobGone) {
			// The subject deleted their account between the enqueue and
			// the claim and the FK cascade took the row. There is
			// nothing to build and nobody to tell; failing the job would
			// only page an operator about a correct erasure.
			logger.Info("data export row is gone (account deleted); dropping job")
			return nil
		}
		return err
	}
	// A retry that arrives after the artifact already landed must not
	// build a second one: the upload is the expensive half, and the
	// first archive would be orphaned in Storage until the retention
	// sweep collected it.
	if row.Status == "ready" && row.ObjectPath != "" {
		logger.Info("data export already built; skipping rebuild")
		// Still announce. The window this covers is a crash between the
		// Finish write and the announcement: the artifact is there, the
		// row says ready, and the only thing missing is that nobody told
		// the subject. Announcing here rather than only on the fresh-build
		// path is what makes the retry repair that instead of inheriting
		// it — the RPC's own stamp is what keeps it from announcing twice.
		w.announceExportReady(ctx, p.ExportJobID, logger)
		return nil
	}
	if row.Status == "expired" {
		logger.Info("data export expired before it was built; dropping job")
		return nil
	}

	now := time.Now().UTC().Format(time.RFC3339Nano)
	if err := w.Backend.MarkDataExportRunning(ctx, p.ExportJobID, now); err != nil {
		return err
	}

	art, buildErr := w.DataExport.BuildExportArtifact(ctx, p.UserID, p.Format)
	if buildErr != nil {
		// Mark the row failed only when no further attempt is coming.
		// While a retry is still budgeted the row stays `running`, which
		// is the true thing to show a subject watching the page: the
		// export has not failed yet, it is being tried again.
		if int(job.Attempts) >= ExportJobMaxAttempts || !isTransient(buildErr) {
			w.recordExportFailure(ctx, p.ExportJobID, exportErrorCode(buildErr), logger)
		}
		return buildErr
	}

	// The artifact exists from here — tus materialised it when Finish
	// returned. If this write fails the job retries and rebuilds, which
	// costs one orphaned archive that the 7-day sweep collects; the
	// alternative, swallowing the error, would leave the subject
	// watching a `running` row whose export is sitting in Storage.
	if err := w.Backend.FinishDataExportJob(ctx, p.ExportJobID, ExportJobResult{
		Status:     "ready",
		ObjectPath: &art.ObjectPath,
		RunCount:   &art.Runs,
		TotalRuns:  &art.TotalRuns,
		Complete:   &art.Complete,
		FinishedAt: now,
	}); err != nil {
		return err
	}

	w.announceExportReady(ctx, p.ExportJobID, logger)
	return nil
}

// announceExportReady tells the subject their archive is collectable
// (decisions.md § 729). Called only once the row already says `ready`,
// because that is the claim the announcement makes.
//
// Deliberately returns nothing. A failure here must not fail the job:
// the export succeeded, the archive is in Storage, and the status
// endpoint the message merely points at is already reporting it. Failing
// would spend the second attempt rebuilding a whole archive to fix a
// missing email — and the rebuild would find the row `ready` and skip,
// so the retry could not even repair what it cost. The subject is told
// late, or not at all, rather than charged for an announcement.
func (w *Worker) announceExportReady(ctx context.Context, exportJobID string, logger *slog.Logger) {
	announced, err := w.Backend.NotifyDataExportReady(ctx, exportJobID)
	if err != nil {
		logger.Error("data export: announcing the finished export failed", "err", err)
		return
	}
	if announced {
		logger.Info("data export: subject notified")
	}
}

func (w *Worker) recordExportFailure(ctx context.Context, exportJobID, code string, logger *slog.Logger) {
	err := w.Backend.FinishDataExportJob(ctx, exportJobID, ExportJobResult{
		Status:     "failed",
		ErrorCode:  &code,
		FinishedAt: time.Now().UTC().Format(time.RFC3339Nano),
	})
	if err != nil {
		// The row is left saying `running`; the status endpoint's
		// staleness derivation is what stops that reading as "still
		// building" for ever.
		logger.Error("data export: recording the failure failed", "err", err, "code", code)
	}
}
