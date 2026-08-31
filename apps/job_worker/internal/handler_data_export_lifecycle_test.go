package internal

// The queued Art 20 handler's lifecycle: whose archive it builds, what
// it does when a delivery arrives on top of another, and what it leaves
// behind when it dies half-way (decisions.md § 717 / § 724 / § 729).
//
// The queue is at-least-once and the machine can be killed at any
// instant, so every one of these paths runs in production. Two outcomes
// are unacceptable and everything here is about avoiding them: an
// archive recorded against a subject who did not ask for it, and a
// subject left watching a row nothing will ever finish.

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"sync"
	"testing"
)

// recordingExportBuilder notes whose archive it was asked to build.
type recordingExportBuilder struct {
	mu       sync.Mutex
	art      ExportArtifact
	err      error
	subjects []string
	formats  []string
}

func (r *recordingExportBuilder) BuildExportArtifact(_ context.Context, userID, format string) (ExportArtifact, error) {
	r.mu.Lock()
	r.subjects = append(r.subjects, userID)
	r.formats = append(r.formats, format)
	r.mu.Unlock()
	if r.err != nil {
		return ExportArtifact{}, r.err
	}
	return r.art, nil
}

func (r *recordingExportBuilder) calls() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.subjects)
}

func exportJobFor(exportID, subject, format string, attempts int16) *Job {
	payload, _ := json.Marshal(DataExportPayload{ExportJobID: exportID, UserID: subject, Format: format})
	return &Job{ID: 1, Kind: "data_export", Payload: payload, Attempts: attempts}
}

func exportRowBackend(row *ExportJobRow) *fakeBackend {
	return &fakeBackend{exportJobs: map[string]*ExportJobRow{row.ID: row}}
}

func lastFinish(t *testing.T, be *fakeBackend) exportFinishCall {
	t.Helper()
	if len(be.exportFinishes) == 0 {
		t.Fatal("nothing was recorded against the export row")
	}
	return be.exportFinishes[len(be.exportFinishes)-1]
}

// ─────────────────── whose archive ───────────────────

func TestDataExport_BuildsForThePayloadsSubjectAndFormat(t *testing.T) {
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "gpx", Status: "queued"})
	b := &recordingExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "gpx", 1)); err != nil {
		t.Fatal(err)
	}
	if len(b.subjects) != 1 || b.subjects[0] != "user-A" {
		t.Fatalf("built for %v", b.subjects)
	}
	if b.formats[0] != "gpx" {
		t.Fatalf("format=%q", b.formats[0])
	}
}

func TestDataExport_APayloadNamingADifferentSubjectBuildsNothing(t *testing.T) {
	// The payload says whose archive to build; the row says who will be
	// handed the signed URL for it. A queue entry where the two disagree
	// would put one subject's entire personal-data archive behind
	// another subject's download link — the worst outcome available on
	// this rail, and worse than no export at all.
	//
	// `enqueue_data_export` derives both from one argument so it cannot
	// produce such a row, and `jobs` is RLS-on-with-no-policies so no
	// client can write one. This is the assertion behind those two
	// facts, not a substitute for them.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "victim", Format: "backup", Status: "queued"})
	b := &recordingExportBuilder{art: ExportArtifact{ObjectPath: "attacker/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "attacker", "backup", 1))
	if err == nil {
		t.Fatal("a payload whose subject does not own the row must be refused")
	}
	if b.calls() != 0 {
		t.Fatalf("built %d archives for %v", b.calls(), b.subjects)
	}
	fin := lastFinish(t, be)
	if fin.res.Status != "failed" {
		t.Fatalf("row recorded as %q, want failed — a subject must not poll a "+
			"refused export for ever", fin.res.Status)
	}
	if fin.res.ObjectPath != nil {
		t.Fatalf("a refused export recorded an artifact path %q", *fin.res.ObjectPath)
	}
	if len(be.exportNotifies) != 0 {
		t.Fatal("a refused export announced itself")
	}
}

// ─────────────────── redelivery ───────────────────

func TestDataExport_ARedeliveryOfAReadyRowWithNoArtifactRebuilds(t *testing.T) {
	// The skip is gated on the PATH, not on the status, and this is why:
	// a row saying `ready` with nothing behind it is a claim the archive
	// cannot honour, so the right response to seeing it again is to
	// build the archive, not to congratulate the subject.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup",
		Status: "ready", ObjectPath: ""})
	b := &recordingExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1)); err != nil {
		t.Fatal(err)
	}
	if b.calls() != 1 {
		t.Fatalf("builds=%d, want 1", b.calls())
	}
	fin := lastFinish(t, be)
	if fin.res.ObjectPath == nil || *fin.res.ObjectPath != "user-A/exports/x.zip" {
		t.Fatalf("the rebuild did not record its artifact: %+v", fin.res)
	}
}

