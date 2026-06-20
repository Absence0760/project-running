package internal

// Supabase REST client used by the worker. Everything goes through
// PostgREST + Storage REST so the worker has a single transport (HTTP)
// and zero direct DB dependencies — handy for Fly.io deploys where the
// Postgres VPC peering would be its own setup, and matches the Edge
// Functions' stack so deploy parity stays clean.

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

// SupabaseClient wraps the REST surface the worker needs. All calls
// authenticate with the service-role key; nothing here is meant to be
// reachable from anon / authenticated traffic.
type SupabaseClient struct {
	BaseURL    string
	ServiceKey string
	HTTP       *http.Client
}

// NewSupabaseClient builds a client with a sane default timeout. The
// http client is reused across calls so connection re-use kicks in for
// the polling loop.
func NewSupabaseClient(baseURL, serviceKey string) *SupabaseClient {
	return &SupabaseClient{
		BaseURL:    baseURL,
		ServiceKey: serviceKey,
		HTTP: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// HTTPError lets the worker's transient/permanent classifier branch on
// the status code rather than substring-matching the message text.
// Same pattern as SupabaseClient.kt's HttpException on the watch.
type HTTPError struct {
	StatusCode int
	Body       string
}

func (e *HTTPError) Error() string {
	return fmt.Sprintf("supabase http %d: %s", e.StatusCode, e.Body)
}

func (c *SupabaseClient) do(ctx context.Context, req *http.Request) ([]byte, error) {
	req.Header.Set("apikey", c.ServiceKey)
	req.Header.Set("Authorization", "Bearer "+c.ServiceKey)

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, &HTTPError{StatusCode: resp.StatusCode, Body: string(body)}
	}
	return body, nil
}

// rpc invokes a PostgREST function endpoint with the supplied JSON body
// and decodes the response into `out`. Pass `out = nil` for void
// functions like finish_job / defer_job.
func (c *SupabaseClient) rpc(ctx context.Context, fn string, params any, out any) error {
	payload, err := json.Marshal(params)
	if err != nil {
		return fmt.Errorf("rpc %s: marshal params: %w", fn, err)
	}
	url := c.BaseURL + "/rest/v1/rpc/" + fn
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	body, err := c.do(ctx, req)
	if err != nil {
		return err
	}
	if out == nil || len(body) == 0 {
		return nil
	}
	return json.Unmarshal(body, out)
}

// ClaimNextJob calls the SECURITY DEFINER RPC. Returns (nil, nil) when
// the queue is empty so the caller can sleep + retry without treating
// emptiness as an error condition.
//
// Empty `kindFilter` omits the `kind_filter` RPC parameter so the SQL
// default of NULL kicks in and the worker drains any kind it knows how
// to dispatch. A non-empty value pins the claim to that single kind —
// useful for partitioning workers by job class if we ever need it.
func (c *SupabaseClient) ClaimNextJob(ctx context.Context, workerID, kindFilter string) (*Job, error) {
	params := map[string]any{
		"worker_id": workerID,
	}
	if kindFilter != "" {
		params["kind_filter"] = kindFilter
	}
	var rows []Job
	if err := c.rpc(ctx, "claim_next_job", params, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &rows[0], nil
}

// FinishJob marks a job done | failed | cancelled. Bad result_status
// raises 22023 server-side; the worker shouldn't pass anything else.
func (c *SupabaseClient) FinishJob(ctx context.Context, jobID int64, resultStatus string, errMsg *string) error {
	params := map[string]any{
		"job_id":        jobID,
		"result_status": resultStatus,
		"err":           errMsg,
	}
	return c.rpc(ctx, "finish_job", params, nil)
}

// DeferJob re-queues a transient failure with backoff. Server doesn't
// decrement attempts; the per-job max_attempts ceiling still applies.
// Returns the resulting job status: "queued" on re-queue, or "failed"
// when the retry budget was exhausted and defer_job terminated the job
// instead (migration 20261201_001) — the worker logs accordingly.
func (c *SupabaseClient) DeferJob(ctx context.Context, jobID int64, delaySeconds int, errMsg *string) (string, error) {
	params := map[string]any{
		"job_id":        jobID,
		"delay_seconds": delaySeconds,
		"err":           errMsg,
	}
	var status string
	if err := c.rpc(ctx, "defer_job", params, &status); err != nil {
		return "", err
	}
	return status, nil
}

// DownloadTrack fetches a gzipped track from the runs Storage bucket
// and decompresses it into a TrackPoint slice. Path is the value stored
// in runs.track_url — `{user_id}/{run_id}.json.gz`.
func (c *SupabaseClient) DownloadTrack(ctx context.Context, path string) ([]TrackPoint, error) {
	url := c.BaseURL + "/storage/v1/object/" + schema.BucketRuns + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	// Storage may auto-decompress when Content-Encoding: gzip lands on
	// the response, but the upload path on the watch sets that header
	// AND the file is gzipped on disk. Detect the gzip magic and
	// decompress only when present so both cases work.
	pts, err := parseTrack(body)
	if err != nil {
		return nil, fmt.Errorf("parse track %s: %w", path, err)
	}
	return pts, nil
}

func parseTrack(body []byte) ([]TrackPoint, error) {
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

// UploadMatchedTrack gzips and stores the matched track at the given
// path. Uses upsert=true so a re-match overwrites any prior file.
func (c *SupabaseClient) UploadMatchedTrack(ctx context.Context, path string, points []TrackPoint) error {
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if err := json.NewEncoder(zw).Encode(points); err != nil {
		return err
	}
	if err := zw.Close(); err != nil {
		return err
	}

	url := c.BaseURL + "/storage/v1/object/" + schema.BucketRuns + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, &buf)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Content-Encoding", "gzip")
	// Storage's "x-upsert: true" header lets re-matches overwrite the
	// previous file rather than 409ing.
	req.Header.Set("x-upsert", "true")
	_, err = c.do(ctx, req)
	return err
}

// DownloadPhoto fetches the raw bytes of a photo from the run-photos
// Storage bucket. Returns the body + the response's Content-Type so
// the caller can preserve it on the re-upload (some browsers fall
// back to extension-sniffing when it's missing, but Supabase Storage
// signed URLs only use the stored header).
func (c *SupabaseClient) DownloadPhoto(ctx context.Context, path string) ([]byte, string, error) {
	url := c.BaseURL + "/storage/v1/object/" + schema.BucketRunPhotos + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, "", err
	}
	// We need the response headers, not just the body — re-use
	// http.Client directly here rather than go through `c.do` which
	// throws the response away.
	req.Header.Set("apikey", c.ServiceKey)
	req.Header.Set("Authorization", "Bearer "+c.ServiceKey)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", err
	}
	if resp.StatusCode >= 400 {
		return nil, "", &HTTPError{StatusCode: resp.StatusCode, Body: string(body)}
	}
	return body, resp.Header.Get("Content-Type"), nil
}

// UploadPhoto writes [body] back to the same Storage path as
// DownloadPhoto, with `x-upsert: true` so a re-process overwrites
// the original. Used by the photo_process handler after EXIF
// stripping. Idempotent — uploading already-stripped bytes a second
// time produces no observable difference.
func (c *SupabaseClient) UploadPhoto(ctx context.Context, path string, body []byte, contentType string) error {
	url := c.BaseURL + "/storage/v1/object/" + schema.BucketRunPhotos + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("x-upsert", "true")
	_, err = c.do(ctx, req)
	return err
}

// UpdatePhotoThumb512Path PATCHes the `thumb_512_path` column on a
// run_photos row after the worker has uploaded the resized variant.
// Service role bypasses RLS so the standard PostgREST surface works
// without a definer function.
func (c *SupabaseClient) UpdatePhotoThumb512Path(ctx context.Context, photoID, path string) error {
	url := c.BaseURL + "/rest/v1/" + schema.TableRunPhotos + "?id=eq." + photoID
	body, err := json.Marshal(map[string]string{"thumb_512_path": path})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
}

// ErrStaleSourceTrackURL is returned by UpdateMatchedTrackRow when the
// conditional PATCH found zero rows — meaning a re-upload trigger
// reset the row's source_track_url between the worker reading it and
// writing the result. Caller treats this as "discard cleanly": the
// match the worker just produced is for an old track, and a fresh
// job already queued by the trigger will produce the right answer.
var ErrStaleSourceTrackURL = errors.New("source_track_url changed during match")

// UpdateMatchedTrackRow PATCHes the run_matched_tracks row with the
// match output. When `expectedSourceTrackURL` is non-empty, the PATCH
// is conditional on `source_track_url = <value>` — closing the
// re-upload race at the DB level via CAS. Service role bypasses RLS
// so the standard PostgREST surface works without going through a
// definer function.
//
// Returns ErrStaleSourceTrackURL when the CAS matched 0 rows. Pass
// the empty string to skip the CAS for callers that don't care
// (none today; left as an escape hatch).
func (c *SupabaseClient) UpdateMatchedTrackRow(
	ctx context.Context,
	runID string,
	expectedSourceTrackURL string,
	row MatchedTrackRow,
) error {
	payload, err := json.Marshal(row)
	if err != nil {
		return err
	}
	q := "run_id=eq." + runID
	if expectedSourceTrackURL != "" {
		q += "&source_track_url=eq." + url.QueryEscape(expectedSourceTrackURL)
	}
	endpoint := c.BaseURL + "/rest/v1/" + schema.TableRunMatchedTracks + "?" + q
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	// Prefer=return=representation makes PostgREST return the
	// updated rows in the response body — that's how we count
	// affected rows for the CAS check. With return=minimal we'd
	// just get a 204 and have no idea whether the conditional
	// matched.
	req.Header.Set("Prefer", "return=representation")
	body, err := c.do(ctx, req)
	if err != nil {
		return err
	}
	if expectedSourceTrackURL != "" {
		var rows []json.RawMessage
		if err := json.Unmarshal(body, &rows); err != nil {
			return fmt.Errorf("decode update response: %w", err)
		}
		if len(rows) == 0 {
			return ErrStaleSourceTrackURL
		}
	}
	return nil
}

