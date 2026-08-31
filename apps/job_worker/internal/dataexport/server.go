// Package dataexport is the GDPR data-portability HTTP endpoint on
// the Go service. Replaces the `export-data` Edge Function at
// apps/backend/supabase/functions/export-data/index.ts: the client asks
// for `{format: 'csv'|'gpx'|'backup'}` with a Bearer JWT, the worker
// builds the artifact into the `exports` Storage bucket under the
// caller's user-id prefix, and the status read hands back a 10-minute
// signed URL.
//
// Why move it out of the Edge Function:
//
//   - A deep history's GPX zip pushes the 150s EF timeout when the
//     per-run track downloads are slow; the Go runtime has no request
//     clock at all and can run wide-fanout downloads against Storage.
//   - All other Strava + token work is in this service, so the
//     export consolidates the third Edge Function move (after
//     refresh-tokens and strava-webhook) and lets us deprecate the
//     `export-data` EF in a follow-up.
//
// The archive is STREAMED, never assembled: every section is read page
// by page and serialised into a chunked (tus) Storage upload as it
// arrives, so peak memory is one 6 MiB chunk plus whichever blob is in
// flight, flat in the size of the history. That is what removed this
// rail's 5000-run cap and its 50,000-row-per-section ceiling
// (decisions.md §708); both were memory bounds, and a cap that exists
// to keep an allocation alive is a data subject not receiving their
// data. Fail-closed is the other half: tus materialises the object only
// once the declared length arrives, so any mid-build failure aborts the
// session and answers 500 with no artifact at all.
//
// The rail is QUEUED, and since decisions.md § 724 it is the only one:
// `POST /v1/export/jobs` enqueues a `data_export` job and answers with
// its id, the worker builds it with no connection attached, and `GET
// /v1/export/jobs/latest` reports the outcome and mints the signed URL
// at read time. The synchronous `POST /v1/export` that § 717 kept alive
// for the un-migrated mobile client is gone with that client's
// migration — it held the caller's connection open for the whole build,
// which on a phone is the ordinary way an export died rather than an
// edge case.
//
// Rate limit + auth model is unchanged from the EF: HS256 JWT
// over SUPABASE_JWT_SECRET (same as the live hub's authorizer),
// then per-user tiered throttle via `check_rate_limit_tiered`
// (free 2/h, pro 8/h).
package dataexport

import (
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
	"github.com/Absence0760/project-running/apps/job_worker/internal/supajwt"
)

// Server wires the data-export HTTP endpoint to the worker's
// service-role Supabase client. Mounted from main.go on the same
// mux as /health and the live hub.
type Server struct {
	// Verifier resolves a bearer token to its `sub` claim. When it has
	// no key material the endpoint refuses every request (503) —
	// production must supply it, same as the live hub.
	Verifier *supajwt.Verifier

	// Backend wraps the Supabase REST calls. Production wires the
	// worker's existing SupabaseClient (it implements this
	// interface natively); tests substitute a fake.
	Backend Backend

	Log *slog.Logger

	// AllowedOrigins is the exact `Origin` allowlist the browser rail
	// is answered for. The web client posts from a different origin
	// than the worker in every deployment, so without this the
	// preflight is refused and the enqueue never leaves the browser.
	// Empty → no CORS headers at all, which is correct for a
	// server-to-server deployment and fail-closed for a browser one.
	AllowedOrigins []string
}

// allowOrigin answers the exact origin when it is on the allowlist.
//
// Exact match rather than a wildcard: the endpoint is authenticated,
// and `Access-Control-Allow-Origin: *` is invalid the moment a request
// carries credentials — a browser rejects the response rather than
// relaxing the check.
func (s *Server) allowOrigin(origin string) bool {
	if origin == "" {
		return false
	}
	for _, o := range s.AllowedOrigins {
		if o == origin {
			return true
		}
	}
	return false
}

// writeCORS stamps the allow headers when the caller's origin is
// permitted, and reports whether it did. `Vary: Origin` is not
// optional: without it a cache can serve one origin's allow header to
// another.
func (s *Server) writeCORS(w http.ResponseWriter, r *http.Request) bool {
	w.Header().Add("Vary", "Origin")
	origin := r.Header.Get("Origin")
	if !s.allowOrigin(origin) {
		return false
	}
	w.Header().Set("Access-Control-Allow-Origin", origin)
	w.Header().Set("Access-Control-Allow-Credentials", "true")
	return true
}

// preflight answers an OPTIONS probe and reports whether it handled
// the request. A disallowed origin gets 403 rather than the mux's 405:
// the method IS allowed, the caller is not.
func (s *Server) preflight(w http.ResponseWriter, r *http.Request, methods string) bool {
	if r.Method != http.MethodOptions {
		return false
	}
	if !s.writeCORS(w, r) {
		w.WriteHeader(http.StatusForbidden)
		return true
	}
	w.Header().Set("Access-Control-Allow-Methods", methods)
	w.Header().Set("Access-Control-Allow-Headers", "authorization, content-type")
	w.Header().Set("Access-Control-Max-Age", "600")
	w.WriteHeader(http.StatusNoContent)
	return true
}

