package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/Absence0760/project-running/apps/job_worker/internal/digesttoken"
)

// handleLifecycleDrip drains a `lifecycle_drip` job (migration 20270223_001).
//
// ENGAGEMENT MAIL, BEHIND THE GATE — the sibling of handleWeeklyDigest. The
// jobs are enqueued by the `enqueue_lifecycle_drip()` pg_cron (cohort selection
// lives in SQL: onboarding / re-engagement / streak), but nothing sends until
// SMTP is provisioned, and even then every recipient is gated on the opt-IN
// `email_lifecycle_drip` pref + the email_suppressions hard-block. Enabling an
// actual send is the CISO/counsel-gated step (bulk/promotional mail under
// CAN-SPAM + GDPR/ePrivacy, unlike the transactional kinds). See
// docs/features/email.md.
//
// Two hard gates, both fail-closed, in this order — identical to the digest:
//  1. opt-IN consent — user_settings.prefs.email_lifecycle_drip MUST equal the
//     literal 'on'. Default off / non-string / read error → skip. Marketing
//     consent is never inferred from the transactional email_notifications
//     setting, NOR from the weekly-digest opt-in (a SEPARATE stream).
//  2. suppression — the resolved address MUST NOT be on email_suppressions
//     (bounce / complaint / prior unsubscribe of ANY stream).
//
// The job payload carries the template (drip_onboarding / drip_first_week /
// drip_reengagement / drip_streak) the SQL enqueue function chose for the
// recipient's cohort. The
// handler doesn't re-derive the cohort — the cohort math is the enqueue
// function's job; an opted-in + un-suppressed recipient gets the template they
// were enqueued with. No notifications row, no send-once log: at-least-once
// delivery is fine for a nudge, and the (pref + suppression) gates are the
// dedupe against an accidental double-enqueue.
//
// When no SMTP sender is configured the job finishes done without sending.
func (w *Worker) handleLifecycleDrip(ctx context.Context, job *Job) error {
	if w.Email == nil {
		w.Log.Info("lifecycle_drip: sender not configured; skipping")
		return nil
	}

	var p LifecycleDripPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.UserID == "" || p.Template == "" {
		return errors.New("payload missing user_id or template")
	}
	if !dripTemplates[p.Template] {
		// An unknown template is a permanent skip (a stale enqueue from an old
		// migration), not a retry loop.
		w.Log.Warn("lifecycle_drip: unknown template; skipping", "template", p.Template)
		return nil
	}

	// Gate 1: opt-IN consent. Default off → skip. A prefs read error is
	// fail-closed (skip) — we never send marketing mail on an uncertain
	// consent state.
	prefs, err := w.Backend.FetchUserSettingsPrefs(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("fetch prefs: %w", err)
	}
	if !dripOptedIn(prefs) {
		w.Log.Info("lifecycle_drip: recipient not opted in; skipping", "user_id", p.UserID)
		return nil
	}

	email, err := w.Backend.FetchUserEmail(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("fetch email: %w", err)
	}
	if email == "" {
		w.Log.Warn("lifecycle_drip: recipient has no address; skipping", "user_id", p.UserID)
		return nil
	}

	// Gate 2: suppression hard-block. A suppression read error is fail-closed
	// (treat as suppressed, skip) — better to miss one nudge than email an
	// address that bounced or complained.
	suppressed, err := w.Backend.IsEmailSuppressed(ctx, email)
	if err != nil {
		w.Log.Warn("lifecycle_drip: suppression check failed; failing closed (skip)", "user_id", p.UserID, "err", err)
		return nil
	}
	if suppressed {
		w.Log.Info("lifecycle_drip: address is suppressed; hard-blocking send", "user_id", p.UserID)
		return nil
	}

	unsubURL := w.engagementUnsubURL(digesttoken.StreamLifecycleDrip, "/unsubscribe/lifecycle-drip", p.UserID)
	msg, ok := renderLifecycleDrip(p.Template, w.AppBaseURL, localeFromPrefs(prefs), unsubURL)
	if !ok {
		w.Log.Warn("lifecycle_drip: template did not render; skipping", "template", p.Template)
		return nil
	}
	if err := w.Email.Send(ctx, email, msg); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	w.Log.Info("lifecycle_drip: sent", "user_id", p.UserID, "template", p.Template)
	return nil
}

// dripOptedIn reports whether the prefs bag carries an explicit opt-IN to the
// lifecycle drip. ONLY the literal string 'on' opts a recipient in; absent,
// 'off', or a non-string value is a skip. The inverse of the transactional
// email_notifications default, and a SEPARATE key from email_weekly_digest.
func dripOptedIn(prefs map[string]interface{}) bool {
	v, ok := prefs["email_lifecycle_drip"].(string)
	return ok && v == "on"
}
