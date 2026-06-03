package internal

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
)

func lifecycleJob(userID, template string) *Job {
	p, _ := json.Marshal(LifecycleEmailPayload{UserID: userID, Template: template})
	return &Job{ID: 1, Kind: "lifecycle_email", Payload: p}
}

func TestLifecycleEmail_WelcomeSendsAndRecords(t *testing.T) {
	be := &fakeBackend{userEmails: map[string]string{"u1": "runner@test.com"}}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), lifecycleJob("u1", "welcome")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 welcome sent, got %d", len(sender.sent))
	}
	if sender.sent[0].to != "runner@test.com" {
		t.Errorf("wrong recipient %q", sender.sent[0].to)
	}
	if sender.sent[0].msg.Subject != "Welcome to Threkir" {
		t.Errorf("unexpected subject %q", sender.sent[0].msg.Subject)
	}
	if be.recordedLifecycle == nil || be.recordedLifecycle[0] != "u1|welcome" {
		t.Errorf("expected u1|welcome recorded, got %v", be.recordedLifecycle)
	}
}

func TestLifecycleEmail_AlreadySentIsNoop(t *testing.T) {
	be := &fakeBackend{
		userEmails:    map[string]string{"u1": "runner@test.com"},
		lifecycleSent: map[string]bool{"u1|welcome": true},
	}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), lifecycleJob("u1", "welcome")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 || len(be.recordedLifecycle) != 0 {
		t.Errorf("already-sent must be a no-op; sent=%d recorded=%v", len(sender.sent), be.recordedLifecycle)
	}
}

func TestLifecycleEmail_NoAddressRecordsToStopRetries(t *testing.T) {
	be := &fakeBackend{userEmails: map[string]string{}} // no address
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), lifecycleJob("u1", "welcome")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("no address → no send")
	}
	if len(be.recordedLifecycle) != 1 {
		t.Errorf("no-address must record so it isn't retried forever, got %v", be.recordedLifecycle)
	}
}

func TestLifecycleEmail_NilSenderSkips(t *testing.T) {
	be := &fakeBackend{userEmails: map[string]string{"u1": "runner@test.com"}}
	w := newEmailTestWorker(be, nil)

	if err := w.handleLifecycleEmail(context.Background(), lifecycleJob("u1", "welcome")); err != nil {
		t.Fatalf("nil sender should finish done, got %v", err)
	}
	if len(be.recordedLifecycle) != 0 {
		t.Errorf("nil sender must not record — leave it for a later email-enabled deploy, got %v", be.recordedLifecycle)
	}
}

func TestLifecycleEmail_UnknownTemplateSkips(t *testing.T) {
	be := &fakeBackend{userEmails: map[string]string{"u1": "runner@test.com"}}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), lifecycleJob("u1", "no_such_template")); err != nil {
		t.Fatalf("unknown template should finish done, got %v", err)
	}
	if len(sender.sent) != 0 || len(be.recordedLifecycle) != 0 {
		t.Errorf("unknown template must not send or record; sent=%d recorded=%v", len(sender.sent), be.recordedLifecycle)
	}
}

func TestLifecycleEmail_SendErrorPropagatesUnrecorded(t *testing.T) {
	be := &fakeBackend{userEmails: map[string]string{"u1": "runner@test.com"}}
	sender := &fakeEmailSender{err: errors.New("smtp 451 try again")}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleEmail(context.Background(), lifecycleJob("u1", "welcome")); err == nil {
		t.Fatalf("send failure must return an error so the queue retries")
	}
	if len(be.recordedLifecycle) != 0 {
		t.Errorf("a failed send must not record, got %v", be.recordedLifecycle)
	}
}
