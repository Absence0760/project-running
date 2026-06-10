package internal

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// StravaClient is the worker's view of Strava's OAuth endpoint. The
// only call we make is `/oauth/token` with `grant_type=refresh_token`
// — the rest of Strava's API (activity ingest etc.) is the responsibility
// of the strava-webhook / strava-import paths.
//
// BaseURL is configurable so tests can point at a httptest.Server.
// Empty string → `https://www.strava.com`.
type StravaClient struct {
	ClientID     string
	ClientSecret string
	BaseURL      string // empty → "https://www.strava.com"
	HTTP         *http.Client
}

// StravaTokenResponse is the subset of Strava's `/oauth/token` reply
// the worker writes back. Strava returns more (`token_type`, `athlete`,
// the original `scope`) but only these three matter for the refresh
// path.
type StravaTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresAt    int64  `json:"expires_at"` // unix seconds
}

// Refresh exchanges a refresh token for a fresh pair. Mirrors the
// shape of the strava-import Edge Function's connect-path POST, just
// with `grant_type=refresh_token` instead of `authorization_code`.
//
// Returns the response struct on 200 + parseable body. Non-2xx
// responses surface as *HTTPError so the worker's transient/permanent
// classifier can branch on the code (5xx → transient retry, 4xx →
// permanent skip).
func (c *StravaClient) Refresh(ctx context.Context, refreshToken string) (*StravaTokenResponse, error) {
	base := c.BaseURL
	if base == "" {
		base = "https://www.strava.com"
	}
	body := url.Values{}
	body.Set("client_id", c.ClientID)
	body.Set("client_secret", c.ClientSecret)
	body.Set("grant_type", "refresh_token")
	body.Set("refresh_token", refreshToken)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+"/oauth/token", strings.NewReader(body.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	client := c.HTTP
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, err := readAllResponse(resp)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, &HTTPError{StatusCode: resp.StatusCode, Body: string(raw)}
	}
	var out StravaTokenResponse
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, fmt.Errorf("strava: decode token response: %w", err)
	}
	if out.AccessToken == "" || out.RefreshToken == "" || out.ExpiresAt == 0 {
		return nil, fmt.Errorf("strava: token response missing required fields")
	}
	return &out, nil
}

// FetchActivity GETs a single Strava activity by id. Mirrors the EF
// helper `fetchStravaActivity` — the 429 / 503 branch surfaces as
// StravaFetchRateLimited so the caller can defer + retry; any other
// non-2xx surfaces as StravaFetchNotFound so the caller can finish
// the job cleanly (Strava retries up to 3× on non-200; once we ack
// 200-with-skip the event is dropped).
func (c *StravaClient) FetchActivity(ctx context.Context, accessToken string, activityID int64) (StravaActivityResult, error) {
	base := c.BaseURL
	if base == "" {
		base = "https://www.strava.com"
	}
	url := fmt.Sprintf("%s/api/v3/activities/%d", base, activityID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return StravaActivityResult{}, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")
	client := c.HTTP
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		// Network-level failure (DNS, dial, TLS, EOF) — transient.
		// The dedupe-rollback in the caller lets the next retry
		// reach the fetch stage cleanly. audit/strava H5.
		return StravaActivityResult{Status: StravaFetchTransient}, nil
	}
	defer resp.Body.Close()
	raw, readErr := readAllResponse(resp)
	if readErr != nil {
		// Body-read failure after a connection that dialled fine —
		// the same transient class as the dial failure above. Without
		// this the truncated bytes fall through to json.Unmarshal,
		// which fails as a permanent decode error and drops the
		// activity. audit/strava H5.
		return StravaActivityResult{Status: StravaFetchTransient}, nil
	}
	if resp.StatusCode == 429 || resp.StatusCode == 503 {
		return StravaActivityResult{Status: StravaFetchRateLimited}, nil
	}
	// Other 5xx (500/502/504): transient. Multi-hour 5xx incidents
	// from Strava are common — silent drop on a genuine outage is
	// worse than a retry-with-backoff outcome. audit/strava H5.
	if resp.StatusCode >= 500 && resp.StatusCode < 600 {
		return StravaActivityResult{Status: StravaFetchTransient}, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return StravaActivityResult{Status: StravaFetchNotFound}, nil
	}
	var act StravaActivity
	if err := json.Unmarshal(raw, &act); err != nil {
		return StravaActivityResult{}, fmt.Errorf("strava: decode activity: %w", err)
	}
	return StravaActivityResult{Status: StravaFetchOK, Activity: &act}, nil
}

// FetchStreams pulls the latlng/altitude/time/heartrate streams for
// an activity. Returns the raw map keyed by stream type — the caller
// (handler_strava_event) walks it into a TrackPoint slice via
// `BuildTrackFromStreams`. Returns nil + no error when Strava has no
// stream for the activity (404 — short/indoor activities) so the
// caller can ingest the row without a track.
func (c *StravaClient) FetchStreams(ctx context.Context, accessToken string, activityID int64) (map[string]StravaStream, error) {
	base := c.BaseURL
	if base == "" {
		base = "https://www.strava.com"
	}
	url := fmt.Sprintf("%s/api/v3/activities/%d/streams?keys=latlng,altitude,time,heartrate&key_by_type=true", base, activityID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")
	client := c.HTTP
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == 404 {
		return nil, nil // no streams for this activity
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := readAllResponse(resp)
		return nil, &HTTPError{StatusCode: resp.StatusCode, Body: string(body)}
	}
	raw, err := readAllResponse(resp)
	if err != nil {
		return nil, err
	}
	out := map[string]StravaStream{}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, fmt.Errorf("strava: decode streams: %w", err)
	}
	return out, nil
}

// StravaStream is the per-stream payload Strava returns — `data` is
// always present but its element type depends on the stream key
// (latlng → [lat, lng] pairs, altitude → numbers, time → ints,
// heartrate → ints). The handler unmarshals each branch into its
// concrete type via `BuildTrackFromStreams`.
type StravaStream struct {
	Data []json.RawMessage `json:"data"`
}

// readAllResponse reads the full response body. A mid-stream read
// failure (connection reset / truncated body during transfer) is
// returned, not swallowed: the request reached the server and got a
// 2xx, so a body-read failure is transient and the caller must defer +
// retry rather than mis-classify the truncated bytes as a permanent
// decode error and drop the user's activity.
func readAllResponse(resp *http.Response) ([]byte, error) {
	return io.ReadAll(resp.Body)
}
