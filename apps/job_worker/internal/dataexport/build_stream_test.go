package dataexport

// The streaming archive's two remaining bounds and its ownership seam
// (decisions.md § 703 / § 708).
//
// Both row caps are gone, so nothing in this package limits how much of
// a subject's history reaches them. What DOES bound the build is the
// Storage object ceiling and the sink underneath it, and what bounds
// what may go IN is that every byte must be the calling subject's own.
// A build that quietly archives another subject's object is the Art 20
// failure that matters most, and a build that quietly finalises a short
// archive is the second.

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"regexp"
	"strings"
	"testing"
)

func discardLog() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

// incompressible builds a deterministic, high-entropy string. The zip
// builders write through a deflate stream that buffers, so a compressible
// fixture can sit entirely inside that buffer and make a genuinely
// streaming builder look like a buffering one.
func incompressible(seed uint64, n int) string {
	b := make([]byte, n)
	x := seed | 1
	for i := range b {
		x ^= x << 13
		x ^= x >> 7
		x ^= x << 17
		b[i] = byte('!' + x%90)
	}
	return string(b)
}

func runFor(subject, id string) ExportRun {
	track := subject + "/" + id + ".json.gz"
	return ExportRun{
		ID: id, UserID: subject, StartedAt: "2026-05-11T10:00:00Z",
		ActivityType: "run", Source: "manual", TrackURL: &track,
	}
}

func zipEntries(t *testing.T, body []byte) map[string][]byte {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("archive is not a readable zip: %v", err)
	}
	out := map[string][]byte{}
	for _, f := range zr.File {
		rc, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		b, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			t.Fatal(err)
		}
		out[f.Name] = b
	}
	return out
}

// ─────────────────── the artifact's own identity ───────────────────

func TestBuildArtifact_LandsUnderTheSubjectsOwnPrefixInEveryFormat(t *testing.T) {
	for _, tc := range []struct {
		format      string
		ext         string
		contentType string
	}{
		{"csv", ".csv", "text/csv"},
		{"gpx", ".zip", "application/zip"},
		{"backup", ".zip", "application/zip"},
	} {
		be := &fakeBackend{runs: []ExportRun{runFor("user-A", "run-1")}}
		art, err := BuildArtifact(context.Background(), be, discardLog(), "user-A", tc.format)
		if err != nil {
			t.Fatalf("%s: %v", tc.format, err)
		}
		if !strings.HasPrefix(art.ObjectPath, "user-A/exports/") {
			t.Errorf("%s: object path %q is not under the subject's own prefix",
				tc.format, art.ObjectPath)
		}
		if !strings.HasSuffix(art.ObjectPath, tc.ext) {
			t.Errorf("%s: object path %q, want a %s artifact", tc.format, art.ObjectPath, tc.ext)
		}
		if len(be.uploads) != 1 {
			t.Fatalf("%s: uploads=%v", tc.format, be.uploads)
		}
		if be.uploads[0].Path != art.ObjectPath {
			t.Errorf("%s: uploaded to %q, reported %q", tc.format, be.uploads[0].Path, art.ObjectPath)
		}
		if be.uploads[0].ContentType != tc.contentType {
			t.Errorf("%s: content type %q, want %q", tc.format, be.uploads[0].ContentType, tc.contentType)
		}
	}
}

func TestBuildArtifact_ThePathIsDerivedFromTheSubjectAndNothingElse(t *testing.T) {
	// The only caller-influenced component is the subject id, which
	// arrives as a JWT `sub`. The rest is a millisecond timestamp and a
	// format-determined extension, so no request field can steer the
	// artifact out of the subject's own folder or into another object's
	// key.
	be := &fakeBackend{runs: []ExportRun{runFor("user-A", "run-1")}}
	art, err := BuildArtifact(context.Background(), be, discardLog(), "user-A", "backup")
	if err != nil {
		t.Fatal(err)
	}
	shape := regexp.MustCompile(`^user-A/exports/\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.\d{3}Z\.zip$`)
	if !shape.MatchString(art.ObjectPath) {
		t.Fatalf("object path %q does not match {uid}/exports/{ms timestamp}.{ext}", art.ObjectPath)
	}
	if strings.Contains(art.ObjectPath, "..") || strings.HasPrefix(art.ObjectPath, "/") {
		t.Fatalf("object path %q is not a canonical Storage key", art.ObjectPath)
	}
}

func TestBuildArtifact_UnknownFormatUploadsNothingAtAll(t *testing.T) {
	be := &fakeBackend{runs: []ExportRun{runFor("user-A", "run-1")}}
	if _, err := BuildArtifact(context.Background(), be, discardLog(), "user-A", "tar"); err == nil {
		t.Fatal("an unknown format must be refused")
	}
	if len(be.uploads) != 0 || be.sink != nil {
		t.Fatalf("a refused format must not even open a session: uploads=%v", be.uploads)
	}
}

