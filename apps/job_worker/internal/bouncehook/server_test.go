package bouncehook

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

const testSecret = "0123456789abcdef0123456789abcdef" // 32 chars — meets the floor

// fakeBackend records every suppression insert. A scripted err makes the next
// insert fail.
type fakeBackend struct {
	mu   sync.Mutex
	rows []suppression
	err  error
}

func (f *fakeBackend) InsertEmailSuppression(_ context.Context, email, reason string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	f.rows = append(f.rows, suppression{email: email, reason: reason})
	return nil
}

func (f *fakeBackend) snapshot() []suppression {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]suppression, len(f.rows))
	copy(out, f.rows)
	return out
}

func newTestServer(t *testing.T, srv *Server) (string, func()) {
	t.Helper()
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	return ts.URL, ts.Close
}

func post(t *testing.T, url, body string) *http.Response {
	t.Helper()
	resp, err := http.Post(url, "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatalf("POST failed: %v", err)
	}
	return resp
}

func TestBounce_ResendPermanentBounceSuppresses(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	body := `{"type":"email.bounced","data":{"to":["dead@example.com"],"bounce":{"type":"Permanent"}}}`
	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	rows := be.snapshot()
	if len(rows) != 1 || rows[0].email != "dead@example.com" || rows[0].reason != "bounce" {
		t.Fatalf("want one bounce row for dead@example.com, got %+v", rows)
	}
}

func TestBounce_ResendComplaintSuppresses(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	body := `{"type":"email.complained","data":{"to":["angry@example.com"]}}`
	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	rows := be.snapshot()
	if len(rows) != 1 || rows[0].reason != "complaint" {
		t.Fatalf("want one complaint row, got %+v", rows)
	}
}

func TestBounce_ResendSoftBounceIsNoOp(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	body := `{"type":"email.bounced","data":{"to":["mailbox-full@example.com"],"bounce":{"type":"Transient"}}}`
	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	if rows := be.snapshot(); len(rows) != 0 {
		t.Fatalf("a soft bounce must not suppress, got %+v", rows)
	}
}

func TestBounce_ResendDeliveredIsNoOp(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	resp := post(t, base+"/v1/email/bounce?secret="+testSecret,
		`{"type":"email.delivered","data":{"to":["fine@example.com"]}}`)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	if rows := be.snapshot(); len(rows) != 0 {
		t.Fatalf("a delivery event must not suppress, got %+v", rows)
	}
}

func TestBounce_SESPermanentBounceSuppresses(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	// SES-over-SNS: the notification is a JSON string inside Message.
	body := `{"Type":"Notification","Message":"{\"notificationType\":\"Bounce\",\"bounce\":{\"bounceType\":\"Permanent\",\"bouncedRecipients\":[{\"emailAddress\":\"Dead@Example.com\"}]}}"}`
	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	rows := be.snapshot()
	if len(rows) != 1 || rows[0].email != "dead@example.com" || rows[0].reason != "bounce" {
		t.Fatalf("want lower-cased bounce row, got %+v", rows)
	}
}

func TestBounce_SESComplaintSuppresses(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	body := `{"notificationType":"Complaint","complaint":{"complainedRecipients":[{"emailAddress":"angry@example.com"}]}}`
	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	rows := be.snapshot()
	if len(rows) != 1 || rows[0].reason != "complaint" {
		t.Fatalf("want one complaint row, got %+v", rows)
	}
}

func TestBounce_SESTransientBounceIsNoOp(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	body := `{"notificationType":"Bounce","bounce":{"bounceType":"Transient","bouncedRecipients":[{"emailAddress":"full@example.com"}]}}`
	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	if rows := be.snapshot(); len(rows) != 0 {
		t.Fatalf("a transient SES bounce must not suppress, got %+v", rows)
	}
}