// ReadRunTrackURL fetches just the runs.track_url for a given id. The
// trigger payload carries user_id but not the path; we look it up at
// match time so a re-upload that changes track_url is matched against
// the latest version.
func (c *SupabaseClient) ReadRunTrackURL(ctx context.Context, runID string) (string, error) {
	url := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?id=eq." + runID + "&select=track_url"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return "", err
	}
	var rows []struct {
		TrackURL *string `json:"track_url"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return "", err
	}
	if len(rows) == 0 || rows[0].TrackURL == nil {
		return "", errors.New("run has no track_url")
	}
	return *rows[0].TrackURL, nil
}

// RunLinkInfo bundles the columns the auto-link path needs to decide
// "should I link this run, and to what?". Single round-trip is
// cheaper than two narrow reads.
type RunLinkInfo struct {
	RouteID   string
	DistanceM float64
}

// ReadRunForAutoLink fetches the columns the auto-link decision needs:
// route_id (skip if already linked) + distance_m (length-similarity
// half of the scoring policy). Distance comparison uses the stored
// run.distance_m rather than a haversine recomputation over the
// track because that's what web/mobile compare against — the
// canonical run distance comes from the recorder, not a worker-side
// re-derivation.
func (c *SupabaseClient) ReadRunForAutoLink(
	ctx context.Context, runID string,
) (RunLinkInfo, error) {
	url := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?id=eq." + runID + "&select=route_id,distance_m"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return RunLinkInfo{}, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return RunLinkInfo{}, err
	}
	var rows []struct {
		RouteID   *string `json:"route_id"`
		DistanceM float64 `json:"distance_m"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return RunLinkInfo{}, err
	}
	if len(rows) == 0 {
		return RunLinkInfo{}, errors.New("run not found")
	}
	out := RunLinkInfo{DistanceM: rows[0].DistanceM}
	if rows[0].RouteID != nil {
		out.RouteID = *rows[0].RouteID
	}
	return out, nil
}

