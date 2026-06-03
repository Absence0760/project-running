package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
)

// handleNotificationEmail drains a `notification_email` job: load the
// referenced notification, decide whether the recipient wants this
// category by email, resolve their address, and send. Enqueued one-per-row
// by the notifications AFTER INSERT trigger (migration
// 20261130_001_notification_email_channel.sql) — so each job is a single
// recipient and completes well within the queue's < 30 s budget.
//
// The notifications row is the single source of truth shared with the
// in-app bell. This handler is the *email* consumer; a future FCM/APNs
// sender would be a sibling consumer of the same rows.
//
// Terminal-state discipline: every path that won't send stamps
// email_sent_at (skip / no-address / already-sent) so a row is considered
// exactly once. The one exception is "email sender not configured" — that
// finishes the job done WITHOUT stamping, so the rows are still pending if
// a later deploy turns email on. (Those jobs drain to done; the rows wait.)
//
// Delivery is at-least-once: if the SMTP send succeeds but the subsequent
// MarkNotificationEmailed fails transiently, the job defers and re-runs,
// re-sending. The EmailSentAt guard makes the common case idempotent; a
// duplicate only escapes in the narrow send-ok/mark-failed window, which
// is the standard email-delivery trade-off.
func (w *Worker) handleNotificationEmail(ctx context.Context, job *Job) error {
	if w.Email == nil {
		// No SMTP configured (existing deploys without the email env).
		// Finish done without stamping: the notification stays pending
		// so a later email-enabled deploy can still send it.
		w.Log.Info("notification_email: sender not configured; leaving row pending")
		return nil
	}

	var p NotificationEmailPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.NotificationID == "" {
		return errors.New("payload missing notification_id")
	}

	n, err := w.Backend.FetchNotificationForEmail(ctx, p.NotificationID)
	if err != nil {
		return fmt.Errorf("fetch notification: %w", err)
	}
	if n == nil {
		w.Log.Info("notification_email: notification gone (inbox cleared)", "id", p.NotificationID)
		return nil
	}
	if n.EmailSentAt != nil {
		// Already handled (re-enqueue or post-send retry). Idempotent.
		return nil
	}

	prefs, err := w.Backend.FetchUserSettingsPrefs(ctx, n.UserID)
	if err != nil {
		return fmt.Errorf("fetch prefs: %w", err)
	}
	if !shouldEmail(n.Kind, emailMode(prefs)) {
		// Recipient opted this category out. Terminal: stamp so we
		// don't reconsider on a future sweep.
		if err := w.Backend.MarkNotificationEmailed(ctx, n.ID); err != nil {
			return fmt.Errorf("mark skipped: %w", err)
		}
		return nil
	}

	email, err := w.Backend.FetchUserEmail(ctx, n.UserID)
	if err != nil {
		return fmt.Errorf("fetch email: %w", err)
	}
	if email == "" {
		w.Log.Warn("notification_email: recipient has no address", "user_id", n.UserID)
		return w.Backend.MarkNotificationEmailed(ctx, n.ID)
	}

	msg := renderNotificationEmail(*n, w.AppBaseURL, localeFromPrefs(prefs))
	if err := w.Email.Send(ctx, email, msg); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	if err := w.Backend.MarkNotificationEmailed(ctx, n.ID); err != nil {
		return fmt.Errorf("mark sent: %w", err)
	}
	w.Log.Info("notification_email: sent", "kind", n.Kind, "user_id", n.UserID)
	return nil
}