// Backend is the Supabase REST surface the export endpoint
// exercises. Defined as a leaf interface so the `dataexport`
// package can be tested without importing `internal`.
type Backend interface {
	// CheckRateLimitTiered consults `check_rate_limit_tiered`.
	// Returns `denied=true` + a Retry-After hint when the user is
	// over their tier's per-hour quota.
	CheckRateLimitTiered(ctx context.Context, userID, bucket string, freeMax, proMax, windowSec int) (denied bool, retryAfterSec int, err error)

	// StreamExportRuns walks the user's runs most-recent-first, handing
	// each page to `emit` and dropping it. The projection is the same
	// shape the EF pulled — id, started_at, duration_s, distance_m,
	// source, external_id, metadata, track_url, is_public, event_id,
	// route_id, created_at, updated_at.
	// Returns an ExportCompleteness naming the authoritative row count —
	// a walk that could not read every page must be visible in
	// manifest.json, not silently truncated.
	StreamExportRuns(ctx context.Context, userID string, emit func([]ExportRun) error) (ExportCompleteness, error)

	// DownloadTrackBytes pulls the gzipped track from Storage and
	// returns the decompressed JSON bytes. Used by the GPX zip
	// builder when assembling per-run track files. Returns
	// (nil, nil) when the track doesn't exist or fails to
	// decompress — the row still ships in the manifest without a
	// per-run GPX file.
	DownloadTrackBytes(ctx context.Context, path string) ([]TrackPoint, error)

	// OpenExportArtifact opens a chunked upload session for the artifact
	// at `path` with `Content-Type: contentType`. Nothing is written to
	// Storage until the session's Finish, and a session that is aborted
	// leaves no object — which is what lets a mid-build failure answer
	// 500 with no artifact rather than a short-but-real archive.
	// `upsert=false` so a duplicate timestamp doesn't overwrite a
	// previous export (the path includes a ms-precision timestamp so
	// collisions only happen on extreme parallel retries from the same
	// client).
	OpenExportArtifact(ctx context.Context, path, contentType string) ArtifactSink

	// CreateSignedURL returns a presigned Storage URL valid for
	// `ttlSec` seconds. The caller hands this back to the client
	// as the single download token; the user has no need for the
	// underlying Storage path. Returns an error wrapping
	// ErrArtifactGone when the object is no longer there, which the
	// queued rail reports as an expiry rather than as an outage.
	CreateSignedURL(ctx context.Context, path string, ttlSec int) (string, error)

	// EnqueueDataExport queues one Art 20 export for `userID`, or
	// returns the one already in flight (`Reused`). Both the state row
	// and its queue entry land in one statement — see
	// `enqueue_data_export`, migration 20270603_001.
	EnqueueDataExport(ctx context.Context, userID, format string) (ExportJobRef, error)

	// LatestDataExportJob returns the subject's most recent export
	// request, or (nil, nil) when they have never asked for one.
	LatestDataExportJob(ctx context.Context, userID string) (*ExportJobRow, error)

	// StreamExportRoutes walks the user's saved routes for the
	// `format=backup` path, page by page. Service role bypasses RLS; the
	// caller's userID filter is the only access gate. Mirrors the
	// `routes` selection the mobile / web backup writers do.
	StreamExportRoutes(ctx context.Context, userID string, emit func([]ExportRoute) error) (ExportCompleteness, error)

	// FetchExportProfile returns the user's profile via a direct
	// service-role select on `user_profiles` (NOT `get_my_profile`,
	// which keys on auth.uid() and would return empty for the
	// service-role worker). The column-level revokes on
	// `subscription_tier` / `parkrun_number` / `subscription_at`
	// (migration 20260707_001) are scoped to `authenticated`;
	// service_role keeps full column access. Returns nil + nil error
	// when the row is absent (new account).
	FetchExportProfile(ctx context.Context, userID string) (map[string]interface{}, error)

	// FetchUserSettingsPrefs returns the user's `user_settings.prefs`
	// jsonb for inclusion in `profile.json`. Returns an empty map +
	// nil error when no row exists yet — the restore path tolerates
	// missing prefs.
	FetchUserSettingsPrefs(ctx context.Context, userID string) (map[string]interface{}, error)

	// DownloadRawTrackBytes pulls the raw **gzipped** bytes from
	// Storage without decoding to TrackPoint[]. The backup ZIP
	// archives tracks in their on-disk `.json.gz` form so restore
	// can upload them verbatim. Returns nil + nil error when the
	// track is missing — the run row still ships, just without a
	// `tracks/{id}.json.gz` entry.
	DownloadRawTrackBytes(ctx context.Context, path string) ([]byte, error)

	// DownloadPhoto pulls the raw bytes (+ Content-Type) of a
	// run-photos Storage object. The Art 20 export bundles the photo
	// files themselves, not just their metadata rows (audit-findings
	// 2026-05-30 High). Returns a non-nil error when the object is
	// missing or the fetch fails; the builder tolerates that per-photo
	// and ships the zip without the failed entry.
	DownloadPhoto(ctx context.Context, path string) ([]byte, string, error)

	// DownloadAvatar pulls the raw bytes (+ Content-Type) of an
	// avatars-bucket object. The Art 20 export bundles the profile
	// picture itself, not just the avatar_url on the profile row.
	// Returns a non-nil error when the object is missing; the builder
	// probes each candidate path and tolerates misses.
	DownloadAvatar(ctx context.Context, path string) ([]byte, string, error)

	// ListStorageObjects walks a Storage bucket under `prefix` (the
	// user's folder) and returns every object key, recursing into
	// subfolders. The backup builder uses it to sweep CAS-orphaned
	// objects that no DB row references into the DSAR export.
	ListStorageObjects(ctx context.Context, bucket, prefix string) ([]string, error)

	// FetchExportPersonalDataTables bundles every additional table
	// the audit/data-export-completeness pass added to the export
	// (May 2026 + 2026-05-25 refresh): coach_messages, notifications,
	// training plans + weeks + workouts, integrations (with secrets
	// scrubbed), run_kudos + run_comments authored by the user,
	// run_photos metadata, segment_efforts, gear + run_gear,
	// fitness_snapshots, personal_records, device_tokens (with raw
	// token redacted), live_run_pings, user_follows, event_attendees,
	// club_members, saved_routes, route_reviews, race_pings,
	// user_device_settings, user_coach_usage, and the reporter side
	// of reports.
	//
	// Pages are handed to `emit` keyed by zip entry name (the table name
	// with a `.json` extension). Pages of one table arrive consecutively
	// and tables never interleave, so the consumer opens an archive
	// entry on a table's first page and closes it when the next table
	// (or the walk) ends. An empty table emits nothing, so the zip
	// carries no zero-row entries. Service-role auth bypasses RLS; the
	// implementation filters on user_id for every table.
	//
	// Bundled as one call rather than 16 separate Backend methods
	// to keep the fake-backend surface small and avoid leaking the
	// per-table fan-out into the Server handler. Single Backend
	// method = one fake stub for tests.
	StreamExportPersonalDataTables(ctx context.Context, userID string, emit func(entry string, rows []map[string]interface{}) error) (ExportCompleteness, error)
}

// ArtifactSink is a chunked, fail-closed Storage upload session. The
// builders write the archive into it as they produce it, so nothing
// larger than one chunk is ever resident.
//
// The lifecycle is the fail-closed guarantee: the object does not exist
// until Finish returns nil, and Abort removes any partial session. A
// build that dies half-way therefore leaves nothing behind, where the
// old single-shot upload would happily have stored a short-but-real
// archive and handed back a signed URL to it.
type ArtifactSink interface {
	io.Writer
	// Finish flushes the tail and materialises the object.
	Finish() error
	// Abort terminates the session. It runs on a path that is already
	// failing, so it reports rather than returns.
	Abort()
}

