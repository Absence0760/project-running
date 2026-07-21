package supajwt

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testKid = "77243e23-0f5d-40ad-9606-e8e35932bb4d"

func ecJWKS(t *testing.T, key *ecdsa.PublicKey, kid string) string {
	t.Helper()
	byteLen := (key.Curve.Params().BitSize + 7) / 8
	xb := make([]byte, byteLen)
	yb := make([]byte, byteLen)
	key.X.FillBytes(xb)
	key.Y.FillBytes(yb)
	doc := map[string]any{"keys": []map[string]string{{
		"kty": "EC", "crv": "P-256", "use": "sig", "alg": "ES256", "kid": kid,
		"x": base64.RawURLEncoding.EncodeToString(xb),
		"y": base64.RawURLEncoding.EncodeToString(yb),
	}}}
	b, err := json.Marshal(doc)
	if err != nil {
		t.Fatalf("marshal jwks: %v", err)
	}
	return string(b)
}

// jwksServer serves a JWKS document and counts fetches so the refresh
// throttle can be asserted on.
func jwksServer(t *testing.T, body *atomic.Value, hits *atomic.Int64) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != jwksPath {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		hits.Add(1)
		w.Header().Set("content-type", "application/json")
		fmt.Fprint(w, body.Load().(string))
	}))
	t.Cleanup(srv.Close)
	return srv
}

func signES256(t *testing.T, key *ecdsa.PrivateKey, kid, sub string, exp time.Time) string {
	t.Helper()
	tok := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"sub": sub, "exp": exp.Unix(),
	})
	if kid != "" {
		tok.Header["kid"] = kid
	}
	s, err := tok.SignedString(key)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return s
}

func signHS256(t *testing.T, secret []byte, sub string, exp time.Time) string {
	t.Helper()
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": sub, "exp": exp.Unix(),
	}).SignedString(secret)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return s
}

func newECVerifier(t *testing.T) (*Verifier, *ecdsa.PrivateKey, *atomic.Value, *atomic.Int64) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("keygen: %v", err)
	}
	body := &atomic.Value{}
	body.Store(ecJWKS(t, &key.PublicKey, testKid))
	hits := &atomic.Int64{}
	srv := jwksServer(t, body, hits)
	return New("", srv.URL, srv.Client()), key, body, hits
}

func TestSubjectAcceptsES256FromJWKS(t *testing.T) {
	v, key, _, _ := newECVerifier(t)
	tok := signES256(t, key, testKid, "user-1", time.Now().Add(time.Hour))
	sub, err := v.Subject(tok)
	if err != nil {
		t.Fatalf("expected valid token, got %v", err)
	}
	if sub != "user-1" {
		t.Fatalf("sub = %q, want user-1", sub)
	}
}

func TestSubjectRejectsExpiredES256(t *testing.T) {
	v, key, _, _ := newECVerifier(t)
	tok := signES256(t, key, testKid, "user-1", time.Now().Add(-time.Minute))
	if _, err := v.Subject(tok); err == nil {
		t.Fatal("expired token accepted")
	}
}

// A token with no exp would otherwise be valid forever.
func TestSubjectRejectsMissingExp(t *testing.T) {
	v, key, _, _ := newECVerifier(t)
	tok := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{"sub": "user-1"})
	tok.Header["kid"] = testKid
	raw, err := tok.SignedString(key)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	if _, err := v.Subject(raw); err == nil {
		t.Fatal("token without exp accepted")
	}
}

func TestSubjectRejectsWrongSigningKey(t *testing.T) {
	v, _, _, _ := newECVerifier(t)
	other, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("keygen: %v", err)
	}
	tok := signES256(t, other, testKid, "user-1", time.Now().Add(time.Hour))
	if _, err := v.Subject(tok); err == nil {
		t.Fatal("token signed by an unrelated key accepted")
	}
}

func TestSubjectRejectsUnknownKid(t *testing.T) {
	v, key, _, _ := newECVerifier(t)
	tok := signES256(t, key, "not-the-kid", "user-1", time.Now().Add(time.Hour))
	if _, err := v.Subject(tok); err == nil {
		t.Fatal("token with unknown kid accepted")
	}
}

// The attack this design exists to defeat: JWKS public keys are public,
// so if the HMAC branch ever returned one, anyone could mint a token.
// With no shared secret configured, HS256 must not even be an allowed
// method.
func TestJWKSOnlyVerifierRejectsHS256SignedWithPublicKey(t *testing.T) {
	v, key, _, _ := newECVerifier(t)
	byteLen := (key.Curve.Params().BitSize + 7) / 8
	xb := make([]byte, byteLen)
	key.X.FillBytes(xb)

	forged := signHS256(t, xb, "user-1", time.Now().Add(time.Hour))
	if _, err := v.Subject(forged); err == nil {
		t.Fatal("HS256 token forged with the public key was accepted")
	}
	for _, m := range v.Methods() {
		if m == "HS256" {
			t.Fatal("HS256 advertised with no shared secret configured")
		}
	}
}

