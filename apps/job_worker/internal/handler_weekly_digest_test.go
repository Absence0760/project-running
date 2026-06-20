package internal

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func digestJob(userID string) *Job {
	p, _ := json.Marshal(WeeklyDigestPayload{UserID: userID})
	return &Job{ID: 1, Kind: "weekly_digest", Payload: p}
}

func digestBackend() *fakeBackend {
	return &fakeBackend{
		userEmails:   map[string]string{"u1": "runner@test.com"},
		userPrefs:    map[string]map[string]interface{}{"u1": {"email_weekly_digest": "on"}},
		suppressed:   map[string]bool{},
		digestByUser: map[string]DigestSummary{"u1": {RunCount: 3, DistanceM: 21400, KudosCount: 5, NewPBs: 1}},
	}
}

func TestWeeklyDigest_OptedInSends(t *testing.T) {
	be := digestBackend()
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 digest sent, got %d", len(sender.sent))
	}
	got := sender.sent[0]
	if got.to != "runner@test.com" {
		t.Errorf("wrong recipient %q", got.to)
	}
	if got.msg.Subject != emailCatalogue["en"]["weekly_digest"].subject {
		t.Errorf("unexpected subject %q", got.msg.Subject)
	}
	// Stats line interpolated from the summary.
	if !strings.Contains(got.msg.Body, "3 runs") || !strings.Contains(got.msg.Body, "5 kudos") {
		t.Errorf("digest body missing stats: %q", got.msg.Body)
	}
	// RFC 8058 one-click unsubscribe present.
	if got.msg.ListUnsubscribe == "" {
		t.Error("opted-in digest must carry a List-Unsubscribe header")
	}
	if !strings.Contains(got.msg.ListUnsubscribe, "/unsubscribe/weekly-digest") {
		t.Errorf("unsubscribe URL wrong: %q", got.msg.ListUnsubscribe)
	}
	// RFC 8058: the digest target honours the one-click POST, so the
	// companion List-Unsubscribe-Post header must be advertised.
	if !got.msg.ListUnsubscribeOneClick {
		t.Error("opted-in digest must advertise RFC 8058 one-click POST")
	}
	if raw := buildMIME("Threkir <noreply@threkir.com>", "runner@test.com", got.msg); !strings.Contains(raw, "List-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n") {
		t.Errorf("digest MIME missing List-Unsubscribe-Post header:\n%s", raw)
	}
}

func TestWeeklyDigest_DefaultOffSkips(t *testing.T) {
	be := digestBackend()
	be.userPrefs = map[string]map[string]interface{}{} // no pref → default off
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("default-off recipient must not be sent to; got %d", len(sender.sent))
	}
}

func TestWeeklyDigest_ExplicitOffSkips(t *testing.T) {
	be := digestBackend()
	be.userPrefs["u1"]["email_weekly_digest"] = "off"
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("explicit-off recipient must not be sent to; got %d", len(sender.sent))
	}
}

func TestWeeklyDigest_NonStringPrefSkips(t *testing.T) {
	be := digestBackend()
	be.userPrefs["u1"]["email_weekly_digest"] = true // non-string → not opted in
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("non-string pref must not opt in; got %d sent", len(sender.sent))
	}
}

func TestWeeklyDigest_SuppressedHardBlocks(t *testing.T) {
	be := digestBackend()
	be.suppressed["runner@test.com"] = true
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("suppressed address must be hard-blocked even when opted in; got %d", len(sender.sent))
	}
}

func TestWeeklyDigest_SuppressionErrorFailsClosed(t *testing.T) {
	be := digestBackend()
	be.suppressErr = errors.New("db blip")
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("suppression error should be a skip, not a job error: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("a suppression-check failure must fail closed (no send); got %d", len(sender.sent))
	}
}

func TestWeeklyDigest_NoAddressSkips(t *testing.T) {
	be := digestBackend()
	be.userEmails = map[string]string{} // no address
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("no address → no send; got %d", len(sender.sent))
	}
}

func TestWeeklyDigest_NilSenderSkips(t *testing.T) {
	be := digestBackend()
	w := newEmailTestWorker(be, nil)

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("nil sender should finish done, got %v", err)
	}
}

func TestWeeklyDigest_QuietWeekStillSends(t *testing.T) {
	be := digestBackend()
	be.digestByUser["u1"] = DigestSummary{} // nothing happened
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("a quiet week is still a legitimate nudge; want 1 sent, got %d", len(sender.sent))
	}
	// The quiet-week copy replaces the stats line.
	if !strings.Contains(sender.sent[0].msg.Body, lookupEmailShared("en").digestQuietWeek) {
		t.Error("quiet week should render the quiet-week nudge")
	}
}

func TestWeeklyDigest_NoSecretOmitsUnsubscribeHeaderButStillSends(t *testing.T) {
	be := digestBackend()
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "" // misconfigured / not yet provisioned

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 sent, got %d", len(sender.sent))
	}
	if sender.sent[0].msg.ListUnsubscribe != "" {
		t.Error("without a secret the digest must omit the List-Unsubscribe header (no forgeable link)")
	}
}

func TestWeeklyDigest_SendErrorPropagates(t *testing.T) {
	be := digestBackend()
	sender := &fakeEmailSender{err: errors.New("smtp 451 try again")}
	w := newEmailTestWorker(be, sender)

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err == nil {
		t.Fatal("a send failure must return an error so the queue retries")
	}
}

func TestWeeklyDigest_Localized(t *testing.T) {
	be := digestBackend()
	be.userPrefs["u1"]["locale"] = "de"
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	w.DigestUnsubSecret = "s3cret"

	if err := w.handleWeeklyDigest(context.Background(), digestJob("u1")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if sender.sent[0].msg.Subject != emailCatalogue["de"]["weekly_digest"].subject {
		t.Errorf("de digest subject = %q, want the German catalogue subject", sender.sent[0].msg.Subject)
	}
	if !strings.Contains(sender.sent[0].msg.HTML, `lang="de"`) {
		t.Error("de digest HTML should carry lang=\"de\"")
	}
}