// RunSource walks the subject's runs newest-first, handing each page to
// `emit` and dropping it, and returns the walk's completeness ledger.
type RunSource func(ctx context.Context, emit func([]ExportRun) error) (ExportCompleteness, error)

// RouteSource is RunSource for the subject's saved routes.
type RouteSource func(ctx context.Context, emit func([]ExportRoute) error) (ExportCompleteness, error)

// TableSource walks the personal-data sections. Pages of one section
// arrive consecutively and sections never interleave.
type TableSource func(ctx context.Context, emit func(entry string, rows []map[string]interface{}) error) (ExportCompleteness, error)

// BuildResult is what a finished archive reports back to the handler.
type BuildResult struct {
	// Runs is the number of run rows the archive carries.
	Runs int
	// Completeness carries every section's authoritative total and the
	// sections that came up short.
	Completeness ExportCompleteness
}

// sectionError names the section whose READ failed, so the handler can
// keep the error codes the client already distinguishes. A failure in
// the archive writer or the upload is deliberately NOT one of these.
type sectionError struct {
	section string
	err     error
}

func (e *sectionError) Error() string { return e.section + " fetch failed: " + e.err.Error() }
func (e *sectionError) Unwrap() error { return e.err }

// ExportCompleteness is the honesty ledger a paged export carries beside
// its rows: the authoritative row count the database holds for each
// section, and the sections whose pages could not all be read. It is
// what keeps manifest.json from presenting a truncated archive as whole.
// Mirrors the `internal` type of the same name; the adapter in main.go
// translates, same leaf-package reasoning as ExportRun.
type ExportCompleteness struct {
	Totals     map[string]int
	Incomplete []string
}

// IsComplete reports whether every section was read in full.
func (e ExportCompleteness) IsComplete() bool { return len(e.Incomplete) == 0 }

// Merge folds another section's ledger into this one.
func (e *ExportCompleteness) Merge(other ExportCompleteness) {
	if e.Totals == nil {
		e.Totals = map[string]int{}
	}
	for k, v := range other.Totals {
		e.Totals[k] = v
	}
	e.Incomplete = append(e.Incomplete, other.Incomplete...)
}

// ExportRoute is the routes-table projection for the backup format.
// Mirrors the columns the mobile / web writers include in
// `routes.json`. `user_id` deliberately omitted — the caller strips
// it for re-homeability; restore stamps the new owner's uid.
type ExportRoute struct {
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Waypoints   interface{}            `json:"waypoints"`
	DistanceM   *float64               `json:"distance_m,omitempty"`
	ElevationM  *float64               `json:"elevation_m,omitempty"`
	Surface     *string                `json:"surface,omitempty"`
	IsPublic    *bool                  `json:"is_public,omitempty"`
	Slug        *string                `json:"slug,omitempty"`
	Tags        []string               `json:"tags,omitempty"`
	Featured    *bool                  `json:"is_featured,omitempty"`
	RunCount    *int                   `json:"run_count,omitempty"`
	IsStarred   *bool                  `json:"is_starred,omitempty"`
	Description *string                `json:"description,omitempty"`
	ClubID      *string                `json:"club_id,omitempty"`
	CreatedAt   *string                `json:"created_at,omitempty"`
	UpdatedAt   *string                `json:"updated_at,omitempty"`
	Extra       map[string]interface{} `json:"-"`
}

// ExportRun is the row projection the export builder consumes.
// Mirrors the EF's RunRow shape at export-data/index.ts.
type ExportRun struct {
	ID           string                 `json:"id"`
	UserID       string                 `json:"user_id"`
	StartedAt    string                 `json:"started_at"`
	DurationS    int                    `json:"duration_s"`
	DistanceM    float64                `json:"distance_m"`
	Source       string                 `json:"source"`
	ActivityType string                 `json:"activity_type"`
	IsDNF        bool                   `json:"is_dnf"`
	ExternalID   *string                `json:"external_id"`
	Metadata     map[string]interface{} `json:"metadata"`
	TrackURL     *string                `json:"track_url"`
	HrSeriesURL  *string                `json:"hr_series_url"`
	IsPublic     *bool                  `json:"is_public"`
	EventID      *string                `json:"event_id"`
	RouteID      *string                `json:"route_id"`
	CreatedAt    string                 `json:"created_at"`
	UpdatedAt    string                 `json:"updated_at"`
}

// TrackPoint is the wire shape inside each gzipped Storage track.
// Mirrors apps/web/src/lib/types.ts TrackPoint — kept here as a
// leaf type so the dataexport package doesn't import the worker's
// `internal` for a 4-field struct.
type TrackPoint struct {
	Lat float64  `json:"lat"`
	Lng float64  `json:"lng"`
	Ele *float64 `json:"ele,omitempty"`
	Ts  *string  `json:"ts,omitempty"`
	Bpm *int     `json:"bpm,omitempty"`
}

const (
	// SignedURLTTLSec is the 10-min window the client has to
	// download. Matches the EF.
	SignedURLTTLSec = 600
	// FreeQuotaPerHour / ProQuotaPerHour mirror the EF's
	// checkRateLimitTiered call.
	FreeQuotaPerHour = 2
	ProQuotaPerHour  = 8
	// MaxBodyBytes caps the request body. The body is just
	// `{format: 'csv'|'gpx'}` so 1 KiB is generous.
	MaxBodyBytes = 1024
)

// RegisterRoutes mounts the export endpoints on [mux].
//
// The queued rail is the only rail: `/v1/export/jobs` enqueues and
// `/v1/export/jobs/latest` reports. The synchronous `POST /v1/export`
// was deleted with decisions.md § 724 once mobile moved off it — it
// held the caller's connection open for the whole build, which on a
// phone is the ordinary way an export died rather than an edge case.
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/v1/export/jobs", s.handleJobsCreate)
	mux.HandleFunc("/v1/export/jobs/latest", s.handleJobsLatest)
}

func (s *Server) extractUserID(r *http.Request) (string, error) {
	raw := bearerToken(r)
	if raw == "" {
		return "", errors.New("missing_bearer")
	}
	sub, err := s.Verifier.Subject(raw)
	if err != nil {
		return "", errors.New("invalid_token")
	}
	return sub, nil
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(h, prefix) {
		return ""
	}
	return strings.TrimSpace(h[len(prefix):])
}

func (s *Server) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// --- CSV builder -----------------------------------------------------

