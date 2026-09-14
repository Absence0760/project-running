package internal

import (
	"context"
	"crypto/hmac"
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
	hash := receiptDigest(email, w.DeletionAuditKey)

	already, err := w.Backend.AccountDeletionReceiptAlreadySent(ctx, hash)
	if err != nil {
		return fmt.Errorf("check receipt log: %w", err)
	}
	// Changeover read. Rows written before the operator provisioned the key
	// carry the LEGACY unkeyed digest, and the keyed build cannot recognise
	// them — without this probe, provisioning the key re-sends a receipt to
	// everyone who deleted inside the table's 30-day window, which is a mail to
	// a former user about an account that no longer exists. Once every row
	// predating the changeover has aged out of that window the probe can go;
	// until then a miss on the keyed digest is not yet a miss.
	if !already && w.DeletionAuditKey != "" {
		already, err = w.Backend.AccountDeletionReceiptAlreadySent(ctx, hashEmailForReceipt(email))
		if err != nil {
			return fmt.Errorf("check legacy receipt log: %w", err)
		}
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

// receiptDigestDomain separates this digest's HMAC input from every other use
// of the same operator key. DELETION_AUDIT_KEY also keys delete-account's
// hashUserIdForAudit, which HMACs a bare user id; prefixing here means the two
// record types can never produce the same digest for related inputs, and a
// third use of the key later cannot collide with either. It is part of the
// wire format: changing the string re-keys every row and would re-send a
// receipt for anyone still inside the 30-day window, so it is versioned.
const receiptDigestDomain = "account-deletion-receipt:v1:"

// normaliseReceiptEmail is the ONE normalisation both digests take, so a
// differently cased or padded re-enqueue dedups under either mode.
func normaliseReceiptEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

// hashEmailForReceipt is the LEGACY, unkeyed send-once key: hex SHA-256 of the
// lowercased, trimmed address. It is what every row written before an operator
// provisioned DELETION_AUDIT_KEY carries, which is why it survives as its own
// function rather than as a branch — the keyed handler still has to recognise
// those rows (decisions § 1600).
//
// It is pseudonymisation, not anonymisation, and the difference is the whole
// reason the keyed mode exists: an email address is a GUESSABLE input, so a
// holder of a candidate address can recompute this digest and ask the table
// whether that person deleted their account. The table cannot be enumerated;
// it can be queried. The 30-day sweep time-bounds that window rather than
// closing it (decisions § 1551).
func hashEmailForReceipt(email string) string {
	sum := sha256.Sum256([]byte(normaliseReceiptEmail(email)))
	return hex.EncodeToString(sum[:])
}

// receiptDigest is the send-once key this worker WRITES. With a key set it is
// HMAC-SHA256 over the domain-separated address, which an adversary cannot
// reproduce from a candidate address, so the membership test above stops
// existing rather than merely expiring. With no key it is exactly the legacy
// digest, so an operator who has provisioned nothing sees no change at all —
// the guard needs only stable equality, and an HMAC serves that identically.
//
// The key reaches this worker through its OWN environment (DELETION_AUDIT_KEY
// on the job_worker process); setting it for the Edge Function alone keys the
// audit log and leaves the receipt digest legacy, which is a safe half-state
// and not an error.
func receiptDigest(email, key string) string {
	if key == "" {
		return hashEmailForReceipt(email)
	}
	mac := hmac.New(sha256.New, []byte(key))
	mac.Write([]byte(receiptDigestDomain + normaliseReceiptEmail(email)))
	return hex.EncodeToString(mac.Sum(nil))
}