func TestDataExport_ARedeliveryMidBuildRebuildsRatherThanStalling(t *testing.T) {
	// The machine died while the row said `running`. Nothing else will
	// ever write to that row, so the redelivery has to treat it as work
	// still to do.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "running"})
	b := &recordingExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 2)); err != nil {
		t.Fatal(err)
	}
	if b.calls() != 1 {
		t.Fatalf("builds=%d, want 1", b.calls())
	}
}

func TestDataExport_ARetryOfAFailedRowTriesAgain(t *testing.T) {
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup",
		Status: "failed", ErrorCode: "upload_failed"})
	b := &recordingExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 2)); err != nil {
		t.Fatal(err)
	}
	if b.calls() != 1 {
		t.Fatalf("builds=%d, want 1 — a failed attempt is exactly what a retry is for", b.calls())
	}
	if lastFinish(t, be).res.Status != "ready" {
		t.Fatalf("the successful retry did not clear the failure: %+v", lastFinish(t, be).res)
	}
}

func TestDataExport_AnExpiredRowIsDroppedWithoutBuilding(t *testing.T) {
	// The retention sweep already collected the artifact's window. There
	// is nothing to deliver and nobody waiting.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "expired"})
	b := &recordingExportBuilder{}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1)); err != nil {
		t.Fatalf("an expired row is not a failure: %v", err)
	}
	if b.calls() != 0 || len(be.exportFinishes) != 0 || len(be.exportNotifies) != 0 {
		t.Fatalf("an expired row must be left alone: builds=%d finishes=%d notifies=%d",
			b.calls(), len(be.exportFinishes), len(be.exportNotifies))
	}
}

func TestDataExport_TwoConcurrentDeliveriesUploadOneArchive(t *testing.T) {
	// The queue is at-least-once and two workers can claim before either
	// finishes. Storage is charged per upload and the loser's archive
	// would be orphaned, so the second delivery to see a completed row
	// must stop.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
	b := &recordingExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1)); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_ = w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 2))
		}()
	}
	wg.Wait()
	if b.calls() != 1 {
		t.Fatalf("builds=%d, want 1 — every redelivery after the artifact landed "+
			"must skip the rebuild", b.calls())
	}
	// And the announcement is stamped once, by the RPC, however many
	// deliveries asked.
	announced := 0
	for range be.exportNotifies {
		announced++
	}
	if announced < 2 {
		t.Fatalf("the redeliveries did not reach the announcement (%d) — the "+
			"crash-between-Finish-and-announce window is what that call repairs", announced)
	}
}

// ─────────────────── failures on the way ───────────────────

func TestDataExport_AFailedRunningStampBuildsNothing(t *testing.T) {
	// The stamp is also what keeps the row warm against the status
	// reader's staleness derivation. Building against a row that still
	// says `queued` would make a live export read as stalled.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
	be.markExportRunningErr = errors.New("postgrest 503")
	b := &recordingExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip"}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1)); err == nil {
		t.Fatal("a failed running-stamp must fail the job so it retries")
	}
	if b.calls() != 0 {
		t.Fatalf("builds=%d, want 0", b.calls())
	}
	if len(be.exportFinishes) != 0 {
		t.Fatal("nothing may be recorded when the attempt never started")
	}
}

func TestDataExport_AFailedResultWriteAnnouncesNothing(t *testing.T) {
	// The archive is in Storage but the row does not say so, so the
	// status endpoint cannot serve it. Announcing here would send the
	// subject to a page that reports their export as still building.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
	be.finishExportJobErr = errors.New("postgrest 503")
	b := &recordingExportBuilder{art: ExportArtifact{ObjectPath: "user-A/exports/x.zip", Complete: true}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1)); err == nil {
		t.Fatal("a failed result write must fail the job so it retries")
	}
	if len(be.exportNotifies) != 0 {
		t.Fatalf("announced %v against a row that does not say ready", be.exportNotifies)
	}
}

func TestDataExport_AReadFailureRetriesRatherThanDroppingTheExport(t *testing.T) {
	// Only ErrExportJobGone means the account went away. Anything else
	// dropped here is a subject whose Art 20 request silently ends.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
	be.getExportJobErr = errors.New("postgrest 503")
	b := &recordingExportBuilder{}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1)); err == nil {
		t.Fatal("a read outage must fail the job so the queue retries it")
	}
	if b.calls() != 0 {
		t.Fatal("nothing may be built off a row that could not be read")
	}
	if len(be.exportFinishes) != 0 {
		t.Fatal("a transient read failure must not be recorded as the export failing")
	}
}