// csvColumns mirrors the EF's column order at export-data/index.ts.
// `track_url` is deliberately omitted (audit/all storage Low — see
// EF comment); consumers get the actual track bytes in the GPX zip
// when they pick that format.
var csvColumns = []string{
	"id",
	"started_at",
	"distance_m",
	"duration_s",
	"source",
	"activity_type",
	"is_dnf",
	schema.MetaTitle,
	schema.MetaAvgBPM,
	schema.MetaSteps,
	schema.MetaElevationM,
	"route_id",
	"event_id",
	"external_id",
	"is_public",
	"metadata",
	"created_at",
	"updated_at",
}

// WriteCSV streams one summary row per run into `w` with the column
// shape the EF used, a page at a time. Nothing but the current page is
// resident, so a runner's hundred-thousandth row costs what their first
// one did.
func WriteCSV(ctx context.Context, w io.Writer, runs RunSource) (BuildResult, error) {
	cw := csv.NewWriter(w)
	if err := cw.Write(csvColumns); err != nil {
		return BuildResult{}, err
	}
	written := 0
	var emitErr error
	comp, err := runs(ctx, func(page []ExportRun) error {
		for _, r := range page {
			if err := cw.Write(csvRow(r)); err != nil {
				emitErr = err
				return err
			}
		}
		written += len(page)
		// Flush per page: csv.Writer buffers, and an unflushed writer
		// would hold the whole history exactly as the old builder did.
		cw.Flush()
		if err := cw.Error(); err != nil {
			emitErr = err
			return err
		}
		return nil
	})
	if emitErr != nil {
		return BuildResult{}, emitErr
	}
	if err != nil {
		return BuildResult{}, &sectionError{section: "runs", err: err}
	}
	cw.Flush()
	if err := cw.Error(); err != nil {
		return BuildResult{}, err
	}
	return BuildResult{Runs: written, Completeness: comp}, nil
}

func csvRow(r ExportRun) []string {
	md := r.Metadata
	if md == nil {
		md = map[string]interface{}{}
	}
	mdJSON, _ := json.Marshal(md)
	return []string{
		r.ID,
		r.StartedAt,
		fmt.Sprintf("%.0f", r.DistanceM),
		fmt.Sprintf("%d", r.DurationS),
		r.Source,
		r.ActivityType,
		strconv.FormatBool(r.IsDNF),
		stringy(md[schema.MetaTitle]),
		stringy(md[schema.MetaAvgBPM]),
		stringy(md[schema.MetaSteps]),
		stringy(md[schema.MetaElevationM]),
		deref(r.RouteID),
		deref(r.EventID),
		deref(r.ExternalID),
		derefBool(r.IsPublic),
		string(mdJSON),
		r.CreatedAt,
		r.UpdatedAt,
	}
}

func stringy(v interface{}) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	case float64:
		// JSON numbers all decode to float64; format integers
		// without trailing .0 (matches the EF's `String(num)`).
		if x == float64(int64(x)) {
			return fmt.Sprintf("%d", int64(x))
		}
		return fmt.Sprintf("%g", x)
	case bool:
		if x {
			return "true"
		}
		return "false"
	default:
		b, _ := json.Marshal(x)
		return string(b)
	}
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func derefBool(b *bool) string {
	if b == nil || !*b {
		return "false"
	}
	return "true"
}

// --- GPX zip builder -------------------------------------------------

// TrackFetcher pulls the decompressed track for a Storage path.
// Used by WriteGpxZip; production wires SupabaseClient.DownloadTrack.
// Tests substitute a deterministic fake.
type TrackFetcher func(ctx context.Context, path string) ([]TrackPoint, error)

// gpxRef is what the GPX builder retains per run while `runs.json`
// streams past: enough to name the entry and title the document, for
// the runs that actually have a track. The rows themselves are dropped
// — retaining them is what the deleted 5000-run cap existed to bound.
type gpxRef struct {
	userID    string
	id        string
	startedAt string
	title     string
}

// WriteGpxZip streams `runs.json` (manifest) + per-run `runs/<id>.gpx`
// into `w`. Mirrors the EF's `writeGpxZip`. Track download failures are
// silently swallowed — the row stays in the manifest, the per-run GPX is
// omitted, the zip ships.
//
// `trackFetcher` is the per-run track download. Runs with no track_url
// never enter the ref list, so no round trip is spent on them.
func WriteGpxZip(ctx context.Context, w io.Writer, runs RunSource, trackFetcher TrackFetcher) (BuildResult, error) {
	zw := zip.NewWriter(w)

	// Manifest first so a partial / corrupt zip still has it.
	fw, err := zw.Create("runs.json")
	if err != nil {
		return BuildResult{}, err
	}
	manifest := &jsonArray{w: fw}
	var refs []gpxRef
	written := 0
	var emitErr error
	comp, err := runs(ctx, func(page []ExportRun) error {
		for _, r := range page {
			if err := manifest.row(map[string]interface{}{
				"id":            r.ID,
				"started_at":    r.StartedAt,
				"distance_m":    r.DistanceM,
				"duration_s":    r.DurationS,
				"source":        r.Source,
				"activity_type": r.ActivityType,
				"is_dnf":        r.IsDNF,
				"external_id":   r.ExternalID,
				"metadata":      r.Metadata,
				"is_public":     r.IsPublic,
				"event_id":      r.EventID,
				"route_id":      r.RouteID,
			}); err != nil {
				emitErr = err
				return err
			}
			if hasCanonicalTrack(r) {
				refs = append(refs, gpxRef{
					userID:    r.UserID,
					id:        r.ID,
					startedAt: r.StartedAt,
					title:     stringy(r.Metadata[schema.MetaTitle]),
				})
			}
		}
		written += len(page)
		return nil
	})
	if emitErr != nil {
		return BuildResult{}, emitErr
	}
	if err != nil {
		return BuildResult{}, &sectionError{section: "runs", err: err}
	}
	if err := manifest.close(); err != nil {
		return BuildResult{}, err
	}

	for _, ref := range refs {
		track, err := trackFetcher(ctx, trackPath(ref.userID, ref.id))
		if err != nil || len(track) < 2 {
			continue
		}
		fw, err := zw.Create(fmt.Sprintf("runs/%s.gpx", ref.id))
		if err != nil {
			return BuildResult{}, err
		}
		if _, err := io.WriteString(fw, buildGpxDoc(ref.id, ref.startedAt, ref.title, track)); err != nil {
			return BuildResult{}, err
		}
	}

	if err := zw.Close(); err != nil {
		return BuildResult{}, err
	}
	return BuildResult{Runs: written, Completeness: comp}, nil
}

