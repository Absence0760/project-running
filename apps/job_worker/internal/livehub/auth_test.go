package livehub

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testJWTSecret = "test-secret-do-not-use-in-prod"

// signTestToken builds a Supabase-shaped HS256 token for tests. The
// `sub` is the user id; setting `expSecsFromNow=-1` produces an
// expired token.
func signTestToken(t *testing.T, sub string, expSecsFromNow int) string {
	t.Helper()
	claims := jwt.MapClaims{
		"sub": sub,
	}
	if expSecsFromNow != 0 {
		claims["exp"] = time.Now().Add(time.Duration(expSecsFromNow) * time.Second).Unix()
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	s, err := tok.SignedString([]byte(testJWTSecret))
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return s
}

// fakeRunMetaFetcher returns canned RunMeta for unit-testing the
// authorizer without booting Supabase.
type fakeRunMetaFetcher struct {
	rows  map[string]*RunMeta
	calls int
	err   error
}

func (f *fakeRunMetaFetcher) RunMeta(_ context.Context, runID string) (*RunMeta, error) {
	f.calls++
	if f.err != nil {
		return nil, f.err
	}
	return f.rows[runID], nil
}

// reqWith builds an http.Request with the supplied Authorization
// header. Used to feed JWTAuthorizer.Authorize directly without
// going through the full HTTP stack.
func reqWith(authHeader string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	if authHeader != "" {
		r.Header.Set("Authorization", authHeader)
	}
	return r
}

func TestJWTAuthorizer_PushOwnerAllowed(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)
	token := signTestToken(t, "user-A", 60)

	if err := a.Authorize(reqWith("Bearer "+token), "run-1", ActionPush); err != nil {
		t.Fatalf("owner push must be allowed: %v", err)
	}
}

func TestJWTAuthorizer_PushNonOwnerDenied(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: true}, // public on read; still owner-only on push
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)
	token := signTestToken(t, "user-B", 60)

	err := a.Authorize(reqWith("Bearer "+token), "run-1", ActionPush)
	if err == nil {
		t.Fatal("non-owner push must be denied even on public runs")
	}
}

func TestJWTAuthorizer_PushMissingHeaderDenied(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: true},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)

	err := a.Authorize(reqWith(""), "run-1", ActionPush)
	if err == nil {
		t.Fatal("push with no bearer token must be denied")
	}
}

func TestJWTAuthorizer_SubscribeAnonAllowedOnPublic(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: true},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)

	if err := a.Authorize(reqWith(""), "run-1", ActionSubscribe); err != nil {
		t.Fatalf("anon subscribe to public run must be allowed: %v", err)
	}
	if err := a.Authorize(reqWith(""), "run-1", ActionSnapshot); err != nil {
		t.Fatalf("anon snapshot of public run must be allowed: %v", err)
	}
}

func TestJWTAuthorizer_SubscribeAnonDeniedOnPrivate(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)

	if err := a.Authorize(reqWith(""), "run-1", ActionSubscribe); err == nil {
		t.Fatal("anon subscribe to private run must be denied")
	}
}

func TestJWTAuthorizer_SubscribeOwnerAllowedOnPrivate(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)
	token := signTestToken(t, "user-A", 60)

	if err := a.Authorize(reqWith("Bearer "+token), "run-1", ActionSubscribe); err != nil {
		t.Fatalf("owner subscribe to private run must be allowed: %v", err)
	}
}

func TestJWTAuthorizer_SubscribeNonOwnerDeniedOnPrivate(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)
	token := signTestToken(t, "user-B", 60)

	if err := a.Authorize(reqWith("Bearer "+token), "run-1", ActionSubscribe); err == nil {
		t.Fatal("non-owner subscribe to private run must be denied")
	}
}

func TestJWTAuthorizer_ExpiredTokenDenied(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)
	// `exp` was 10 minutes ago
	token := signTestToken(t, "user-A", -600)

	if err := a.Authorize(reqWith("Bearer "+token), "run-1", ActionPush); err == nil {
		t.Fatal("expired token must be denied")
	}
}

func TestJWTAuthorizer_TamperedSignatureDenied(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)
	token := signTestToken(t, "user-A", 60)
	// Flip the last character of the signature segment to invalidate it.
	tampered := token[:len(token)-1] + flipLast(rune(token[len(token)-1]))

	if err := a.Authorize(reqWith("Bearer "+tampered), "run-1", ActionPush); err == nil {
		t.Fatal("tampered signature must be denied")
	}
}

func flipLast(c rune) string {
	// Map last character to a different valid base64url character.
	if c == 'A' {
		return "B"
	}
	return "A"
}

func TestJWTAuthorizer_DifferentSecretDenied(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)

	// Sign with a different secret — Supabase rotation scenario.
	claims := jwt.MapClaims{"sub": "user-A", "exp": time.Now().Add(time.Minute).Unix()}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, _ := tok.SignedString([]byte("a-different-secret"))

	if err := a.Authorize(reqWith("Bearer "+signed), "run-1", ActionPush); err == nil {
		t.Fatal("token signed with the wrong key must be denied")
	}
}

