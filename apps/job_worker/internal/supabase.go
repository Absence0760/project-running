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
func (c *SupabaseClient) DeferJob(ctx context.Context, jobID int64, delaySeconds int, errMsg *string) error {
	params := map[string]any{
		"job_id":        jobID,
		"delay_seconds": delaySeconds,
		"err":           errMsg,
	}
	return c.rpc(ctx, "defer_job", params, nil)
}

// DownloadTrack fetches a gzipped track from the runs Storage bucket
// and decompresses it into a TrackPoint slice. Path is the value stored
// in runs.track_url — `{user_id}/{run_id}.json.gz`.
func (c *SupabaseClient) DownloadTrack(ctx context.Context, path string) ([]TrackPoint, error) {
	url := c.BaseURL + "/storage/v1/object/runs/" + path
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

	url := c.BaseURL + "/storage/v1/object/runs/" + path
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
	url := c.BaseURL + "/storage/v1/object/run-photos/" + path
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
	url := c.BaseURL + "/storage/v1/object/run-photos/" + path
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
	url := c.BaseURL + "/rest/v1/run_photos?id=eq." + photoID
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
	endpoint := c.BaseURL + "/rest/v1/run_matched_tracks?" + q
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
	url := c.BaseURL + "/rest/v1/runs?id=eq." + runID + "&select=track_url"
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
	url := c.BaseURL + "/rest/v1/runs?id=eq." + runID + "&select=route_id,distance_m"
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
	url := c.BaseURL + "/rest/v1/runs?id=eq." + runID
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
	u := c.BaseURL + "/rest/v1/integrations?" + q.Encode()
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
	u := c.BaseURL + "/rest/v1/integrations?" + q.Encode()
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
	u := c.BaseURL + "/rest/v1/integrations?" + q.Encode()
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
	u := c.BaseURL + "/rest/v1/runs?" + q.Encode()
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

// InsertStravaRun inserts a runs row sourced from a Strava activity.
// Mirrors the EF `ingestActivity` row shape (apps/backend/supabase/
// functions/_shared/strava.ts) — fields, source='strava', metadata
// keys all in lockstep so dashboard queries that read across both
// writers see one consistent shape.
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
		"strava_id":            stravaIDStr,
		"activity_type":        activityType,
		"imported_from":        "strava",
		"imported_at":          time.Now().UTC().Format(time.RFC3339),
		"strava_activity_type": act.Type,
	}
	if act.AverageHeartrate > 0 {
		metadata["avg_bpm"] = int(math.Round(act.AverageHeartrate))
	}
	if act.Name != "" {
		metadata["title"] = act.Name
	}
	if act.TotalElevationGain != 0 {
		metadata["elevation_m"] = int(math.Round(act.TotalElevationGain))
	}

	duration := act.MovingTime
	if duration == 0 {
		duration = act.ElapsedTime
	}

	row := map[string]any{
		"user_id":    userID,
		"started_at": act.StartDate,
		"distance_m": int(math.Round(act.Distance)),
		"duration_s": duration,
		"source":     "strava",
		// `external_id = 'strava:<id>'` is the cross-source dedupe key
		// — same shape mobile ZIP writes. /audit/strava M3.
		"external_id": "strava:" + stravaIDStr,
		"metadata":    metadata,
	}
	payload, err := json.Marshal(row)
	if err != nil {
		return nil, err
	}
	u := c.BaseURL + "/rest/v1/runs"
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
	u := c.BaseURL + "/rest/v1/runs?id=eq." + runID
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
	u := c.BaseURL + "/rest/v1/webhook_events"
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
	u := c.BaseURL + "/rest/v1/webhook_events?" + q.Encode()
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
	u := c.BaseURL + "/rest/v1/jobs"
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
		"id,user_id,started_at,duration_s,distance_m,source,external_id,metadata,track_url,is_public,event_id,route_id,created_at,updated_at")
	q.Set("order", "started_at.desc")
	q.Set("limit", strconv.Itoa(limit))
	u := c.BaseURL + "/rest/v1/runs?" + q.Encode()
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

