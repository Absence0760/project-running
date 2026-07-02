package livehub

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/schema"
)

// BlockChecker answers whether two users are blocked from interacting
// in EITHER direction — the same symmetric predicate the rest of the
// app expresses as SQL `is_blocked_either_way(a, b)` and gates kudos,
// comments, follows, segment leaderboards, and the public profile page
// on. The live-spectator stream is a social surface too: a viewer the
// runner has blocked (or who has blocked the runner) must not be able
// to watch their real-time GPS position, even on a public run.
//
// Returns an error when block status can't be determined; the
// authorizer treats that as deny (fail-closed) — the same posture the
// privacy-zone fetcher takes on a Supabase outage.
//
// Tests stub this with a fake; production wires [SupabaseBlockChecker].
type BlockChecker interface {
	IsBlockedEitherWay(ctx context.Context, a, b string) (bool, error)
}

// SupabaseBlockChecker reads `user_blocks` via PostgREST with the
// service-role key — RLS would otherwise hide the row from the hub's
// anon context, since a block is owner-read-only. Mirrors
// [SupabaseRunMetaFetcher] / [SupabaseZoneFetcher].
type SupabaseBlockChecker struct {
	BaseURL    string
	ServiceKey string
	HTTP       *http.Client
}

// IsBlockedEitherWay implements [BlockChecker]. A single matching row
// in either direction is enough — the block is symmetric.
func (f *SupabaseBlockChecker) IsBlockedEitherWay(ctx context.Context, a, b string) (bool, error) {
	// (blocker=a AND blocked=b) OR (blocker=b AND blocked=a) — the same
	// disjunction the SECURITY DEFINER `is_blocked_either_way` runs. One
	// row proves a block; `limit=1` keeps it a point read.
	q := url.Values{}
	q.Set("or", fmt.Sprintf(
		"(and(blocker_id.eq.%s,blocked_id.eq.%s),and(blocker_id.eq.%s,blocked_id.eq.%s))",
		a, b, b, a,
	))
	q.Set("select", "blocker_id")
	q.Set("limit", "1")
	body, err := f.get(ctx, "/rest/v1/"+schema.TableUserBlocks+"?"+q.Encode())
	if err != nil {
		return false, fmt.Errorf("blocks: fetch: %w", err)
	}
	var rows []struct {
		BlockerID string `json:"blocker_id"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return false, fmt.Errorf("blocks: decode: %w", err)
	}
	return len(rows) > 0, nil
}

func (f *SupabaseBlockChecker) get(ctx context.Context, path string) ([]byte, error) {
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
		// Fallback timeout — same rationale as runmeta.go / zones.go.
		// /audit/livehub M8. Production sets f.HTTP to the worker's
		// pooled client (main.go); this branch is tests + dev only.
		client = &http.Client{Timeout: 30 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	// io.ReadAll surfaces a truncated 2xx body as a fetch error rather
	// than silently treating the partial bytes as a complete (empty)
	// result — so the authorizer fails closed (deny) instead of missing
	// a block relationship on a half-read response. Mirrors runmeta.go.
	buf, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("supabase %d %s: %s", resp.StatusCode, path, string(buf))
	}
	return buf, nil
}
