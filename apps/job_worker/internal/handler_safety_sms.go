package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
)

// handleSafetySms drains a `safety_sms` job (migration 20270410_001): render
// the localized overdue SMS and send it via the configured provider.
//
// Fail-closed by design. When no SMS provider is configured (w.Sms == nil —
// the default, since no SMS credential ships) the job finishes done WITHOUT
// sending. That is safe: the same overdue scan enqueues a safety_email
// 'overdue' job for every confirmed contact independently, so the email
// escalation is the guaranteed floor and a missing SMS provider can never
// suppress the alert. The SMS leg is a pure amplifier for contacts who
// stored a phone AND opted in.
//
// Privacy mirrors the email exactly: double opt-in (the scan only enqueues
// for a confirmed contact with sms_opt_in_at set), once-per-run (the same
// safety_escalated_at stamp gates the scan), and times + the live link only —
// never coordinates.
//
// The phone is in the payload (the scan sets contact_phone). contact_user_id,
// when present, only localizes the copy to the linked account's language — it
// is never a gate. A transient send error returns so the queue retries.
func (w *Worker) handleSafetySms(ctx context.Context, job *Job) error {
	if w.Sms == nil {
		w.Log.Info("safety_sms: provider not configured; skipping (email escalation still delivers)")
		return nil
	}

	var p SafetySmsPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.Template == "" {
		return errors.New("payload missing template")
	}

	to := p.ContactPhone
	if to == "" {
		w.Log.Warn("safety_sms: no recipient phone", "template", p.Template)
		return nil
	}

	locale := "en"
	if p.ContactUserID != nil {
		if prefs, err := w.Backend.FetchUserSettingsPrefs(ctx, *p.ContactUserID); err == nil {
			locale = localeFromPrefs(prefs)
		}
	}

	body, ok := renderSafetySms(p, w.AppBaseURL, locale)
	if !ok {
		w.Log.Warn("safety_sms: unknown template; skipping", "template", p.Template)
		return nil
	}
	if err := w.Sms.Send(ctx, to, body); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	w.Log.Info("safety_sms: sent", "template", p.Template)
	return nil
}
