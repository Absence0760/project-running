package internal

// The queued Art 20 export handler (decisions.md § 717).
//
// The build itself is already covered by the dataexport package's own
// suites; what is new here is everything AROUND it — a subject watching
// a status page has to be told the truth about a build that succeeded,
// one that is being retried, one that will not be retried again, and one
// whose account was deleted underneath it. And a retry must never charge
// Storage for a second copy of an archive that already landed.

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"testing"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/dataexport"
)

type fakeExportBuilder struct {
	art   ExportArtifact
	err   error
	calls int
}

func (f *fakeExportBuilder) BuildExportArtifact(_ context.Context, _, _ string) (ExportArtifact, error) {
	f.calls++
	if f.err != nil {
		return ExportArtifact{}, f.err
	}
	return f.art, nil
}

func exportJob(exportID string, attempts int16) *Job {
	payload, _ := json.Marshal(DataExportPayload{ExportJobID: exportID, UserID: "user-A", Format: "backup"})
	return &Job{ID: 1, Kind: "data_export", Payload: payload, Attempts: attempts}
}

func exportWorker(be *fakeBackend, b DataExportBuilder) *Worker {
	return &Worker{Backend: be, DataExport: b, Log: slog.New(slog.DiscardHandler)}
}

func queuedExportBackend(exportID string) *fakeBackend {
	return &fakeBackend{exportJobs: map[string]*ExportJobRow{
		exportID: {ID: exportID, UserID: "user-A", Format: "backup", Status: "queued"},
	}}
}

func TestDataExport_SuccessRecordsThePathAndTheCompletenessVerdict(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{art: ExportArtifact{
		ObjectPath: "user-A/exports/2026-08-24T10-00-00.000Z.zip",
		Runs:       5000, TotalRuns: 7412, Complete: false,
	}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJob("exp-1", 1)); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if len(be.exportRunningMarks) != 1 {
		t.Fatalf("the row must be stamped running before the build so a status read can see it")
	}
	if len(be.exportFinishes) != 1 {
		t.Fatalf("finishes=%d, want 1", len(be.exportFinishes))
	}
	got := be.exportFinishes[0].res
	if got.Status != "ready" || got.ObjectPath == nil || *got.ObjectPath != b.art.ObjectPath {
		t.Fatalf("result=%+v, want a ready row carrying the object path", got)
	}
	if got.Complete == nil || *got.Complete {
		t.Fatal("a short archive must be recorded as short — the subject's client gates its notice on it")
	}
	if got.RunCount == nil || *got.RunCount != 5000 || got.TotalRuns == nil || *got.TotalRuns != 7412 {
		t.Fatalf("result=%+v, want both counts recorded", got)
	}
}

func TestDataExport_ARetryAfterTheArtifactLandedRebuildsNothing(t *testing.T) {
	// Storage charges per upload. A job re-delivered after its build
	// already succeeded must not push a second archive and orphan the
	// first, which is exactly what an at-least-once queue will do.
	be := &fakeBackend{exportJobs: map[string]*ExportJobRow{
		"exp-1": {ID: "exp-1", UserID: "user-A", Format: "backup", Status: "ready",
			ObjectPath: "user-A/exports/already-there.zip"},
	}}
	b := &fakeExportBuilder{}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJob("exp-1", 2)); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if b.calls != 0 {
		t.Fatalf("builds=%d, want 0 — the archive was already there", b.calls)
	}
	if len(be.exportFinishes) != 0 {
		t.Fatal("a no-op retry must not rewrite the row")
	}
}

func TestDataExport_ATransientFailureWithRetriesLeftLeavesTheRowRunning(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{err: &ExportBuildError{Code: "build_failed", Err: context.DeadlineExceeded}}
	w := exportWorker(be, b)

	err := w.handleDataExport(context.Background(), exportJob("exp-1", 1))
	if err == nil {
		t.Fatal("a failed build must report the failure so the queue can retry")
	}
	if !isTransient(err) {
		t.Fatal("a deadline must stay classifiable as transient through the wrapper, or the retry never happens")
	}
	if len(be.exportFinishes) != 0 {
		t.Fatal("the export has not failed yet — it is being tried again, and the row must say so")
	}
}