func TestDataExport_TheAttemptBoundaryDecidesWhatTheSubjectIsTold(t *testing.T) {
	// While an attempt is still budgeted, `running` is the true thing to
	// show: the export has not failed, it is being tried again.
	for _, tc := range []struct {
		name       string
		attempts   int16
		wantFailed bool
	}{
		{"first attempt of two", 1, false},
		{"last attempt", ExportJobMaxAttempts, true},
		{"past the budget", ExportJobMaxAttempts + 1, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
			b := &recordingExportBuilder{err: &ExportBuildError{Code: "upload_failed", Err: errors.New("i/o timeout")}}
			w := exportWorker(be, b)

			if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", tc.attempts)); err == nil {
				t.Fatal("a failed build must fail the job")
			}
			recorded := len(be.exportFinishes) > 0
			if recorded != tc.wantFailed {
				t.Fatalf("recorded a failure=%v, want %v", recorded, tc.wantFailed)
			}
			if tc.wantFailed {
				fin := lastFinish(t, be)
				if fin.res.Status != "failed" || fin.res.ErrorCode == nil || *fin.res.ErrorCode != "upload_failed" {
					t.Fatalf("recorded %+v, want the builder's own token", fin.res)
				}
			}
		})
	}
}

func TestDataExport_APermanentFailureIsRecordedOnTheFirstAttempt(t *testing.T) {
	// Nothing is gained by rebuilding a whole archive against an error
	// that will recur, and an export retry costs an upload.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
	b := &recordingExportBuilder{err: &ExportBuildError{Code: "runs_fetch_failed", Err: errors.New("column does not exist")}}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1)); err == nil {
		t.Fatal("a failed build must fail the job")
	}
	fin := lastFinish(t, be)
	if fin.res.Status != "failed" || *fin.res.ErrorCode != "runs_fetch_failed" {
		t.Fatalf("recorded %+v", fin.res)
	}
}

func TestDataExport_AnUnclassifiedFailureStillCarriesAToken(t *testing.T) {
	// The client renders the code through its own copy; an empty one
	// leaves the subject with a failure and no explanation at all.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
	b := &recordingExportBuilder{err: errors.New("something nobody classified")}
	w := exportWorker(be, b)

	_ = w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", ExportJobMaxAttempts))
	fin := lastFinish(t, be)
	if fin.res.ErrorCode == nil || *fin.res.ErrorCode != "build_failed" {
		t.Fatalf("recorded %+v, want the build_failed fallback", fin.res)
	}
	if fin.res.FinishedAt == "" {
		t.Error("a terminal row must carry a finished_at or nothing dates it")
	}
}

func TestDataExport_EveryRecordedFailureCodeFitsTheColumn(t *testing.T) {
	// data_export_jobs_error_code_len_chk caps this at 64 characters. A
	// longer token makes the failure PATCH 400 and leaves the row saying
	// `running` until the staleness window expires.
	for _, code := range []string{"not_configured", "build_failed", "upload_failed", "subject_mismatch"} {
		be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
		w := exportWorker(be, &recordingExportBuilder{})
		w.recordExportFailure(context.Background(), "exp-1", code, w.Log)
		fin := lastFinish(t, be)
		if fin.res.ErrorCode == nil || len(*fin.res.ErrorCode) > 64 {
			t.Errorf("code %q does not fit the column", code)
		}
		if fin.res.Status != "failed" || fin.res.ObjectPath != nil || fin.res.Complete != nil {
			t.Errorf("a failure row must claim nothing else: %+v", fin.res)
		}
	}
}

// ─────────────────── payload validation ───────────────────

