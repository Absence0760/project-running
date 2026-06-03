package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
)

// handleLifecycleEmail drains a `lifecycle_email` job: render the named
// template for the user and send it. Enqueued by a DB trigger (welcome) or,
// later, a scheduled cron (digest). Transactional/relationship mail — the
// welcome is NOT gated on the email_notifications preference (you can't opt
// out of the email that confirms you signed up).
//
// Send-once: lifecycle_email_log (user_id, template) is checked before
// sending and written after, so a job retry — or a crash between send and
// finish_job — can't re-send. Delivery is at-least-once (a duplicate only
// escapes the narrow send-ok/record-fail window), matching the
// notification_email path's email_sent_at discipline.
//
// When no SMTP sender is configured the job finishes done WITHOUT recording,
// so a later email-enabled deploy still sends. An unknown template is a
// permanent skip (records nothing, finishes done) rather than a retry loop.
func (w *Worker) handleLifecycleEmail(ctx context.Context, job *Job) error {
	if w.Email == nil {
		w.Log.Info("lifecycle_email: sender not configured; skipping")
		return nil
	}

	var p LifecycleEmailPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.UserID == "" || p.Template == "" {
		return errors.New("payload missing user_id or template")
	}

	// Locale is best-effort: a prefs read error falls back to English
	// rather than failing the welcome over a non-critical detail.
	prefs, _ := w.Backend.FetchUserSettingsPrefs(ctx, p.UserID)
	msg, ok := renderLifecycleEmail(p.Template, w.AppBaseURL, localeFromPrefs(prefs))
	if !ok {
		w.Log.Warn("lifecycle_email: unknown template; skipping", "template", p.Template)
		return nil
	}

	// Once-per-account templates (welcome) dedup via the permanent log;
	// recurring transactional templates (pro_welcome, payment_failed) do not
	// — a re-subscribe or a repeat billing failure is a legitimate new send.
	once := oncePerUserTemplates[p.Template]

	if once {
		already, err := w.Backend.LifecycleEmailAlreadySent(ctx, p.UserID, p.Template)
		if err != nil {
			return fmt.Errorf("check log: %w", err)
		}
		if already {
			return nil
		}
	}

	email, err := w.Backend.FetchUserEmail(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("fetch email: %w", err)
	}
	if email == "" {
		// No address (phone-only / deleted). For once-per-user mail, record
		// so we don't retry forever; recurring mail just finishes done.
		w.Log.Warn("lifecycle_email: recipient has no address", "user_id", p.UserID)
		if once {
			return w.Backend.RecordLifecycleEmail(ctx, p.UserID, p.Template)
		}
		return nil
	}

	if err := w.Email.Send(ctx, email, msg); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	if once {
		if err := w.Backend.RecordLifecycleEmail(ctx, p.UserID, p.Template); err != nil {
			return fmt.Errorf("record sent: %w", err)
		}
	}
	w.Log.Info("lifecycle_email: sent", "template", p.Template, "user_id", p.UserID)
	return nil
}