func TestSubjectRejectsAlgNone(t *testing.T) {
	v, _, _, _ := newECVerifier(t)
	raw, err := jwt.NewWithClaims(jwt.SigningMethodNone, jwt.MapClaims{
		"sub": "user-1", "exp": time.Now().Add(time.Hour).Unix(),
	}).SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	if _, err := v.Subject(raw); err == nil {
		t.Fatal("alg=none accepted")
	}
}

// Local dev and CI still issue HS256; production is ES256. Both must
// verify from one binary.
func TestHybridVerifierAcceptsBothSchemes(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("keygen: %v", err)
	}
	body := &atomic.Value{}
	body.Store(ecJWKS(t, &key.PublicKey, testKid))
	hits := &atomic.Int64{}
	srv := jwksServer(t, body, hits)

	secret := []byte("local-dev-secret")
	v := New(string(secret), srv.URL, srv.Client())

	if sub, err := v.Subject(signHS256(t, secret, "hs-user", time.Now().Add(time.Hour))); err != nil || sub != "hs-user" {
		t.Fatalf("HS256 path: sub=%q err=%v", sub, err)
	}
	if sub, err := v.Subject(signES256(t, key, testKid, "es-user", time.Now().Add(time.Hour))); err != nil || sub != "es-user" {
		t.Fatalf("ES256 path: sub=%q err=%v", sub, err)
	}
}

// A rotated key must heal without a redeploy.
func TestUnknownKidTriggersRefresh(t *testing.T) {
	v, _, body, hits := newECVerifier(t)
	v.jwks.minRefresh = 0

	rotated, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("keygen: %v", err)
	}
	const newKid = "rotated-kid"
	body.Store(ecJWKS(t, &rotated.PublicKey, newKid))

	before := hits.Load()
	sub, err := v.Subject(signES256(t, rotated, newKid, "user-2", time.Now().Add(time.Hour)))
	if err != nil {
		t.Fatalf("rotated key not picked up: %v", err)
	}
	if sub != "user-2" {
		t.Fatalf("sub = %q, want user-2", sub)
	}
	if hits.Load() <= before {
		t.Fatal("expected a JWKS refetch after the kid miss")
	}
}

// Unknown kids must not become an outbound-request amplifier.
func TestRefreshIsThrottledOnRepeatedUnknownKid(t *testing.T) {
	v, key, _, hits := newECVerifier(t)
	// Warm the cache so lastFetch is recent.
	if _, err := v.Subject(signES256(t, key, testKid, "user-1", time.Now().Add(time.Hour))); err != nil {
		t.Fatalf("warm-up: %v", err)
	}
	after := hits.Load()
	for range 20 {
		bogus := signES256(t, key, "bogus-kid", "user-1", time.Now().Add(time.Hour))
		if _, err := v.Subject(bogus); err == nil {
			t.Fatal("bogus kid accepted")
		}
	}
	if hits.Load() != after {
		t.Fatalf("throttle breached: %d extra fetches", hits.Load()-after)
	}
}

func TestEnabledAndDescribe(t *testing.T) {
	if (&Verifier{}).Enabled() {
		t.Fatal("empty verifier reports enabled")
	}
	if got := New("s", "", nil).Describe(); got != "shared secret (HS256)" {
		t.Fatalf("Describe() = %q", got)
	}
	if got := New("", "https://x.supabase.co", nil).Describe(); got != "JWKS (ES256/RS256)" {
		t.Fatalf("Describe() = %q", got)
	}
	if got := New("s", "https://x.supabase.co", nil).Describe(); got != "JWKS (ES256/RS256) + shared secret (HS256)" {
		t.Fatalf("Describe() = %q", got)
	}
}

func TestRSAKeyParses(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("keygen: %v", err)
	}
	doc := map[string]any{"keys": []map[string]string{{
		"kty": "RSA", "use": "sig", "alg": "RS256", "kid": testKid,
		"n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
		"e": base64.RawURLEncoding.EncodeToString([]byte{1, 0, 1}),
	}}}
	b, err := json.Marshal(doc)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	body := &atomic.Value{}
	body.Store(string(b))
	hits := &atomic.Int64{}
	srv := jwksServer(t, body, hits)

	v := New("", srv.URL, srv.Client())
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"sub": "rsa-user", "exp": time.Now().Add(time.Hour).Unix(),
	})
	tok.Header["kid"] = testKid
	raw, err := tok.SignedString(key)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	if sub, err := v.Subject(raw); err != nil || sub != "rsa-user" {
		t.Fatalf("RSA path: sub=%q err=%v", sub, err)
	}
}

func TestJWKSFetchFailureDenies(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	t.Cleanup(srv.Close)
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("keygen: %v", err)
	}
	v := New("", srv.URL, srv.Client())
	if _, err := v.Subject(signES256(t, key, testKid, "user-1", time.Now().Add(time.Hour))); err == nil {
		t.Fatal("token accepted despite JWKS being unreachable")
	}
}