// UploadExportArtifact stores the assembled CSV / GPX-zip body to
// the `runs` bucket. `upsert=false` so a duplicate path doesn't
// stomp on an existing export (the caller picks a ms-precision
// timestamped path).
func (c *SupabaseClient) UploadExportArtifact(ctx context.Context, path, contentType string, body []byte) error {
	u := c.BaseURL + "/storage/v1/object/runs/" + path
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
	u := c.BaseURL + "/storage/v1/object/sign/runs/" + path
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
	u := c.BaseURL + "/rest/v1/routes?" + q.Encode()
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
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Waypoints   interface{}            `json:"waypoints"`
	DistanceM   *float64               `json:"distance_m,omitempty"`
	ElevationM  *float64               `json:"elevation_m,omitempty"`
	Surface     *string                `json:"surface,omitempty"`
	IsPublic    *bool                  `json:"is_public,omitempty"`
	Slug        *string                `json:"slug,omitempty"`
	Tags        []string               `json:"tags,omitempty"`
	Featured    *bool                  `json:"featured,omitempty"`
	RunCount    *int                   `json:"run_count,omitempty"`
	IsStarred   *bool                  `json:"is_starred,omitempty"`
	Description *string                `json:"description,omitempty"`
	ClubID      *string                `json:"club_id,omitempty"`
	CreatedAt   *string                `json:"created_at,omitempty"`
	UpdatedAt   *string                `json:"updated_at,omitempty"`
}

