package livehub

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

// ZoneFetcher resolves the privacy zones the broadcaster has
// configured for a given run. The hub queries it lazily on the
// first push for a room and caches the result for the room's
// lifetime — zones are configured once and rarely updated mid-run,
// so the cache trades a single tiny memory cost for fan-out latency.
//
// Tests stub this with a fake; production wires
// [SupabaseZoneFetcher].
type ZoneFetcher interface {
	Zones(ctx context.Context, runID string) ([]PrivacyZone, error)
}

// NoopZoneFetcher returns an empty zone list — used when the hub is
// running without a Supabase backend (local dev / unit tests). With
// no zones every ping passes through unclipped, which matches the
// privacy-zone contract: zones are opt-in via Settings → Privacy
// zones; an empty list means "broadcast my exact position."
type NoopZoneFetcher struct{}

func (NoopZoneFetcher) Zones(_ context.Context, _ string) ([]PrivacyZone, error) {
	return nil, nil
}

// SupabaseZoneFetcher reads the broadcaster's privacy zones via two
// PostgREST round-trips:
//
//  1. `runs?id=eq.<runId>&select=user_id` — find the owner.
//  2. `user_settings?user_id=eq.<userId>&select=prefs` — pull
//     `prefs.privacy_zones` for that user.
//
// Auths with the service-role key (same as the job-worker REST
// surface). RLS would otherwise hide the broadcaster's settings
// from the hub; the service role is the only role with read access
// to other users' rows.
type SupabaseZoneFetcher struct {
	BaseURL    string
	ServiceKey string
	HTTP       *http.Client
}

// Zones implements [ZoneFetcher].
func (f *SupabaseZoneFetcher) Zones(ctx context.Context, runID string) ([]PrivacyZone, error) {
	userID, err := f.fetchRunOwner(ctx, runID)
	if err != nil {
		return nil, fmt.Errorf("zones: fetch run owner: %w", err)
	}
	if userID == "" {
		return nil, nil
	}
	zones, err := f.fetchZonesForUser(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("zones: fetch user_settings: %w", err)
	}
	return zones, nil
}

func (f *SupabaseZoneFetcher) fetchRunOwner(ctx context.Context, runID string) (string, error) {
	q := url.Values{}
	q.Set("id", "eq."+runID)
	q.Set("select", "user_id")
	q.Set("limit", "1")
	body, err := f.get(ctx, "/rest/v1/"+schema.TableRuns+"?"+q.Encode())
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

func (f *SupabaseZoneFetcher) fetchZonesForUser(ctx context.Context, userID string) ([]PrivacyZone, error) {
	q := url.Values{}
	q.Set("user_id", "eq."+userID)
	q.Set("select", "prefs")
	q.Set("limit", "1")
	body, err := f.get(ctx, "/rest/v1/"+schema.TableUserSettings+"?"+q.Encode())
	if err != nil {
		return nil, err
	}
	// `prefs.privacy_zones` is an array of {lat, lng, radius_m}.
	// `prefs` itself may be absent (no settings row), an object, or
	// null — handle all three.
	var rows []struct {
		Prefs map[string]json.RawMessage `json:"prefs"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	raw, ok := rows[0].Prefs[schema.PrefsPrivacyZones]
	if !ok {
		return nil, nil
	}
	var zones []PrivacyZone
	if err := json.Unmarshal(raw, &zones); err != nil {
		return nil, fmt.Errorf("privacy_zones decode: %w", err)
	}
	return zones, nil
}

func (f *SupabaseZoneFetcher) get(ctx context.Context, path string) ([]byte, error) {
	base := strings.TrimRight(f.BaseURL, "/")
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+path, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("apikey", f.ServiceKey)
	req.Header.Set("Authorization", "Bearer "+f.ServiceKey)
	req.Header.Set("Accept", "application/json")
	client := f.HTTP
	if client == nil {
		// Fallback timeout — same rationale as runmeta.go.
		// /audit/livehub M8.
		client = &http.Client{Timeout: 30 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	buf := make([]byte, 0, 1024)
	chunk := make([]byte, 1024)
	for {
		n, readErr := resp.Body.Read(chunk)
		if n > 0 {
			buf = append(buf, chunk[:n]...)
		}
		if readErr != nil {
			break
		}
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("supabase %d %s: %s", resp.StatusCode, path, string(buf))
	}
	return buf, nil
}
