package internal

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"testing"

	"github.com/Absence0760/project-running/apps/job_worker/internal/webpush"
)

type fakeWebPushSender struct {
	sent     []webpush.Subscription
	payloads [][]byte
	// statuses returned per call in order; default 201 when exhausted.
	statuses []int
	err      error // when set, every call returns (0, err) — a transport failure
}

func (f *fakeWebPushSender) Send(_ context.Context, sub webpush.Subscription, payload []byte) (int, error) {
	f.sent = append(f.sent, sub)
	f.payloads = append(f.payloads, payload)
	if f.err != nil {
		return 0, f.err
	}
	idx := len(f.sent) - 1
	if idx < len(f.statuses) {
		return f.statuses[idx], nil
	}
	return 201, nil
}

func newWebPushTestWorker(be *fakeBackend, sender WebPushSender) *Worker {
	return &Worker{
		Backend:    be,
		WebPush:    sender,
		AppBaseURL: "https://threkir.test",
		Log:        slog.New(slog.NewTextHandler(nullWriter{}, nil)),
	}
}

func webPushJob(notificationID string) *Job {
	p, _ := json.Marshal(WebPushPayload{NotificationID: notificationID})
	return &Job{ID: 1, Kind: "web_push", Payload: p}
}

// seededPushBackend wires a notification + prefs + N device subscriptions.
func seededPushBackend(n *NotificationRow, prefs map[string]interface{}, subs ...PushSubscriptionRow) *fakeBackend {
	be := &fakeBackend{
		notifications: map[string]*NotificationRow{n.ID: n},
		userPrefs:     map[string]map[string]interface{}{},
		pushSubs:      map[string][]PushSubscriptionRow{},
	}
	if prefs != nil {
		be.userPrefs[n.UserID] = prefs
	}
	if len(subs) > 0 {
		be.pushSubs[n.UserID] = subs
	}
	return be
}

func sub(deviceID string) PushSubscriptionRow {
	return PushSubscriptionRow{DeviceID: deviceID, Endpoint: "https://push.test/" + deviceID, P256dh: "key", Auth: "auth"}
}

func TestWebPush_ImportantKindSendsByDefault(t *testing.T) {
	be := seededPushBackend(eventReminderRow(), nil, sub("dev-a"), sub("dev-b"))
	sender := &fakeWebPushSender{}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 2 {
		t.Fatalf("want 2 sends (one per device), got %d", len(sender.sent))
	}
	// Payload contract: title + deep link + dedupe tag.
	var p webPushPayload
	if err := json.Unmarshal(sender.payloads[0], &p); err != nil {
		t.Fatalf("payload: %v", err)
	}
	if p.Title == "" {
		t.Errorf("payload missing title")
	}
	if !strings.Contains(p.URL, "/events/evt-1") {
		t.Errorf("payload should deep-link to the event, got %q", p.URL)
	}
	if p.Tag != "notif-n1" {
		t.Errorf("payload tag should coalesce on the notification id, got %q", p.Tag)
	}
	if len(be.markedWebPushed) != 1 || be.markedWebPushed[0] != "n1" {
		t.Errorf("expected n1 stamped web_push_sent_at, got %v", be.markedWebPushed)
	}
}

func TestWebPush_SocialKindSkippedUnderDefault(t *testing.T) {
	row := &NotificationRow{ID: "n1", UserID: "u1", Kind: "kudos"}
	be := seededPushBackend(row, nil, sub("dev-a")) // default mode = important
	sender := &fakeWebPushSender{}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Fatalf("kudos should not push under default 'important', sent %d", len(sender.sent))
	}
	if len(be.markedWebPushed) != 1 {
		t.Errorf("skipped row must be stamped, got %v", be.markedWebPushed)
	}
}

func TestWebPush_SocialKindSendsUnderAll(t *testing.T) {
	row := &NotificationRow{ID: "n1", UserID: "u1", Kind: "kudos"}
	be := seededPushBackend(row, map[string]interface{}{"push_notifications": "all"}, sub("dev-a"))
	sender := &fakeWebPushSender{}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("kudos should push under 'all', sent %d", len(sender.sent))
	}
}

// The push channel preference is INDEPENDENT of the email one: muting email
// must not mute push, and vice-versa.
func TestWebPush_IndependentOfEmailPref(t *testing.T) {
	be := seededPushBackend(eventReminderRow(),
		map[string]interface{}{"email_notifications": "off"}, sub("dev-a"))
	sender := &fakeWebPushSender{}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("email=off must not suppress push, sent %d", len(sender.sent))
	}
}

func TestWebPush_OffSuppressesEverything(t *testing.T) {
	be := seededPushBackend(eventReminderRow(),
		map[string]interface{}{"push_notifications": "off"}, sub("dev-a"))
	sender := &fakeWebPushSender{}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Fatalf("'off' must suppress even important kinds, sent %d", len(sender.sent))
	}
	if len(be.markedWebPushed) != 1 {
		t.Errorf("suppressed row must be stamped, got %v", be.markedWebPushed)
	}
}

