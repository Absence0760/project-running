package unsubscribe

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/Absence0760/project-running/apps/job_worker/internal/digesttoken"
)

type fakeBackend struct {
	prefOff      []string // user ids flipped off
	suppressed   []string // "email|reason" inserted
	emails       map[string]string
	prefOffErr   error
	suppressErr  error
	emailErr     error
}

func (f *fakeBackend) SetWeeklyDigestPrefOff(_ context.Context, userID string) error {
	if f.prefOffErr != nil {
		return f.prefOffErr
	}
	f.prefOff = append(f.prefOff, userID)
	return nil
}

func (f *fakeBackend) InsertEmailSuppression(_ context.Context, email, reason string) error {
	if f.suppressErr != nil {
		return f.suppressErr
	}
	f.suppressed = append(f.suppressed, email+"|"+reason)
	return nil
}

func (f *fakeBackend) FetchUserEmail(_ context.Context, userID string) (string, error) {
	if f.emailErr != nil {
		return "", f.emailErr
	}
	return f.emails[userID], nil
}

const secret = "s3cret"

func newServer(be *fakeBackend) *Server {
	return &Server{
		Secret:  secret,
		Backend: be,
		Log:     slog.New(slog.NewTextHandler(nullWriter{}, nil)),
	}
}

type nullWriter struct{}

func (nullWriter) Write(p []byte) (int, error) { return len(p), nil }

func reqFor(method, userID, token string) *http.Request {
	q := url.Values{}
	q.Set("u", userID)
	q.Set("t", token)
	return httptest.NewRequest(method, "/unsubscribe/weekly-digest?"+q.Encode(), nil)
}

func TestUnsubscribe_ValidTokenFlipsPrefAndSuppresses(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)
	tok := digesttoken.Mint(secret, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "u1", tok))

	if rr.Code != http.StatusOK {
		t.Fatalf("want 200, got %d (%s)", rr.Code, rr.Body.String())
	}
	if len(be.prefOff) != 1 || be.prefOff[0] != "u1" {
		t.Errorf("expected pref flipped off for u1, got %v", be.prefOff)
	}
	if len(be.suppressed) != 1 || be.suppressed[0] != "runner@test.com|unsubscribe" {
		t.Errorf("expected suppression insert, got %v", be.suppressed)
	}
}

func TestUnsubscribe_PostOneClickWorks(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)
	tok := digesttoken.Mint(secret, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodPost, "u1", tok))

	if rr.Code != http.StatusOK {
		t.Fatalf("RFC 8058 POST one-click must work; got %d", rr.Code)
	}
}

func TestUnsubscribe_BadTokenFailsClosed(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "u1", "forged-token"))

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("a bad token must 400, got %d", rr.Code)
	}
	if len(be.prefOff) != 0 || len(be.suppressed) != 0 {
		t.Error("a bad token must NOT write to the DB")
	}
}

func TestUnsubscribe_MissingTokenFailsClosed(t *testing.T) {
	be := &fakeBackend{}
	srv := newServer(be)

	rr := httptest.NewRecorder()
	srv.handle(rr, httptest.NewRequest(http.MethodGet, "/unsubscribe/weekly-digest", nil))

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("a missing token must 400, got %d", rr.Code)
	}
	if len(be.prefOff) != 0 {
		t.Error("missing token must not write")
	}
}

func TestUnsubscribe_TokenForOtherUserFails(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "a@x.local", "u2": "b@x.local"}}
	srv := newServer(be)
	tok := digesttoken.Mint(secret, "u2") // minted for u2

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "u1", tok)) // presented for u1

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("a token for a different user must 400, got %d", rr.Code)
	}
	if len(be.prefOff) != 0 {
		t.Error("cross-user token must not write")
	}
}

func TestUnsubscribe_NoSecretRefuses(t *testing.T) {
	be := &fakeBackend{}
	srv := &Server{Secret: "", Backend: be, Log: slog.New(slog.NewTextHandler(nullWriter{}, nil))}
	tok := digesttoken.Mint(secret, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "u1", tok))

	if rr.Code != http.StatusServiceUnavailable {
		t.Fatalf("no secret must 503, got %d", rr.Code)
	}
}

func TestUnsubscribe_MethodNotAllowed(t *testing.T) {
	be := &fakeBackend{}
	srv := newServer(be)

	rr := httptest.NewRecorder()
	srv.handle(rr, httptest.NewRequest(http.MethodPut, "/unsubscribe/weekly-digest", nil))

	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("PUT must 405, got %d", rr.Code)
	}
}

func TestUnsubscribe_NoAddressStillFlipsPref(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{}} // no address on file
	srv := newServer(be)
	tok := digesttoken.Mint(secret, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "u1", tok))

	if rr.Code != http.StatusOK {
		t.Fatalf("a no-address user should still opt out via the pref; got %d", rr.Code)
	}
	if len(be.prefOff) != 1 {
		t.Error("pref must still flip off even with no address")
	}
	if len(be.suppressed) != 0 {
		t.Error("no address → no suppression row")
	}
}

func TestUnsubscribe_PrefFlipErrorIs500(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "a@x.local"}, prefOffErr: errors.New("db blip")}
	srv := newServer(be)
	tok := digesttoken.Mint(secret, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "u1", tok))

	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("a pref-flip failure must 500 so the client retries; got %d", rr.Code)
	}
}
