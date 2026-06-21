package internal

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"testing"

	"github.com/Absence0760/project-running/apps/job_worker/internal/nativepush"
)

type fakeNativePushSender struct {
	sent     []nativepush.DeviceToken
	messages []nativepush.Message
	// statuses returned per call in order; default 200 when exhausted.
	statuses []int
	err      error // when set, every call returns (0, err) — a transport failure
	// platformErr maps a platform → ErrPlatformNotConfigured (the per-platform gate).
	platformErr map[string]bool
}

func (f *fakeNativePushSender) Send(_ context.Context, token nativepush.DeviceToken, msg nativepush.Message) (int, error) {
	f.sent = append(f.sent, token)
	f.messages = append(f.messages, msg)
	if f.platformErr[token.Platform] {
		return 0, nativepush.ErrPlatformNotConfigured
	}
	if f.err != nil {
		return 0, f.err
	}
	idx := len(f.sent) - 1
	if idx < len(f.statuses) {
		return f.statuses[idx], nil
	}
	return 200, nil
}

func newNativePushTestWorker(be *fakeBackend, sender NativePushSender) *Worker {
	return &Worker{
		Backend:    be,
		NativePush: sender,
		AppBaseURL: "https://threkir.test",
		Log:        slog.New(slog.NewTextHandler(nullWriter{}, nil)),
	}
}

func nativePushJob(notificationID string) *Job {
	p, _ := json.Marshal(NativePushPayload{NotificationID: notificationID})
	return &Job{ID: 1, Kind: "native_push", Payload: p}
}

// seededNativeBackend wires a notification + prefs + N device tokens.
func seededNativeBackend(n *NotificationRow, prefs map[string]interface{}, tokens ...DeviceTokenRow) *fakeBackend {
	be := &fakeBackend{
		notifications: map[string]*NotificationRow{n.ID: n},
		userPrefs:     map[string]map[string]interface{}{},
		deviceTokens:  map[string][]DeviceTokenRow{},
	}
	if prefs != nil {
		be.userPrefs[n.UserID] = prefs
	}
	if len(tokens) > 0 {
		be.deviceTokens[n.UserID] = tokens
	}
	return be
}

func androidToken(t string) DeviceTokenRow { return DeviceTokenRow{Platform: "android", Token: t} }
func iosToken(t string) DeviceTokenRow     { return DeviceTokenRow{Platform: "ios", Token: t} }

func TestNativePush_ImportantKindSendsByDefault(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil, androidToken("tok-a"), iosToken("tok-b"))
	sender := &fakeNativePushSender{}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 2 {
		t.Fatalf("want 2 sends (one per device), got %d", len(sender.sent))
	}
	m := sender.messages[0]
	if m.Title == "" {
		t.Errorf("message missing title")
	}
	if !strings.Contains(m.URL, "/events/evt-1") {
		t.Errorf("message should deep-link to the event, got %q", m.URL)
	}
	if m.Tag != "notif-n1" {
		t.Errorf("message tag should coalesce on the notification id, got %q", m.Tag)
	}
	if len(be.markedNativePushed) != 1 || be.markedNativePushed[0] != "n1" {
		t.Errorf("expected n1 stamped native_push_sent_at, got %v", be.markedNativePushed)
	}
}

func TestNativePush_SocialKindSkippedUnderDefault(t *testing.T) {
	row := &NotificationRow{ID: "n1", UserID: "u1", Kind: "kudos"}
	be := seededNativeBackend(row, nil, androidToken("tok-a")) // default mode = important
	sender := &fakeNativePushSender{}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Fatalf("kudos should not push under default 'important', sent %d", len(sender.sent))
	}
	if len(be.markedNativePushed) != 1 {
		t.Errorf("skipped row must be stamped, got %v", be.markedNativePushed)
	}
}

func TestNativePush_SocialKindSendsUnderAll(t *testing.T) {
	row := &NotificationRow{ID: "n1", UserID: "u1", Kind: "kudos"}
	be := seededNativeBackend(row, map[string]interface{}{"push_notifications": "all"}, androidToken("tok-a"))
	sender := &fakeNativePushSender{}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("kudos should push under 'all', sent %d", len(sender.sent))
	}
}

