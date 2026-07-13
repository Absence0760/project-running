package internal

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

type fakeSmsSender struct {
	sent []sentSms
	err  error
}

type sentSms struct {
	to   string
	body string
}

func (f *fakeSmsSender) Send(_ context.Context, to, body string) error {
	if f.err != nil {
		return f.err
	}
	f.sent = append(f.sent, sentSms{to: to, body: body})
	return nil
}

func newSmsTestWorker(be *fakeBackend, sender SmsSender) *Worker {
	return &Worker{
		Backend:    be,
		Sms:        sender,
		AppBaseURL: "https://threkir.test",
		Log:        slog.New(slog.NewTextHandler(nullWriter{}, nil)),
	}
}

func smsJob(p SafetySmsPayload) *Job {
	b, _ := json.Marshal(p)
	return &Job{ID: 1, Kind: "safety_sms", Payload: b}
}

func TestSafetySms_NilProviderFailsClosed(t *testing.T) {
	// The core fail-closed guarantee: no provider configured → the job
	// finishes done WITHOUT sending and WITHOUT error, so the queue drains it
	// (the parallel email escalation carries the alert).
	be := &fakeBackend{}
	w := newSmsTestWorker(be, nil)
	err := w.handleSafetySms(context.Background(), smsJob(SafetySmsPayload{
		Template: "overdue", ContactPhone: "+447700900123", OwnerName: "Ada", RunID: strptr("r1"),
		StartedAt: "2026-07-06T18:00:00+00:00",
	}))
	if err != nil {
		t.Fatalf("nil provider must finish done, got %v", err)
	}
}

func TestSafetySms_ConfiguredProviderSends(t *testing.T) {
	be := &fakeBackend{}
	sender := &fakeSmsSender{}
	w := newSmsTestWorker(be, sender)

	job := smsJob(SafetySmsPayload{
		Template:     "overdue",
		ContactPhone: "+447700900123",
		OwnerName:    "Ada Owner",
		RunID:        strptr("run-1"),
		StartedAt:    "2026-07-06T18:00:00+00:00",
		LastSeenAt:   "2026-07-06T18:42:11+00:00",
	})
	if err := w.handleSafetySms(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("configured provider must send once, got %d", len(sender.sent))
	}
	got := sender.sent[0]
	if got.to != "+447700900123" {
		t.Errorf("wrong destination %q", got.to)
	}
	if !strings.Contains(got.body, "Ada Owner") {
		t.Errorf("body should name the owner, got %q", got.body)
	}
	if !strings.Contains(got.body, "/live/run-1") {
		t.Errorf("body must carry the live link, got %q", got.body)
	}
	if !strings.Contains(got.body, "18:00 UTC on 6 Jul") || !strings.Contains(got.body, "18:42 UTC on 6 Jul") {
		t.Errorf("body should carry started + last-seen times, got %q", got.body)
	}
	// No coordinates: a plausible lat/lng fragment must never appear.
	if strings.Contains(got.body, "51.5") || strings.Contains(got.body, "lat") {
		t.Errorf("body must not carry coordinates, got %q", got.body)
	}
}