// ─────────────────── whose bytes go in ───────────────────

func TestBuildBackupZip_ATrackNamingAnotherSubjectsObjectIsNeverFetched(t *testing.T) {
	// `runs.track_url` is a stored string. The canonical shape is
	// `{owner}/{run_id}.json.gz`, and the derivation is what stops a
	// legacy or tampered row pointing the service-role downloader at
	// somebody else's object.
	alien := "user-B/run-1.json.gz"
	run := runFor("user-A", "run-1")
	run.TrackURL = &alien

	fetched := map[string]bool{}
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource([]ExportRun{run}), UserID: "user-A",
	}, BackupFetchers{
		RawTrack: func(_ context.Context, key string) ([]byte, error) {
			fetched[key] = true
			return []byte("someone else's track"), nil
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if fetched[alien] {
		t.Fatalf("the builder fetched %q — another subject's object reached this archive", alien)
	}
	for name := range zipEntries(t, body) {
		if strings.HasPrefix(name, "tracks/") {
			t.Fatalf("archive carries %q for a run whose track key was not its own", name)
		}
	}
}

func TestBuildBackupZip_AnHrSidecarNamingAnotherSubjectIsNeverFetched(t *testing.T) {
	alien := "user-B/run-1.hr.json.gz"
	run := runFor("user-A", "run-1")
	run.TrackURL = nil
	run.HrSeriesURL = &alien

	fetched := map[string]bool{}
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource([]ExportRun{run}), UserID: "user-A",
	}, BackupFetchers{
		RawTrack: func(_ context.Context, key string) ([]byte, error) {
			fetched[key] = true
			return []byte("hr"), nil
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if fetched[alien] {
		t.Fatalf("the builder fetched %q", alien)
	}
	for name := range zipEntries(t, body) {
		if strings.HasPrefix(name, "hr/") {
			t.Fatalf("archive carries %q", name)
		}
	}
}

func TestBuildBackupZip_APhotoRowNamingAnotherSubjectsObjectIsNeverFetched(t *testing.T) {
	// `run_photos.storage_path` is CHECK-constrained to the row owner's
	// own prefix (20260622_001) and the section is read with
	// `owner_id=eq.<subject>`, so a legitimate row cannot name anybody
	// else. The builder asserts it anyway, for the same reason the track
	// keys are derived rather than trusted: the value it hands the
	// service-role downloader is a stored string.
	alien := "user-B/photo-1.jpg"
	fetched := map[string]bool{}
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs:   runSource(nil),
		UserID: "user-A",
		ExtraTables: tableSource(map[string][]map[string]interface{}{
			"run_photos.json": {
				{"id": "photo-1", "storage_path": alien},
				{"id": "photo-2", "storage_path": "user-A/photo-2.jpg"},
			},
		}),
	}, BackupFetchers{
		Photo: func(_ context.Context, key string) ([]byte, string, error) {
			fetched[key] = true
			return []byte("jpegbytes"), "image/jpeg", nil
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if fetched[alien] {
		t.Fatalf("the builder downloaded %q into user-A's Art 20 archive", alien)
	}
	entries := zipEntries(t, body)
	if _, present := entries["photos/photo-1.jpg"]; present {
		t.Fatal("another subject's photo landed in the archive")
	}
	if _, present := entries["photos/photo-2.jpg"]; !present {
		t.Fatal("the subject's own photo must still be archived")
	}
	// The metadata row still ships either way — the export does not
	// silently drop a row it declined to fetch bytes for.
	if !bytes.Contains(entries["run_photos.json"], []byte("photo-1")) {
		t.Error("the run_photos row itself must still be exported")
	}
}

func TestBuildBackupZip_TheOrphanSweepIgnoresKeysOutsideTheSubjectsPrefix(t *testing.T) {
	fetched := map[string]bool{}
	body, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(nil), UserID: "user-A",
	}, BackupFetchers{
		RawTrack: func(_ context.Context, key string) ([]byte, error) {
			fetched[key] = true
			return []byte("bytes"), nil
		},
		ListObjects: func(_ context.Context, bucket, _ string) ([]string, error) {
			return []string{
				"user-A/orphan.json.gz",
				"user-B/secret.json.gz",
				"user-AB/lookalike.json.gz",
				"../escape.json.gz",
			}, nil
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, alien := range []string{"user-B/secret.json.gz", "user-AB/lookalike.json.gz", "../escape.json.gz"} {
		if fetched[alien] {
			t.Errorf("the orphan sweep fetched %q", alien)
		}
	}
	if !fetched["user-A/orphan.json.gz"] {
		t.Error("the subject's own orphaned object must still be swept in")
	}
	for name := range zipEntries(t, body) {
		if strings.Contains(name, "user-B") || strings.Contains(name, "..") {
			t.Errorf("archive carries %q", name)
		}
	}
}

func TestBuildBackupZip_AnEmptySubjectIdSweepsNothing(t *testing.T) {
	// With no subject, the prefix would be "/" and the avatar probe
	// would ask for "/avatar.jpg". Neither may run.
	listed := false
	avatarProbes := 0
	if _, err := buildBackupZip(context.Background(), BuildBackupZipInput{
		Runs: runSource(nil), UserID: "",
	}, BackupFetchers{
		RawTrack: func(_ context.Context, _ string) ([]byte, error) { return []byte("x"), nil },
		Avatar: func(_ context.Context, _ string) ([]byte, string, error) {
			avatarProbes++
			return []byte("png"), "image/png", nil
		},
		ListObjects: func(_ context.Context, _, _ string) ([]string, error) {
			listed = true
			return []string{"user-B/secret.json.gz"}, nil
		},
	}); err != nil {
		t.Fatal(err)
	}
	if listed {
		t.Error("an anonymous build must not walk a bucket prefix")
	}
	if avatarProbes != 0 {
		t.Error("an anonymous build must not probe avatar paths")
	}
}

// ─────────────────── the sink is the bound ───────────────────

func TestBuildArtifact_ATruncatedWriteLeavesNoArtifactInAnyFormat(t *testing.T) {
	// tus materialises nothing until the declared length arrives, so a
	// chunk that dies mid-archive must abort rather than let the walk
	// carry on writing into a session that is gone.
	runs := make([]ExportRun, 300)
	for i := range runs {
		runs[i] = runFor("user-A", fmt.Sprintf("run-%03d", i))
	}
	for _, format := range []string{"csv", "gpx", "backup"} {
		be := &fakeBackend{
			runs:            runs,
			pageSize:        25,
			uploadErr:       errors.New("resumable: patch at offset 6291456 returned 500"),
			uploadFailAfter: 256,
			trackByPath:     map[string][]TrackPoint{},
		}
		_, err := BuildArtifact(context.Background(), be, discardLog(), "user-A", format)
		if err == nil {
			t.Errorf("%s: a dead upload reported a finished archive", format)
			continue
		}
		if len(be.uploads) != 0 {
			t.Errorf("%s: uploads=%v, want nothing recorded", format, be.uploads)
		}
		if be.sink == nil || !be.sink.aborted {
			t.Errorf("%s: the session must be aborted", format)
		}
		if be.sink != nil && be.sink.finished {
			t.Errorf("%s: a failed build must never finalise the object", format)
		}
		// A write that died is NOT a short section. Recording it as one
		// would blame the database in manifest.json for a write that
		// never happened, and main.go would render `runs_fetch_failed`
		// to a subject whose runs read perfectly.
		if s := SectionOf(err); s != "" {
			t.Errorf("%s: a dead upload was blamed on section %q", format, s)
		}
	}
}

func TestBuildArtifact_ACancelledBuildLeavesNoArtifact(t *testing.T) {
	// The queued rail's per-attempt clock cancels the context. Whatever
	// the walk was doing, the outcome must be the same as any other
	// mid-build failure: nothing in Storage.
	runs := make([]ExportRun, 200)
	for i := range runs {
		runs[i] = runFor("user-A", fmt.Sprintf("run-%03d", i))
	}
	for _, format := range []string{"csv", "gpx", "backup"} {
		ctx, cancel := context.WithCancel(context.Background())
		be := &cancellingBackend{
			fakeBackend: &fakeBackend{runs: runs, pageSize: 20},
			cancelAfter: 2,
			cancel:      cancel,
		}
		_, err := BuildArtifact(ctx, be, discardLog(), "user-A", format)
		if err == nil {
			t.Errorf("%s: a cancelled build reported success", format)
			continue
		}
		if len(be.uploads) != 0 {
			t.Errorf("%s: uploads=%v after cancellation", format, be.uploads)
		}
		if be.sink == nil || !be.sink.aborted {
			t.Errorf("%s: the session must be aborted on cancellation", format)
		}
	}
}

// cancellingBackend cancels the build's own context part-way through the
// runs walk, then reports the failure the way a real paged read would.
type cancellingBackend struct {
	*fakeBackend
	cancelAfter int
	cancel      context.CancelFunc
}

func (c *cancellingBackend) StreamExportRuns(ctx context.Context, uid string, emit func([]ExportRun) error) (ExportCompleteness, error) {
	pages := 0
	err := emitPages(c.runs, c.pageSize, func(page []ExportRun) error {
		pages++
		if pages == c.cancelAfter {
			c.cancel()
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		return emit(page)
	})
	return c.runsComp, err
}

func TestBuildArtifact_APageThatWillNotReadNamesItsSectionAndUploadsNothing(t *testing.T) {
	// The other half of the § 708 type distinction: a READ failure is
	// the section's, so the client can render `runs_fetch_failed`.
	be := &fakeBackend{runsErr: errors.New("postgrest 500")}
	_, err := BuildArtifact(context.Background(), be, discardLog(), "user-A", "backup")
	if err == nil {
		t.Fatal("a section that would not read must fail the build")
	}
	if SectionOf(err) != "runs" {
		t.Fatalf("section=%q, want runs", SectionOf(err))
	}
	if len(be.uploads) != 0 {
		t.Fatalf("uploads=%v", be.uploads)
	}
	if be.sink == nil || !be.sink.aborted {
		t.Fatal("the session must be aborted before the signing path")
	}
}

// ─────────────────── it really streams ───────────────────

func TestWriteGpxZip_BytesReachTheSinkBeforeTheWalkEnds(t *testing.T) {
	var w countingWriter
	page := make([]ExportRun, 400)
	for i := range page {
		page[i] = runFor("uid", fmt.Sprintf("r-%03d", i))
		page[i].Metadata = map[string]interface{}{"title": incompressible(uint64(i)+1, 4096)}
	}
	seenMidWalk := -1
	src := RunSource(func(_ context.Context, emit func([]ExportRun) error) (ExportCompleteness, error) {
		for off := 0; off < len(page); off += 50 {
			if err := emit(page[off : off+50]); err != nil {
				return ExportCompleteness{}, err
			}
			if off == 200 {
				seenMidWalk = w.n
			}
		}
		return ExportCompleteness{}, nil
	})
	if _, err := WriteGpxZip(context.Background(), &w, src, func(context.Context, string) ([]TrackPoint, error) {
		return nil, nil
	}); err != nil {
		t.Fatal(err)
	}
	if seenMidWalk <= 0 {
		t.Fatalf("nothing had reached the sink half-way through the walk (%d bytes) — "+
			"the manifest is being assembled before it is written", seenMidWalk)
	}
}

func TestWriteBackupZip_BytesReachTheSinkBeforeTheExtraTablesWalkEnds(t *testing.T) {
	var w countingWriter
	seenMidWalk := -1
	rows := make([]map[string]interface{}, 200)
	for i := range rows {
		rows[i] = map[string]interface{}{"id": fmt.Sprintf("p-%03d", i), "body": incompressible(uint64(i)+1, 4096)}
	}
	tables := TableSource(func(_ context.Context, emit func(string, []map[string]interface{}) error) (ExportCompleteness, error) {
		for off := 0; off < len(rows); off += 25 {
			if err := emit("live_run_pings.json", rows[off:off+25]); err != nil {
				return ExportCompleteness{}, err
			}
			if off == 100 {
				seenMidWalk = w.n
			}
		}
		return ExportCompleteness{}, nil
	})
	if _, err := WriteBackupZip(context.Background(), &w, BuildBackupZipInput{
		Runs: runSource(nil), Routes: routeSource(nil), ExtraTables: tables, UserID: "uid",
	}, BackupFetchers{}); err != nil {
		t.Fatal(err)
	}
	if seenMidWalk <= 0 {
		t.Fatalf("nothing had reached the sink half-way through the section walk (%d bytes)", seenMidWalk)
	}
}

func TestBuildArtifact_AnObjectFarPastTheChunkSizeStreamsThrough(t *testing.T) {
	// The remaining bound is the Storage object ceiling, not a row count
	// and not anything in this package. A single blob larger than the
	// sink's own chunk must pass through in one piece.
	big := bytes.Repeat([]byte{0x1f, 0x8b, 0x08, 0x00}, 2*1024*1024) // 8 MiB
	run := runFor("user-A", "run-1")
	be := &fakeBackend{
		runs:          []ExportRun{run},
		rawTrackBytes: map[string][]byte{"user-A/run-1.json.gz": big},
	}
	art, err := BuildArtifact(context.Background(), be, discardLog(), "user-A", "backup")
	if err != nil {
		t.Fatal(err)
	}
	if art.Runs != 1 {
		t.Fatalf("runs=%d", art.Runs)
	}
	entries := zipEntries(t, be.sink.body.Bytes())
	got, present := entries["tracks/run-1.json.gz"]
	if !present {
		t.Fatal("the track did not make it into the archive")
	}
	if !bytes.Equal(got, big) {
		t.Fatalf("track archived as %d bytes, want %d verbatim", len(got), len(big))
	}
}