func TestJWTAuthorizer_UnknownRunDenied(t *testing.T) {
	hub := NewHub()
	// Empty rows → fetcher returns (nil, nil) for any runID.
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)
	token := signTestToken(t, "user-A", 60)

	if err := a.Authorize(reqWith("Bearer "+token), "ghost-run", ActionPush); err == nil {
		t.Fatal("a token referring to an unknown run must be denied")
	}
}

func TestJWTAuthorizer_FetcherErrorDenied(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{err: context.DeadlineExceeded}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)
	token := signTestToken(t, "user-A", 60)

	if err := a.Authorize(reqWith("Bearer "+token), "run-1", ActionPush); err == nil {
		t.Fatal("a Supabase fetch error must deny (fail-closed)")
	}
}

func TestJWTAuthorizer_CachesRunMetaPerRoom(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: true},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)

	for i := 0; i < 10; i++ {
		if err := a.Authorize(reqWith(""), "run-1", ActionSubscribe); err != nil {
			t.Fatalf("iter %d: %v", i, err)
		}
	}
	if f.calls != 1 {
		t.Fatalf("expected exactly 1 fetcher call for the cache; got %d", f.calls)
	}
}

func TestJWTAuthorizer_AlgNoneRejected(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)

	// Hand-craft a `alg: none` token (no signature). Vulnerable
	// libraries accept this; ours must reject.
	header := `eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0` // {"alg":"none","typ":"JWT"}
	payload := `eyJzdWIiOiJ1c2VyLUEifQ`             // {"sub":"user-A"}
	noneToken := header + "." + payload + "."

	if err := a.Authorize(reqWith("Bearer "+noneToken), "run-1", ActionPush); err == nil {
		t.Fatal("alg:none token must be rejected")
	}
}

func TestJWTAuthorizer_NilSecretFactoryReturnsNil(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{}
	if a := NewJWTAuthorizer("", hub, f); a != nil {
		t.Fatal("empty secret must produce a nil authorizer so callers fall back to permissive dev mode")
	}
}

func TestBearerToken(t *testing.T) {
	cases := []struct {
		header string
		want   string
	}{
		{"", ""},
		{"Bearer abc.def.ghi", "abc.def.ghi"},
		{"Bearer   spaced  ", "spaced"},
		{"Token abc", ""},
		// Case-insensitive scheme per RFC 7235 §2.1 — /audit/livehub M9.
		{"bearer abc", "abc"},
		{"BEARER abc", "abc"},
		{"BeArEr abc", "abc"},
	}
	for _, c := range cases {
		got := bearerToken(reqWith(c.header))
		if got != c.want {
			t.Errorf("bearerToken(%q) = %q, want %q", c.header, got, c.want)
		}
	}
}

func TestBearerToken_QuerystringFallbackForGET(t *testing.T) {
	// audit/livehub C1: browser WebSocket clients can't set Authorization
	// headers on the upgrade. Falling back to `?token=<jwt>` is the
	// only available channel on GET requests (subscribe + snapshot).
	// POST (push) keeps requiring the header — mobile + server-to-
	// server callers can set headers freely.
	t.Run("GET reads ?token=… when header missing", func(t *testing.T) {
		r, _ := http.NewRequest(http.MethodGet, "https://h/v1/live/r/subscribe?token=abc.def", nil)
		if got := bearerToken(r); got != "abc.def" {
			t.Fatalf("bearerToken(GET ?token=) = %q, want %q", got, "abc.def")
		}
	})
	t.Run("POST does NOT read ?token=… (header-only)", func(t *testing.T) {
		r, _ := http.NewRequest(http.MethodPost, "https://h/v1/live/r/push?token=abc.def", nil)
		if got := bearerToken(r); got != "" {
			t.Fatalf("bearerToken(POST ?token=) = %q, want empty (POST requires header)", got)
		}
	})
	t.Run("Header takes precedence over querystring", func(t *testing.T) {
		r, _ := http.NewRequest(http.MethodGet, "https://h/v1/live/r/subscribe?token=fromquery", nil)
		r.Header.Set("Authorization", "Bearer fromheader")
		if got := bearerToken(r); got != "fromheader" {
			t.Fatalf("bearerToken header+query = %q, want header value", got)
		}
	})
}

// TestJWTAuthorizer_EndToEndOnServer wires the authorizer into a
// real Server + httptest.Server and pushes a ping over HTTP. This
// pins the contract that the Server.Authorizer integration point
// actually fires per-request and produces the right HTTP status.
func TestJWTAuthorizer_EndToEndOnServer(t *testing.T) {
	hub := NewHub()
	f := &fakeRunMetaFetcher{rows: map[string]*RunMeta{
		"run-1": {UserID: "user-A", IsPublic: false},
	}}
	a := NewJWTAuthorizer(testJWTSecret, hub, f)

	srv := &Server{Hub: hub, Authorizer: a.Authorize}
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	defer ts.Close()

	// Unauthenticated push → 403.
	resp, err := http.Post(ts.URL+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":51.5,"lng":-0.1}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("unauth push: status = %d, want 403", resp.StatusCode)
	}

	// Owner push → 202.
	token := signTestToken(t, "user-A", 60)
	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/v1/live/run-1/push",
		strings.NewReader(`{"lat":51.5,"lng":-0.1}`))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp2, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp2.Body.Close()
	if resp2.StatusCode != http.StatusAccepted {
		t.Fatalf("owner push: status = %d, want 202", resp2.StatusCode)
	}
}
