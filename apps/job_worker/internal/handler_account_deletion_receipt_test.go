package internal

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"regexp"
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

// ── keyed digest (decisions § 1600) ─────────────────────────────────────────

const testAuditKey = "an-operator-secret-at-least-32-bytes-long"

// With DELETION_AUDIT_KEY set the worker records the KEYED digest, which is not
// the legacy one — that difference is the whole point: the legacy digest is a
// bare hash of a guessable input, so a holder of a candidate address can
// recompute it and ask the table whether that person deleted their account.
func TestAccountDeletionReceipt_KeyedModeRecordsTheKeyedDigest(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DeletionAuditKey = testAuditKey

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	want := receiptDigest("gone@test.com", testAuditKey)
	legacy := hashEmailForReceipt("gone@test.com")
	if want == legacy {
		t.Fatalf("keyed and unkeyed digests must differ, both %q", want)
	}
	if len(be.recordedReceipts) != 1 || be.recordedReceipts[0] != want {
		t.Errorf("expected the keyed digest %q recorded, got %v", want, be.recordedReceipts)
	}
}

// An unset key changes nothing: the digest is byte-for-byte the legacy one, so
// a deploy that provisions no secret behaves exactly as before.
func TestAccountDeletionReceipt_UnkeyedModeIsTheLegacyDigest(t *testing.T) {
	if got, want := receiptDigest("gone@test.com", ""), hashEmailForReceipt("gone@test.com"); got != want {
		t.Fatalf("unkeyed digest %q != legacy %q", got, want)
	}
	be := &fakeBackend{}
	w := newEmailTestWorker(be, &fakeEmailSender{})
	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(be.recordedReceipts) != 1 || be.recordedReceipts[0] != hashEmailForReceipt("gone@test.com") {
		t.Errorf("unkeyed worker must write the legacy digest, got %v", be.recordedReceipts)
	}
}

// THE CHANGEOVER. Rows written before the key was provisioned carry the legacy
// digest. A keyed build that looked only at its own digest would miss them and
// re-send a receipt to everyone deleted inside the table's 30-day window.
func TestAccountDeletionReceipt_KeyedWorkerHonoursALegacyRow(t *testing.T) {
	legacy := hashEmailForReceipt("gone@test.com")
	be := &fakeBackend{receiptSent: map[string]bool{legacy: true}}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DeletionAuditKey = testAuditKey

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("a legacy row must still dedup under a keyed worker; sent=%d", len(sender.sent))
	}
	if len(be.recordedReceipts) != 0 {
		t.Errorf("nothing to record when the receipt already went out, got %v", be.recordedReceipts)
	}
}

// The legacy probe costs a round trip and is only owed during the changeover,
// so an UNKEYED worker must not make it: with no key the two digests are the
// same value and a second lookup would ask the identical question twice.
func TestAccountDeletionReceipt_UnkeyedWorkerProbesOnce(t *testing.T) {
	be := &fakeBackend{}
	w := newEmailTestWorker(be, &fakeEmailSender{})
	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(be.receiptLookups) != 1 {
		t.Errorf("want exactly one send-once lookup with no key set, got %v", be.receiptLookups)
	}
}

// A keyed worker probes its own digest FIRST and the legacy one only on a miss,
// so the ordinary steady-state path costs one lookup and the changeover two.
func TestAccountDeletionReceipt_KeyedWorkerProbesKeyedThenLegacy(t *testing.T) {
	be := &fakeBackend{}
	w := newEmailTestWorker(be, &fakeEmailSender{})
	w.DeletionAuditKey = testAuditKey
	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	want := []string{receiptDigest("gone@test.com", testAuditKey), hashEmailForReceipt("gone@test.com")}
	if len(be.receiptLookups) != 2 || be.receiptLookups[0] != want[0] || be.receiptLookups[1] != want[1] {
		t.Errorf("want probes %v, got %v", want, be.receiptLookups)
	}

	be2 := &fakeBackend{receiptSent: map[string]bool{receiptDigest("gone@test.com", testAuditKey): true}}
	w2 := newEmailTestWorker(be2, &fakeEmailSender{})
	w2.DeletionAuditKey = testAuditKey
	if err := w2.handleLifecycleEmail(context.Background(), deletionReceiptJob("gone@test.com", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(be2.receiptLookups) != 1 {
		t.Errorf("a hit on the keyed digest must not go on to probe the legacy one, got %v", be2.receiptLookups)
	}
}

// The key is actually mixed in, and the input is domain-separated from the bare
// address. DELETION_AUDIT_KEY also keys delete-account's user-id HMAC; without
// the prefix the two record types would share one keyed function of their input.
func TestAccountDeletionReceipt_DigestIsKeyedAndDomainSeparated(t *testing.T) {
	a := receiptDigest("gone@test.com", testAuditKey)
	b := receiptDigest("gone@test.com", "a-different-operator-secret-32-byte")
	if a == b {
		t.Errorf("two keys produced the same digest %q — the key is not mixed in", a)
	}
	if len(a) != 64 {
		t.Errorf("want 64 hex chars like the legacy digest, got %d", len(a))
	}
	if !regexp.MustCompile(`^[0-9a-f]{64}$`).MatchString(a) {
		t.Errorf("digest %q is not lowercase hex", a)
	}

	bare := hmac.New(sha256.New, []byte(testAuditKey))
	bare.Write([]byte("gone@test.com"))
	if a == hex.EncodeToString(bare.Sum(nil)) {
		t.Errorf("the digest is a plain HMAC of the address — the %q domain prefix is not applied", receiptDigestDomain)
	}
}

// Normalisation is shared, so a differently cased or padded re-enqueue still
// dedups under the keyed digest exactly as it does under the legacy one.
func TestAccountDeletionReceipt_KeyedDigestNormalisesAddress(t *testing.T) {
	hash := receiptDigest("gone@test.com", testAuditKey)
	be := &fakeBackend{receiptSent: map[string]bool{hash: true}}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DeletionAuditKey = testAuditKey

	if err := w.handleLifecycleEmail(context.Background(), deletionReceiptJob("  GONE@Test.COM ", "en")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("a differently-cased address must reach the same keyed digest, sent=%d", len(sender.sent))
	}
}