// FindMatchingRoutes calls the routes_intersecting_track RPC (migration
// 20260610_001). The RPC pre-filters with ST_DWithin against the
// routes.geom GIST index, so this stays cheap even for users with
// many saved routes.
func (c *SupabaseClient) FindMatchingRoutes(
	ctx context.Context, userID string, track []TrackPoint, toleranceM float64, maxResults int,
) ([]RouteMatchCandidate, error) {
	if len(track) < 2 {
		return nil, nil
	}
	coords := make([][2]float64, len(track))
	for i, p := range track {
		coords[i] = [2]float64{p.Lng, p.Lat}
	}
	params := map[string]any{
		"caller_user_id": userID,
		"track_geojson": map[string]any{
			"type":        "LineString",
			"coordinates": coords,
		},
		"tolerance_m": toleranceM,
		"max_results": maxResults,
	}
	var out []RouteMatchCandidate
	if err := c.rpc(ctx, "routes_intersecting_track", params, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// LinkRunToRoute PATCHes runs.route_id. Idempotent — re-linking to the
// same id is a no-op (PostgREST UPDATE with the same value writes the
// row but doesn't change observable state). Service role bypasses
// RLS, so the worker can write without the runner's session.
func (c *SupabaseClient) LinkRunToRoute(ctx context.Context, runID, routeID string) error {
	body, err := json.Marshal(map[string]any{"route_id": routeID})
	if err != nil {
		return err
	}
	url := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?id=eq." + runID
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
}

// FetchExpiringStravaIntegrations returns Strava integrations whose
// access token expires within `within`. Used by the token-refresh
// handler — the wider window the cron picks, the larger this slice
// gets, so it's the only knob between "refresh ahead of expiry" and
// "burn Strava's quota on too many rotations".
//
// Bounded at 500 rows. The job handler walks the slice sequentially
// (one Strava call per row at ~1 s) and finishes well inside the
// per-job HandleTimeout. If a tenant ever has more than 500 expiring
// at once the next cron tick picks up the remainder.
func (c *SupabaseClient) FetchExpiringStravaIntegrations(ctx context.Context, within time.Duration) ([]IntegrationRow, error) {
	cutoff := time.Now().Add(within).UTC().Format(time.RFC3339)
	q := url.Values{}
	q.Set("provider", "eq.strava")
	q.Set("token_expiry", "lt."+cutoff)
	// Filter out already-disconnected rows so a permanently-broken
	// grant doesn't get retried every hour forever. Migration
	// 20261004_001 added the column. /audit/strava High #2.
	q.Set("disconnected_at", "is.null")
	q.Set("select", "id,user_id")
	q.Set("order", "token_expiry.asc")
	q.Set("limit", "500")
	u := c.BaseURL + "/rest/v1/" + schema.TableIntegrations + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []IntegrationRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	return rows, nil
}

// GetIntegrationTokens decrypts the (access, refresh) pair from Vault
// via the `get_integration_tokens` SECURITY DEFINER RPC. Service role
// bypasses the owner check baked into the function.
//
// Returns (nil, nil) when the integration row exists but no Vault
// entry is attached — the caller skips refresh for that user, same
// fail-safe shape as the Edge Function it replaces.
func (c *SupabaseClient) GetIntegrationTokens(ctx context.Context, userID, provider string) (*TokenPair, error) {
	params := map[string]any{
		"p_user_id":  userID,
		"p_provider": provider,
	}
	var rows []TokenPair
	if err := c.rpc(ctx, "get_integration_tokens", params, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 || rows[0].RefreshToken == "" {
		return nil, nil
	}
	return &rows[0], nil
}

// SetIntegrationTokens round-trips a refreshed pair through Vault via
// the `set_integration_tokens` RPC. The function also updates
// `integrations.token_expiry` + `updated_at` so the next sweep skips
// this user.
func (c *SupabaseClient) SetIntegrationTokens(ctx context.Context, userID, provider, accessToken, refreshToken string, tokenExpiry time.Time) error {
	params := map[string]any{
		"p_user_id":       userID,
		"p_provider":      provider,
		"p_access_token":  accessToken,
		"p_refresh_token": refreshToken,
		"p_token_expiry":  tokenExpiry.UTC().Format(time.RFC3339),
	}
	return c.rpc(ctx, "set_integration_tokens", params, nil)
}

// FindIntegrationUserByAthlete maps a Strava athlete id (the external
// id Strava sends in webhook payloads) back to the Supabase user id
// that owns the integration row. Returns "" + nil when no integration
// matches — the caller treats that as "ack 200, skip" (the user
// disconnected, or never connected).
func (c *SupabaseClient) FindIntegrationUserByAthlete(ctx context.Context, provider string, athleteID int64) (string, error) {
	q := url.Values{}
	q.Set("provider", "eq."+provider)
	q.Set("external_id", "eq."+strconv.FormatInt(athleteID, 10))
	q.Set("select", "user_id")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableIntegrations + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return "", err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return "", err
	}
	var rows []struct {
		UserID string `json:"user_id"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return "", nil
	}
	return rows[0].UserID, nil
}

// TryConsumeStravaQuota calls the `try_consume_strava_quota` RPC
// (migration 20261007_001). Returns true when the call may proceed,
// false when we've hit 90% of Strava's app-level limit. Fail-open
// on RPC error — a Supabase outage shouldn't block legitimate
// Strava traffic. /audit/strava M7.
func (c *SupabaseClient) TryConsumeStravaQuota(ctx context.Context) (bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.BaseURL+"/rest/v1/rpc/try_consume_strava_quota",
		bytes.NewReader([]byte("{}")))
	if err != nil {
		return true, err
	}
	req.Header.Set("Content-Type", "application/json")
	respBody, err := c.do(ctx, req)
	if err != nil {
		// Fail-open. A blocked legitimate refresh is worse than a
		// chance of brushing Strava's ceiling during a Supabase blip.
		return true, nil
	}
	var allowed bool
	if err := json.Unmarshal(respBody, &allowed); err != nil {
		return true, nil
	}
	return allowed, nil
}

// SetIntegrationTokensCAS calls the `set_integration_tokens_cas`
// RPC (migration 20261006_001). Returns `applied = true` when the
// vault row matched expected + the write went through, false when
// another caller rotated first. /audit/strava High #3.
func (c *SupabaseClient) SetIntegrationTokensCAS(
	ctx context.Context,
	userID, provider, expectedRefresh, access, refresh string,
	expiry time.Time,
) (bool, error) {
	body, err := json.Marshal(map[string]any{
		"p_user_id":                userID,
		"p_provider":               provider,
		"p_expected_refresh_token": expectedRefresh,
		"p_access_token":           access,
		"p_refresh_token":          refresh,
		"p_token_expiry":           expiry.UTC().Format(time.RFC3339),
	})
	if err != nil {
		return false, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.BaseURL+"/rest/v1/rpc/set_integration_tokens_cas",
		bytes.NewReader(body))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")
	respBody, err := c.do(ctx, req)
	if err != nil {
		return false, err
	}
	// The RPC returns a JSON boolean directly.
	var applied bool
	if err := json.Unmarshal(respBody, &applied); err != nil {
		return false, fmt.Errorf("set_integration_tokens_cas: decode: %w", err)
	}
	return applied, nil
}

// MarkIntegrationDisconnected stamps `disconnected_at = now()` +
// `disconnected_reason` on the integrations row for the given user
// + provider. Idempotent: re-stamping is harmless — the timestamp
// updates to the newer mark but the FetchExpiring sweep filter
// remains effective. /audit/strava High #2.
func (c *SupabaseClient) MarkIntegrationDisconnected(ctx context.Context, userID, provider, reason string) error {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("provider", "eq."+provider)
	u := c.BaseURL + "/rest/v1/" + schema.TableIntegrations + "?" + q.Encode()
	body, err := json.Marshal(map[string]any{
		"disconnected_at":     time.Now().UTC().Format(time.RFC3339),
		"disconnected_reason": reason,
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, u, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	if _, err := c.do(ctx, req); err != nil {
		return err
	}
	return nil
}

// IsStravaActivityImported is the metadata.strava_id dedupe check.
// Mirrors the EF helper `isAlreadyImported` (apps/backend/supabase/
// functions/_shared/strava.ts) — both webhook + backfill paths use
// the same dedupe key so a webhook firing during a backfill is a
// no-op rather than a duplicate row.
func (c *SupabaseClient) IsStravaActivityImported(ctx context.Context, userID string, stravaActivityID int64) (bool, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("source", "eq.strava")
	q.Set("metadata->>strava_id", "eq."+strconv.FormatInt(stravaActivityID, 10))
	q.Set("select", "id")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return false, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return false, err
	}
	var rows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return false, err
	}
	return len(rows) > 0, nil
}

// privacyDefaultIsPublic resolves whether a newly-imported run for this
// user should be public, from the universal `privacy_default` pref in
// user_settings.prefs. Only an explicit 'public' default publishes;
// followers/private/unset — and any read error — fall closed to private.
// Mirrors the web `privacyDefaultToIsPublic` mapping + the EF parkrun /
// strava-import paths (persona #27).
func (c *SupabaseClient) privacyDefaultIsPublic(ctx context.Context, userID string) bool {
	prefs, err := c.FetchUserSettingsPrefs(ctx, userID)
	if err != nil {
		return false
	}
	return prefs["privacy_default"] == "public"
}

// InsertStravaRun inserts a runs row sourced from a Strava activity.
// Mirrors the EF `ingestActivity` row shape (apps/backend/supabase/
// functions/_shared/strava.ts) — fields, source='strava', metadata
// keys all in lockstep so dashboard queries that read across both
// writers see one consistent shape. is_public honours the user's
// privacy_default (persona #27), fail-closed to private.
//
// Returns the inserted row's id (so the caller can subsequently
// upload the gzipped track + PATCH track_url).
func (c *SupabaseClient) InsertStravaRun(ctx context.Context, userID string, act *StravaActivity) (*IngestedRunInfo, error) {
	sport := strings.ToLower(act.SportType)
	if sport == "" {
		sport = strings.ToLower(act.Type)
	}
	activityType := "run"
	if strings.Contains(sport, "walk") {
		activityType = "walk"
	} else if strings.Contains(sport, "hike") {
		activityType = "hike"
	}

	// Stringify the Strava id so metadata.strava_id is the same type
	// across every writer (EF / Go / mobile ZIP). PG's `->>` coerces
	// numbers to canonical strings on read but downstream pure-TS
	// readers compare against typeof === 'string'. /audit/strava L3.
	stravaIDStr := strconv.FormatInt(act.ID, 10)
	metadata := map[string]any{
		schema.MetaStravaID:           stravaIDStr,
		schema.MetaImportedFrom:       "strava",
		schema.MetaImportedAt:         time.Now().UTC().Format(time.RFC3339),
		schema.MetaStravaActivityType: act.Type,
	}
	if act.AverageHeartrate > 0 {
		metadata[schema.MetaAvgBPM] = int(math.Round(act.AverageHeartrate))
	}
	if act.Name != "" {
		metadata[schema.MetaTitle] = act.Name
	}
	if act.TotalElevationGain != 0 {
		metadata[schema.MetaElevationM] = int(math.Round(act.TotalElevationGain))
	}

	duration := act.MovingTime
	if duration == 0 {
		duration = act.ElapsedTime
	}

	row := map[string]any{
		"user_id": userID,
		// activity_type is a real column now (F3 / 20261207_001), no
		// longer a metadata key. is_dnf defaults to false at the DB.
		"activity_type": activityType,
		"started_at":    act.StartDate,
		"distance_m":    int(math.Round(act.Distance)),
		"duration_s":    duration,
		"source":        "strava",
		"is_public":     c.privacyDefaultIsPublic(ctx, userID),
		// `external_id = 'strava:<id>'` is the cross-source dedupe key
		// — same shape mobile ZIP writes. /audit/strava M3.
		"external_id": "strava:" + stravaIDStr,
		"metadata":    metadata,
	}
	payload, err := json.Marshal(row)
	if err != nil {
		return nil, err
	}
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []IngestedRunInfo
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, errors.New("strava run insert: no row returned")
	}
	return &rows[0], nil
}

// UpdateRunTrackURL PATCHes runs.track_url after a successful Storage
// upload. Service role bypasses RLS; the upload + PATCH happen in
// the worker so the runner doesn't need to be present.
func (c *SupabaseClient) UpdateRunTrackURL(ctx context.Context, runID, trackURL string) error {
	body, err := json.Marshal(map[string]any{"track_url": trackURL})
	if err != nil {
		return err
	}
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?id=eq." + runID
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, u, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
}

// InsertWebhookEvent is the replay-protection dedupe insert. Returns
// `inserted == true` on a fresh row, `false` when the unique
// constraint on (provider, event_id) rejected it (Strava-side retry
// of an event we've already ack'd).
//
// 23505 (unique_violation) is the only "false" path; anything else
// (RLS denial, table missing, network) bubbles as an error.
func (c *SupabaseClient) InsertWebhookEvent(ctx context.Context, provider, eventID string) (bool, error) {
	body, err := json.Marshal(map[string]any{
		"provider": provider,
		"event_id": eventID,
	})
	if err != nil {
		return false, err
	}
	u := c.BaseURL + "/rest/v1/" + schema.TableWebhookEvents
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	if err == nil {
		return true, nil
	}
	// PostgREST surfaces 23505 as 409 with `code: "23505"` in the
	// JSON body. The `do` wrapper preserves the body text on
	// HTTPError so we can sniff for the SQLSTATE.
	var hErr *HTTPError
	if errors.As(err, &hErr) {
		if hErr.StatusCode == http.StatusConflict && strings.Contains(hErr.Body, "23505") {
			return false, nil
		}
	}
	return false, err
}

// DeleteWebhookEvent is the rollback path for the Strava webhook's
// "fetch returned 429 / 503 → propagate retry to Strava" branch.
// The dedupe row was inserted before the fetch attempt; without
// undoing it a Strava-side retry would skip the activity entirely
// because the dedupe wins. Removing the row reopens the dedupe
// gate for the next retry attempt.
func (c *SupabaseClient) DeleteWebhookEvent(ctx context.Context, provider, eventID string) error {
	q := url.Values{}
	q.Set("provider", "eq."+provider)
	q.Set("event_id", "eq."+eventID)
	u := c.BaseURL + "/rest/v1/" + schema.TableWebhookEvents + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
}

// EnqueueStravaEvent inserts a `kind='strava_event'` job row with
// the webhook payload. Called by the stravahook HTTP endpoint after
// validation + dedupe. The CHECK constraint on `jobs.kind`
// (`20260823_001_jobs_kind_allowlist_strava_event.sql`) gates the
// insert; an out-of-allowlist kind would 23514 here.
//
// Note the struct shape is mirrored — `stravahook.Server` doesn't
// import `internal` (it's a leaf package for testability), so the
// payload type appears in both packages. The JSON wire shape is
// identical, so the SupabaseClient adapter at main.go translates
// across them.
func (c *SupabaseClient) EnqueueStravaEvent(ctx context.Context, payload map[string]any) (int64, error) {
	body, err := json.Marshal(map[string]any{
		"kind":    "strava_event",
		"payload": payload,
	})
	if err != nil {
		return 0, err
	}
	u := c.BaseURL + "/rest/v1/" + schema.TableJobs
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")
	resp, err := c.do(ctx, req)
	if err != nil {
		return 0, err
	}
	var rows []struct {
		ID int64 `json:"id"`
	}
	if err := json.Unmarshal(resp, &rows); err != nil {
		return 0, err
	}
	if len(rows) == 0 {
		return 0, errors.New("enqueue strava_event: no row returned")
	}
	return rows[0].ID, nil
}

// CheckRateLimitTiered consults the `check_rate_limit_tiered`
// SECURITY DEFINER RPC. Mirrors the EF helper of the same shape.
// Returns `denied=true` + the suggested Retry-After when the user
// is over their tier's per-hour quota. RPC errors bubble so the
// caller can fail-closed (treat outage as throttled) — matches the
// EF's `failClosed: true` posture.
func (c *SupabaseClient) CheckRateLimitTiered(ctx context.Context, userID, bucket string, freeMax, proMax, windowSec int) (bool, int, error) {
	params := map[string]any{
		"p_user_id":        userID,
		"p_bucket":         bucket,
		"p_free_max":       freeMax,
		"p_pro_max":        proMax,
		"p_window_seconds": windowSec,
	}
	var rows []struct {
		Allowed           bool   `json:"allowed"`
		RetryAfterSeconds int    `json:"retry_after_seconds"`
		Tier              string `json:"tier"`
	}
	if err := c.rpc(ctx, "check_rate_limit_tiered", params, &rows); err != nil {
		return false, 0, err
	}
	if len(rows) == 0 {
		// The RPC always returns one row; an empty result means a
		// schema-level surprise. Fail-closed.
		return true, 60, nil
	}
	return !rows[0].Allowed, rows[0].RetryAfterSeconds, nil
}

// FetchExportRuns reads the user's runs with the column projection
// the GDPR export needs. Service role bypasses RLS; the userID
// filter is the only access gate. Ordered most-recent-first, capped
// at `limit`. Returns dataexport.ExportRun rows so the adapter
// doesn't need to translate fields.
func (c *SupabaseClient) FetchExportRuns(ctx context.Context, userID string, limit int) ([]dataexportRow, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("select",
		"id,user_id,started_at,duration_s,distance_m,source,activity_type,is_dnf,external_id,metadata,track_url,hr_series_url,is_public,event_id,route_id,created_at,updated_at")
	q.Set("order", "started_at.desc")
	q.Set("limit", strconv.Itoa(limit))
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []dataexportRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	return rows, nil
}

// dataexportRow mirrors dataexport.ExportRun. We don't import the
// dataexport package here to keep `internal` a leaf (the adapter
// in main.go bridges across).
type dataexportRow struct {
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

// UploadExportArtifact stores the assembled CSV / GPX-zip body to
// the `runs` bucket. `upsert=false` so a duplicate path doesn't
// stomp on an existing export (the caller picks a ms-precision
// timestamped path).
func (c *SupabaseClient) UploadExportArtifact(ctx context.Context, path, contentType string, body []byte) error {
	u := c.BaseURL + "/storage/v1/object/" + schema.BucketRuns + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("x-upsert", "false")
	_, err = c.do(ctx, req)
	return err
}

// CreateSignedURL calls the Storage /object/sign endpoint to mint
// a time-bounded download URL. The returned `signedURL` is a path
// (e.g. `/object/sign/runs/...?token=...`) — we prepend the
// project's storage host so the caller hands back a full URL.
func (c *SupabaseClient) CreateSignedURL(ctx context.Context, path string, ttlSec int) (string, error) {
	body, err := json.Marshal(map[string]any{"expiresIn": ttlSec})
	if err != nil {
		return "", err
	}
	u := c.BaseURL + "/storage/v1/object/sign/" + schema.BucketRuns + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.do(ctx, req)
	if err != nil {
		return "", err
	}
	var parsed struct {
		SignedURL string `json:"signedURL"`
	}
	if err := json.Unmarshal(resp, &parsed); err != nil {
		return "", err
	}
	if parsed.SignedURL == "" {
		return "", errors.New("signed url: empty")
	}
	// The signedURL field is path-relative (`/storage/v1/object/sign/...`).
	// Front it with the base URL so the client doesn't need to know.
	if strings.HasPrefix(parsed.SignedURL, "/") {
		return strings.TrimRight(c.BaseURL, "/") + parsed.SignedURL, nil
	}
	return parsed.SignedURL, nil
}

// FetchExportRoutes reads the user's saved routes for the backup
// export format. Service role bypasses RLS; the userID filter is
// the only access gate. Mirrors the column shape mobile + web
// backup writers archive.
func (c *SupabaseClient) FetchExportRoutes(ctx context.Context, userID string) ([]exportRouteRow, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("select", "*")
	u := c.BaseURL + "/rest/v1/" + schema.TableRoutes + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []exportRouteRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	return rows, nil
}

// exportRouteRow mirrors dataexport.ExportRoute. Same leaf-package
// reasoning as `dataexportRow` — keep `internal` from importing
// `dataexport`.
type exportRouteRow struct {
	ID          string      `json:"id"`
	Name        string      `json:"name"`
	Waypoints   interface{} `json:"waypoints"`
	DistanceM   *float64    `json:"distance_m,omitempty"`
	ElevationM  *float64    `json:"elevation_m,omitempty"`
	Surface     *string     `json:"surface,omitempty"`
	IsPublic    *bool       `json:"is_public,omitempty"`
	Slug        *string     `json:"slug,omitempty"`
	Tags        []string    `json:"tags,omitempty"`
	Featured    *bool       `json:"is_featured,omitempty"`
	RunCount    *int        `json:"run_count,omitempty"`
	IsStarred   *bool       `json:"is_starred,omitempty"`
	Description *string     `json:"description,omitempty"`
	ClubID      *string     `json:"club_id,omitempty"`
	CreatedAt   *string     `json:"created_at,omitempty"`
	UpdatedAt   *string     `json:"updated_at,omitempty"`
}

// FetchExportProfile reads the user's profile with a direct
// service-role select on `user_profiles`, NOT via `get_my_profile()`.
// The RPC keys on `auth.uid()`, which is empty for a service-role
// caller, so it would return an empty profile for the export worker
// (audit-findings 2026-05-30 High — this path was flagged to confirm
// it doesn't silently strand the profile section; it doesn't, because
// it never calls the RPC). The column-level revokes on
// `subscription_tier` / `parkrun_number` / `subscription_at`
// (migration 20260707_001) are scoped to `authenticated`; `service_role`
// retains full column access, so the direct select below returns
// `parkrun_number` + `date_of_birth` fine. Returns nil + nil when no
// row exists yet.
func (c *SupabaseClient) FetchExportProfile(ctx context.Context, userID string) (map[string]interface{}, error) {
	q := url.Values{}
	q.Set("id", "eq."+userID)
	// audit/data-export-completeness (May 2026): `birth_year` was
	// listed in the projection but never existed in the schema, and
	// `date_of_birth` (the real column, added by
	// 20260829_001_segments_v2_tiered_leaderboards.sql) + `parkrun_number`
	// were missing entirely. Both are personal data the subject has
	// an Art 20 right to receive.
	q.Set("select", "id,display_name,avatar_url,bio,location,preferred_unit,created_at,hr_zones,date_of_birth,parkrun_number,gender,activity_default,privacy_default")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableUserProfiles + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []map[string]interface{}
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return rows[0], nil
}

// FetchUserSettingsPrefs reads `user_settings.prefs` for inclusion
// in `profile.json`. Returns an empty map + nil when the row is
// absent — restore tolerates missing prefs and the user keeps
// their on-device defaults.
func (c *SupabaseClient) FetchUserSettingsPrefs(ctx context.Context, userID string) (map[string]interface{}, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("select", "prefs")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableUserSettings + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []struct {
		Prefs map[string]interface{} `json:"prefs"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 || rows[0].Prefs == nil {
		return map[string]interface{}{}, nil
	}
	return rows[0].Prefs, nil
}

// FetchNotificationForEmail reads the projection the notification-email
// handler needs. Returns (nil, nil) when the row is gone — the user
// cleared their inbox before the worker drained the job, which is a
// finish-done, not an error.
func (c *SupabaseClient) FetchNotificationForEmail(ctx context.Context, notificationID string) (*NotificationRow, error) {
	q := url.Values{}
	q.Set("id", "eq."+notificationID)
	q.Set("select", "id,user_id,kind,run_id,event_id,club_id,comment_id,email_sent_at")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableNotifications + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []NotificationRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &rows[0], nil
}

// FetchUserEmail resolves a user's email via the GoTrue Admin API. The
// address lives in auth.users, which PostgREST doesn't expose; the admin
// endpoint is the supported service-role read. Returns "" (no error) when
// the user has no email on file (e.g. a phone-only or deleted account) so
// the caller can mark the notification handled rather than retry forever.
func (c *SupabaseClient) FetchUserEmail(ctx context.Context, userID string) (string, error) {
	u := c.BaseURL + "/auth/v1/admin/users/" + userID
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return "", err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return "", err
	}
	var out struct {
		Email string `json:"email"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", err
	}
	return out.Email, nil
}

// MarkNotificationEmailed stamps email_sent_at so the row reaches a
// terminal state — sent OR deliberately skipped (opted-out category, no
// address). Idempotent: re-stamping an already-stamped row is harmless.
func (c *SupabaseClient) MarkNotificationEmailed(ctx context.Context, notificationID string) error {
	q := url.Values{}
	q.Set("id", "eq."+notificationID)
	u := c.BaseURL + "/rest/v1/" + schema.TableNotifications + "?" + q.Encode()
	payload, err := json.Marshal(map[string]string{
		"email_sent_at": time.Now().UTC().Format(time.RFC3339),
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
}

// FetchNotificationForWebPush is the web-push sibling of
// FetchNotificationForEmail — same row, but selects web_push_sent_at (the
// per-channel guard) instead of email_sent_at. Returns (nil, nil) when the row
// is gone (inbox cleared before the job drained).
func (c *SupabaseClient) FetchNotificationForWebPush(ctx context.Context, notificationID string) (*NotificationRow, error) {
	q := url.Values{}
	q.Set("id", "eq."+notificationID)
	q.Set("select", "id,user_id,kind,run_id,event_id,club_id,comment_id,web_push_sent_at")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableNotifications + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []NotificationRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &rows[0], nil
}

// MarkNotificationWebPushed stamps web_push_sent_at so the row reaches a
// terminal state for the push channel — sent OR deliberately skipped (opted
// out, no subscription). Independent of email_sent_at: a notification can be
// emailed but not pushed, or vice-versa.
func (c *SupabaseClient) MarkNotificationWebPushed(ctx context.Context, notificationID string) error {
	q := url.Values{}
	q.Set("id", "eq."+notificationID)
	u := c.BaseURL + "/rest/v1/" + schema.TableNotifications + "?" + q.Encode()
	payload, err := json.Marshal(map[string]string{
		"web_push_sent_at": time.Now().UTC().Format(time.RFC3339),
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
}

// FetchPushSubscriptions reads every browser Web Push registration a user has
// stored on user_device_settings.prefs.push_subscription (one per device). The
// `prefs->push_subscription=not.is.null` filter keeps the read to rows that
// actually carry a subscription so a no-push user costs a single empty fetch.
func (c *SupabaseClient) FetchPushSubscriptions(ctx context.Context, userID string) ([]PushSubscriptionRow, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("prefs->push_subscription", "not.is.null")
	q.Set("select", "device_id,sub:prefs->push_subscription")
	u := c.BaseURL + "/rest/v1/" + schema.TableUserDeviceSettings + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []struct {
		DeviceID string `json:"device_id"`
		Sub      struct {
			Endpoint string `json:"endpoint"`
			Keys     struct {
				P256dh string `json:"p256dh"`
				Auth   string `json:"auth"`
			} `json:"keys"`
		} `json:"sub"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	out := make([]PushSubscriptionRow, 0, len(rows))
	for _, r := range rows {
		if r.Sub.Endpoint == "" {
			continue // malformed registration; skip rather than crash a send
		}
		out = append(out, PushSubscriptionRow{
			DeviceID: r.DeviceID,
			Endpoint: r.Sub.Endpoint,
			P256dh:   r.Sub.Keys.P256dh,
			Auth:     r.Sub.Keys.Auth,
		})
	}
	return out, nil
}

// ClearPushSubscription removes the push_subscription key from one device's
// prefs after the push service reports the registration is dead (404/410). Goes
// through the clear_push_subscription SECURITY DEFINER RPC (migration
// 20261219_001) so the jsonb `- 'push_subscription'` minus is one atomic
// statement — PostgREST can't express a jsonb key-delete in a PATCH.
func (c *SupabaseClient) ClearPushSubscription(ctx context.Context, userID, deviceID string) error {
	return c.rpc(ctx, "clear_push_subscription", map[string]string{
		"p_user_id":   userID,
		"p_device_id": deviceID,
	}, nil)
}

// LifecycleEmailAlreadySent reports whether a (user, template) row exists in
// lifecycle_email_log — the send-once guard for transactional lifecycle mail.
func (c *SupabaseClient) LifecycleEmailAlreadySent(ctx context.Context, userID, template string) (bool, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("template", "eq."+template)
	q.Set("select", "user_id")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableLifecycleEmailLog + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return false, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return false, err
	}
	var rows []struct {
		UserID string `json:"user_id"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return false, err
	}
	return len(rows) > 0, nil
}

// RecordLifecycleEmail marks a (user, template) as sent. Idempotent — a
// duplicate insert is ignored (resolution=ignore-duplicates) so a benign
// re-record can't 409.
func (c *SupabaseClient) RecordLifecycleEmail(ctx context.Context, userID, template string) error {
	u := c.BaseURL + "/rest/v1/" + schema.TableLifecycleEmailLog
	payload, err := json.Marshal(map[string]string{"user_id": userID, "template": template})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal,resolution=ignore-duplicates")
	_, err = c.do(ctx, req)
	return err
}

// AccountDeletionReceiptAlreadySent reports whether the account-deletion
// receipt for this email hash has already been sent. The send-once guard for
// the account_deleted template lives in the non-cascading
// account_deletion_receipts table (keyed by hash, not the now-gone user_id) —
// see migration 20270217_001.
func (c *SupabaseClient) AccountDeletionReceiptAlreadySent(ctx context.Context, emailHash string) (bool, error) {
	q := url.Values{}
	q.Set("email_hash", "eq."+emailHash)
	q.Set("select", "email_hash")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableAccountDeletionReceipts + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return false, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return false, err
	}
	var rows []struct {
		EmailHash string `json:"email_hash"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return false, err
	}
	return len(rows) > 0, nil
}

// RecordAccountDeletionReceipt marks an email hash as having received the
// deletion receipt. Idempotent — a duplicate insert is ignored so a benign
// re-record can't 409.
func (c *SupabaseClient) RecordAccountDeletionReceipt(ctx context.Context, emailHash string) error {
	u := c.BaseURL + "/rest/v1/" + schema.TableAccountDeletionReceipts
	payload, err := json.Marshal(map[string]string{"email_hash": emailHash})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal,resolution=ignore-duplicates")
	_, err = c.do(ctx, req)
	return err
}

// exportTableSpec describes one personal-data table the GDPR Art 20
// export bundles: (zip entry name, PostgREST table, filter param,
// select clause). The filter param is the column the table joins on —
// almost all `user_id`, with a few owner_id / author_id / claimant_id
// exceptions.
type exportTableSpec struct {
	name   string // zip entry name (with .json suffix)
	table  string // PostgREST table
	filter string // querystring KV (e.g. "user_id=eq.<uid>")
	sel    string // select clause; "*" to include every column
}

// exportPersonalDataSpecs is the SINGLE SOURCE OF TRUTH for which
// personal-data tables the Art 20 export fetches one-row-per-table.
// `uid` must already be url.QueryEscape'd by the caller (the filter
// strings are appended to the URL verbatim, not through url.Values).
//
// personal_data_export_guard_test.go parses every migration for tables
// carrying a `user_id` column and asserts each one appears here (or in
// an explicit exclusion list) — so adding a new personal-data table to
// the schema fails the build until it is wired into this list or
// consciously excluded. Keep the shape in lockstep with the TS twin in
// apps/web/.../backup_spec.test.ts.
func exportPersonalDataSpecs(uid string) []exportTableSpec {
	uidEq := "user_id=eq." + uid
	return []exportTableSpec{
		// coach_messages — full chat transcripts with the assistant.
		// Densest single PII corpus outside GPS tracks.
		{name: "coach_messages.json", table: schema.TableCoachMessages, filter: uidEq, sel: "*"},
		// notifications — actor + target + read_at; everything that
		// landed in the user's inbox.
		{name: "notifications.json", table: schema.TableNotifications, filter: uidEq, sel: "*"},
		// training_plans (+ weeks + workouts via nested embeds).
		{
			name: "training_plans.json", table: schema.TableTrainingPlans, filter: uidEq,
			sel: "*,weeks:plan_weeks(*,workouts:plan_workouts(*))",
		},
		// integrations — fact of connection + cursor + scope +
		// disconnect timestamp/reason. Strip the secret-id columns;
		// token bodies live in vault and the subject shouldn't carry
		// them around in plaintext. `disconnected_at` +
		// `disconnected_reason` added per persona-hunt Round 3
		// finding Privacy #2 — migration `20261004_001` introduced
		// these columns and they're personal data under GDPR Art 15
		// (right of access), so the export must reflect them.
		{
			name: "integrations.json", table: schema.TableIntegrations, filter: uidEq,
			sel: "id,provider,external_id,scope,last_sync_at,sync_cursor,disconnected_at,disconnected_reason,created_at,updated_at",
		},
		// run_kudos given BY the user (the row where user_id = me).
		{name: "run_kudos.json", table: schema.TableRunKudos, filter: uidEq, sel: "*"},
		// run_comments authored by the user.
		{
			name: "run_comments.json", table: schema.TableRunComments,
			filter: "author_id=eq." + uid, sel: "*",
		},
		// run_photos metadata. The image bytes themselves are bundled
		// under `photos/` by BuildBackupZip via DownloadPhoto, keyed off
		// each row's `storage_path` (audit-findings 2026-05-30 High).
		{name: "run_photos.json", table: schema.TableRunPhotos, filter: "owner_id=eq." + uid, sel: "*"},
		// segment_efforts — performance history.
		{name: "segment_efforts.json", table: schema.TableSegmentEfforts, filter: uidEq, sel: "*"},
		// gear + run_gear — owner-private inventory + join.
		{name: "gear.json", table: schema.TableGear, filter: "owner_id=eq." + uid, sel: "*"},
		// run_gear is filled below by a two-step fetch (PostgREST
		// `in.()` takes a literal value list, not a SQL subselect —
		// the self-audit caught the malformed query that this entry
		// used to attempt). See the post-loop block.
		// fitness_snapshots — derived VDOT / VO2 / load.
		{name: "fitness_snapshots.json", table: schema.TableFitnessSnapshots, filter: uidEq, sel: "*"},
		// personal_records.
		{name: "personal_records.json", table: schema.TablePersonalRecords, filter: uidEq, sel: "*"},
		// device_tokens — redact the raw token below.
		{name: "device_tokens.json", table: schema.TableDeviceTokens, filter: uidEq, sel: "*"},
		// live_run_pings — short-TTL but in-flight rows may exist
		// when an export is taken.
		{name: "live_run_pings.json", table: schema.TableLiveRunPings, filter: uidEq, sel: "*"},
		// user_follows (both directions).
		{
			name: "following.json", table: schema.TableUserFollows,
			filter: "follower_id=eq." + uid, sel: "*",
		},
		{
			name: "followers.json", table: schema.TableUserFollows,
			filter: "followee_id=eq." + uid, sel: "*",
		},
		// event_attendees — RSVPs.
		{name: "event_attendees.json", table: schema.TableEventAttendees, filter: uidEq, sel: "*"},
		// club_members — joins.
		{name: "club_members.json", table: schema.TableClubMembers, filter: uidEq, sel: "*"},
		// saved_routes — starred-route library.
		{name: "saved_routes.json", table: schema.TableSavedRoutes, filter: uidEq, sel: "*"},
		// route_reviews authored by the user.
		{name: "route_reviews.json", table: schema.TableRouteReviews, filter: uidEq, sel: "*"},
		// route_markers — the subject's own course annotations (aid
		// stations, cutoffs, crew access, hazards, notes, climbs) dropped
		// on their saved routes. Authored content keyed by user_id = author;
		// every column is the subject's own input or geometry-derived, so
		// `*` leaks no third party. Same Art 15/20 footing as route_reviews.
		{name: "route_markers.json", table: schema.TableRouteMarkers, filter: uidEq, sel: "*"},
		// race_pings — live race GPS+HR at ~10s granularity. Personal
		// health + location data; absent before audit/data-export-
		// completeness (2026-05-25).
		{name: "race_pings.json", table: schema.TableRacePings, filter: uidEq, sel: "*"},
		// user_settings — the universal (per-user) prefs bag: privacy
		// zones, HR settings, date-of-birth, week-start, units, and
		// every other preference. The dataexport server also surfaces
		// this as `profile.json`'s `settings_prefs` field via the
		// separate FetchUserSettingsPrefs call, but the EF rollback
		// path has no profile.json — so the spec list now carries
		// user_settings too, keeping both export paths in lockstep and
		// giving the subject a self-describing `user_settings.json`.
		// It's the subject's own data, so the full prefs ship
		// unredacted. persona round-5 privacy / GDPR Art 20.
		{name: "user_settings.json", table: schema.TableUserSettings, filter: uidEq, sel: "*"},
		// user_device_settings — per-device behavioural prefs +
		// last-seen-at. Distinct from user_settings (the per-user bag
		// above). Added per audit/data-export-completeness
		// (2026-05-25).
		{name: "user_device_settings.json", table: schema.TableUserDeviceSettings, filter: uidEq, sel: "*"},
		// user_coach_usage — daily message_count behavioural log.
		// Small but personal; added per audit/data-export-completeness
		// (2026-05-25).
		{name: "user_coach_usage.json", table: schema.TableUserCoachUsage, filter: uidEq, sel: "*"},
		// reports authored by the user (subject's own report history).
		// reporter_id is the user; target rows belong to others and are
		// out of scope of THIS subject's export.
		{
			name: "reports.json", table: schema.TableReports,
			filter: "reporter_id=eq." + uid, sel: "*",
		},
		// reports filed AGAINST the user (target_kind='user'). GDPR
		// Art 15(1)(c) gives the data subject the right to know
		// recipients of their data, including moderation actions
		// taken against them. We project a narrow column set —
		// reporter_id is anonymised (competing rights under Art 15(4))
		// while existence + reason + status disclose the action.
		// audit/data-export-completeness May 2026 Low closeout.
		{
			name:   "reports_against_me.json",
			table:  "reports",
			filter: "target_kind=eq.user&target_id=eq." + uid,
			sel:    "id,target_kind,target_id,reason,status,notes,created_at,resolved_at",
		},
		// direct_messages — private 1:1 conversations, both directions
		// (messages the user sent and messages they received). `body`
		// ships verbatim: it is the subject's own correspondence.
		// audit/data-export-completeness (2026-05-30) Critical.
		{
			name: "direct_messages_sent.json", table: schema.TableDirectMessages,
			filter: "sender_id=eq." + uid, sel: "*",
		},
		{
			name: "direct_messages_received.json", table: schema.TableDirectMessages,
			filter: "recipient_id=eq." + uid, sel: "*",
		},
		// coach_athletes — the subject's coaching relationships, as coach
		// and as athlete. `invite_token` is a redeemable credential
		// (anyone holding it can claim the link), so the projection omits
		// it — same rationale as integrations' vault columns.
		// audit/data-export-completeness (2026-05-30) Critical.
		{
			name: "coaching_as_coach.json", table: schema.TableCoachAthletes,
			filter: "coach_id=eq." + uid,
			sel:    "id,coach_id,athlete_id,status,note,created_at,accepted_at,ended_at",
		},
		{
			name: "coaching_as_athlete.json", table: schema.TableCoachAthletes,
			filter: "athlete_id=eq." + uid,
			sel:    "id,coach_id,athlete_id,status,note,created_at,accepted_at,ended_at",
		},
		// event_results — the subject's own race finish records (time,
		// rank, DNF/DNS, age-grade). Health-adjacent performance data.
		// audit/data-export-completeness (2026-05-30) Critical.
		{name: "event_results.json", table: schema.TableEventResults, filter: uidEq, sel: "*"},
		// checkpoint_crossings — the subject's own race-checkpoint timing
		// (in/out times) and, where a checkpoint weighs runners in, their
		// Art 9 weigh-in body weight + medical hold/note. Recorded by a race
		// official ABOUT the subject during their participation — same Art
		// 15/20 footing as event_results / race_pings, and the subject is
		// unconditionally entitled to their OWN health data. Filtered to the
		// subject's account rows (user_id = me); bib-only crossings have no
		// account to attach to. Projection omits `recorded_by` — that is the
		// official who logged the crossing, a third-party uid we must not
		// leak to the subject (mirrors the integrations secret-id strip).
		{
			name: "checkpoint_crossings.json", table: schema.TableCheckpointCrossings, filter: uidEq,
			sel: "id,event_id,checkpoint_id,instance_start,user_id,bib,runner_name,in_time,out_time,body_weight_kg,body_weight_pct,medical_hold,medical_note,recorded_at,updated_at",
		},
		// event_result_claims — the subject's own "this result is me"
		// claims (status + decision). `decided_by` belongs to the
		// organiser who ruled on it, so the projection keeps it (it's a
		// recipient disclosure under Art 15(1)(c)) but the filter is the
		// subject's claimant_id. audit-findings (2026-05-30) High.
		{
			name: "event_result_claims.json", table: schema.TableEventResultClaims,
			filter: "claimant_id=eq." + uid, sel: "*",
		},
		// user_blocks — the subject's own block list (who they blocked +
		// why). audit-findings (2026-05-30) High.
		{
			name: "user_blocks.json", table: schema.TableUserBlocks,
			filter: "blocker_id=eq." + uid, sel: "*",
		},
		// club_posts — club-feed posts the subject authored.
		// audit-findings (2026-05-30) High.
		{
			name: "club_posts.json", table: schema.TableClubPosts,
			filter: "author_id=eq." + uid, sel: "*",
		},
		// event_exceptions — recurring-event instance cancellations the
		// subject made (cancelled_by + reason). audit-findings
		// (2026-05-30) High.
		{
			name: "event_exceptions.json", table: schema.TableEventExceptions,
			filter: "cancelled_by=eq." + uid, sel: "*",
		},
		// gym_workouts (+ sets via nested embed). Phase 4 multi-modal
		// strength-training log (migration 20261204_001). gym_sets has
		// no user_id of its own — it cascades from the parent workout —
		// so the export nests each workout's sets inside its row, the
		// same shape training_plans uses for plan_weeks / plan_workouts.
		// audit/data-export-completeness gym/nutrition gap.
		{
			name: "gym_workouts.json", table: schema.TableGymWorkouts, filter: uidEq,
			sel: "*,sets:gym_sets(*)",
		},
		// gym_routines (+ exercises + their planned sets via nested embeds).
		// The gym-programming P1 reusable plan (migration 20270101_001).
		// Author-scoped (NOT user_id), so the export-completeness guard's
		// user_id-column scan can't flag it — it is wired in explicitly.
		// gym_routine_exercises / gym_routine_sets have no user_id of their
		// own (they cascade from the parent routine), so the export nests
		// them, mirroring the training_plans + gym_workouts embeds. Keep the
		// shape in lockstep with the TS twin in backup_spec.ts.
		// gym_programming.md § DSAR export.
		{
			name: "gym_routines.json", table: schema.TableGymRoutines,
			filter: "author_id=eq." + uid,
			sel:    "*,exercises:gym_routine_exercises(*,sets:gym_routine_sets(*))",
		},
		// food_log — Phase 4 nutrition diary (per-item calories + macros,
		// migration 20261204_001). Owner-scoped personal data the subject
		// has an Art 20 right to receive.
		{name: "food_log.json", table: schema.TableFoodLog, filter: uidEq, sel: "*"},
		// body_metrics — Phase 4 nutrition weight time-series (migration
		// 20261216_001). GDPR special-category health data; owner-scoped and
		// squarely within the Art 20 right to receive. height_cm lives on
		// user_profiles and ships in that export entry.
		{name: "body_metrics.json", table: schema.TableBodyMetrics, filter: uidEq, sel: "*"},
		// instructor_payout_accounts — the host's Stripe Connect payout-account
		// metadata (migration for the club_events.md paid-registration rail).
		// The subject's own data under Art 15: their connected-account
		// reference (`stripe_connect_account_id`, an `acct_…` id — a reference,
		// not a secret key) + the onboarding/capability status flags Stripe
		// mirrors back. There is no Stripe secret/API key stored on this row, so
		// the select carries every column (`*`): status flags + country +
		// default_currency + onboarded_at are all the subject's own data.
		{name: "instructor_payout_accounts.json", table: schema.TableInstructorPayoutAccounts, filter: uidEq, sel: "*"},
		// safety_contacts — the opt-in finish-alert relationships
		// (migration 20261218_001). The subject is on BOTH legs: rows they
		// OWN (owner_id — the contacts they designated) and rows where they
		// are the designated contact (contact_user_id, set once they confirm
		// in-app). Both are the subject's own personal data under Art 20.
		// The guard's `user_id`-keyed scan can't see this table (it uses
		// owner_id / contact_user_id), so it is wired in explicitly.
		// `confirm_token` is a capability credential — anyone holding it can
		// confirm the contact via confirm_safety_contact_by_token — so the
		// narrow select omits it, mirroring coach_athletes' invite_token and
		// integrations' vault columns.
		{
			name: "safety_contacts_owned.json", table: schema.TableSafetyContacts,
			filter: "owner_id=eq." + uid,
			sel:    "id,owner_id,contact_user_id,contact_email,confirmed_at,created_at,updated_at",
		},
		{
			name: "safety_contacts_as_contact.json", table: schema.TableSafetyContacts,
			filter: "contact_user_id=eq." + uid,
			sel:    "id,owner_id,contact_user_id,contact_email,confirmed_at,created_at,updated_at",
		},
	}
}

// FetchExportPersonalDataTables bundles the personal-data tables
// the audit/data-export-completeness (May 2026) pass added to the
// Art 20 export. One call per table; failures on individual tables
// are tolerated (the table is omitted from the result rather than
// failing the whole export) so a single missing migration or
// rename doesn't strand the user's data.
//
// `device_tokens.token` is redacted to "<redacted>" — the bare
// FCM/APNs token is server-managed credential material and isn't
// useful to the subject in an export.
//
// `integrations.access_token` / `refresh_token` columns aren't
// fetched at all (column projection scrubs them).
//
// Return-value convention: empty table => key absent. The backup
// builder treats an absent key the same as a zero-row entry so the
// zip stays small.
func (c *SupabaseClient) FetchExportPersonalDataTables(
	ctx context.Context,
	userID string,
) (map[string][]map[string]interface{}, error) {
	// Each spec is (zip entry name, table, filter param, select clause).
	// The filter param is the column the table joins on; almost all are
	// `user_id`, with a few exceptions (run_comments, run_kudos use
	// `author_id`/`user_id` against the runs the user authored; we use
	// the simple `user_id`-equivalent for these).
	// The filter is appended to the URL verbatim below (unlike `select`,
	// which goes through url.Values), so the value must be encoded here.
	// QueryEscape renders space as `+`, which PostgREST decodes back to
	// space — functionally identical to the EF for any DB lookup.
	// audit-findings 2026-05-30 Medium.
	uid := url.QueryEscape(userID)
	specs := exportPersonalDataSpecs(uid)

	out := make(map[string][]map[string]interface{}, len(specs))
	for _, s := range specs {
		q := url.Values{}
		// `filter` is a pre-built KV like `user_id=eq.<uid>` or with
		// the `in.(select ...)` form — pass through verbatim.
		q.Set("select", s.sel)
		// Strip the explicit user-id filter from `q` since it's
		// already in the raw filter param; append the filter at the
		// end of the URL string instead of through url.Values so
		// nested-query commas aren't escaped.
		u := c.BaseURL + "/rest/v1/" + s.table + "?" + q.Encode() + "&" + s.filter
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			// A single table failing is logged + skipped; the rest
			// of the export still ships. Falls through the loop's
			// error swallow below.
			continue
		}
		body, err := c.do(ctx, req)
		if err != nil {
			// Tolerate per-table failure; the audit notes "partial
			// export with a manifest count" is better than no
			// export.
			continue
		}
		var rows []map[string]interface{}
		if err := json.Unmarshal(body, &rows); err != nil {
			continue
		}
		if len(rows) == 0 {
			continue
		}
		// device_tokens.token is server-managed credential material
		// and shouldn't ship in a portability export. Redact it.
		if s.name == "device_tokens.json" {
			for _, row := range rows {
				if _, ok := row["token"]; ok {
					row["token"] = "<redacted>"
				}
			}
		}
		out[s.name] = rows
	}

	// jobs summary — GDPR Art 15(1) right-to-know, audit/data-export-
	// completeness May 2026 Medium. The `jobs` table holds the user's
	// UUID inside payload jsonb (`payload->>user_id`). Disclosing the
	// raw payload would leak internal retry state + worker timing
	// details; the audit's preferred shape is a count-by-kind summary.
	//
	// Fetch the kind column only via PostgREST jsonb path filter, then
	// group + count in Go. Failure to fetch is tolerated as with every
	// other table — the rest of the export still ships.
	{
		jq := url.Values{}
		jq.Set("select", "kind")
		u := c.BaseURL + "/rest/v1/" + schema.TableJobs + "?" + jq.Encode() +
			"&payload->>user_id=eq." + uid
		if req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil); err == nil {
			if body, err := c.do(ctx, req); err == nil {
				var rows []struct {
					Kind string `json:"kind"`
				}
				if json.Unmarshal(body, &rows) == nil && len(rows) > 0 {
					counts := make(map[string]int, len(rows))
					for _, r := range rows {
						counts[r.Kind]++
					}
					summary := make([]map[string]interface{}, 0, len(counts))
					for kind, n := range counts {
						summary = append(summary, map[string]interface{}{
							"kind":  kind,
							"count": n,
						})
					}
					if len(summary) > 0 {
						out["jobs_summary.json"] = summary
					}
				}
			}
		}
	}

	// Two-step fetch for run_gear: PostgREST's `in.()` filter takes
	// a comma-separated value list, not a SQL subselect. Pull the
	// user's gear ids first, then filter run_gear by that list. A
	// runner with hundreds of pieces of gear is unlikely, so a
	// single id-list filter is fine; if it ever grows past
	// PostgREST's URL length cap, page through it.
	if gearRows, ok := out["gear.json"]; ok && len(gearRows) > 0 {
		ids := make([]string, 0, len(gearRows))
		for _, g := range gearRows {
			if id, ok := g["id"].(string); ok && id != "" {
				ids = append(ids, id)
			}
		}
		if len(ids) > 0 {
			// Build the `in.(uuid1,uuid2,...)` value list. UUIDs
			// don't need URL-encoding but join with commas only.
			q := url.Values{}
			q.Set("select", "*")
			u := c.BaseURL + "/rest/v1/" + schema.TableRunGear + "?" + q.Encode() +
				"&gear_id=in.(" + strings.Join(ids, ",") + ")"
			req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
			if err == nil {
				if body, err := c.do(ctx, req); err == nil {
					var rows []map[string]interface{}
					if err := json.Unmarshal(body, &rows); err == nil && len(rows) > 0 {
						out["run_gear.json"] = rows
					}
				}
			}
		}
	}

	return out, nil
}