func TestDataExport_AnIncompletePayloadIsRefusedBeforeAnyRead(t *testing.T) {
	for _, tc := range []struct {
		name    string
		payload string
	}{
		{"no export job id", `{"user_id":"user-A","format":"backup"}`},
		{"no user id", `{"export_job_id":"exp-1","format":"backup"}`},
		{"no format", `{"export_job_id":"exp-1","user_id":"user-A"}`},
		{"not json", `nonsense`},
		{"empty object", `{}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
			b := &recordingExportBuilder{}
			w := exportWorker(be, b)

			job := &Job{ID: 1, Kind: "data_export", Payload: json.RawMessage(tc.payload), Attempts: 1}
			if err := w.handleDataExport(context.Background(), job); err == nil {
				t.Fatal("an unusable payload must fail the job")
			}
			if b.calls() != 0 || len(be.exportFinishes) != 0 || len(be.exportRunningMarks) != 0 {
				t.Fatal("an unusable payload must touch no row")
			}
		})
	}
}

func TestDataExport_AFormatTheBuilderRefusesFailsTheRowRatherThanLooping(t *testing.T) {
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "tar", Status: "queued"})
	b := &recordingExportBuilder{err: errors.New(`unknown export format "tar"`)}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "tar", ExportJobMaxAttempts)); err == nil {
		t.Fatal("an unbuildable format must fail the job")
	}
	if lastFinish(t, be).res.Status != "failed" {
		t.Fatal("the subject must be told rather than left polling")
	}
}

func TestDataExport_AnUnconfiguredBuilderTellsTheSubjectAndTouchesNoQueueRow(t *testing.T) {
	// Every other optional transport finishes its job `done` and leaves
	// the underlying row for a later configured deploy. An export cannot:
	// the subject is watching a status that would then say `queued` for
	// ever.
	be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
	w := exportWorker(be, nil)

	err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1))
	if err == nil {
		t.Fatal("an unconfigured builder must fail the job")
	}
	fin := lastFinish(t, be)
	if fin.res.Status != "failed" || fin.res.ErrorCode == nil || *fin.res.ErrorCode != "not_configured" {
		t.Fatalf("recorded %+v", fin.res)
	}
	if len(be.exportRunningMarks) != 0 {
		t.Fatal("an unconfigured deploy must not stamp the row as running")
	}
}

func TestDataExport_ADeletedAccountIsDroppedWithoutMarkingAnythingFailed(t *testing.T) {
	// The FK cascade took the row with the account. There is nothing to
	// build and nobody to tell; failing the job would page an operator
	// about a correct erasure.
	be := &fakeBackend{exportJobs: map[string]*ExportJobRow{}}
	b := &recordingExportBuilder{}
	w := exportWorker(be, b)

	if err := w.handleDataExport(context.Background(), exportJobFor("exp-gone", "user-A", "backup", 1)); err != nil {
		t.Fatalf("a correct erasure is not a job failure: %v", err)
	}
	if b.calls() != 0 {
		t.Fatal("nothing may be built for a deleted account")
	}
	if len(be.exportFinishes) != 0 {
		t.Fatalf("wrote %v against a row that no longer exists", be.exportFinishes)
	}
	if len(be.exportNotifies) != 0 {
		t.Fatal("a deleted account must not be mailed about an export")
	}
}

func TestDataExport_TheCompletenessVerdictReachesTheRowVerbatim(t *testing.T) {
	// The subject's truncation notice is gated on an explicit
	// `complete: false`, so a short archive that records `true` — or
	// records nothing — is a data-rights disclosure that never happens.
	for _, complete := range []bool{true, false} {
		be := exportRowBackend(&ExportJobRow{ID: "exp-1", UserID: "user-A", Format: "backup", Status: "queued"})
		b := &recordingExportBuilder{art: ExportArtifact{
			ObjectPath: "user-A/exports/x.zip", Runs: 41, TotalRuns: 42, Complete: complete,
		}}
		w := exportWorker(be, b)
		if err := w.handleDataExport(context.Background(), exportJobFor("exp-1", "user-A", "backup", 1)); err != nil {
			t.Fatal(err)
		}
		fin := lastFinish(t, be)
		if fin.res.Complete == nil || *fin.res.Complete != complete {
			t.Fatalf("complete=%v, want %v", fin.res.Complete, complete)
		}
		if fin.res.RunCount == nil || *fin.res.RunCount != 41 || fin.res.TotalRuns == nil || *fin.res.TotalRuns != 42 {
			t.Fatalf("counts=%+v", fin.res)
		}
		if fin.res.Status != "ready" {
			t.Fatalf("status=%q", fin.res.Status)
		}
	}
}

func TestDataExport_TheHandlerNeverMintsASignedUrl(t *testing.T) {
	// § 717's whole answer to a queue meeting a 10-minute TTL. The
	// handler records a path; the reader signs. A URL minted here would
	// start its clock at a moment the subject had no part in choosing.
	src := readWorkerSource(t, "handler_data_export.go")
	for _, banned := range []string{"CreateSignedURL", "SignedURL", "signed_url"} {
		if strings.Contains(src, banned) {
			t.Errorf("handler_data_export.go mentions %q — the URL is minted at read time", banned)
		}
	}
}

// readWorkerSource reads a source file in this package so a guard can
// assert what the handler does NOT do.
func readWorkerSource(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(name)
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return string(b)
}
