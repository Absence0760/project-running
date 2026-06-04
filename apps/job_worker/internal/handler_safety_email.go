package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
)

// handleSafetyEmail drains a `safety_email` job (migration 20261218_001):
// render the named template for a safety contact and send it. Two templates:
//   - "confirm": the opt-in request, enqueued when an owner adds a contact;
//   - "finish":  the finish alert, enqueued per CONFIRMED contact on every
//     run insert regardless of is_public.
//
// Deliberately NOT the notification_email channel: there is no notifications
// row and — critically — NO email_notifications preference gate (a safety
// contact opted in explicitly and must not be silenced by the *runner's*
// social-email setting). Also not lifecycle_email: the recipient may be a
// non-user identified only by an email, and the copy carries per-finish
// context. decisions §131.
//
// The address is in the payload (contact_email is always set by the
// triggers). contact_user_id, when present, is used ONLY to localize the
// mail to the linked account's language — never as a gate.
//
// Delivery is at-least-once with no send-once log: a finish alert is a fresh
// event each run, and for safety mail a rare duplicate is preferable to a
// miss. A transient send error returns so the queue retries. When no SMTP
// sender is configured the job finishes done without sending.
func (w *Worker) handleSafetyEmail(ctx context.Context, job *Job) error {
	if w.Email == nil {
		w.Log.Info("safety_email: sender not configured; skipping")
		return nil
	}

	var p SafetyEmailPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.Template == "" {
		return errors.New("payload missing template")
	}

	to := p.ContactEmail
	locale := "en"
	if p.ContactUserID != nil {
		// Linked app-user contact: localize to their language. A prefs read
		// error falls back to English rather than failing the alert.
		if prefs, err := w.Backend.FetchUserSettingsPrefs(ctx, *p.ContactUserID); err == nil {
			locale = localeFromPrefs(prefs)
		}
		if to == "" {
			// Defensive: the triggers always set contact_email, but if a
			// future caller omits it, resolve the linked account's address.
			email, err := w.Backend.FetchUserEmail(ctx, *p.ContactUserID)
			if err != nil {
				return fmt.Errorf("fetch contact email: %w", err)
			}
			to = email
		}
	}
	if to == "" {
		w.Log.Warn("safety_email: no recipient address", "template", p.Template)
		return nil
	}

	msg, ok := renderSafetyEmail(p, w.AppBaseURL, locale)
	if !ok {
		w.Log.Warn("safety_email: unknown template; skipping", "template", p.Template)
		return nil
	}
	if err := w.Email.Send(ctx, to, msg); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	w.Log.Info("safety_email: sent", "template", p.Template)
	return nil
}
