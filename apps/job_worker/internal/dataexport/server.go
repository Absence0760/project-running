// Package dataexport is the GDPR data-portability HTTP endpoint on
// the Go service. Replaces the synchronous `export-data` Edge
// Function at apps/backend/supabase/functions/export-data/index.ts
// with the same UX: client POSTs `{format: 'csv'|'gpx'}` with a
// Bearer JWT, server builds the artifact, uploads to the `runs`
// Storage bucket under the caller's user-id prefix, returns a
// 10-minute signed URL.
//
// Why move it out of the Edge Function:
//
//   - 5000-run GPX zips push the 150s EF timeout when the per-run
//     track downloads are slow; the Go runtime has no such cap and
//     can run wide-fanout downloads against Storage.
//   - All other Strava + token work is in this service, so the
//     export consolidates the third Edge Function move (after
//     refresh-tokens and strava-webhook) and lets us deprecate the
//     `export-data` EF in a follow-up.
//   - Future improvement: gzip on the wire, range-resumable
//     downloads, the per-run CSV-of-tracks variant — all easier
//     to grow here than in Deno.
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
	"sort"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Server wires the data-export HTTP endpoint to the worker's
// service-role Supabase client. Mounted from main.go on the same
// mux as /health and the live hub.
type Server struct {
	// JWTSecret is the Supabase project's HS256 signing key. When
	// empty the endpoint refuses every request (503) — production
	// must set SUPABASE_JWT_SECRET, same as the live hub.
	JWTSecret []byte

	// Backend wraps the Supabase REST calls. Production wires the
	// worker's existing SupabaseClient (it implements this
	// interface natively); tests substitute a fake.
	Backend Backend

	Log *slog.Logger
}

// Backend is the Supabase REST surface the export endpoint
// exercises. Defined as a leaf interface so the `dataexport`
// package can be tested without importing `internal`.
type Backend interface {
	// CheckRateLimitTiered consults `check_rate_limit_tiered`.
	// Returns `denied=true` + a Retry-After hint when the user is
	// over their tier's per-hour quota.
	CheckRateLimitTiered(ctx context.Context, userID, bucket string, freeMax, proMax, windowSec int) (denied bool, retryAfterSec int, err error)

	// FetchExportRuns returns up to `limit` rows for the user,
	// most-recent-first. The projection is the same shape the EF
	// pulled — id, started_at, duration_s, distance_m, source,
	// external_id, metadata, track_url, is_public, event_id,
	// route_id, created_at, updated_at.
	FetchExportRuns(ctx context.Context, userID string, limit int) ([]ExportRun, error)

	// DownloadTrackBytes pulls the gzipped track from Storage and
	// returns the decompressed JSON bytes. Used by the GPX zip
	// builder when assembling per-run track files. Returns
	// (nil, nil) when the track doesn't exist or fails to
	// decompress — the row still ships in the manifest without a
	// per-run GPX file.
	DownloadTrackBytes(ctx context.Context, path string) ([]TrackPoint, error)

	// UploadExportArtifact writes the assembled body to the
	// `runs` bucket at `path` with `Content-Type: contentType`.
	// `upsert=false` so a duplicate timestamp doesn't overwrite
	// a previous export (the path includes a ms-precision
	// timestamp so collisions only happen on extreme parallel
	// retries from the same client).
	UploadExportArtifact(ctx context.Context, path, contentType string, body []byte) error

	// CreateSignedURL returns a presigned Storage URL valid for
	// `ttlSec` seconds. The caller hands this back to the client
	// as the single download token; the user has no need for the
	// underlying Storage path.
	CreateSignedURL(ctx context.Context, path string, ttlSec int) (string, error)

	// FetchExportRoutes returns the user's saved routes for the
	// `format=backup` path. Service role bypasses RLS; the
	// caller's userID filter is the only access gate. Mirrors the
	// `routes` selection the mobile / web backup writers do.
	FetchExportRoutes(ctx context.Context, userID string) ([]ExportRoute, error)

	// FetchExportProfile returns the user's profile via the
	// `get_my_profile` SECURITY DEFINER RPC. Column-level revokes
	// on `subscription_tier` / `parkrun_number` / `subscription_at`
	// (migration 20260707_001) require this path rather than a
	// direct table select. Returns nil + nil error when the row
	// is absent (new account).
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
	// Returns a map keyed by zip entry name (the table name with a
	// `.json` extension); each value is a list of JSON-encodable
	// row maps. Empty tables are omitted from the map so the zip
	// doesn't carry zero-row entries. Service-role auth bypasses
	// RLS; the implementation filters on user_id for every table.
	//
	// Bundled as one call rather than 16 separate Backend methods
	// to keep the fake-backend surface small and avoid leaking the
	// per-table fan-out into the Server handler. Single Backend
	// method = one fake stub for tests.
	FetchExportPersonalDataTables(ctx context.Context, userID string) (map[string][]map[string]interface{}, error)
}