func TestWebPush_NoSubscriptionMarksHandled(t *testing.T) {
	be := seededPushBackend(eventReminderRow(), nil) // no devices registered
	sender := &fakeWebPushSender{}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("no subscription → no send")
	}
	if len(be.markedWebPushed) != 1 {
		t.Errorf("no-subscription row must be stamped so it isn't retried forever, got %v", be.markedWebPushed)
	}
}

func TestWebPush_AlreadySentIsNoop(t *testing.T) {
	row := eventReminderRow()
	stamped := "2026-01-01T00:00:00Z"
	row.WebPushSentAt = &stamped
	be := seededPushBackend(row, nil, sub("dev-a"))
	sender := &fakeWebPushSender{}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 || len(be.markedWebPushed) != 0 {
		t.Errorf("already-sent row must be a no-op; sent=%d marked=%v", len(sender.sent), be.markedWebPushed)
	}
}

func TestWebPush_MissingRowIsNoopNotError(t *testing.T) {
	be := &fakeBackend{notifications: map[string]*NotificationRow{}}
	sender := &fakeWebPushSender{}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("gone")); err != nil {
		t.Fatalf("missing row should finish done, got error: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("nothing should send for a missing row")
	}
}

func TestWebPush_NilSenderLeavesRowPending(t *testing.T) {
	be := seededPushBackend(eventReminderRow(), nil, sub("dev-a"))
	w := newWebPushTestWorker(be, nil) // push disabled

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("nil sender should finish done, got error: %v", err)
	}
	if len(be.markedWebPushed) != 0 {
		t.Errorf("nil sender must NOT stamp — row stays pending for a later push-enabled deploy, got %v", be.markedWebPushed)
	}
}

func TestWebPush_DeadSubscriptionPrunedAndHandled(t *testing.T) {
	be := seededPushBackend(eventReminderRow(), nil, sub("dev-dead"), sub("dev-live"))
	sender := &fakeWebPushSender{statuses: []int{410, 201}} // first gone, second ok
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(be.clearedSubs) != 1 || be.clearedSubs[0] != "u1|dev-dead" {
		t.Errorf("dead subscription should be pruned, got %v", be.clearedSubs)
	}
	if len(be.markedWebPushed) != 1 {
		t.Errorf("row must be stamped after a prune+send, got %v", be.markedWebPushed)
	}
}

func TestWebPush_TransientStatusRetriesUnstamped(t *testing.T) {
	be := seededPushBackend(eventReminderRow(), nil, sub("dev-a"))
	sender := &fakeWebPushSender{statuses: []int{503}}
	w := newWebPushTestWorker(be, sender)

	err := w.handleWebPush(context.Background(), webPushJob("n1"))
	if err == nil {
		t.Fatalf("a 5xx from the push service must return an error so the queue retries")
	}
	if !isTransient(err) {
		t.Errorf("error should classify transient so defer_job runs, got %v", err)
	}
	if len(be.markedWebPushed) != 0 {
		t.Errorf("a transient failure must not stamp the row, got %v", be.markedWebPushed)
	}
}

func TestWebPush_TransportErrorRetriesUnstamped(t *testing.T) {
	be := seededPushBackend(eventReminderRow(), nil, sub("dev-a"))
	sender := &fakeWebPushSender{err: errors.New("dial tcp: connection refused")}
	w := newWebPushTestWorker(be, sender)

	err := w.handleWebPush(context.Background(), webPushJob("n1"))
	if err == nil {
		t.Fatalf("a transport failure must return an error so the queue retries")
	}
	if !isTransient(err) {
		t.Errorf("error should classify transient, got %v", err)
	}
	if len(be.markedWebPushed) != 0 {
		t.Errorf("a failed send must not stamp the row, got %v", be.markedWebPushed)
	}
}

// A permanent 4xx for one subscription (e.g. 413 too large) is dropped, not
// retried — the row still reaches terminal state.
func TestWebPush_PermanentStatusDroppedNotRetried(t *testing.T) {
	be := seededPushBackend(eventReminderRow(), nil, sub("dev-a"))
	sender := &fakeWebPushSender{statuses: []int{413}}
	w := newWebPushTestWorker(be, sender)

	if err := w.handleWebPush(context.Background(), webPushJob("n1")); err != nil {
		t.Fatalf("a permanent push-service status must not fail the job, got %v", err)
	}
	if len(be.clearedSubs) != 0 {
		t.Errorf("a 413 is not a dead-subscription prune, got %v", be.clearedSubs)
	}
	if len(be.markedWebPushed) != 1 {
		t.Errorf("row must still be stamped, got %v", be.markedWebPushed)
	}
}
