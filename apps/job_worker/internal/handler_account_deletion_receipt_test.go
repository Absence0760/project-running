package internal

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func deletionReceiptJob(email, locale string) *Job {
	p, _ := json.Marshal(LifecycleEmailPayload{Template: "account_deleted", Email: email, Locale: locale})
	return &Job{ID: 1, Kind: "lifecycle_email", Payload: p}
}

// The address is live in the payload (the user is gone, so no GoTrue lookup),
// the receipt sends, and the non-cascading send-once record is written keyed by
// the email hash.
func TestAccountDeletionReceipt_SendsAndRecordsByHash(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 receipt sent, got %d", len(sender.sent))
	}
	if sender.sent[0].to != "gone@test.com" {
		t.Errorf("wrong recipient %q", sender.sent[0].to)
	}
	if sender.sent[0].msg.Subject != emailCatalogue["en"]["account_deleted"].subject {
		t.Errorf("unexpected subject %q", sender.sent[0].msg.Subject)
	}
	want := hashEmailForReceipt("gone@test.com")
	if len(be.recordedReceipts) != 1 || be.recordedReceipts[0] != want {
		t.Errorf("expected receipt recorded by hash %q, got %v", want, be.recordedReceipts)
	}
}

// A retry (or a crash between send and finish_job) can't re-send: the hash is
// already on record, so the second drain is a no-op.
func TestAccountDeletionReceipt_AlreadySentIsNoop(t *testing.T) {
	hash := hashEmailForReceipt("gone@test.com")
	be := &fakeBackend{receiptSent: map[string]bool{hash: true}}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 || len(be.recordedReceipts) != 0 {
		t.Errorf("already-sent must be a no-op; sent=%d recorded=%v", len(sender.sent), be.recordedReceipts)
	}
}

// The hash is case/whitespace-insensitive, so a re-enqueue with a differently
// cased or padded address still dedups against the original receipt.
func TestAccountDeletionReceipt_HashNormalisesAddress(t *testing.T) {
	hash := hashEmailForReceipt("gone@test.com")
	be := &fakeBackend{receiptSent: map[string]bool{hash: true}}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("  GONE@Test.COM ", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("a differently-cased address must hash to the same key and not re-send, sent=%d", len(sender.sent))
	}
}

// A blank address is a permanent skip — there's nothing to send and no user to
// retry for.
func TestAccountDeletionReceipt_NoAddressSkips(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("   ", "en")); err != nil {
		t.Fatalf("blank address should finish done, got %v", err)
	}
	if len(sender.sent) != 0 || len(be.recordedReceipts) != 0 {
		t.Errorf("blank address → no send, no record; sent=%d recorded=%v", len(sender.sent), be.recordedReceipts)
	}
}

// A send failure must return an error (so the queue retries) and must NOT
// record — otherwise the retry would dedup against a receipt that never sent.
func TestAccountDeletionReceipt_SendErrorPropagatesUnrecorded(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{err: errors.New("smtp 451 try again")}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err == nil {
		t.Fatalf("send failure must return an error so the queue retries")
	}
	if len(be.recordedReceipts) != 0 {
		t.Errorf("a failed send must not record, got %v", be.recordedReceipts)
	}
}

// Nil sender → the job finishes done without recording, so a later
// email-enabled deploy can still send (matches the welcome path).
func TestAccountDeletionReceipt_NilSenderSkips(t *testing.T) {
	be := &fakeBackend{}
	w := newEmailTestWorker(be, nil)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("nil sender should finish done, got %v", err)
	}
	if len(be.recordedReceipts) != 0 {
		t.Errorf("nil sender must not record, got %v", be.recordedReceipts)
	}
}

// Locale comes from the payload (no user_settings to read post-deletion).
func TestAccountDeletionReceipt_LocaleFromPayload(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "de")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 sent, got %d", len(sender.sent))
	}
	if sender.sent[0].msg.Subject != emailCatalogue["de"]["account_deleted"].subject {
		t.Errorf("de subject = %q, want the German catalogue subject", sender.sent[0].msg.Subject)
	}
	if !strings.Contains(sender.sent[0].msg.HTML, `lang="de"`) {
		t.Error("de receipt HTML should carry lang=\"de\"")
	}
}

// The check-log step failing is transient: the handler returns an error
// without sending so the queue retries, rather than send-then-double-send.
func TestAccountDeletionReceipt_CheckErrorPropagatesUnsent(t *testing.T) {
	be := &fakeBackend{receiptSentErr: errors.New("postgrest 503")}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err == nil {
		t.Fatalf("a send-once check failure must return an error so the queue retries")
	}
	if len(sender.sent) != 0 {
		t.Errorf("must not send when the dedup check failed, sent=%d", len(sender.sent))
	}
}

// The receipt copy must not carry a /settings/preferences link — the account
// is gone, so there's nothing to manage.
func TestAccountDeletionReceipt_NoPreferencesLink(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if strings.Contains(sender.sent[0].msg.HTML, "/settings/preferences") ||
		strings.Contains(sender.sent[0].msg.Body, "/settings/preferences") {
		t.Error("deletion receipt must not link to settings/preferences — the account is gone")
	}
	if sender.sent[0].msg.ListUnsubscribe != "" {
		t.Error("deletion receipt must not carry a List-Unsubscribe header")
	}
}