// ExportRoute is the routes-table projection for the backup format.
// Mirrors the columns the mobile / web writers include in
// `routes.json`. `user_id` deliberately omitted — the caller strips
// it for re-homeability; restore stamps the new owner's uid.
type ExportRoute struct {
	ID                 string                 `json:"id"`
	Name               string                 `json:"name"`
	Waypoints          interface{}            `json:"waypoints"`
	DistanceM          *float64               `json:"distance_m,omitempty"`
	ElevationM         *float64               `json:"elevation_m,omitempty"`
	Surface            *string                `json:"surface,omitempty"`
	IsPublic           *bool                  `json:"is_public,omitempty"`
	Slug               *string                `json:"slug,omitempty"`
	Tags               []string               `json:"tags,omitempty"`
	Featured           *bool                  `json:"featured,omitempty"`
	RunCount           *int                   `json:"run_count,omitempty"`
	IsStarred          *bool                  `json:"is_starred,omitempty"`
	Description        *string                `json:"description,omitempty"`
	ClubID             *string                `json:"club_id,omitempty"`
	CreatedAt          *string                `json:"created_at,omitempty"`
	UpdatedAt          *string                `json:"updated_at,omitempty"`
	Extra              map[string]interface{} `json:"-"`
}

// ExportRun is the row projection the export builder consumes.
// Mirrors the EF's RunRow shape at export-data/index.ts.
type ExportRun struct {
	ID         string                 `json:"id"`
	UserID     string                 `json:"user_id"`
	StartedAt  string                 `json:"started_at"`
	DurationS  int                    `json:"duration_s"`
	DistanceM  float64                `json:"distance_m"`
	Source     string                 `json:"source"`
	ExternalID *string                `json:"external_id"`
	Metadata   map[string]interface{} `json:"metadata"`
	TrackURL   *string                `json:"track_url"`
	IsPublic   *bool                  `json:"is_public"`
	EventID    *string                `json:"event_id"`
	RouteID    *string                `json:"route_id"`
	CreatedAt  string                 `json:"created_at"`
	UpdatedAt  string                 `json:"updated_at"`
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
	// MaxRunsPerExport caps a single export at 5000 runs. Mirrors
	// the EF cap. A serious power-user still sees every run; a
	// runaway loop on a corrupt account can't run forever.
	MaxRunsPerExport = 5000
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

// RegisterRoutes mounts POST /v1/export on [mux].
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/v1/export", s.handle)
}

type exportRequest struct {
	Format string `json:"format"`
}

