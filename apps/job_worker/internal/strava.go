package internal

import (
	"context"
	"encoding/json"
	"fmt"
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

func readAllResponse(resp *http.Response) ([]byte, error) {
	buf := make([]byte, 0, 1024)
	chunk := make([]byte, 1024)
	for {
		n, err := resp.Body.Read(chunk)
		if n > 0 {
			buf = append(buf, chunk[:n]...)
		}
		if err != nil {
			break
		}
	}
	return buf, nil
}
