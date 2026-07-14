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

func TestSafetyEmail_OverdueCarriesLiveLinkAndTimes(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{
		Template:     "overdue",
		ContactEmail: "partner@safe.local",
		OwnerName:    "Ada Owner",
		RunID:        strptr("run-1"),
		StartedAt:    "2026-07-06T18:00:00+00:00",
		LastSeenAt:   "2026-07-06T18:42:11+00:00",
	})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("overdue must send, got %d", len(sender.sent))
	}
	got := sender.sent[0]
	if !strings.Contains(got.msg.Subject, "Ada Owner") {
		t.Errorf("subject should name the owner, got %q", got.msg.Subject)
	}
	if !strings.Contains(got.msg.Body, "/live/run-1") {
		t.Errorf("overdue mail must carry the live link, got %q", got.msg.Body)
	}
	if !strings.Contains(got.msg.Body, "18:00 UTC on 6 Jul") ||
		!strings.Contains(got.msg.Body, "18:42 UTC on 6 Jul") {
		t.Errorf("body should carry started + last-seen wall clocks, got %q", got.msg.Body)
	}
	// Calibrated copy: signal loss is a stated possibility, and no
	// coordinates appear (times + link only).
	if !strings.Contains(got.msg.Body, "signal") {
		t.Errorf("overdue copy must mention the loss-of-signal caveat, got %q", got.msg.Body)
	}
	if got.msg.ListUnsubscribe != "" {
		t.Errorf("safety mail carries no List-Unsubscribe, got %q", got.msg.ListUnsubscribe)
	}
}

func TestSafetyEmail_OverdueWithoutPingsUsesStartOnlyVariant(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{
		Template:     "overdue",
		ContactEmail: "partner@safe.local",
		OwnerName:    "Ada",
		RunID:        strptr("run-2"),
		StartedAt:    "2026-07-06T18:00:00+00:00",
	})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	body := sender.sent[0].msg.Body
	if !strings.Contains(body, "no position has been received since the start") {
		t.Errorf("no-ping overdue should use the start-only variant, got %q", body)
	}
}

func TestSafetyEmail_OverdueLocalizesToLinkedContact(t *testing.T) {
	be := &fakeBackend{
		userPrefs: map[string]map[string]interface{}{"c1": {"locale": "fr"}},
	}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{
		Template: "overdue", ContactUserID: strptr("c1"),
		ContactEmail: "p@safe.local", OwnerName: "Ada",
		RunID: strptr("run-3"), StartedAt: "2026-07-06T18:00:00+00:00",
	})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if !strings.Contains(sender.sent[0].msg.HTML, `lang="fr"`) {
		t.Error("a French-locale contact should get a French overdue email")
	}
}

func TestSafetyEmail_OffRouteCarriesLiveLinkAndTimes(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	job := safetyJob(SafetyEmailPayload{
		Template:     "off_route",
		ContactEmail: "partner@safe.local",
		OwnerName:    "Ada Owner",
		RunID:        strptr("run-9"),
		StartedAt:    "2026-07-06T18:00:00+00:00",
		LastSeenAt:   "2026-07-06T18:42:11+00:00",
	})
	if err := w.handleSafetyEmail(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("off_route must send, got %d", len(sender.sent))
	}
	got := sender.sent[0]
	if !strings.Contains(got.msg.Subject, "Ada Owner") {
		t.Errorf("subject should name the owner, got %q", got.msg.Subject)
	}
	if !strings.Contains(got.msg.Body, "/live/run-9") {
		t.Errorf("off_route mail must carry the live link, got %q", got.msg.Body)
	}
	if !strings.Contains(got.msg.Body, "off route") && !strings.Contains(got.msg.Body, "off their planned route") {
		t.Errorf("off_route copy must state the route departure, got %q", got.msg.Body)
	}
	if !strings.Contains(got.msg.Body, "18:00 UTC on 6 Jul") ||
		!strings.Contains(got.msg.Body, "18:42 UTC on 6 Jul") {
		t.Errorf("body should carry started + last-seen wall clocks, got %q", got.msg.Body)
	}
	if got.msg.ListUnsubscribe != "" {
		t.Errorf("safety mail carries no List-Unsubscribe, got %q", got.msg.ListUnsubscribe)
	}
}

func TestFormatTimeUTC(t *testing.T) {
	if got := formatTimeUTC("2026-07-06T18:42:11.123456+02:00"); got != "16:42 UTC on 6 Jul" {
		t.Errorf("offset input should normalise to UTC, got %q", got)
	}
	if got := formatTimeUTC("not-a-time"); got != "not-a-time" {
		t.Errorf("unparseable input falls back to the raw string, got %q", got)
	}
}
