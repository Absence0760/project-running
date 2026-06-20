package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal/digesttoken"
)

// digestWindow is the look-back the weekly summary covers.
const digestWindow = 7 * 24 * time.Hour

// handleWeeklyDigest drains a `weekly_digest` job (migration 20270108_001).
//
// ENGAGEMENT MAIL, BEHIND THE GATE. This handler exists, but nothing
// enqueues these jobs on a schedule: the digest builder (EnqueueAllWeeklyDigests)
// is left UNSCHEDULED, and wiring its pg_cron is a deliberate later
// CISO/counsel-gated step (bulk/promotional mail under CAN-SPAM + GDPR/
// ePrivacy, unlike the transactional kinds). See docs/features/email.md.
//
// Two hard gates, both fail-closed, in this order:
//  1. opt-IN consent — the recipient's user_settings.prefs.email_weekly_digest
//     MUST equal the literal 'on'. Default off → skip. Marketing consent is
//     never inferred from the transactional email_notifications setting.
//  2. suppression — the resolved address MUST NOT be on email_suppressions
//     (bounce / complaint / prior unsubscribe). A suppressed address is a
//     hard block regardless of the pref.
//
// Only after both pass does the handler build the bounded weekly summary and
// send a localized digest carrying an RFC 8058 unsubscribe token. No
// notifications row, no send-once log: at-least-once delivery is fine for a
// weekly nudge, and the (pref + suppression) gates are the dedupe against an
// accidental double-enqueue of the same week.
//
// When no SMTP sender is configured the job finishes done without sending.
func (w *Worker) handleWeeklyDigest(ctx context.Context, job *Job) error {
	if w.Email == nil {
		w.Log.Info("weekly_digest: sender not configured; skipping")
		return nil
	}

	var p WeeklyDigestPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.UserID == "" {
		return errors.New("payload missing user_id")
	}

	// Gate 1: opt-IN consent. Default off → skip. A prefs read error is
	// fail-closed (skip) — we never send marketing mail on an uncertain
	// consent state.
	prefs, err := w.Backend.FetchUserSettingsPrefs(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("fetch prefs: %w", err)
	}
	if !digestOptedIn(prefs) {
		w.Log.Info("weekly_digest: recipient not opted in; skipping", "user_id", p.UserID)
		return nil
	}

	email, err := w.Backend.FetchUserEmail(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("fetch email: %w", err)
	}
	if email == "" {
		w.Log.Warn("weekly_digest: recipient has no address; skipping", "user_id", p.UserID)
		return nil
	}

	// Gate 2: suppression hard-block. A suppression read error is
	// fail-closed (treat as suppressed, skip) — better to miss one digest
	// than email an address that bounced or complained.
	suppressed, err := w.Backend.IsEmailSuppressed(ctx, email)
	if err != nil {
		w.Log.Warn("weekly_digest: suppression check failed; failing closed (skip)", "user_id", p.UserID, "err", err)
		return nil
	}
	if suppressed {
		w.Log.Info("weekly_digest: address is suppressed; hard-blocking send", "user_id", p.UserID)
		return nil
	}

	summary, err := w.Backend.BuildWeeklyDigest(ctx, p.UserID, time.Now().Add(-digestWindow))
	if err != nil {
		return fmt.Errorf("build digest: %w", err)
	}

	unsubURL := w.digestUnsubURL(p.UserID)
	msg := renderWeeklyDigest(summary, w.AppBaseURL, localeFromPrefs(prefs), unsubURL)
	if err := w.Email.Send(ctx, email, msg); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	w.Log.Info("weekly_digest: sent", "user_id", p.UserID, "runs", summary.RunCount, "kudos", summary.KudosCount, "new_pbs", summary.NewPBs)
	return nil
}

// digestOptedIn reports whether the prefs bag carries an explicit opt-IN.
// ONLY the literal string 'on' opts a recipient in; absent, 'off', or a
// non-string value is a skip. This is the fail-closed marketing-consent
// gate — the inverse of the transactional email_notifications default.
func digestOptedIn(prefs map[string]interface{}) bool {
	v, ok := prefs["email_weekly_digest"].(string)
	return ok && v == "on"
}

// digestUnsubURL builds the token-bearing one-click unsubscribe URL for a
// recipient: APP_BASE_URL + /unsubscribe/weekly-digest?u=<user_id>&t=<hmac>.
// Returns "" when the operator secret is unset so renderWeeklyDigest omits
// the List-Unsubscribe header + footer link rather than emit a forgeable
// one.
func (w *Worker) digestUnsubURL(userID string) string {
	return w.engagementUnsubURL(digesttoken.StreamWeeklyDigest, "/unsubscribe/weekly-digest", userID)
}

// engagementUnsubURL builds the token-bearing one-click unsubscribe URL for an
// engagement-mail stream (the weekly digest, the lifecycle drip). The token is
// scoped to the stream so one stream's link can't unsubscribe another. Returns
// "" when the operator secret is unset so the renderer omits the
// List-Unsubscribe header + footer link rather than emit a forgeable one (the
// single shared unsubscribe secret keys every stream — WEEKLY_DIGEST_UNSUB_SECRET).
func (w *Worker) engagementUnsubURL(stream, path, userID string) string {
	if w.DigestUnsubSecret == "" {
		return ""
	}
	tok := digesttoken.Mint(w.DigestUnsubSecret, stream, userID)
	if tok == "" {
		return ""
	}
	base := strings.TrimRight(w.AppBaseURL, "/")
	q := url.Values{}
	q.Set("u", userID)
	q.Set("t", tok)
	return base + path + "?" + q.Encode()
}