func TestSafetySms_NoPingUsesStartOnlyVariant(t *testing.T) {
	sender := &fakeSmsSender{}
	w := newSmsTestWorker(&fakeBackend{}, sender)
	job := smsJob(SafetySmsPayload{
		Template: "overdue", ContactPhone: "+447700900123", OwnerName: "Ada",
		RunID: strptr("run-2"), StartedAt: "2026-07-06T18:00:00+00:00",
	})
	if err := w.handleSafetySms(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if !strings.Contains(sender.sent[0].body, "no position received since") {
		t.Errorf("no-ping SMS should use the start-only variant, got %q", sender.sent[0].body)
	}
}

func TestSafetySms_LocalizesToLinkedContact(t *testing.T) {
	be := &fakeBackend{userPrefs: map[string]map[string]interface{}{"c1": {"locale": "fr"}}}
	sender := &fakeSmsSender{}
	w := newSmsTestWorker(be, sender)
	job := smsJob(SafetySmsPayload{
		Template: "overdue", ContactUserID: strptr("c1"), ContactPhone: "+33600000000",
		OwnerName: "Ada", RunID: strptr("run-3"), StartedAt: "2026-07-06T18:00:00+00:00",
	})
	if err := w.handleSafetySms(context.Background(), job); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if !strings.Contains(sender.sent[0].body, "Départ") {
		t.Errorf("a French-locale contact should get a French SMS, got %q", sender.sent[0].body)
	}
}

func TestSafetySms_NoPhoneSkips(t *testing.T) {
	sender := &fakeSmsSender{}
	w := newSmsTestWorker(&fakeBackend{}, sender)
	if err := w.handleSafetySms(context.Background(), smsJob(SafetySmsPayload{Template: "overdue"})); err != nil {
		t.Fatalf("no phone should finish done, got %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("no phone → no send")
	}
}

func TestSafetySms_UnknownTemplateSkips(t *testing.T) {
	sender := &fakeSmsSender{}
	w := newSmsTestWorker(&fakeBackend{}, sender)
	if err := w.handleSafetySms(context.Background(), smsJob(SafetySmsPayload{Template: "no_such", ContactPhone: "+1"})); err != nil {
		t.Fatalf("unknown template should finish done, got %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("unknown template must not send")
	}
}

func TestSafetySms_SendErrorRetries(t *testing.T) {
	sender := &fakeSmsSender{err: errors.New("twilio 429 slow down")}
	w := newSmsTestWorker(&fakeBackend{}, sender)
	err := w.handleSafetySms(context.Background(), smsJob(SafetySmsPayload{
		Template: "overdue", ContactPhone: "+447700900123", OwnerName: "Ada", StartedAt: "2026-07-06T18:00:00+00:00",
	}))
	if err == nil {
		t.Fatal("a send failure must return an error so the queue retries")
	}
}

// TwilioSender is exercised against a local httptest server — never the live
// Twilio endpoint — so the exact request shape (path, basic auth, form body)
// is verified without any real message.
func TestTwilioSender_PostsCorrectRequest(t *testing.T) {
	var gotPath, gotAuthUser, gotAuthPass, gotTo, gotFrom, gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotAuthUser, gotAuthPass, _ = r.BasicAuth()
		_ = r.ParseForm()
		gotTo = r.Form.Get("To")
		gotFrom = r.Form.Get("From")
		gotBody = r.Form.Get("Body")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"sid":"SM123","status":"queued"}`))
	}))
	defer srv.Close()

	s := &TwilioSender{
		AccountSID: "AC_test",
		AuthToken:  "tok_test",
		From:       "+15005550006",
		HTTP:       srv.Client(),
		BaseURL:    srv.URL,
	}
	if err := s.Send(context.Background(), "+447700900123", "Ada may be overdue"); err != nil {
		t.Fatalf("send: %v", err)
	}
	if gotPath != "/2010-04-01/Accounts/"+url.PathEscape("AC_test")+"/Messages.json" {
		t.Errorf("wrong path %q", gotPath)
	}
	if gotAuthUser != "AC_test" || gotAuthPass != "tok_test" {
		t.Errorf("wrong basic auth %q/%q", gotAuthUser, gotAuthPass)
	}
	if gotTo != "+447700900123" || gotFrom != "+15005550006" || gotBody != "Ada may be overdue" {
		t.Errorf("wrong form fields to=%q from=%q body=%q", gotTo, gotFrom, gotBody)
	}
}

func TestSmsCatalogueParity(t *testing.T) {
	// Every email locale must carry an SMS entry with both variants populated
	// (no blank fallback when a linked contact's language is set).
	for _, loc := range emailLocales {
		s, ok := smsCatalogue[loc]
		if !ok {
			t.Errorf("smsCatalogue missing locale %q", loc)
			continue
		}
		if s.withLastSeen == "" || s.noPing == "" {
			t.Errorf("smsCatalogue[%q] has an empty variant", loc)
		}
	}
}

func TestTwilioSender_Non2xxErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"code":20003,"message":"Authenticate"}`))
	}))
	defer srv.Close()
	s := &TwilioSender{AccountSID: "AC", AuthToken: "bad", From: "+1", HTTP: srv.Client(), BaseURL: srv.URL}
	if err := s.Send(context.Background(), "+1", "x"); err == nil {
		t.Fatal("a non-2xx response must return an error")
	}
}