// DownloadRawTrackBytes pulls the **gzipped** bytes from Storage
// without decoding. Sibling of DownloadTrack which decompresses +
// JSON-parses to TrackPoint[]; the backup format archives tracks
// in their on-disk `.json.gz` form so restore is a byte-for-byte
// upload.
func (c *SupabaseClient) DownloadRawTrackBytes(ctx context.Context, path string) ([]byte, error) {
	u := c.BaseURL + "/storage/v1/object/" + schema.BucketRuns + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	return c.do(ctx, req)
}

// FetchUserSubscriptionTier reads the `subscription_tier` column on
// `user_profiles`. Returns "free" when no row exists (a user that
// hasn't completed onboarding); otherwise returns the value
// verbatim — the caller decides whether it counts as Pro.
func (c *SupabaseClient) FetchUserSubscriptionTier(ctx context.Context, userID string) (string, error) {
	q := url.Values{}
	q.Set("id", "eq."+userID)
	q.Set("select", "subscription_tier")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableUserProfiles + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return "", err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return "", err
	}
	var rows []struct {
		Tier string `json:"subscription_tier"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return "", err
	}
	if len(rows) == 0 || rows[0].Tier == "" {
		return "free", nil
	}
	return rows[0].Tier, nil
}

// FetchPremiumRuns reads the projection the Pro endpoints need
// (started_at + distance + duration + metadata). Service role.
// Ordered most-recent first, capped at limit, filtered to runs
// since `since` when non-zero.
func (c *SupabaseClient) FetchPremiumRuns(ctx context.Context, userID string, since time.Time, limit int) ([]premiumRunRow, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("select", "started_at,distance_m,duration_s,activity_type,metadata")
	q.Set("order", "started_at.desc")
	q.Set("limit", strconv.Itoa(limit))
	if !since.IsZero() {
		q.Set("started_at", "gte."+since.UTC().Format(time.RFC3339))
	}
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []premiumRunRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	return rows, nil
}

// premiumRunRow mirrors premium.PremiumRun. Keeping it in `internal`
// avoids importing `premium` and creating a cycle; the adapter in
// main.go translates across.
type premiumRunRow struct {
	StartedAt    string                 `json:"started_at"`
	DistanceM    float64                `json:"distance_m"`
	DurationS    int                    `json:"duration_s"`
	ActivityType string                 `json:"activity_type"`
	Metadata     map[string]interface{} `json:"metadata"`
}

// ─────────────────── weekly digest (engagement, gated) ───────────────────

// IsEmailSuppressed reports whether an address is on the hard-block list
// (bounce / complaint / explicit unsubscribe — migration 20270108_001).
// The digest builder + handler MUST consult this before any send. Service
// role bypasses the fail-closed RLS (no policy → anon/authenticated denied;
// the worker is the sole reader/writer). An empty address is treated as
// suppressed (can't send to nothing) so a missing-email path never sends.
func (c *SupabaseClient) IsEmailSuppressed(ctx context.Context, email string) (bool, error) {
	if email == "" {
		return true, nil
	}
	q := url.Values{}
	// email is the table's primary key; an exact match is the lookup.
	q.Set("email", "eq."+email)
	q.Set("select", "email")
	q.Set("limit", "1")
	u := c.BaseURL + "/rest/v1/" + schema.TableEmailSuppressions + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return false, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return false, err
	}
	var rows []struct {
		Email string `json:"email"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return false, err
	}
	return len(rows) > 0, nil
}

