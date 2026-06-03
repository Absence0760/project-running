package internal

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"testing"
)

type fakeEmailSender struct {
	sent []sentEmail
	err  error
}

type sentEmail struct {
	to  string
	msg Email
}

func (f *fakeEmailSender) Send(_ context.Context, to string, msg Email) error {
	if f.err != nil {
		return f.err
	}
	f.sent = append(f.sent, sentEmail{to: to, msg: msg})
	return nil
}

func newEmailTestWorker(be *fakeBackend, sender EmailSender) *Worker {
	return &Worker{
		Backend:    be,
		Email:      sender,
		AppBaseURL: "https://threkir.test",
		Log:        slog.New(slog.NewTextHandler(nullWriter{}, nil)),
	}
}

func emailJob(notificationID string) *Job {
	p, _ := json.Marshal(NotificationEmailPayload{NotificationID: notificationID})
	return &Job{ID: 1, Kind: "notification_email", Payload: p}
}

func seededBackend(n *NotificationRow, prefs map[string]interface{}, email string) *fakeBackend {
	be := &fakeBackend{
		notifications: map[string]*NotificationRow{n.ID: n},
		userPrefs:     map[string]map[string]interface{}{},
		userEmails:    map[string]string{n.UserID: email},
	}
	if prefs != nil {
		be.userPrefs[n.UserID] = prefs
	}
	return be
}

func eventReminderRow() *NotificationRow {
	ev := "evt-1"
	return &NotificationRow{ID: "n1", UserID: "u1", Kind: "event_reminder", EventID: &ev}
}

func TestNotificationEmail_ImportantKindSendsByDefault(t *testing.T) {
	be := seededBackend(eventReminderRow(), nil, "runner@test.com")
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleNotificationEmail(context.Background(), emailJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 email sent, got %d", len(sender.sent))
	}
	if sender.sent[0].to != "runner@test.com" {
		t.Errorf("wrong recipient: %q", sender.sent[0].to)
	}
	if len(be.markedEmailed) != 1 || be.markedEmailed[0] != "n1" {
		t.Errorf("expected n1 stamped email_sent_at, got %v", be.markedEmailed)
	}
}

func TestNotificationEmail_SocialKindSkippedUnderDefault(t *testing.T) {
	row := &NotificationRow{ID: "n1", UserID: "u1", Kind: "kudos"}
	be := seededBackend(row, nil, "runner@test.com") // default mode = important
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleNotificationEmail(context.Background(), emailJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Fatalf("kudos should not email under default 'important', sent %d", len(sender.sent))
	}
	// Still stamped — terminal, won't be reconsidered.
	if len(be.markedEmailed) != 1 {
		t.Errorf("expected the skipped row to be stamped, got %v", be.markedEmailed)
	}
}

func TestNotificationEmail_SocialKindSendsUnderAll(t *testing.T) {
	row := &NotificationRow{ID: "n1", UserID: "u1", Kind: "kudos"}
	be := seededBackend(row, map[string]interface{}{"email_notifications": "all"}, "runner@test.com")
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleNotificationEmail(context.Background(), emailJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("kudos should email under 'all', sent %d", len(sender.sent))
	}
}

func TestNotificationEmail_OffSuppressesEverything(t *testing.T) {
	be := seededBackend(eventReminderRow(), map[string]interface{}{"email_notifications": "off"}, "runner@test.com")
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleNotificationEmail(context.Background(), emailJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Fatalf("'off' must suppress even important kinds, sent %d", len(sender.sent))
	}
	if len(be.markedEmailed) != 1 {
		t.Errorf("expected suppressed row stamped, got %v", be.markedEmailed)
	}
}

func TestNotificationEmail_AlreadySentIsNoop(t *testing.T) {
	row := eventReminderRow()
	stamped := "2026-01-01T00:00:00Z"
	row.EmailSentAt = &stamped
	be := seededBackend(row, nil, "runner@test.com")
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleNotificationEmail(context.Background(), emailJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 || len(be.markedEmailed) != 0 {
		t.Errorf("already-sent row must be a no-op; sent=%d marked=%v", len(sender.sent), be.markedEmailed)
	}
}

func TestNotificationEmail_MissingRowIsNoopNotError(t *testing.T) {
	be := &fakeBackend{notifications: map[string]*NotificationRow{}} // empty → (nil,nil)
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleNotificationEmail(context.Background(), emailJob("gone")); err != nil {
		t.Fatalf("missing row should finish done, got error: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("nothing should send for a missing row")
	}
}

func TestNotificationEmail_NoAddressMarksHandled(t *testing.T) {
	be := seededBackend(eventReminderRow(), nil, "") // no email on file
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleNotificationEmail(context.Background(), emailJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("no address → no send")
	}
	if len(be.markedEmailed) != 1 {
		t.Errorf("no-address row must be stamped so it isn't retried forever, got %v", be.markedEmailed)
	}
}

func TestNotificationEmail_NilSenderLeavesRowPending(t *testing.T) {
	be := seededBackend(eventReminderRow(), nil, "runner@test.com")
	w := newEmailTestWorker(be, nil) // email disabled

	if err := w.handleNotificationEmail(context.Background(), emailJob("n1")); err != nil {
		t.Fatalf("nil sender should finish done, got error: %v", err)
	}
	if len(be.markedEmailed) != 0 {
		t.Errorf("nil sender must NOT stamp — row stays pending for a later email-enabled deploy, got %v", be.markedEmailed)
	}
}

func TestNotificationEmail_SendErrorPropagatesUnstamped(t *testing.T) {
	be := seededBackend(eventReminderRow(), nil, "runner@test.com")
	sender := &fakeEmailSender{err: errors.New("smtp 451 try again")}
	w := newEmailTestWorker(be, sender)

	err := w.handleNotificationEmail(context.Background(), emailJob("n1"))
	if err == nil {
		t.Fatalf("send failure must return an error so the queue retries")
	}
	if len(be.markedEmailed) != 0 {
		t.Errorf("a failed send must not stamp the row, got %v", be.markedEmailed)
	}
}