// The push channel preference is INDEPENDENT of the email one: muting email
// must not mute native push.
func TestNativePush_IndependentOfEmailPref(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(),
		map[string]interface{}{"email_notifications": "off"}, androidToken("tok-a"))
	sender := &fakeNativePushSender{}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("email=off must not suppress native push, sent %d", len(sender.sent))
	}
}

func TestNativePush_OffSuppressesEverything(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(),
		map[string]interface{}{"push_notifications": "off"}, androidToken("tok-a"))
	sender := &fakeNativePushSender{}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Fatalf("'off' must suppress even important kinds, sent %d", len(sender.sent))
	}
	if len(be.markedNativePushed) != 1 {
		t.Errorf("suppressed row must be stamped, got %v", be.markedNativePushed)
	}
}

func TestNativePush_NoTokenMarksHandled(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil) // no devices registered
	sender := &fakeNativePushSender{}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("no token → no send")
	}
	if len(be.markedNativePushed) != 1 {
		t.Errorf("no-token row must be stamped so it isn't retried forever, got %v", be.markedNativePushed)
	}
}

func TestNativePush_AlreadySentIsNoop(t *testing.T) {
	row := eventReminderRow()
	stamped := "2026-01-01T00:00:00Z"
	row.NativePushSentAt = &stamped
	be := seededNativeBackend(row, nil, androidToken("tok-a"))
	sender := &fakeNativePushSender{}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 || len(be.markedNativePushed) != 0 {
		t.Errorf("already-sent row must be a no-op; sent=%d marked=%v", len(sender.sent), be.markedNativePushed)
	}
}

func TestNativePush_MissingRowIsNoopNotError(t *testing.T) {
	be := &fakeBackend{notifications: map[string]*NotificationRow{}}
	sender := &fakeNativePushSender{}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("gone")); err != nil {
		t.Fatalf("missing row should finish done, got error: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("nothing should send for a missing row")
	}
}

func TestNativePush_NilSenderLeavesRowPending(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil, androidToken("tok-a"))
	w := newNativePushTestWorker(be, nil) // native push disabled (no credentials)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("nil sender should finish done, got error: %v", err)
	}
	if len(be.markedNativePushed) != 0 {
		t.Errorf("nil sender must NOT stamp — row stays pending for a later credentialed deploy, got %v", be.markedNativePushed)
	}
}

// A platform with no configured transport (e.g. APNs keys unset, an iOS token
// shows up) leaves the row pending — the credential gate is per-platform, same
// fail-closed posture as the nil-sender branch.
func TestNativePush_PlatformNotConfiguredLeavesRowPending(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil, iosToken("tok-ios"))
	sender := &fakeNativePushSender{platformErr: map[string]bool{"ios": true}}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("unconfigured platform should finish done, got error: %v", err)
	}
	if len(be.markedNativePushed) != 0 {
		t.Errorf("unconfigured platform must NOT stamp — row stays pending, got %v", be.markedNativePushed)
	}
}

// A user with one configured-platform device and one unconfigured-platform
// device must still receive the push on the configured device. The
// unconfigured leg is skipped, not allowed to abort delivery to the rest of
// the list — and the row is stamped because a configured send went through.
// Regression guard: ordering the unconfigured token first must not strand the
// configured one.
func TestNativePush_MixedPlatformSendsConfiguredSkipsUnconfigured(t *testing.T) {
	for _, order := range []struct {
		name   string
		tokens []DeviceTokenRow
	}{
		{"unconfigured_first", []DeviceTokenRow{iosToken("tok-ios"), androidToken("tok-android")}},
		{"configured_first", []DeviceTokenRow{androidToken("tok-android"), iosToken("tok-ios")}},
	} {
		t.Run(order.name, func(t *testing.T) {
			be := seededNativeBackend(eventReminderRow(), nil, order.tokens...)
			sender := &fakeNativePushSender{platformErr: map[string]bool{"ios": true}}
			w := newNativePushTestWorker(be, sender)

			if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
				t.Fatalf("handler: %v", err)
			}
			var sentAndroid bool
			for _, tok := range sender.sent {
				if tok.Platform == "android" {
					sentAndroid = true
				}
			}
			if !sentAndroid {
				t.Fatalf("the configured android device must receive the push, sent=%v", sender.sent)
			}
			if len(be.markedNativePushed) != 1 {
				t.Errorf("a configured send went through, so the row must be stamped, got %v", be.markedNativePushed)
			}
		})
	}
}

