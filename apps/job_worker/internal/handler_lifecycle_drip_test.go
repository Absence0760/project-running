package internal

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func dripJob(userID, template string) *Job {
	p, _ := json.Marshal(LifecycleDripPayload{UserID: userID, Template: template})
	return &Job{ID: 1, Kind: "lifecycle_drip", Payload: p}
}

func dripBackend() *fakeBackend {
	return &fakeBackend{
		userEmails: map[string]string{"u1": "runner@test.com"},
		userPrefs:  map[string]map[string]interface{}{"u1": {"email_lifecycle_drip": "on"}},
		suppressed: map[string]bool{},
	}
}

func TestLifecycleDrip_OptedInSends(t *testing.T) {
	be := dripBackend()
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_onboarding")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 drip sent, got %d", len(sender.sent))
	}
	got := sender.sent[0]
	if got.to != "runner@test.com" {
		t.Errorf("wrong recipient %q", got.to)
	}
	if got.msg.Subject != emailCatalogue["en"]["drip_onboarding"].subject {
		t.Errorf("unexpected subject %q", got.msg.Subject)
	}
	// RFC 8058 one-click unsubscribe present, scoped to the drip stream.
	if got.msg.ListUnsubscribe == "" {
		t.Error("opted-in drip must carry a List-Unsubscribe header")
	}
	if !strings.Contains(got.msg.ListUnsubscribe, "/unsubscribe/lifecycle-drip") {
		t.Errorf("unsubscribe URL must target the drip stream: %q", got.msg.ListUnsubscribe)
	}
	if !got.msg.ListUnsubscribeOneClick {
		t.Error("opted-in drip must advertise RFC 8058 one-click POST")
	}
}

func TestLifecycleDrip_EachTemplateRenders(t *testing.T) {
	for _, tmpl := range []string{"drip_onboarding", "drip_first_week", "drip_reengagement", "drip_streak"} {
		be := dripBackend()
		sender := &fakeEmailSender{}
		w := newEmailTestWorker(be, sender)
		w.DigestUnsubSecret = "s3cret"

		if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", tmpl)); err != nil {
			t.Fatalf("%s handler: %v", tmpl, err)
		}
		if len(sender.sent) != 1 {
			t.Fatalf("%s: want 1 sent, got %d", tmpl, len(sender.sent))
		}
		if sender.sent[0].msg.Subject != emailCatalogue["en"][tmpl].subject {
			t.Errorf("%s: subject = %q, want catalogue", tmpl, sender.sent[0].msg.Subject)
		}
	}
}

func TestLifecycleDrip_DefaultOffSkips(t *testing.T) {
	be := dripBackend()
	be.userPrefs = map[string]map[string]interface{}{} // no pref → default off
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_onboarding")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("default-off recipient must not be sent to; got %d", len(sender.sent))
	}
}

func TestLifecycleDrip_DigestOptInDoesNotImplyDrip(t *testing.T) {
	// Opting into the weekly digest is NOT consent to the lifecycle drip —
	// they're separate marketing-consent keys.
	be := dripBackend()
	be.userPrefs = map[string]map[string]interface{}{"u1": {"email_weekly_digest": "on"}}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_streak")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("a weekly-digest opt-in must not opt the recipient into the drip; got %d", len(sender.sent))
	}
}

func TestLifecycleDrip_NonStringPrefSkips(t *testing.T) {
	be := dripBackend()
	be.userPrefs["u1"]["email_lifecycle_drip"] = true
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_onboarding")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("non-string pref must not opt in; got %d sent", len(sender.sent))
	}
}

func TestLifecycleDrip_SuppressedHardBlocks(t *testing.T) {
	be := dripBackend()
	be.suppressed["runner@test.com"] = true
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_reengagement")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("suppressed address must be hard-blocked even when opted in; got %d", len(sender.sent))
	}
}

func TestLifecycleDrip_SuppressionErrorFailsClosed(t *testing.T) {
	be := dripBackend()
	be.suppressErr = errors.New("db blip")
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_onboarding")); err != nil {
		t.Fatalf("suppression error should be a skip, not a job error: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("a suppression-check failure must fail closed (no send); got %d", len(sender.sent))
	}
}

func TestLifecycleDrip_UnknownTemplateSkips(t *testing.T) {
	be := dripBackend()
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_bogus")); err != nil {
		t.Fatalf("unknown template should be a permanent skip, not an error: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("unknown template must not send; got %d", len(sender.sent))
	}
}

func TestLifecycleDrip_NoAddressSkips(t *testing.T) {
	be := dripBackend()
	be.userEmails = map[string]string{}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_onboarding")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("no address → no send; got %d", len(sender.sent))
	}
}

func TestLifecycleDrip_NilSenderSkips(t *testing.T) {
	be := dripBackend()
	w := newEmailTestWorker(be, nil)

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_onboarding")); err != nil {
		t.Fatalf("nil sender should finish done, got %v", err)
	}
}

func TestLifecycleDrip_NoSecretOmitsUnsubscribeHeaderButStillSends(t *testing.T) {
	be := dripBackend()
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "" // not yet provisioned

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_streak")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 sent, got %d", len(sender.sent))
	}
	if sender.sent[0].msg.ListUnsubscribe != "" {
		t.Error("without a secret the drip must omit the List-Unsubscribe header (no forgeable link)")
	}
}

func TestLifecycleDrip_SendErrorPropagates(t *testing.T) {
	be := dripBackend()
	sender := &fakeEmailSender{err: errors.New("smtp 451 try again")}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_onboarding")); err == nil {
		t.Fatal("a send failure must return an error so the queue retries")
	}
}

func TestLifecycleDrip_Localized(t *testing.T) {
	be := dripBackend()
	be.userPrefs["u1"]["locale"] = "ja"
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "drip_reengagement")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if sender.sent[0].msg.Subject != emailCatalogue["ja"]["drip_reengagement"].subject {
		t.Errorf("ja drip subject = %q, want the Japanese catalogue subject", sender.sent[0].msg.Subject)
	}
	if !strings.Contains(sender.sent[0].msg.HTML, `lang="ja"`) {
		t.Error("ja drip HTML should carry lang=\"ja\"")
	}
}

func TestLifecycleDrip_MissingFieldsAreError(t *testing.T) {
	be := dripBackend()
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleLifecycleDrip(context.Background(), dripJob("", "drip_onboarding")); err == nil {
		t.Error("missing user_id must be a permanent error")
	}
	if err := w.handleLifecycleDrip(context.Background(), dripJob("u1", "")); err == nil {
		t.Error("missing template must be a permanent error")
	}
}