// trackPath / hrPath are the canonical Storage keys for a run's track
// and HR sidecar. The CHECK constraint on `runs.track_url`
// (20260621_001) enforces this shape for new writes; hasCanonicalTrack
// is the runtime backstop against legacy / malformed rows, and keeping
// the derivation here is what lets the builders retain a run id instead
// of a pair of Storage URLs.
func trackPath(userID, runID string) string { return userID + "/" + runID + ".json.gz" }
func hrPath(userID, runID string) string    { return userID + "/" + runID + ".hr.json.gz" }

func hasCanonicalTrack(r ExportRun) bool {
	return r.TrackURL != nil && *r.TrackURL == trackPath(r.UserID, r.ID)
}

func hasCanonicalHr(r ExportRun) bool {
	return r.HrSeriesURL != nil && *r.HrSeriesURL == hrPath(r.UserID, r.ID)
}

// jsonArray streams a JSON array into an archive entry one row at a
// time, so a section never has to be resident to be serialised. The
// per-row indentation differs from a whole-value MarshalIndent (each
// row's braces start at column zero); the EF's streaming sections made
// the same trade, and every consumer parses the JSON rather than
// diffing it.
type jsonArray struct {
	w     io.Writer
	count int
}

func (a *jsonArray) row(v interface{}) error {
	encoded, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	sep := ",\n"
	if a.count == 0 {
		sep = "[\n"
	}
	if _, err := io.WriteString(a.w, sep); err != nil {
		return err
	}
	if _, err := a.w.Write(encoded); err != nil {
		return err
	}
	a.count++
	return nil
}

func (a *jsonArray) close() error {
	if a.count == 0 {
		_, err := io.WriteString(a.w, "[]\n")
		return err
	}
	_, err := io.WriteString(a.w, "\n]\n")
	return err
}

// --- run-app-backup v1 builder ---------------------------------------

// BuildBackupZipInput bundles every input the backup builder needs.
// Defined as a struct because the parameter list outgrew positional
// signatures the moment the caller had to pass runs + routes +
// profile + prefs + user id + exported-from in one go.
type BuildBackupZipInput struct {
	Runs          RunSource
	Routes        RouteSource
	Profile       map[string]interface{}
	SettingsPrefs map[string]interface{}
	UserID        string
	ExportedFrom  string
	// ExtraTables walks the personal-data sections, each serialised as
	// `{name}.json` (with the .json suffix already baked into the entry
	// key, e.g. "coach_messages.json"). Audit/data-export-completeness
	// (May 2026) — every personal-data table the subject has an Art 20
	// right to receive arrives through here.
	ExtraTables TableSource
}

// RawTrackFetcher pulls the **gzipped** bytes for a Storage path
// without decoding. Sibling of TrackFetcher (which decodes for the
// GPX builder); the backup format archives tracks in their on-disk
// form so restore is a byte-for-byte upload.
type RawTrackFetcher func(ctx context.Context, path string) ([]byte, error)

// PhotoFetcher pulls the raw bytes (+ Content-Type) for a run-photos
// Storage object. Sibling of RawTrackFetcher; the backup format
// archives the photo files under `photos/` so an Art 20 export carries
// the images themselves, not just `run_photos.json` metadata.
type PhotoFetcher func(ctx context.Context, path string) ([]byte, string, error)

// ObjectLister enumerates every object key under a bucket prefix.
// Backs the backup builder's orphan sweep; production wires
// SupabaseClient.ListStorageObjects.
type ObjectLister func(ctx context.Context, bucket, prefix string) ([]string, error)

// BackupFetchers bundles the Storage callbacks WriteBackupZip fans out
// over. Grouped in a struct because the positional list outgrew the
// signature once avatars joined tracks + photos; a nil field skips its
// section (tests exercise one section at a time).
type BackupFetchers struct {
	RawTrack    RawTrackFetcher
	Photo       PhotoFetcher
	Avatar      PhotoFetcher
	ListObjects ObjectLister
}

// avatarExts enumerates the extensions the avatar uploader can write.
// The web uploader keeps a SINGLE object at the stable
// `{uid}/avatar.{ext}` path (remove-then-insert across all three
// extensions), so the full candidate set is enumerable without a
// bucket list — mirror of avatarPathsFor in apps/web/src/lib/core/data.ts.
var avatarExts = []string{"jpg", "png", "webp"}

// BackupFormatVersion is the manifest's `version` field. Bump only
// when the on-disk shape changes incompatibly; readers reject
// versions above the one they know.
const BackupFormatVersion = 1

// BackupFormatName is the manifest's `format` field. Hard-coded
// here + on every mobile / web writer. A non-matching manifest is
// rejected by every restore path.
const BackupFormatName = "run-app-backup"

// runRef is what the backup builder retains per run while `runs.json`
// streams past — an id plus whether the row named a canonically-shaped
// track / HR object. Around a hundred bytes a run, against the row
// itself, which is what the deleted 5000-run cap existed to bound. The
// Storage keys are derived rather than kept because the path-shape
// assertion has already proved they are exactly trackPath / hrPath.
type runRef struct {
	userID   string
	id       string
	hasTrack bool
	hasHr    bool
}

// extraSections streams the personal-data sections into the archive as
// they page out of PostgREST: it opens an entry on a section's first
// page and closes it when the next section arrives. Nothing but the
// current page is resident, which is what removed the 50,000-row
// ceiling (`live_run_pings` runs into the millions on a deep history).
type extraSections struct {
	zw     *zip.Writer
	name   string
	arr    *jsonArray
	counts map[string]int
	// ownerPrefix is the subject's own Storage folder. A `storage_path`
	// is a stored string handed to the service-role downloader, so it is
	// checked against the caller the way the orphan sweep already checks
	// the keys it lists — the CHECK constraint that ties the column to
	// `owner_id` (20260622_001) is the guarantee, this is the assertion.
	// Empty means no subject to attribute anything to, so nothing is
	// collected.
	ownerPrefix string
	// photoPaths are the run-photo Storage keys the blob sweep below
	// downloads. Keys, not rows: a path per photo is bounded by a few
	// dozen bytes where the metadata row is not.
	photoPaths []string
}

func (e *extraSections) write(entry string, rows []map[string]interface{}) error {
	if entry != e.name {
		if err := e.closeCurrent(); err != nil {
			return err
		}
		fw, err := e.zw.Create(entry)
		if err != nil {
			return err
		}
		e.name, e.arr = entry, &jsonArray{w: fw}
	}
	for _, row := range rows {
		if entry == "run_photos.json" {
			if sp, ok := row["storage_path"].(string); ok && e.ownsStoragePath(sp) {
				e.photoPaths = append(e.photoPaths, sp)
			}
		}
		if err := e.arr.row(row); err != nil {
			return err
		}
	}
	e.counts[strings.TrimSuffix(entry, ".json")] += len(rows)
	return nil
}