func (s *Server) handle(w http.ResponseWriter, r *http.Request) {
	if len(s.JWTSecret) == 0 {
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

	// Body parse + format pick — same shape as the EF: tiny request,
	// `{format: 'csv'|'gpx'}`.
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, MaxBodyBytes))
	dec.DisallowUnknownFields()
	var req exportRequest
	if err := dec.Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, `{"error":"bad_body"}`, http.StatusBadRequest)
		return
	}
	format := req.Format
	if format == "" {
		format = "csv"
	}
	if format != "csv" && format != "gpx" && format != "backup" {
		http.Error(w, `{"error":"format must be csv, gpx, or backup"}`, http.StatusBadRequest)
		return
	}

	// Tiered rate limit. EF runs this with `failClosed: true`; an
	// RPC error treats the user as throttled. Same posture here —
	// a wave of 429s under a DB blip is preferable to free
	// multi-MB zips during the outage.
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

	runs, err := s.Backend.FetchExportRuns(r.Context(), userID, MaxRunsPerExport)
	if err != nil {
		s.log().Error("dataexport: runs select failed", "err", err, "user_id", userID)
		http.Error(w, `{"error":"runs_fetch_failed"}`, http.StatusInternalServerError)
		return
	}

	ts := time.Now().UTC().Format("2006-01-02T15-04-05.000Z")
	var (
		body        []byte
		contentType string
		ext         string
	)
	switch format {
	case "csv":
		body = []byte(BuildCSV(runs))
		contentType = "text/csv"
		ext = "csv"
	case "gpx":
		zipped, err := BuildGpxZip(r.Context(), runs, s.Backend.DownloadTrackBytes)
		if err != nil {
			s.log().Error("dataexport: gpx zip build failed", "err", err, "user_id", userID)
			http.Error(w, `{"error":"export_build_failed"}`, http.StatusInternalServerError)
			return
		}
		body = zipped
		contentType = "application/zip"
		ext = "zip"
	case "backup":
		// Fetch the extra inputs only needed for the backup format —
		// routes + profile + user_settings.prefs. None of these are
		// huge so a single batch fetch is fine inside the EF timeout.
		routes, rerr := s.Backend.FetchExportRoutes(r.Context(), userID)
		if rerr != nil {
			s.log().Error("dataexport: routes fetch failed", "err", rerr, "user_id", userID)
			http.Error(w, `{"error":"routes_fetch_failed"}`, http.StatusInternalServerError)
			return
		}
		profile, perr := s.Backend.FetchExportProfile(r.Context(), userID)
		if perr != nil {
			s.log().Warn("dataexport: profile fetch failed; including null", "err", perr, "user_id", userID)
			profile = nil
		}
		prefs, prefErr := s.Backend.FetchUserSettingsPrefs(r.Context(), userID)
		if prefErr != nil {
			s.log().Warn("dataexport: prefs fetch failed; including empty", "err", prefErr, "user_id", userID)
			prefs = map[string]interface{}{}
		}
		// audit/data-export-completeness (May 2026): the prior shape
		// only included runs + routes + profile. Pull every other
		// personal-data table the subject has an Art 20 right to
		// receive in one Backend call. Failure here is logged + we
		// ship a partial export rather than 500 — losing the runs
		// + routes export over a single optional table being slow
		// would be a worse outcome.
		extras, extrasErr := s.Backend.FetchExportPersonalDataTables(r.Context(), userID)
		if extrasErr != nil {
			s.log().Warn("dataexport: extra-tables fetch failed; shipping partial",
				"err", extrasErr, "user_id", userID)
			extras = nil
		}
		zipped, err := BuildBackupZip(r.Context(), BuildBackupZipInput{
			Runs:          runs,
			Routes:        routes,
			Profile:       profile,
			SettingsPrefs: prefs,
			UserID:        userID,
			ExportedFrom:  "go-service",
			ExtraTables:   extras,
		}, s.Backend.DownloadRawTrackBytes)
		if err != nil {
			s.log().Error("dataexport: backup zip build failed", "err", err, "user_id", userID)
			http.Error(w, `{"error":"export_build_failed"}`, http.StatusInternalServerError)
			return
		}
		body = zipped
		contentType = "application/zip"
		ext = "zip"
	}

	path := fmt.Sprintf("%s/exports/%s.%s", userID, ts, ext)
	if err := s.Backend.UploadExportArtifact(r.Context(), path, contentType, body); err != nil {
		s.log().Error("dataexport: storage upload failed", "err", err, "path", path)
		http.Error(w, `{"error":"upload_failed"}`, http.StatusInternalServerError)
		return
	}
	signed, err := s.Backend.CreateSignedURL(r.Context(), path, SignedURLTTLSec)
	if err != nil {
		s.log().Error("dataexport: signed URL failed", "err", err, "path", path)
		http.Error(w, `{"error":"signed_url_failed"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"url":        signed,
		"expires_in": SignedURLTTLSec,
		"count":      len(runs),
		"format":     format,
	})
}

func (s *Server) extractUserID(r *http.Request) (string, error) {
	raw := bearerToken(r)
	if raw == "" {
		return "", errors.New("missing_bearer")
	}
	tok, err := jwt.Parse(raw, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected alg: %v", t.Header["alg"])
		}
		return s.JWTSecret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil || !tok.Valid {
		return "", errors.New("invalid_token")
	}
	claims, ok := tok.Claims.(jwt.MapClaims)
	if !ok {
		return "", errors.New("invalid_claims")
	}
	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return "", errors.New("missing_sub")
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
	"title",
	"avg_bpm",
	"steps",
	"elevation_m",
	"route_id",
	"event_id",
	"external_id",
	"is_public",
	"metadata",
	"created_at",
	"updated_at",
}

// BuildCSV emits one summary row per run with the column shape the
// EF used. Exposed for unit testing without booting the HTTP host.
func BuildCSV(runs []ExportRun) string {
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)
	_ = w.Write(csvColumns)
	for _, r := range runs {
		md := r.Metadata
		if md == nil {
			md = map[string]interface{}{}
		}
		mdJSON, _ := json.Marshal(md)
		row := []string{
			r.ID,
			r.StartedAt,
			fmt.Sprintf("%.0f", r.DistanceM),
			fmt.Sprintf("%d", r.DurationS),
			r.Source,
			stringy(md["activity_type"]),
			stringy(md["title"]),
			stringy(md["avg_bpm"]),
			stringy(md["steps"]),
			stringy(md["elevation_m"]),
			deref(r.RouteID),
			deref(r.EventID),
			deref(r.ExternalID),
			derefBool(r.IsPublic),
			string(mdJSON),
			r.CreatedAt,
			r.UpdatedAt,
		}
		_ = w.Write(row)
	}
	w.Flush()
	return buf.String()
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
// Used by BuildGpxZip; production wires SupabaseClient.DownloadTrack.
// Tests substitute a deterministic fake.
type TrackFetcher func(ctx context.Context, path string) ([]TrackPoint, error)

// BuildGpxZip assembles `runs.json` (manifest) + per-run `runs/<id>.gpx`
// into a single zip. Mirrors the EF's `buildGpxZip`. Track download
// failures are silently swallowed — the row stays in the manifest,
// the per-run GPX is omitted, the zip ships.
//
// `trackFetcher` is the per-run track download. nil tracks (no
// track_url, or fetch failed, or fewer than 2 points) skip the
// per-run GPX file.
func BuildGpxZip(ctx context.Context, runs []ExportRun, trackFetcher TrackFetcher) ([]byte, error) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	// Manifest first so a partial / corrupt zip still has it.
	manifest := make([]map[string]interface{}, 0, len(runs))
	for _, r := range runs {
		manifest = append(manifest, map[string]interface{}{
			"id":          r.ID,
			"started_at":  r.StartedAt,
			"distance_m":  r.DistanceM,
			"duration_s":  r.DurationS,
			"source":      r.Source,
			"external_id": r.ExternalID,
			"metadata":    r.Metadata,
			"is_public":   r.IsPublic,
			"event_id":    r.EventID,
			"route_id":    r.RouteID,
		})
	}
	manifestJSON, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return nil, err
	}
	fw, err := zw.Create("runs.json")
	if err != nil {
		return nil, err
	}
	if _, err := fw.Write(manifestJSON); err != nil {
		return nil, err
	}

	for _, r := range runs {
		if r.TrackURL == nil || *r.TrackURL == "" {
			continue
		}
		// Path-shape assertion — same gate the EF runs. The CHECK
		// constraint on `runs.track_url` (20260621_001) enforces this
		// shape for new writes; this assertion is the runtime
		// backstop against legacy / malformed rows.
		expected := fmt.Sprintf("%s/%s.json.gz", r.UserID, r.ID)
		if *r.TrackURL != expected {
			continue
		}
		track, err := trackFetcher(ctx, *r.TrackURL)
		if err != nil || len(track) < 2 {
			continue
		}
		gpx := BuildGpx(r, track)
		fw, err := zw.Create(fmt.Sprintf("runs/%s.gpx", r.ID))
		if err != nil {
			return nil, err
		}
		if _, err := fw.Write([]byte(gpx)); err != nil {
			return nil, err
		}
	}

	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// --- run-app-backup v1 builder ---------------------------------------

// BuildBackupZipInput bundles every input the backup builder needs.
// Defined as a struct because the parameter list outgrew positional
// signatures the moment the caller had to pass runs + routes +
// profile + prefs + user id + exported-from in one go.
type BuildBackupZipInput struct {
	Runs          []ExportRun
	Routes        []ExportRoute
	Profile       map[string]interface{}
	SettingsPrefs map[string]interface{}
	UserID        string
	ExportedFrom  string
	// ExtraTables: zip-entry-name -> rows. Each non-empty entry is
	// serialised as `{name}.json` (with the .json suffix already
	// baked into the key, e.g. "coach_messages.json"). Audit/data-
	// export-completeness (May 2026) — every personal-data table
	// the subject has an Art 20 right to receive lives here.
	ExtraTables map[string][]map[string]interface{}
}

// RawTrackFetcher pulls the **gzipped** bytes for a Storage path
// without decoding. Sibling of TrackFetcher (which decodes for the
// GPX builder); the backup format archives tracks in their on-disk
// form so restore is a byte-for-byte upload.
type RawTrackFetcher func(ctx context.Context, path string) ([]byte, error)

// BackupFormatVersion is the manifest's `version` field. Bump only
// when the on-disk shape changes incompatibly; readers reject
// versions above the one they know.
const BackupFormatVersion = 1

// BackupFormatName is the manifest's `format` field. Hard-coded
// here + on every mobile / web writer. A non-matching manifest is
// rejected by every restore path.
const BackupFormatName = "run-app-backup"

// BuildBackupZip assembles `manifest.json` + `runs.json` +
// `routes.json` + `profile.json` + per-run `tracks/<id>.json.gz`
// (raw gzipped bytes) into a single zip. Output is byte-compatible
// with `BackupService.restore` on mobile and `restoreBackup` on
// web. Track download failures are silently swallowed — the row
// stays in the manifest, the `tracks/...` entry is omitted, the
// zip ships.
func BuildBackupZip(ctx context.Context, in BuildBackupZipInput, rawTrackFetcher RawTrackFetcher) ([]byte, error) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	// runs.json — strip user_id for re-homeability.
	runsOut := make([]map[string]interface{}, 0, len(in.Runs))
	for _, r := range in.Runs {
		runsOut = append(runsOut, map[string]interface{}{
			"id":          r.ID,
			"started_at":  r.StartedAt,
			"duration_s":  r.DurationS,
			"distance_m":  r.DistanceM,
			"source":      r.Source,
			"external_id": r.ExternalID,
			"metadata":    r.Metadata,
			"track_url":   r.TrackURL,
			"is_public":   r.IsPublic,
			"event_id":    r.EventID,
			"route_id":    r.RouteID,
			"created_at":  r.CreatedAt,
			"updated_at":  r.UpdatedAt,
		})
	}
	if err := writeJSONEntry(zw, "runs.json", runsOut); err != nil {
		return nil, err
	}

	// routes.json
	routesOut := make([]map[string]interface{}, 0, len(in.Routes))
	for _, r := range in.Routes {
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
			row["featured"] = *r.Featured
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
		routesOut = append(routesOut, row)
	}
	if err := writeJSONEntry(zw, "routes.json", routesOut); err != nil {
		return nil, err
	}

	// profile.json — strip `id` from the profile so the archive
	// is re-homeable (restore stamps the new owner's uid).
	profileOut := map[string]interface{}{
		"profile":        stripProfileID(in.Profile),
		"settings_prefs": defaultIfNil(in.SettingsPrefs),
	}
	if err := writeJSONEntry(zw, "profile.json", profileOut); err != nil {
		return nil, err
	}

	// Tracks — raw gzipped bytes, archived verbatim. STORE (no
	// recompression) since the source is already deflated.
	tracksAdded := 0
	for _, r := range in.Runs {
		if r.TrackURL == nil || *r.TrackURL == "" {
			continue
		}
		// Same path-shape assertion as the GPX builder.
		expected := fmt.Sprintf("%s/%s.json.gz", r.UserID, r.ID)
		if *r.TrackURL != expected {
			continue
		}
		bytes, err := rawTrackFetcher(ctx, *r.TrackURL)
		if err != nil || len(bytes) == 0 {
			continue
		}
		header := &zip.FileHeader{
			Name:   fmt.Sprintf("tracks/%s.json.gz", r.ID),
			Method: zip.Store, // already gzipped; STORE avoids wasted CPU
		}
		fw, err := zw.CreateHeader(header)
		if err != nil {
			return nil, err
		}
		if _, err := fw.Write(bytes); err != nil {
			return nil, err
		}
		tracksAdded++
	}

	// Extra personal-data tables. Stable sort so the zip is
	// reproducible byte-for-byte for tests (and so a restore tool
	// can rely on entry order if it ever wants to).
	extraCounts := map[string]int{}
	if in.ExtraTables != nil {
		names := make([]string, 0, len(in.ExtraTables))
		for n := range in.ExtraTables {
			names = append(names, n)
		}
		sort.Strings(names)
		for _, name := range names {
			rows := in.ExtraTables[name]
			if len(rows) == 0 {
				continue
			}
			if err := writeJSONEntry(zw, name, rows); err != nil {
				return nil, err
			}
			extraCounts[strings.TrimSuffix(name, ".json")] = len(rows)
		}
	}

	// manifest last so the counts include the actual tracks +
	// extra tables that made it in.
	counts := map[string]interface{}{
		"runs":   len(in.Runs),
		"routes": len(in.Routes),
		"tracks": tracksAdded,
	}
	for k, v := range extraCounts {
		counts[k] = v
	}
	manifest := map[string]interface{}{
		"format":              BackupFormatName,
		"version":             BackupFormatVersion,
		"exported_at":         time.Now().UTC().Format(time.RFC3339),
		"exported_by_user_id": in.UserID,
		"exported_from":       in.ExportedFrom,
		"counts":              counts,
	}
	if err := writeJSONEntry(zw, "manifest.json", manifest); err != nil {
		return nil, err
	}

	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
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
func BuildGpx(run ExportRun, track []TrackPoint) string {
	title := stringy(run.Metadata["title"])
	if title == "" {
		title = "Run " + run.ID
	}
	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	b.WriteString(`<gpx version="1.1" creator="Runonward" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">` + "\n")
	fmt.Fprintf(&b, "  <metadata><name>%s</name><time>%s</time></metadata>\n",
		xmlEscape(title), xmlEscape(run.StartedAt))
	b.WriteString("  <trk>\n")
	fmt.Fprintf(&b, "    <name>%s</name>\n", xmlEscape(title))
	b.WriteString("    <trkseg>\n")
	for _, p := range track {
		fmt.Fprintf(&b, `      <trkpt lat="%v" lon="%v">`, p.Lat, p.Lng)
		if p.Ele != nil {
			fmt.Fprintf(&b, "<ele>%v</ele>", *p.Ele)
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