func TestDataExport_TheLastAttemptTellsTheSubjectItFailed(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{err: &ExportBuildError{Code: "upload_failed", Err: context.DeadlineExceeded}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJob("exp-1", ExportJobMaxAttempts)); err == nil {
		t.Fatal("want an error")
	}
	if len(be.exportFinishes) != 1 {
		t.Fatal("the final attempt must record the failure, or the row says `running` for ever")
	}
	got := be.exportFinishes[0].res
	if got.Status != "failed" || got.ErrorCode == nil || *got.ErrorCode != "upload_failed" {
		t.Fatalf("result=%+v, want the failure and its code", got)
	}
}

func TestDataExport_APermanentFailureIsRecordedWithoutSpendingTheRetry(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{err: &ExportBuildError{Code: "runs_fetch_failed", Err: errors.New("400 bad projection")}}
	w := exportWorker(be, b)

	err := w.handleDataExport(context.Background(), exportJob("exp-1", 1))
	if err == nil {
		t.Fatal("want an error")
	}
	if isTransient(err) {
		t.Fatal("a 400-class failure is permanent; retrying it burns the budget for nothing")
	}
	if len(be.exportFinishes) != 1 || be.exportFinishes[0].res.Status != "failed" {
		t.Fatal("a permanent failure must be recorded on the first attempt")
	}
}

func TestDataExport_ADeletedAccountDropsTheJobQuietly(t *testing.T) {
	// The row cascades away with the user. Failing the job would page an
	// operator about a correct Art 17 erasure.
	be := &fakeBackend{exportJobs: map[string]*ExportJobRow{}}
	b := &fakeExportBuilder{}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJob("exp-gone", 1)); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if b.calls != 0 {
		t.Fatal("nothing to build for a deleted subject")
	}
	if len(be.exportFinishes) != 0 {
		t.Fatal("nothing to record for a row that no longer exists")
	}
}

func TestDataExport_AnUnconfiguredBuilderFailsTheRowRatherThanHoldingTheSubject(t *testing.T) {
	// Every other optional transport finishes quietly and leaves its row
	// for a later deploy. An export cannot: a subject is watching a
	// status that would otherwise say `queued` for ever.
	be := queuedExportBackend("exp-1")
	w := exportWorker(be, nil)

	if err := w.handleDataExport(context.Background(), exportJob("exp-1", 1)); err == nil {
		t.Fatal("want an error")
	}
	if len(be.exportFinishes) != 1 || be.exportFinishes[0].res.Status != "failed" {
		t.Fatal("an unconfigured deploy must tell the subject, not hold them")
	}
	if code := be.exportFinishes[0].res.ErrorCode; code == nil || *code != "not_configured" {
		t.Fatalf("error code=%v, want not_configured", code)
	}
}

func TestDataExport_ABadPayloadIsRejectedBeforeAnyWrite(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{}
	w := exportWorker(be, b)

	job := &Job{ID: 1, Kind: "data_export", Payload: json.RawMessage(`{"user_id":"user-A"}`), Attempts: 1}
	if err := w.handleDataExport(context.Background(), job); err == nil {
		t.Fatal("a payload with no export_job_id names no row to report against")
	}
	if b.calls != 0 || len(be.exportFinishes) != 0 || len(be.exportRunningMarks) != 0 {
		t.Fatal("nothing may be written for a payload the handler cannot resolve")
	}
}

func TestDataExport_DispatchRoutesTheKind(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.dispatch(context.Background(), exportJob("exp-1", 1)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if b.calls != 1 {
		t.Fatal("the data_export kind must reach the export handler, not the unknown-kind branch")
	}
}

func TestDataExport_TheBuildClockIsWiderThanTheGenericOne(t *testing.T) {
	// A deep-history archive is dominated by per-object Storage fetches.
	// Capping it at the generic per-job timeout would make the queued
	// rail worse than the synchronous endpoint it replaces, which had no
	// clock at all.
	w := &Worker{Config: Config{HandleTimeout: 5 * time.Minute}}
	if got := w.handleTimeoutFor("map_match"); got != 5*time.Minute {
		t.Fatalf("map_match timeout=%v, want the generic one", got)
	}
	if got := w.handleTimeoutFor("data_export"); got != ExportJobTimeout {
		t.Fatalf("data_export timeout=%v, want %v", got, ExportJobTimeout)
	}
	if ExportJobTimeout <= 5*time.Minute {
		t.Fatal("an export clock no wider than the generic one buys nothing")
	}
}

func TestDataExport_TheStalenessWindowOutlastsTheWholeRetryBudget(t *testing.T) {
	// The status reader gives up on a row after dataexport.ExportJobStaleAfter.
	// That number is DERIVED from these two, and the derivation has to hold
	// or a live export gets reported dead while it is still being retried.
	budget := time.Duration(ExportJobMaxAttempts) * ExportJobTimeout
	if dataexport.ExportJobStaleAfter <= budget {
		t.Fatalf("ExportJobStaleAfter=%v must exceed the whole retry budget of %v (%d attempts x %v)",
			dataexport.ExportJobStaleAfter, budget, ExportJobMaxAttempts, ExportJobTimeout)
	}
}

// ─────────── the completion announcement (decisions.md § 729) ───────────

func TestDataExport_AFinishedBuildTellsTheSubject(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJob("exp-1", 1)); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if len(be.exportNotifies) != 1 || be.exportNotifies[0] != "exp-1" {
		t.Fatalf("notifies=%v, want one announcement for exp-1", be.exportNotifies)
	}
}

