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
	"net/http"
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
func (c *SupabaseClient) ClaimNextJob(ctx context.Context, workerID, kindFilter string) (*Job, error) {
	params := map[string]any{
		"worker_id":   workerID,
		"kind_filter": kindFilter,
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

// UpdateMatchedTrackRow PATCHes the run_matched_tracks row with the
// match output. Service role bypasses RLS so the standard PostgREST
// surface works without going through a definer function.
func (c *SupabaseClient) UpdateMatchedTrackRow(ctx context.Context, runID string, row MatchedTrackRow) error {
	payload, err := json.Marshal(row)
	if err != nil {
		return err
	}
	url := c.BaseURL + "/rest/v1/run_matched_tracks?run_id=eq." + runID
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	_, err = c.do(ctx, req)
	return err
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
