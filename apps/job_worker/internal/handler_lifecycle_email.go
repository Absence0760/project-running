package internal

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
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

	// account_deleted carries its address INLINE — by send time the user is
	// gone, so there's no user_id to resolve from. Dispatch it to its own path
	// (non-cascading send-once guard, address from the payload) before the
	// user_id-keyed lifecycle path below.
	if inlineAddressTemplates[p.Template] {
		return w.handleAccountDeletionReceipt(ctx, p)
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

// handleAccountDeletionReceipt sends the account-deletion confirmation. The
// address + locale are in the payload (the user is already deleted, so GoTrue
// 404s and there's no user_settings to read). The send-once guard is the
// non-cascading account_deletion_receipts table keyed by the address hash, NOT
// lifecycle_email_log (which cascaded away with the user). decisions §121.
//
// Always-once: unlike the recurring transactional templates, a deletion is
// terminal, so this always dedups. A blank address is a permanent skip
// (records nothing, finishes done) — there's nothing to send and no user to
// retry for.
func (w *Worker) handleAccountDeletionReceipt(ctx context.Context, p LifecycleEmailPayload) error {
	email := strings.TrimSpace(p.Email)
	if email == "" {
		w.Log.Warn("lifecycle_email: account_deleted has no address; skipping")
		return nil
	}
	hash := hashEmailForReceipt(email)

	already, err := w.Backend.AccountDeletionReceiptAlreadySent(ctx, hash)
	if err != nil {
		return fmt.Errorf("check receipt log: %w", err)
	}
	if already {
		return nil
	}

	msg, ok := renderLifecycleEmail(p.Template, w.AppBaseURL, p.Locale)
	if !ok {
		w.Log.Warn("lifecycle_email: unknown template; skipping", "template", p.Template)
		return nil
	}

	if err := w.Email.Send(ctx, email, msg); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	if err := w.Backend.RecordAccountDeletionReceipt(ctx, hash); err != nil {
		return fmt.Errorf("record receipt: %w", err)
	}
	w.Log.Info("lifecycle_email: sent", "template", p.Template)
	return nil
}

// hashEmailForReceipt is the send-once key for the account-deletion receipt:
// hex SHA-256 of the lowercased, trimmed address. Keeping a hash (not the raw
// address) means account_deletion_receipts is not a directory of deleted
// accounts, matching deletion_audit_log's pseudonymisation intent.
func hashEmailForReceipt(email string) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	return hex.EncodeToString(sum[:])
}