// InsertEmailSuppression adds an address to the hard-block list with the
// given reason ('bounce' | 'complaint' | 'unsubscribe' | 'manual'). Used by
// the unsubscribe endpoint (reason 'unsubscribe') and, later, the provider
// bounce/complaint webhook. Idempotent: a 23505 on the email primary key
// (already suppressed) is swallowed as success — re-unsubscribing is a no-op,
// not an error.
func (c *SupabaseClient) InsertEmailSuppression(ctx context.Context, email, reason string) error {
	body, err := json.Marshal(map[string]any{"email": email, "reason": reason})
	if err != nil {
		return err
	}
	u := c.BaseURL + "/rest/v1/" + schema.TableEmailSuppressions
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	if err == nil {
		return nil
	}
	var hErr *HTTPError
	if errors.As(err, &hErr) && hErr.StatusCode == http.StatusConflict && strings.Contains(hErr.Body, "23505") {
		return nil // already suppressed — idempotent
	}
	return err
}

// SetWeeklyDigestPrefOff flips the recipient's opt-in pref to 'off' in
// user_settings.prefs, via the merge-aware `set_user_setting` RPC if present.
// We instead PATCH the jsonb key directly with `prefs = prefs || '{...}'`
// using a PostgREST jsonb merge so the rest of the bag is preserved. Service
// role bypasses RLS. Used by the unsubscribe endpoint alongside the
// suppression insert (belt-and-braces: pref off AND address blocked).
func (c *SupabaseClient) SetWeeklyDigestPrefOff(ctx context.Context, userID string) error {
	// PostgREST can't express `prefs = prefs || jsonb` in a PATCH body, so
	// read-merge-write: fetch the current bag, set the one key, write it back.
	prefs, err := c.FetchUserSettingsPrefs(ctx, userID)
	if err != nil {
		return err
	}
	if prefs == nil {
		prefs = map[string]interface{}{}
	}
	prefs[schema.PrefsEmailWeeklyDigest] = "off"
	payload, err := json.Marshal(map[string]any{
		"user_id": userID,
		"prefs":   prefs,
	})
	if err != nil {
		return err
	}
	// Upsert on the user_id conflict target so a user with no settings row
	// yet still gets one with the digest explicitly off.
	u := c.BaseURL + "/rest/v1/" + schema.TableUserSettings + "?on_conflict=user_id"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "resolution=merge-duplicates,return=minimal")
	_, err = c.do(ctx, req)
	return err
}