func TestBounce_DedupesMultipleRecipients(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	body := `{"type":"email.bounced","data":{"to":["a@x.com","A@X.com"," a@x.com "],"bounce":{"type":"Permanent"}}}`
	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	if rows := be.snapshot(); len(rows) != 1 {
		t.Fatalf("want a single de-duped row, got %+v", rows)
	}
}

func TestBounce_NoSecretConfigured503(t *testing.T) {
	base, done := newTestServer(t, &Server{Secret: "", Backend: &fakeBackend{}})
	defer done()

	resp := post(t, base+"/v1/email/bounce", `{}`)
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("want 503 when secret unset, got %d", resp.StatusCode)
	}
}

func TestBounce_ShortSecret503(t *testing.T) {
	base, done := newTestServer(t, &Server{Secret: "tooshort", Backend: &fakeBackend{}})
	defer done()

	resp := post(t, base+"/v1/email/bounce?secret=tooshort", `{}`)
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("want 503 on a short secret, got %d", resp.StatusCode)
	}
}

func TestBounce_WrongSecret403(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	body := `{"type":"email.bounced","data":{"to":["dead@example.com"],"bounce":{"type":"Permanent"}}}`
	resp := post(t, base+"/v1/email/bounce?secret=wrongwrongwrongwrongwrongwrongwr", body)
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("want 403 on a wrong secret, got %d", resp.StatusCode)
	}
	if rows := be.snapshot(); len(rows) != 0 {
		t.Fatalf("a forbidden request must not write, got %+v", rows)
	}
}

func TestBounce_GetNotAllowed(t *testing.T) {
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: &fakeBackend{}})
	defer done()

	resp, err := http.Get(base + "/v1/email/bounce?secret=" + testSecret)
	if err != nil {
		t.Fatalf("GET failed: %v", err)
	}
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("want 405 on GET, got %d", resp.StatusCode)
	}
}

func TestBounce_BadPayload400(t *testing.T) {
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: &fakeBackend{}})
	defer done()

	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, `{not json`)
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("want 400 on a malformed body, got %d", resp.StatusCode)
	}
}

func TestBounce_InsertFailure500(t *testing.T) {
	be := &fakeBackend{err: errors.New("db down")}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	body := `{"type":"email.complained","data":{"to":["angry@example.com"]}}`
	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, body)
	if resp.StatusCode != http.StatusInternalServerError {
		t.Fatalf("want 500 when the insert fails (so the provider retries), got %d", resp.StatusCode)
	}
}

func TestBounce_UnknownShapeIsNoOp(t *testing.T) {
	be := &fakeBackend{}
	base, done := newTestServer(t, &Server{Secret: testSecret, Backend: be})
	defer done()

	resp := post(t, base+"/v1/email/bounce?secret="+testSecret, `{"hello":"world"}`)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200 on an unrecognised shape, got %d", resp.StatusCode)
	}
	if rows := be.snapshot(); len(rows) != 0 {
		t.Fatalf("an unrecognised shape must not suppress, got %+v", rows)
	}
}

// classify is the pure heart of the handler; cover its branches directly too.
func TestClassify_PureBranches(t *testing.T) {
	cases := []struct {
		name string
		body string
		want int
	}{
		{"resend hard bounce", `{"type":"email.bounced","data":{"email":"x@y.com","bounce":{"type":"Permanent"}}}`, 1},
		{"resend missing subtype treated permanent", `{"type":"email.bounced","data":{"email":"x@y.com"}}`, 1},
		{"resend soft bounce", `{"type":"email.bounced","data":{"email":"x@y.com","bounce":{"type":"Transient"}}}`, 0},
		{"ses undetermined no-op", `{"notificationType":"Bounce","bounce":{"bounceType":"Undetermined","bouncedRecipients":[{"emailAddress":"x@y.com"}]}}`, 0},
		{"empty addresses", `{"type":"email.complained","data":{"to":[]}}`, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := classify([]byte(c.body))
			if len(got) != c.want {
				t.Fatalf("classify(%s): want %d, got %d (%+v)", c.body, c.want, len(got), got)
			}
		})
	}
}