// The announcement claims the archive is collectable, so it may only follow
// the write that makes that claim true. Announcing off the build's return
// value would send a subject to a page whose status endpoint still says the
// export is running.
func TestDataExport_TheAnnouncementFollowsTheRowSayingReady(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJob("exp-1", 1)); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if len(be.exportFinishes) != 1 || be.exportFinishes[0].res.Status != "ready" {
		t.Fatal("precondition: the row was recorded ready")
	}
	if be.exportJobs["exp-1"].Status != "ready" {
		t.Fatal("precondition: the fake row followed the write")
	}
}

// An at-least-once queue re-delivers a job whose build already succeeded. The
// rebuild is already skipped; the announcement must be too, or the subject is
// told twice about one archive.
func TestDataExport_ARedeliveryAnnouncesNothingASecondTime(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	for i := 0; i < 3; i++ {
		if err := w.handleDataExport(context.Background(), exportJob("exp-1", 1)); err != nil {
			t.Fatalf("handle %d: %v", i, err)
		}
	}
	if b.calls != 1 {
		t.Fatalf("builds=%d, want 1 - the redeliveries must not rebuild", b.calls)
	}
	// Asking three times is deliberate: the already-built branch still asks,
	// which is what repairs a crash between the finish write and the
	// announcement. Announcing three times is not, and the stamp that stops
	// it lives in the RPC rather than in a flag this handler keeps.
	if len(be.exportNotifies) != 3 {
		t.Fatalf("notify calls=%d, want 3 - a retry must still ASK", len(be.exportNotifies))
	}
	if len(be.exportNotified) != 1 || !be.exportNotified["exp-1"] {
		t.Fatalf("notified=%v, want exactly one announcement recorded", be.exportNotified)
	}
}

// The archive is in Storage and the row says ready; the status endpoint the
// message merely points at is already reporting it. Failing here would spend
// the second attempt rebuilding a whole archive to fix a missing email - and
// that attempt would find the row ready and skip, so it could not even repair
// what it cost.
func TestDataExport_AFailedAnnouncementDoesNotFailTheExport(t *testing.T) {
	be := queuedExportBackend("exp-1")
	be.notifyExportErr = errors.New("500 from postgrest")
	b := &fakeExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJob("exp-1", 1)); err != nil {
		t.Fatalf("a failed announcement must not fail the job: %v", err)
	}
	if len(be.exportFinishes) != 1 || be.exportFinishes[0].res.Status != "ready" {
		t.Fatal("the export still succeeded and the row must still say so")
	}
}

func TestDataExport_AFailedExportAnnouncesNothing(t *testing.T) {
	be := queuedExportBackend("exp-1")
	b := &fakeExportBuilder{err: &ExportBuildError{Code: "upload_failed", Err: errors.New("boom")}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJob("exp-1", ExportJobMaxAttempts)); err == nil {
		t.Fatal("want an error")
	}
	if len(be.exportNotifies) != 0 {
		t.Fatal("there is no archive to collect; announcing one would send the subject to an empty page")
	}
}

func TestDataExport_ADeletedAccountIsAnnouncedNothing(t *testing.T) {
	be := &fakeBackend{exportJobs: map[string]*ExportJobRow{}}
	w := exportWorker(be, &fakeExportBuilder{})

	if err := w.handleDataExport(context.Background(), exportJob("exp-gone", 1)); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if len(be.exportNotifies) != 0 {
		t.Fatal("there is nobody left to tell")
	}
}
