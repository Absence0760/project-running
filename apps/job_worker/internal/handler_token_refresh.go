package internal

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// handleTokenRefresh sweeps Strava integrations whose access token
// expires within the next hour and rotates each via Strava's
// `/oauth/token` `grant_type=refresh_token` flow. Mirrors the
// behaviour of the now-deprecated `refresh-tokens` Edge Function
// (see apps/backend/supabase/functions/refresh-tokens/index.ts) so
// the cutover from pg_cron → EF to pg_cron → jobs row is purely
// operational — no schema change.
//
// Payload is currently ignored (`{}` from the cron-enqueued row). A
// later slice may want a `provider` discriminator so a single job
// kind can serve other OAuth providers (Garmin, RunSignUp) — the
// switch lives in dispatch already, so for now we treat
// `token_refresh` as Strava-only and add `token_refresh_garmin`
// when needed.
//
// Error semantics:
//
//   - Strava 5xx / network blip on ONE row → that row is skipped and
//     logged; the job as a whole keeps going. We don't want one stuck
//     user to block 499 others.
//   - Strava 4xx (expired refresh token, revoked grant) on ONE row →
//     same: log and skip. The next time the user re-connects they'll
//     get a fresh refresh token; we don't have a graceful UX path for
//     that here.
//   - Supabase-level errors (RPC unavailable, service-role rejected)
//     → fail the job (transient if 5xx, permanent otherwise). The
//     queue's retry policy applies.
//
// The Strava client is plumbed via Worker.Strava so tests substitute
// a fake without booting an HTTP server. When `Strava` is nil the
// handler returns a permanent error — `token_refresh` jobs shouldn't
// be enqueued on a worker that wasn't built with Strava creds.
func (w *Worker) handleTokenRefresh(ctx context.Context, _ *Job) error {
	if w.Strava == nil {
		return errors.New("token_refresh: Strava client not configured (missing STRAVA_CLIENT_ID/SECRET)")
	}

	// Match the EF's 1-hour expiry window. Cron fires hourly; a wider
	// window pre-refreshes too aggressively (Strava quota churn), a
	// narrower one races with users whose token expires in the gap
	// between the cron tick and the row claim.
	const expiryWindow = time.Hour

	rows, err := w.Backend.FetchExpiringStravaIntegrations(ctx, expiryWindow)
	if err != nil {
		return fmt.Errorf("token_refresh: list expiring: %w", err)
	}
	if len(rows) == 0 {
		w.Log.Info("token_refresh: no expiring tokens")
		return nil
	}

	refreshed, skipped := 0, 0
	for _, row := range rows {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err := w.refreshOne(ctx, row.UserID); err != nil {
			skipped++
			w.Log.Warn("token_refresh: skip user", "user_id", row.UserID, "err", err)
			continue
		}
		refreshed++
	}
	w.Log.Info("token_refresh: done",
		"candidates", len(rows),
		"refreshed", refreshed,
		"skipped", skipped)
	return nil
}

// refreshOne carries out the per-user refresh: pull the current refresh
// token out of Vault, ask Strava for a new pair, write it back. Returns
// a non-nil error to push the caller into the skip path.
func (w *Worker) refreshOne(ctx context.Context, userID string) error {
	tokens, err := w.Backend.GetIntegrationTokens(ctx, userID, "strava")
	if err != nil {
		return fmt.Errorf("get_integration_tokens: %w", err)
	}
	if tokens == nil {
		// Row exists, Vault entry doesn't — see SupabaseClient.GetIntegrationTokens.
		return errors.New("no refresh token in vault")
	}

	fresh, err := w.Strava.Refresh(ctx, tokens.RefreshToken)
	if err != nil {
		return fmt.Errorf("strava refresh: %w", err)
	}

	expiry := time.Unix(fresh.ExpiresAt, 0).UTC()
	if err := w.Backend.SetIntegrationTokens(ctx, userID, "strava",
		fresh.AccessToken, fresh.RefreshToken, expiry); err != nil {
		return fmt.Errorf("set_integration_tokens: %w", err)
	}
	return nil
}
