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
//     user to block 499 others. The next hourly tick retries.
//   - Strava 4xx (expired refresh token, revoked grant) on ONE row →
//     stamp `disconnected_at` so subsequent sweeps don't pick the
//     row up. The UI will show "Reconnect Strava" via the existing
//     integrations list (a non-NULL `disconnected_at` is the flag).
//     /audit/strava High #2.
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

	refreshed, skipped, disconnected := 0, 0, 0
	for _, row := range rows {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err := w.refreshOne(ctx, row.UserID); err != nil {
			// audit/strava High #2: branch on 4xx (permanent) vs
			// 5xx + network (transient). 4xx → mark disconnected
			// so the next sweep doesn't pick this row up forever.
			// Use a typed HTTPError check (mirrors isTransient in
			// worker.go) so a wrapped error still routes correctly.
			var httpErr *HTTPError
			if errors.As(err, &httpErr) && httpErr.StatusCode >= 400 && httpErr.StatusCode < 500 {
				reason := classifyStravaRefreshFailure(httpErr)
				if dErr := w.Backend.MarkIntegrationDisconnected(ctx, row.UserID, "strava", reason); dErr != nil {
					w.Log.Warn("token_refresh: mark-disconnected failed",
						"user_id", row.UserID, "err", dErr)
				}
				disconnected++
				w.Log.Info("token_refresh: marked disconnected",
					"user_id", row.UserID, "reason", reason, "status", httpErr.StatusCode)
				continue
			}
			// 5xx / network / wrapped non-HTTP error: transient.
			// Log + leave the row alone; next sweep retries.
			skipped++
			w.Log.Warn("token_refresh: skip user (transient)", "user_id", row.UserID, "err", err)
			continue
		}
		refreshed++
	}
	w.Log.Info("token_refresh: done",
		"candidates", len(rows),
		"refreshed", refreshed,
		"skipped", skipped,
		"disconnected", disconnected)
	return nil
}

// classifyStravaRefreshFailure inspects a 4xx response from Strava's
// /oauth/token endpoint and emits the short tag for
// integrations.disconnected_reason. `invalid_grant` is the canonical
// "user revoked at Strava's end" response; 401 typically means the
// refresh token aged out (90+ days idle). Anything else 4xx is
// `unauthorized` — caller has the bytes if they want detail.
func classifyStravaRefreshFailure(err *HTTPError) string {
	if err.StatusCode == 401 {
		return "unauthorized"
	}
	// Strava returns 400 with `{"error":"invalid_grant"}` for revoked
	// or expired refresh tokens. Quick substring match — the body
	// is short and the alternative (full JSON parse) is overkill.
	if err.StatusCode == 400 && (containsToken(err.Body, "invalid_grant") || containsToken(err.Body, "expired")) {
		return "invalid_grant"
	}
	return "unauthorized"
}

func containsToken(haystack, needle string) bool {
	return len(haystack) >= len(needle) && (indexOf(haystack, needle) >= 0)
}

func indexOf(haystack, needle string) int {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return i
		}
	}
	return -1
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
