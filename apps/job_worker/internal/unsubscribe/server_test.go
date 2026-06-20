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
	prefOff     []string // user ids whose weekly-digest pref was flipped off
	dripOff     []string // user ids whose lifecycle-drip pref was flipped off
	suppressed  []string // "email|reason" inserted
	emails      map[string]string
	prefOffErr  error
	suppressErr error
	emailErr    error
}

func (f *fakeBackend) SetWeeklyDigestPrefOff(_ context.Context, userID string) error {
	if f.prefOffErr != nil {
		return f.prefOffErr
	}
	f.prefOff = append(f.prefOff, userID)
	return nil
}

func (f *fakeBackend) SetLifecycleDripPrefOff(_ context.Context, userID string) error {
	if f.prefOffErr != nil {
		return f.prefOffErr
	}
	f.dripOff = append(f.dripOff, userID)
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

// digestStream / dripStream pull the two stream descriptors out of the server
// so the handler can be exercised directly with the right scope + pref-flip.
func (s *Server) digestStream() stream { return s.streams()[0] }
func (s *Server) dripStream() stream   { return s.streams()[1] }

func reqFor(method, path, userID, token string) *http.Request {
	q := url.Values{}
	q.Set("u", userID)
	q.Set("t", token)
	return httptest.NewRequest(method, path+"?"+q.Encode(), nil)
}

func TestUnsubscribe_ValidTokenFlipsPrefAndSuppresses(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)
	tok := digesttoken.Mint(secret, digesttoken.StreamWeeklyDigest, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/weekly-digest", "u1", tok), srv.digestStream())

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

func TestUnsubscribe_DripValidTokenFlipsDripPref(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)
	tok := digesttoken.Mint(secret, digesttoken.StreamLifecycleDrip, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/lifecycle-drip", "u1", tok), srv.dripStream())

	if rr.Code != http.StatusOK {
		t.Fatalf("want 200, got %d (%s)", rr.Code, rr.Body.String())
	}
	if len(be.dripOff) != 1 || be.dripOff[0] != "u1" {
		t.Errorf("expected drip pref flipped off for u1, got %v", be.dripOff)
	}
	if len(be.prefOff) != 0 {
		t.Errorf("drip unsubscribe must NOT flip the weekly-digest pref, got %v", be.prefOff)
	}
	if len(be.suppressed) != 1 || be.suppressed[0] != "runner@test.com|unsubscribe" {
		t.Errorf("expected suppression insert, got %v", be.suppressed)
	}
}

func TestUnsubscribe_CrossStreamTokenFails(t *testing.T) {
	// A weekly-digest token presented at the lifecycle-drip endpoint (and
	// vice-versa) must fail closed — the stream namespaces the MAC.
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)

	digestTok := digesttoken.Mint(secret, digesttoken.StreamWeeklyDigest, "u1")
	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/lifecycle-drip", "u1", digestTok), srv.dripStream())
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("a weekly-digest token at the drip endpoint must 400, got %d", rr.Code)
	}

	dripTok := digesttoken.Mint(secret, digesttoken.StreamLifecycleDrip, "u1")
	rr = httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/weekly-digest", "u1", dripTok), srv.digestStream())
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("a drip token at the weekly-digest endpoint must 400, got %d", rr.Code)
	}

	if len(be.prefOff) != 0 || len(be.dripOff) != 0 {
		t.Error("a cross-stream token must NOT write to the DB")
	}
}

func TestUnsubscribe_RegisterRoutesMountsBothStreams(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)

	tok := digesttoken.Mint(secret, digesttoken.StreamLifecycleDrip, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, reqFor(http.MethodGet, "/unsubscribe/lifecycle-drip", "u1", tok))
	if rr.Code != http.StatusOK {
		t.Fatalf("lifecycle-drip route must be mounted; got %d", rr.Code)
	}
}

func TestUnsubscribe_PostOneClickWorks(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)
	tok := digesttoken.Mint(secret, digesttoken.StreamWeeklyDigest, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodPost, "/unsubscribe/weekly-digest", "u1", tok), srv.digestStream())

	if rr.Code != http.StatusOK {
		t.Fatalf("RFC 8058 POST one-click must work; got %d", rr.Code)
	}
}

func TestUnsubscribe_BadTokenFailsClosed(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{"u1": "runner@test.com"}}
	srv := newServer(be)

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/weekly-digest", "u1", "forged-token"), srv.digestStream())

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
	srv.handle(rr, httptest.NewRequest(http.MethodGet, "/unsubscribe/weekly-digest", nil), srv.digestStream())

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
	tok := digesttoken.Mint(secret, digesttoken.StreamWeeklyDigest, "u2") // minted for u2

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/weekly-digest", "u1", tok), srv.digestStream()) // presented for u1

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
	tok := digesttoken.Mint(secret, digesttoken.StreamWeeklyDigest, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/weekly-digest", "u1", tok), srv.digestStream())

	if rr.Code != http.StatusServiceUnavailable {
		t.Fatalf("no secret must 503, got %d", rr.Code)
	}
}

func TestUnsubscribe_MethodNotAllowed(t *testing.T) {
	be := &fakeBackend{}
	srv := newServer(be)

	rr := httptest.NewRecorder()
	srv.handle(rr, httptest.NewRequest(http.MethodPut, "/unsubscribe/weekly-digest", nil), srv.digestStream())

	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("PUT must 405, got %d", rr.Code)
	}
}

func TestUnsubscribe_NoAddressStillFlipsPref(t *testing.T) {
	be := &fakeBackend{emails: map[string]string{}} // no address on file
	srv := newServer(be)
	tok := digesttoken.Mint(secret, digesttoken.StreamWeeklyDigest, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/weekly-digest", "u1", tok), srv.digestStream())

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
	tok := digesttoken.Mint(secret, digesttoken.StreamWeeklyDigest, "u1")

	rr := httptest.NewRecorder()
	srv.handle(rr, reqFor(http.MethodGet, "/unsubscribe/weekly-digest", "u1", tok), srv.digestStream())

	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("a pref-flip failure must 500 so the client retries; got %d", rr.Code)
	}
}
