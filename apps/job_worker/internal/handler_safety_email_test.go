package internal

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func safetyJob(p SafetyEmailPayload) *Job {
	b, _ := json.Marshal(p)
	return &Job{ID: 1, Kind: "safety_email", Payload: b}
}

func strptr(s string) *string { return &s }

func TestSafetyEmail_FinishSendsRegardlessOfPreference(t *testing.T) {
	// The linked contact has email_notifications OFF — a safety alert must
	// still send (it's opt-in, not gated on the runner's social setting).
	be := &fakeBackend{
		userPrefs:  map[string]map[string]interface{}{"c1": {"email_notifications": "off"}},
		userEmails: map[string]string{},
	}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{
		Template:      "finish",
		ContactUserID: strptr("c1"),
		ContactEmail:  "partner@safe.local",
		OwnerName:     "Ada Owner",
		RunID:         strptr("r1"),
		DistanceM:     5000,
		DurationS:     1830,
	})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("safety finish must send despite email_notifications=off, got %d", len(sender.sent))
	}
	got := sender.sent[0]
	if got.to != "partner@safe.local" {
		t.Errorf("wrong recipient %q", got.to)
	}
	if !strings.Contains(got.msg.Subject, "Ada Owner") {
		t.Errorf("subject should name the owner, got %q", got.msg.Subject)
	}
	if !strings.Contains(got.msg.Body, "5.00 km") || !strings.Contains(got.msg.Body, "30m") {
		t.Errorf("body should carry distance + time, got %q", got.msg.Body)
	}
	if got.msg.ListUnsubscribe != "" {
		t.Errorf("safety mail is transactional opt-in — no List-Unsubscribe, got %q", got.msg.ListUnsubscribe)
	}
}

func TestSafetyEmail_FinishLocalizesToLinkedContact(t *testing.T) {
	be := &fakeBackend{
		userPrefs: map[string]map[string]interface{}{"c1": {"locale": "de"}},
	}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{
		Template: "finish", ContactUserID: strptr("c1"), ContactEmail: "p@safe.local",
		OwnerName: "Ada", DistanceM: 10000, DurationS: 3661,
	})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if !strings.Contains(sender.sent[0].msg.HTML, `lang="de"`) {
		t.Error("a German-locale contact should get a German email")
	}
	if !strings.Contains(sender.sent[0].msg.Body, "1h 01m") {
		t.Errorf("duration over an hour should render h+mm, got %q", sender.sent[0].msg.Body)
	}
}

func TestSafetyEmail_ConfirmCarriesTokenLink(t *testing.T) {
	// An external (non-user) contact — no contact_user_id, default English.
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{
		Template:     "confirm",
		ContactEmail: "external@safe.local",
		OwnerName:    "Ada Owner",
		ConfirmToken: "tok-123",
	})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("confirm must send, got %d", len(sender.sent))
	}
	if !strings.Contains(sender.sent[0].msg.Body, "/safety/confirm?token=tok-123") {
		t.Errorf("confirm mail must carry the token link, got %q", sender.sent[0].msg.Body)
	}
}

func TestSafetyEmail_EmptyOwnerNameUsesFallback(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{
		Template: "finish", ContactEmail: "p@safe.local", DistanceM: 1000, DurationS: 600,
	})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if !strings.Contains(sender.sent[0].msg.Subject, "A Threkir runner") {
		t.Errorf("empty owner name should use the localized fallback, got %q", sender.sent[0].msg.Subject)
	}
}

func TestSafetyEmail_UnknownTemplateSkips(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{Template: "no_such", ContactEmail: "p@safe.local"})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("unknown template should finish done, got %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("unknown template must not send, got %d", len(sender.sent))
	}
}

func TestSafetyEmail_NoAddressSkips(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{Template: "finish"}) // no contact_email
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("no address should finish done, got %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("no address → no send")
	}
}

func TestSafetyEmail_NilSenderSkips(t *testing.T) {
	be := &fakeBackend{}
	w := newEmailTestWorker(be, nil)
	if err := w.handleSafetyEmail(context.Background(), safetyJob(SafetyEmailPayload{Template: "finish", ContactEmail: "p@safe.local"})); err != nil {
		t.Fatalf("nil sender should finish done, got %v", err)
	}
}

func TestSafetyEmail_SendErrorRetries(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{err: errors.New("smtp 451 try again")}
	w := newEmailTestWorker(be, sender)
	err := w.handleSafetyEmail(context.Background(), safetyJob(SafetyEmailPayload{Template: "finish", ContactEmail: "p@safe.local", OwnerName: "Ada"}))
	if err == nil {
		t.Fatal("a send failure must return an error so the queue retries")
	}
}