// BuildWeeklyDigest assembles the bounded per-user weekly summary the digest
// handler renders. `since` is the 7-day window start. Each field is a small
// windowed read over an existing table — no track downloads, no fan-out:
//   - runs:                count + distance sum over runs.started_at >= since
//   - kudos received:      notifications kind=kudos for the user, created_at >= since
//   - new PBs:             personal_records achieved_at >= since
//
// Service role bypasses RLS; the userID filter is the access gate.
func (c *SupabaseClient) BuildWeeklyDigest(ctx context.Context, userID string, since time.Time) (DigestSummary, error) {
	var out DigestSummary
	cutoff := since.UTC().Format(time.RFC3339)

	// Runs in the window: distance_m only, summed in Go. A week of runs is
	// bounded (a serious ultrarunner logs a handful), so reading the rows is
	// cheaper than a custom aggregate RPC.
	runsQ := url.Values{}
	runsQ.Set("user_id", "eq."+userID)
	runsQ.Set("started_at", "gte."+cutoff)
	runsQ.Set("select", "distance_m")
	runsQ.Set("limit", "1000")
	runsURL := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + runsQ.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, runsURL, nil)
	if err != nil {
		return out, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return out, err
	}
	var runRows []struct {
		DistanceM float64 `json:"distance_m"`
	}
	if err := json.Unmarshal(body, &runRows); err != nil {
		return out, err
	}
	out.RunCount = len(runRows)
	for _, r := range runRows {
		out.DistanceM += r.DistanceM
	}

	// Kudos received this week — count of notifications of kind 'kudos'.
	kudosQ := url.Values{}
	kudosQ.Set("user_id", "eq."+userID)
	kudosQ.Set("kind", "eq.kudos")
	kudosQ.Set("created_at", "gte."+cutoff)
	kudosQ.Set("select", "id")
	kudosQ.Set("limit", "1000")
	kudosURL := c.BaseURL + "/rest/v1/" + schema.TableNotifications + "?" + kudosQ.Encode()
	kReq, err := http.NewRequestWithContext(ctx, http.MethodGet, kudosURL, nil)
	if err != nil {
		return out, err
	}
	kBody, err := c.do(ctx, kReq)
	if err != nil {
		return out, err
	}
	var kRows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(kBody, &kRows); err != nil {
		return out, err
	}
	out.KudosCount = len(kRows)

	// New PBs this week — personal_records achieved in the window.
	prQ := url.Values{}
	prQ.Set("user_id", "eq."+userID)
	prQ.Set("achieved_at", "gte."+cutoff)
	prQ.Set("select", "distance")
	prQ.Set("limit", "1000")
	prURL := c.BaseURL + "/rest/v1/" + schema.TablePersonalRecords + "?" + prQ.Encode()
	prReq, err := http.NewRequestWithContext(ctx, http.MethodGet, prURL, nil)
	if err != nil {
		return out, err
	}
	prBody, err := c.do(ctx, prReq)
	if err != nil {
		return out, err
	}
	var prRows []struct {
		Distance string `json:"distance"`
	}
	if err := json.Unmarshal(prBody, &prRows); err != nil {
		return out, err
	}
	out.NewPBs = len(prRows)

	return out, nil
}