// When EVERY device is on an unconfigured platform, the row stays pending (no
// stamp) so a later credentialed deploy can deliver it — matching the
// nil-sender posture.
func TestNativePush_AllUnconfiguredLeavesRowPending(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil, iosToken("tok-ios-1"), iosToken("tok-ios-2"))
	sender := &fakeNativePushSender{platformErr: map[string]bool{"ios": true}}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(be.markedNativePushed) != 0 {
		t.Errorf("all-unconfigured must NOT stamp — row stays pending, got %v", be.markedNativePushed)
	}
}

func TestNativePush_DeadTokenPrunedAndHandled(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil, androidToken("tok-dead"), androidToken("tok-live"))
	sender := &fakeNativePushSender{statuses: []int{404, 200}} // first UNREGISTERED, second ok
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(be.clearedTokens) != 1 || be.clearedTokens[0] != "tok-dead" {
		t.Errorf("dead token should be pruned, got %v", be.clearedTokens)
	}
	if len(be.markedNativePushed) != 1 {
		t.Errorf("row must be stamped after a prune+send, got %v", be.markedNativePushed)
	}
}

func TestNativePush_TransientStatusRetriesUnstamped(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil, androidToken("tok-a"))
	sender := &fakeNativePushSender{statuses: []int{503}}
	w := newNativePushTestWorker(be, sender)

	err := w.handleNativePush(context.Background(), nativePushJob("n1"))
	if err == nil {
		t.Fatalf("a 5xx from the push service must return an error so the queue retries")
	}
	if !isTransient(err) {
		t.Errorf("error should classify transient so defer_job runs, got %v", err)
	}
	if len(be.markedNativePushed) != 0 {
		t.Errorf("a transient failure must not stamp the row, got %v", be.markedNativePushed)
	}
}

func TestNativePush_TransportErrorRetriesUnstamped(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil, androidToken("tok-a"))
	sender := &fakeNativePushSender{err: errors.New("dial tcp: connection refused")}
	w := newNativePushTestWorker(be, sender)

	err := w.handleNativePush(context.Background(), nativePushJob("n1"))
	if err == nil {
		t.Fatalf("a transport failure must return an error so the queue retries")
	}
	if !isTransient(err) {
		t.Errorf("error should classify transient, got %v", err)
	}
	if len(be.markedNativePushed) != 0 {
		t.Errorf("a failed send must not stamp the row, got %v", be.markedNativePushed)
	}
}

// A permanent 4xx for one token (e.g. 400 bad payload, 403 bad auth) is
// dropped, not retried — the row still reaches terminal state.
func TestNativePush_PermanentStatusDroppedNotRetried(t *testing.T) {
	be := seededNativeBackend(eventReminderRow(), nil, androidToken("tok-a"))
	sender := &fakeNativePushSender{statuses: []int{400}}
	w := newNativePushTestWorker(be, sender)

	if err := w.handleNativePush(context.Background(), nativePushJob("n1")); err != nil {
		t.Fatalf("a permanent push-service status must not fail the job, got %v", err)
	}
	if len(be.clearedTokens) != 0 {
		t.Errorf("a 400 is not a dead-token prune, got %v", be.clearedTokens)
	}
	if len(be.markedNativePushed) != 1 {
		t.Errorf("row must still be stamped, got %v", be.markedNativePushed)
	}
}
