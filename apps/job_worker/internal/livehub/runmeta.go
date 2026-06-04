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

// RunMeta captures the two `runs` columns the authorizer cares about:
// the row owner (must match the JWT's `sub` to authorise a push or a
// private spectator subscribe) and the public flag (anon spectators
// are allowed when set).
type RunMeta struct {
	UserID   string
	IsPublic bool
}

// RunMetaFetcher resolves [RunMeta] for a run id. Returns
// (nil, nil) when the row doesn't exist — the authorizer treats that
// as deny rather than allow.
//
// Tests stub this with a fake; production wires
// [SupabaseRunMetaFetcher].
type RunMetaFetcher interface {
	RunMeta(ctx context.Context, runID string) (*RunMeta, error)
}

// SupabaseRunMetaFetcher reads a single `runs` row via PostgREST.
// Auths with the service-role key, same as the rest of the worker —
// the row is otherwise hidden by RLS for the hub's anon context.
type SupabaseRunMetaFetcher struct {
	BaseURL    string
	ServiceKey string
	HTTP       *http.Client
}

// RunMeta implements [RunMetaFetcher].
func (f *SupabaseRunMetaFetcher) RunMeta(ctx context.Context, runID string) (*RunMeta, error) {
	q := url.Values{}
	q.Set("id", "eq."+runID)
	q.Set("select", "user_id,is_public")
	q.Set("limit", "1")
	body, err := f.get(ctx, "/rest/v1/"+schema.TableRuns+"?"+q.Encode())
	if err != nil {
		return nil, fmt.Errorf("runmeta: fetch run: %w", err)
	}
	var rows []struct {
		UserID   string `json:"user_id"`
		IsPublic bool   `json:"is_public"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, fmt.Errorf("runmeta: decode: %w", err)
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &RunMeta{UserID: rows[0].UserID, IsPublic: rows[0].IsPublic}, nil
}

func (f *SupabaseRunMetaFetcher) get(ctx context.Context, path string) ([]byte, error) {
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
		// Fallback timeout — http.DefaultClient has no deadline, so a
		// hung Supabase call would pin the request goroutine forever.
		// /audit/livehub M8. The production path always sets f.HTTP
		// to the worker's pooled client (main.go), so this branch is
		// only hit in tests + dev.
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