// FetchDigestCandidates returns the user ids that have opted IN to the weekly
// digest (user_settings.prefs.email_weekly_digest = 'on'). This is the
// builder's selection step — it enqueues one weekly_digest job per id. The
// per-recipient suppression + pref re-check happens again in the handler
// (defence in depth: the pref could flip, or the address could land on the
// suppression list, between enqueue and send). Bounded at `limit`.
//
// The pref lives in a jsonb bag, so the filter is a PostgREST jsonb path
// equality: `prefs->>email_weekly_digest=eq.on`.
func (c *SupabaseClient) FetchDigestCandidates(ctx context.Context, limit int) ([]string, error) {
	q := url.Values{}
	q.Set("prefs->>"+schema.PrefsEmailWeeklyDigest, "eq.on")
	q.Set("select", "user_id")
	q.Set("limit", strconv.Itoa(limit))
	u := c.BaseURL + "/rest/v1/" + schema.TableUserSettings + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []struct {
		UserID string `json:"user_id"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	out := make([]string, 0, len(rows))
	for _, r := range rows {
		out = append(out, r.UserID)
	}
	return out, nil
}

// EnqueueWeeklyDigests bulk-inserts `kind='weekly_digest'` jobs, one row
// per recipient, in a single PostgREST request (a JSON-array body is a
// bulk insert). Called by the digest builder in chunks. The CHECK on
// jobs.kind (migration 20270108_001) gates the insert; an out-of-allowlist
// kind would 23514. An empty slice is a no-op (no request issued).
func (c *SupabaseClient) EnqueueWeeklyDigests(ctx context.Context, userIDs []string) error {
	if len(userIDs) == 0 {
		return nil
	}
	rows := make([]map[string]any, len(userIDs))
	for i, uid := range userIDs {
		rows[i] = map[string]any{
			"kind":    "weekly_digest",
			"payload": map[string]any{"user_id": uid},
		}
	}
	body, err := json.Marshal(rows)
	if err != nil {
		return err
	}
	u := c.BaseURL + "/rest/v1/" + schema.TableJobs
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
}