// ownsStoragePath reports whether a run-photo key is safe to hand the
// downloader AND belongs to the subject this archive is for.
func (e *extraSections) ownsStoragePath(sp string) bool {
	return isSafeStoragePath(sp) && e.ownerPrefix != "" && strings.HasPrefix(sp, e.ownerPrefix)
}

func (e *extraSections) closeCurrent() error {
	if e.arr == nil {
		return nil
	}
	err := e.arr.close()
	e.arr, e.name = nil, ""
	return err
}

// ownerPrefixOf is the subject's own folder in a user-partitioned
// Storage bucket, or "" when there is no subject.
func ownerPrefixOf(userID string) string {
	if userID == "" {
		return ""
	}
	return userID + "/"
}

// isSafeStoragePath is defence in depth alongside the
// run_photos_storage_path_shape CHECK (migration 20260622): only a
// canonical, non-absolute Storage key may be fed to the service-role
// downloader's URL or used as a zip entry name, so a malformed row
// can't land a traversal entry in the archive.
func isSafeStoragePath(sp string) bool {
	return sp != "" && sp == path.Clean(sp) && !strings.HasPrefix(sp, "/") && !strings.Contains(sp, "..")
}

// WriteBackupZip streams `manifest.json` + `runs.json` + `routes.json` +
// `profile.json` + per-run `tracks/<id>.json.gz` (raw gzipped bytes)
// into `w`. Output is byte-compatible with `BackupService.restore` on
// mobile and `restoreBackup` on web. Track download failures are
// silently swallowed — the row stays in the manifest, the `tracks/...`
// entry is omitted, the zip ships.
//
// Every section is written as it is read, so the peak allocation is one
// page of rows plus whichever blob is in flight, and the archive itself
// is never resident anywhere.
func WriteBackupZip(ctx context.Context, w io.Writer, in BuildBackupZipInput, f BackupFetchers) (BuildResult, error) {
	zw := zip.NewWriter(w)
	completeness := ExportCompleteness{}

	// runs.json — strip user_id for re-homeability.
	fw, err := zw.Create("runs.json")
	if err != nil {
		return BuildResult{}, err
	}
	runsArr := &jsonArray{w: fw}
	var refs []runRef
	runsWritten := 0
	var emitErr error
	runsComp, err := in.Runs(ctx, func(page []ExportRun) error {
		for _, r := range page {
			if err := runsArr.row(map[string]interface{}{
				"id":            r.ID,
				"started_at":    r.StartedAt,
				"duration_s":    r.DurationS,
				"distance_m":    r.DistanceM,
				"source":        r.Source,
				"activity_type": r.ActivityType,
				"is_dnf":        r.IsDNF,
				"external_id":   r.ExternalID,
				"metadata":      r.Metadata,
				"track_url":     r.TrackURL,
				"hr_series_url": r.HrSeriesURL,
				"is_public":     r.IsPublic,
				"event_id":      r.EventID,
				"route_id":      r.RouteID,
				"created_at":    r.CreatedAt,
				"updated_at":    r.UpdatedAt,
			}); err != nil {
				emitErr = err
				return err
			}
			ref := runRef{userID: r.UserID, id: r.ID, hasTrack: hasCanonicalTrack(r), hasHr: hasCanonicalHr(r)}
			if ref.hasTrack || ref.hasHr {
				refs = append(refs, ref)
			}
		}
		runsWritten += len(page)
		return nil
	})
	if emitErr != nil {
		return BuildResult{}, emitErr
	}
	if err != nil {
		return BuildResult{}, &sectionError{section: "runs", err: err}
	}
	if err := runsArr.close(); err != nil {
		return BuildResult{}, err
	}
	completeness.Merge(runsComp)

	// routes.json
	fw, err = zw.Create("routes.json")
	if err != nil {
		return BuildResult{}, err
	}
	routesArr := &jsonArray{w: fw}
	routesWritten := 0
	emitErr = nil
	routesComp, err := in.Routes(ctx, func(page []ExportRoute) error {
		for _, r := range page {
			if err := routesArr.row(routeRow(r)); err != nil {
				emitErr = err
				return err
			}
		}
		routesWritten += len(page)
		return nil
	})
	if emitErr != nil {
		return BuildResult{}, emitErr
	}
	if err != nil {
		return BuildResult{}, &sectionError{section: "routes", err: err}
	}
	if err := routesArr.close(); err != nil {
		return BuildResult{}, err
	}
	completeness.Merge(routesComp)

	// profile.json — strip `id` from the profile so the archive
	// is re-homeable (restore stamps the new owner's uid).
	profileOut := map[string]interface{}{
		"profile":        stripProfileID(in.Profile),
		"settings_prefs": defaultIfNil(in.SettingsPrefs),
	}
	if err := writeJSONEntry(zw, "profile.json", profileOut); err != nil {
		return BuildResult{}, err
	}

	// Object keys the row-driven loops below actually archived, per
	// bucket — the orphan prefix-walk dedupes against these.
	archivedRunObjects := map[string]bool{}
	archivedPhotoObjects := map[string]bool{}

	// Tracks — raw gzipped bytes, archived verbatim. STORE (no
	// recompression) since the source is already deflated.
	// A nil fetcher skips its section, per BackupFetchers.
	tracksAdded := 0
	hrAdded := 0
	if f.RawTrack != nil {
		for _, ref := range refs {
			if !ref.hasTrack {
				continue
			}
			key := trackPath(ref.userID, ref.id)
			body, err := f.RawTrack(ctx, key)
			if err != nil || len(body) == 0 {
				continue
			}
			if err := storeEntry(zw, fmt.Sprintf("tracks/%s.json.gz", ref.id), body); err != nil {
				return BuildResult{}, err
			}
			archivedRunObjects[key] = true
			tracksAdded++
		}

		// HR sidecars (indoor/treadmill runs, decisions §116). Same
		// verbatim-bytes + STORE shape as the tracks loop. Lets restore
		// re-home the per-point HR for trackless runs.
		for _, ref := range refs {
			if !ref.hasHr {
				continue
			}
			key := hrPath(ref.userID, ref.id)
			body, err := f.RawTrack(ctx, key)
			if err != nil || len(body) == 0 {
				continue
			}
			if err := storeEntry(zw, fmt.Sprintf("hr/%s.hr.json.gz", ref.id), body); err != nil {
				return BuildResult{}, err
			}
			archivedRunObjects[key] = true
			hrAdded++
		}
	}

	// Extra personal-data tables, streamed section by section in the
	// order the source walks them.
	extras := &extraSections{zw: zw, counts: map[string]int{}, ownerPrefix: ownerPrefixOf(in.UserID)}
	if in.ExtraTables != nil {
		emitErr = nil
		extrasComp, err := in.ExtraTables(ctx, func(entry string, rows []map[string]interface{}) error {
			if err := extras.write(entry, rows); err != nil {
				emitErr = err
				return err
			}
			return nil
		})
		if emitErr != nil {
			return BuildResult{}, emitErr
		}
		if err := extras.closeCurrent(); err != nil {
			return BuildResult{}, err
		}
		if err != nil {
			// Losing the runs + routes export over one optional table
			// being slow would be the worse outcome; the ledger names
			// what came up short and manifest.json publishes it.
			extrasComp.Incomplete = append(extrasComp.Incomplete, "extra_tables")
		}
		completeness.Merge(extrasComp)
	}

	// Photos — the image bytes themselves, archived under `photos/`
	// so the Art 20 export carries the subject's run photos and not
	// just the `run_photos.json` metadata (audit-findings 2026-05-30
	// High). Each `storage_path` is `{owner_id}/{photo_id}.ext` and we
	// keep the basename (`{photo_id}.ext`) as the zip entry so the
	// extension/content survives. Download failures are tolerated
	// per-photo — the metadata row already shipped; the zip closes
	// without the missing image (same contract as tracks).
	photosAdded := 0
	if f.Photo != nil {
		for _, sp := range extras.photoPaths {
			body, _, err := f.Photo(ctx, sp)
			if err != nil || len(body) == 0 {
				continue
			}
			if err := storeEntry(zw, "photos/"+path.Base(sp), body); err != nil {
				return BuildResult{}, err
			}
			archivedPhotoObjects[sp] = true
			photosAdded++
		}
	}

	// Avatar — the profile picture bytes from the public `avatars`
	// bucket, so the Art 20 export carries the image itself and not just
	// the avatar_url on the profile row. Probes the enumerable candidate
	// paths (see avatarExts); a miss on every path just means the user
	// has no avatar.
	avatarsAdded := 0
	if f.Avatar != nil && in.UserID != "" {
		for _, ext := range avatarExts {
			body, _, err := f.Avatar(ctx, fmt.Sprintf("%s/avatar.%s", in.UserID, ext))
			if err != nil || len(body) == 0 {
				continue
			}
			if err := storeEntry(zw, "avatar."+ext, body); err != nil {
				return BuildResult{}, err
			}
			avatarsAdded++
		}
	}

	// Prefix-walk the user's folders in the runs + run-photos buckets
	// so every object under {uid}/ lands in the zip even without a DB
	// row — the row-driven loops above miss CAS-orphaned matched tracks
	// ({uid}/{run_id}.matched.json.gz left behind by the re-upload race,
	// see worker.go), legacy tracks whose run row is gone, and the
	// worker-generated photo thumbnails. Deduped against the row-driven
	// entries; {uid}/exports/ is skipped (prior export artifacts —
	// self-referential, and each is itself a copy of this data; the
	// artifact now lands in its own bucket, but legacy ones are still
	// under that prefix). A list failure is tolerated so the row-driven
	// export still ships.
	orphansAdded := 0
	if f.ListObjects != nil && in.UserID != "" {
		prefix := ownerPrefixOf(in.UserID)
		type bucketWalk struct {
			bucket   string
			archived map[string]bool
			skipRel  func(string) bool
			fetch    func(context.Context, string) ([]byte, error)
		}
		var walks []bucketWalk
		if f.RawTrack != nil {
			walks = append(walks, bucketWalk{
				bucket:   schema.BucketRuns,
				archived: archivedRunObjects,
				skipRel:  func(rel string) bool { return strings.HasPrefix(rel, "exports/") },
				fetch:    f.RawTrack,
			})
		}
		if f.Photo != nil {
			walks = append(walks, bucketWalk{
				bucket:   schema.BucketRunPhotos,
				archived: archivedPhotoObjects,
				fetch: func(ctx context.Context, key string) ([]byte, error) {
					body, _, err := f.Photo(ctx, key)
					return body, err
				},
			})
		}
		for _, wk := range walks {
			keys, err := f.ListObjects(ctx, wk.bucket, in.UserID)
			if err != nil {
				continue
			}
			for _, key := range keys {
				if !strings.HasPrefix(key, prefix) {
					continue
				}
				rel := strings.TrimPrefix(key, prefix)
				if rel == "" || (wk.skipRel != nil && wk.skipRel(rel)) {
					continue
				}
				if wk.archived[key] {
					continue
				}
				// Same defence-in-depth as the row-driven loops: a
				// hostile object name must not land a traversal entry
				// in the zip.
				if !isSafeStoragePath(key) {
					continue
				}
				body, err := wk.fetch(ctx, key)
				if err != nil || len(body) == 0 {
					continue
				}
				if err := storeEntry(zw, "storage/"+wk.bucket+"/"+rel, body); err != nil {
					return BuildResult{}, err
				}
				orphansAdded++
			}
		}
	}

	// manifest last so the counts include the actual tracks + photos
	// + avatar + orphan objects + extra tables that made it in.
	counts := map[string]interface{}{
		"runs":            runsWritten,
		"routes":          routesWritten,
		"tracks":          tracksAdded,
		"hr_series":       hrAdded,
		"photos":          photosAdded,
		"avatars":         avatarsAdded,
		"storage_orphans": orphansAdded,
	}
	for k, v := range extras.counts {
		counts[k] = v
	}
	// A section's published count is the database's own total, so a file
	// short of it reads as a shortfall instead of as the whole set. A
	// section that failed short is counted even at zero rows — an absent
	// key must not be readable as "the subject has none of these".
	for k, total := range completeness.Totals {
		if fetched, ok := counts[k].(int); ok && fetched > total {
			continue
		}
		counts[k] = total
	}
	incomplete := append([]string{}, completeness.Incomplete...)
	sort.Strings(incomplete)
	manifest := map[string]interface{}{
		"format":              BackupFormatName,
		"version":             BackupFormatVersion,
		"exported_at":         time.Now().UTC().Format(time.RFC3339),
		"exported_by_user_id": in.UserID,
		"exported_from":       in.ExportedFrom,
		"counts":              counts,
		"complete":            len(incomplete) == 0,
		"incomplete":          incomplete,
	}
	if err := writeJSONEntry(zw, "manifest.json", manifest); err != nil {
		return BuildResult{}, err
	}

	if err := zw.Close(); err != nil {
		return BuildResult{}, err
	}
	return BuildResult{Runs: runsWritten, Completeness: completeness}, nil
}

