package dataexport

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"
)

// ArtifactBuild is one finished archive: where it landed and what it
// claims about itself. Deliberately carries the Storage KEY and not a
// signed URL — a URL minted here would start its 10-minute clock at the
// moment the build happened to finish, which on the queued rail can be
// long before the subject next looks. The signing is the reader's job
// (decisions.md § 717).
type ArtifactBuild struct {
	ObjectPath string
	Runs       int
	TotalRuns  int
	Complete   bool
}

// ErrUpload marks a failure of the Storage upload itself rather than of
// the archive build. Both answer the subject with nothing, but they are
// different operational facts and the endpoint already distinguished
// them before the queued rail existed.
var ErrUpload = errors.New("storage upload failed")

// ErrArtifactGone marks a signed-URL request for an object that is no
// longer there — the 7-day retention sweep collected it, or an operator
// removed it. Distinct from a Storage outage on purpose: an export that
// expired is a fact to tell the subject, an outage is not something to
// dress up as one. The production adapter maps a Storage 404 onto it.
var ErrArtifactGone = errors.New("export artifact no longer exists")

// ValidFormat reports whether `format` is one the builders know.
func ValidFormat(format string) bool {
	return format == "csv" || format == "gpx" || format == "backup"
}

// BuildArtifact streams one Art 20 archive into the `exports` bucket and
// returns where it landed. Called only from the queued `data_export` job
// handler now — the synchronous endpoint that shared it was deleted with
// decisions.md § 724 — and deliberately still a package-level function
// rather than a method on the handler, because the archive's contents
// are a data-rights contract and belong somewhere a guard can read them
// without booting a worker.
//
// Fail-closed, unchanged from § 708: the tus session opens before the
// first row is read, and every failure below aborts it. tus materialises
// the object only once the declared length arrives, so a build that dies
// half-way leaves no object at all rather than a short one that a caller
// could sign and hand over as complete.
func BuildArtifact(ctx context.Context, b Backend, log *slog.Logger, userID, format string) (ArtifactBuild, error) {
	if !ValidFormat(format) {
		return ArtifactBuild{}, fmt.Errorf("unknown export format %q", format)
	}

	ts := time.Now().UTC().Format("2006-01-02T15-04-05.000Z")
	contentType, ext := "application/zip", "zip"
	if format == "csv" {
		contentType, ext = "text/csv", "csv"
	}
	objectPath := fmt.Sprintf("%s/exports/%s.%s", userID, ts, ext)

	sink := b.OpenExportArtifact(ctx, objectPath, contentType)
	runs := RunSource(func(ctx context.Context, emit func([]ExportRun) error) (ExportCompleteness, error) {
		return b.StreamExportRuns(ctx, userID, emit)
	})

	var (
		built    BuildResult
		buildErr error
	)
	switch format {
	case "csv":
		built, buildErr = WriteCSV(ctx, sink, runs)
	case "gpx":
		built, buildErr = WriteGpxZip(ctx, sink, runs, b.DownloadTrackBytes)
	case "backup":
		// Two small single-row reads the backup format needs beside the
		// paged sections. Neither is worth failing the export over: a
		// missing profile ships as null, missing prefs as an empty bag.
		profile, perr := b.FetchExportProfile(ctx, userID)
		if perr != nil {
			log.Warn("dataexport: profile fetch failed; including null", "err", perr, "user_id", userID)
			profile = nil
		}
		prefs, prefErr := b.FetchUserSettingsPrefs(ctx, userID)
		if prefErr != nil {
			log.Warn("dataexport: prefs fetch failed; including empty", "err", prefErr, "user_id", userID)
			prefs = map[string]interface{}{}
		}
		built, buildErr = WriteBackupZip(ctx, sink, BuildBackupZipInput{
			Runs: runs,
			Routes: func(ctx context.Context, emit func([]ExportRoute) error) (ExportCompleteness, error) {
				return b.StreamExportRoutes(ctx, userID, emit)
			},
			Profile:       profile,
			SettingsPrefs: prefs,
			UserID:        userID,
			ExportedFrom:  "go-service",
			ExtraTables: func(ctx context.Context, emit func(string, []map[string]interface{}) error) (ExportCompleteness, error) {
				return b.StreamExportPersonalDataTables(ctx, userID, emit)
			},
		}, BackupFetchers{
			RawTrack:    b.DownloadRawTrackBytes,
			Photo:       b.DownloadPhoto,
			Avatar:      b.DownloadAvatar,
			ListObjects: b.ListStorageObjects,
		})
	}

	if buildErr != nil {
		sink.Abort()
		return ArtifactBuild{}, buildErr
	}
	// Until this returns, tus has not been told the archive's length and
	// no object exists. A failure here is the upload's, not the build's.
	if err := sink.Finish(); err != nil {
		sink.Abort()
		return ArtifactBuild{}, fmt.Errorf("%w: %v", ErrUpload, err)
	}

	if !built.Completeness.IsComplete() {
		log.Warn("dataexport: export is short of the database; manifest says so",
			"user_id", userID, "incomplete", built.Completeness.Incomplete)
	}

	return ArtifactBuild{
		ObjectPath: objectPath,
		Runs:       built.Runs,
		TotalRuns:  built.Completeness.Totals["runs"],
		Complete:   built.Completeness.IsComplete(),
	}, nil
}

// SectionOf names the section whose READ failed, when that is what the
// error is. Lets a caller outside this package keep the per-section
// error codes without exporting the error type itself.
func SectionOf(err error) string {
	var se *sectionError
	if errors.As(err, &se) {
		return se.section
	}
	return ""
}