// FetchExportProfile reads the user's profile via the
// `get_my_profile` SECURITY DEFINER RPC. Column-level revokes on
// `subscription_tier` / `parkrun_number` / `subscription_at`
// (migration 20260707_001) require this path rather than a direct
// table select. Returns nil + nil when no row exists yet.
func (c *SupabaseClient) FetchExportProfile(ctx context.Context, userID string) (map[string]interface{}, error) {
	// `get_my_profile` reads `auth.uid()` from the JWT; service-role
	// has no auth.uid() so we pass `p_user_id` for the explicit
	// path. Schema: the function signature is `get_my_profile()` —
	// **but** for service-role we need to read directly since the
	// RPC trusts JWT claims. Fall back to a direct select that
	// excludes the column-restricted fields the export doesn't need.
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
	u := c.BaseURL + "/rest/v1/user_profiles?" + q.Encode()
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
	u := c.BaseURL + "/rest/v1/user_settings?" + q.Encode()
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
	type spec struct {
		name   string // zip entry name (with .json suffix)
		table  string // PostgREST table
		filter string // querystring KV (e.g. "user_id=eq.<uid>")
		sel    string // select clause; "*" to include every column
	}
	uidEq := "user_id=eq." + userID
	specs := []spec{
		// coach_messages — full chat transcripts with the assistant.
		// Densest single PII corpus outside GPS tracks.
		{name: "coach_messages.json", table: "coach_messages", filter: uidEq, sel: "*"},
		// notifications — actor + target + read_at; everything that
		// landed in the user's inbox.
		{name: "notifications.json", table: "notifications", filter: uidEq, sel: "*"},
		// training_plans (+ weeks + workouts via nested embeds).
		{
			name: "training_plans.json", table: "training_plans", filter: uidEq,
			sel: "*,weeks:plan_weeks(*,workouts:plan_workouts(*))",
		},
		// integrations — fact of connection + cursor + scope. Strip
		// the secret-id columns; token bodies live in vault and the
		// subject shouldn't carry them around in plaintext.
		{
			name: "integrations.json", table: "integrations", filter: uidEq,
			sel: "id,provider,external_id,scope,last_sync_at,sync_cursor,created_at,updated_at",
		},
		// run_kudos given BY the user (the row where user_id = me).
		{name: "run_kudos.json", table: "run_kudos", filter: uidEq, sel: "*"},
		// run_comments authored by the user.
		{
			name: "run_comments.json", table: "run_comments",
			filter: "author_id=eq." + userID, sel: "*",
		},
		// run_photos metadata. Storage objects are deferred (see
		// audit Medium re: run-photos bucket walk).
		{name: "run_photos.json", table: "run_photos", filter: "owner_id=eq." + userID, sel: "*"},
		// segment_efforts — performance history.
		{name: "segment_efforts.json", table: "segment_efforts", filter: uidEq, sel: "*"},
		// gear + run_gear — owner-private inventory + join.
		{name: "gear.json", table: "gear", filter: "owner_id=eq." + userID, sel: "*"},
		// run_gear is filled below by a two-step fetch (PostgREST
		// `in.()` takes a literal value list, not a SQL subselect —
		// the self-audit caught the malformed query that this entry
		// used to attempt). See the post-loop block.
		// fitness_snapshots — derived VDOT / VO2 / load.
		{name: "fitness_snapshots.json", table: "fitness_snapshots", filter: uidEq, sel: "*"},
		// personal_records.
		{name: "personal_records.json", table: "personal_records", filter: uidEq, sel: "*"},
		// device_tokens — redact the raw token below.
		{name: "device_tokens.json", table: "device_tokens", filter: uidEq, sel: "*"},
		// live_run_pings — short-TTL but in-flight rows may exist
		// when an export is taken.
		{name: "live_run_pings.json", table: "live_run_pings", filter: uidEq, sel: "*"},
		// user_follows (both directions).
		{
			name: "following.json", table: "user_follows",
			filter: "follower_id=eq." + userID, sel: "*",
		},
		{
			name: "followers.json", table: "user_follows",
			filter: "followee_id=eq." + userID, sel: "*",
		},
		// event_attendees — RSVPs.
		{name: "event_attendees.json", table: "event_attendees", filter: uidEq, sel: "*"},
		// club_members — joins.
		{name: "club_members.json", table: "club_members", filter: uidEq, sel: "*"},
		// saved_routes — starred-route library.
		{name: "saved_routes.json", table: "saved_routes", filter: uidEq, sel: "*"},
		// route_reviews authored by the user.
		{name: "route_reviews.json", table: "route_reviews", filter: uidEq, sel: "*"},
		// race_pings — live race GPS+HR at ~10s granularity. Personal
		// health + location data; absent before audit/data-export-
		// completeness (2026-05-25).
		{name: "race_pings.json", table: "race_pings", filter: uidEq, sel: "*"},
		// user_device_settings — per-device behavioural prefs +
		// last-seen-at. Distinct from user_settings.prefs (in the
		// manifest already). Added per audit/data-export-completeness
		// (2026-05-25).
		{name: "user_device_settings.json", table: "user_device_settings", filter: uidEq, sel: "*"},
		// user_coach_usage — daily message_count behavioural log.
		// Small but personal; added per audit/data-export-completeness
		// (2026-05-25).
		{name: "user_coach_usage.json", table: "user_coach_usage", filter: uidEq, sel: "*"},
		// reports authored by the user (subject's own report history).
		// reporter_id is the user; target rows belong to others and are
		// out of scope of THIS subject's export.
		{
			name: "reports.json", table: "reports",
			filter: "reporter_id=eq." + userID, sel: "*",
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
			filter: "target_kind=eq.user&target_id=eq." + userID,
			sel:    "id,target_kind,target_id,reason,status,notes,created_at,resolved_at",
		},
	}

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
		u := c.BaseURL + "/rest/v1/jobs?" + jq.Encode() +
			"&payload->>user_id=eq." + userID
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
			u := c.BaseURL + "/rest/v1/run_gear?" + q.Encode() +
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
	u := c.BaseURL + "/storage/v1/object/runs/" + path
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
	u := c.BaseURL + "/rest/v1/user_profiles?" + q.Encode()
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
	q.Set("select", "started_at,distance_m,duration_s,metadata")
	q.Set("order", "started_at.desc")
	q.Set("limit", strconv.Itoa(limit))
	if !since.IsZero() {
		q.Set("started_at", "gte."+since.UTC().Format(time.RFC3339))
	}
	u := c.BaseURL + "/rest/v1/runs?" + q.Encode()
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
	StartedAt string                 `json:"started_at"`
	DistanceM float64                `json:"distance_m"`
	DurationS int                    `json:"duration_s"`
	Metadata  map[string]interface{} `json:"metadata"`
}