// routeRow shapes one route for `routes.json`. `user_id` is
// deliberately omitted — the archive is re-homeable and restore stamps
// the new owner's uid.
func routeRow(r ExportRoute) map[string]interface{} {
	row := map[string]interface{}{
		"id":        r.ID,
		"name":      r.Name,
		"waypoints": r.Waypoints,
	}
	if r.DistanceM != nil {
		row["distance_m"] = *r.DistanceM
	}
	if r.ElevationM != nil {
		row["elevation_m"] = *r.ElevationM
	}
	if r.Surface != nil {
		row["surface"] = *r.Surface
	}
	if r.IsPublic != nil {
		row["is_public"] = *r.IsPublic
	}
	if r.Slug != nil {
		row["slug"] = *r.Slug
	}
	if r.Tags != nil {
		row["tags"] = r.Tags
	}
	if r.Featured != nil {
		row["is_featured"] = *r.Featured
	}
	if r.RunCount != nil {
		row["run_count"] = *r.RunCount
	}
	if r.IsStarred != nil {
		row["is_starred"] = *r.IsStarred
	}
	if r.Description != nil {
		row["description"] = *r.Description
	}
	if r.ClubID != nil {
		row["club_id"] = *r.ClubID
	}
	if r.CreatedAt != nil {
		row["created_at"] = *r.CreatedAt
	}
	if r.UpdatedAt != nil {
		row["updated_at"] = *r.UpdatedAt
	}
	return row
}

// storeEntry writes bytes that are already compressed (a gzipped track,
// a JPEG) with STORE, so the archive doesn't spend CPU re-deflating
// them.
func storeEntry(zw *zip.Writer, name string, body []byte) error {
	fw, err := zw.CreateHeader(&zip.FileHeader{Name: name, Method: zip.Store})
	if err != nil {
		return err
	}
	_, err = fw.Write(body)
	return err
}

func writeJSONEntry(zw *zip.Writer, name string, body interface{}) error {
	encoded, err := json.MarshalIndent(body, "", "  ")
	if err != nil {
		return err
	}
	fw, err := zw.Create(name)
	if err != nil {
		return err
	}
	if _, err := fw.Write(encoded); err != nil {
		return err
	}
	return nil
}

func stripProfileID(p map[string]interface{}) interface{} {
	if p == nil {
		return nil
	}
	out := make(map[string]interface{}, len(p))
	for k, v := range p {
		if k == "id" {
			continue
		}
		out[k] = v
	}
	return out
}

func defaultIfNil(m map[string]interface{}) map[string]interface{} {
	if m == nil {
		return map[string]interface{}{}
	}
	return m
}

// BuildGpx emits a minimal GPX 1.1 document for one run + its
// track. Loaders (Strava, Garmin Connect, GPX viewers) handle
// this shape uniformly. Exported for unit testing.

// gpxFloat renders a coordinate the way GPX 1.1 requires.
//
// %v switches to scientific notation below 1e-4 (a longitude of -0.0000123
// printed as "-1.23e-05"), but GPX types lat/lon/ele as xsd:decimal, whose
// lexical space forbids an exponent — so a schema-validating importer rejected
// the whole file. It bites anyone whose track passes near the prime meridian
// or the equator: Greenwich parkrun, for one.
func gpxFloat(v float64) string {
	return strconv.FormatFloat(v, 'f', -1, 64)
}

func BuildGpx(run ExportRun, track []TrackPoint) string {
	return buildGpxDoc(run.ID, run.StartedAt, stringy(run.Metadata[schema.MetaTitle]), track)
}

// buildGpxDoc is BuildGpx over the three fields it actually reads, so
// the streaming builder can hold a gpxRef per run instead of a row.
func buildGpxDoc(runID, startedAt, title string, track []TrackPoint) string {
	if title == "" {
		title = "Run " + runID
	}
	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	b.WriteString(`<gpx version="1.1" creator="Runonward" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">` + "\n")
	fmt.Fprintf(&b, "  <metadata><name>%s</name><time>%s</time></metadata>\n",
		xmlEscape(title), xmlEscape(startedAt))
	b.WriteString("  <trk>\n")
	fmt.Fprintf(&b, "    <name>%s</name>\n", xmlEscape(title))
	b.WriteString("    <trkseg>\n")
	for _, p := range track {
		fmt.Fprintf(&b, `      <trkpt lat="%s" lon="%s">`, gpxFloat(p.Lat), gpxFloat(p.Lng))
		if p.Ele != nil {
			fmt.Fprintf(&b, "<ele>%s</ele>", gpxFloat(*p.Ele))
		}
		if p.Ts != nil {
			fmt.Fprintf(&b, "<time>%s</time>", xmlEscape(*p.Ts))
		}
		if p.Bpm != nil {
			fmt.Fprintf(&b, `<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>%d</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>`, *p.Bpm)
		}
		b.WriteString("</trkpt>\n")
	}
	b.WriteString("    </trkseg>\n")
	b.WriteString("  </trk>\n")
	b.WriteString("</gpx>\n")
	return b.String()
}

func xmlEscape(s string) string {
	r := strings.NewReplacer(
		"&", "&amp;",
		"<", "&lt;",
		">", "&gt;",
		`"`, "&quot;",
		"'", "&apos;",
	)
	return r.Replace(s)
}

// DecodeTrackBytes is a helper exposed so the SupabaseClient
// adapter can reuse the gzip+JSON unwrap logic without importing
// `internal` (which would create an import cycle). Same byte-level
// shape as the EF's decodeTrack.
func DecodeTrackBytes(body []byte) ([]TrackPoint, error) {
	if len(body) >= 2 && body[0] == 0x1f && body[1] == 0x8b {
		zr, err := gzip.NewReader(bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		defer zr.Close()
		var pts []TrackPoint
		if err := json.NewDecoder(zr).Decode(&pts); err != nil {
			return nil, err
		}
		return pts, nil
	}
	var pts []TrackPoint
	if err := json.Unmarshal(body, &pts); err != nil {
		return nil, err
	}
	return pts, nil
}
