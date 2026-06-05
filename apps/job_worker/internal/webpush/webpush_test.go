package webpush

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	jwt "github.com/golang-jwt/jwt/v5"
)

// newUASubscription mints a browser-side subscription: an ECDH keypair whose
// public point is p256dh and a random 16-byte auth secret. Returns the
// subscription (as the server sees it) plus the UA private key (so the test
// can decrypt what the server encrypted).
func newUASubscription(t *testing.T, endpoint string) (Subscription, *ecdh.PrivateKey) {
	t.Helper()
	priv, err := ecdh.P256().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("ua keygen: %v", err)
	}
	auth := make([]byte, 16)
	if _, err := rand.Read(auth); err != nil {
		t.Fatalf("auth: %v", err)
	}
	return Subscription{
		Endpoint: endpoint,
		P256dh:   base64.RawURLEncoding.EncodeToString(priv.PublicKey().Bytes()),
		Auth:     base64.RawURLEncoding.EncodeToString(auth),
	}, priv
}

// uaDecryptWith reverses encrypt() using the UA private key + auth secret —
// the proof that a real browser push service + service worker would recover
// the cleartext (RFC 8291/8188 decryption).
func uaDecryptWith(t *testing.T, body []byte, uaPriv *ecdh.PrivateKey, authSecret []byte) []byte {
	t.Helper()
	salt := body[:16]
	idlen := int(body[20])
	keyid := body[21 : 21+idlen]
	ciphertext := body[21+idlen:]

	asPub, err := ecdh.P256().NewPublicKey(keyid)
	if err != nil {
		t.Fatalf("parse as_public: %v", err)
	}
	shared, err := uaPriv.ECDH(asPub)
	if err != nil {
		t.Fatalf("ua ecdh: %v", err)
	}
	keyInfo := append(append([]byte("WebPush: info\x00"), uaPriv.PublicKey().Bytes()...), keyid...)
	ikm, err := hkdf.Key(sha256.New, shared, authSecret, string(keyInfo), 32)
	if err != nil {
		t.Fatalf("ikm: %v", err)
	}
	prk, err := hkdf.Extract(sha256.New, ikm, salt)
	if err != nil {
		t.Fatalf("extract: %v", err)
	}
	cek, _ := hkdf.Expand(sha256.New, prk, "Content-Encoding: aes128gcm\x00", 16)
	nonce, _ := hkdf.Expand(sha256.New, prk, "Content-Encoding: nonce\x00", 12)
	block, _ := aes.NewCipher(cek)
	gcm, _ := cipher.NewGCM(block)
	plain, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		t.Fatalf("gcm open: %v", err)
	}
	return plain
}

func TestEncrypt_RoundTrip(t *testing.T) {
	sub, uaPriv := newUASubscription(t, "https://push.example/abc")
	authSecret, _ := base64.RawURLEncoding.DecodeString(sub.Auth)

	ephemeral, _ := ecdh.P256().GenerateKey(rand.Reader)
	salt := make([]byte, 16)
	_, _ = rand.Read(salt)

	payload := []byte(`{"title":"New kudos","body":"someone liked your run","url":"/runs/1"}`)
	body, err := encrypt(payload, sub, ephemeral, salt)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}

	// Header sanity: salt prefix, record size, 65-byte keyid.
	if got := body[:16]; string(got) != string(salt) {
		t.Errorf("salt prefix mismatch")
	}
	if rs := binary.BigEndian.Uint32(body[16:20]); rs != 4096 {
		t.Errorf("record size = %d, want 4096", rs)
	}
	if idlen := int(body[20]); idlen != 65 {
		t.Errorf("idlen = %d, want 65", idlen)
	}

	plain := uaDecryptWith(t, body, uaPriv, authSecret)
	// The recovered plaintext is payload + the 0x02 final-record delimiter.
	if len(plain) != len(payload)+1 || plain[len(plain)-1] != 0x02 {
		t.Fatalf("delimiter missing: tail=%v", plain[len(plain)-1:])
	}
	if string(plain[:len(payload)]) != string(payload) {
		t.Errorf("decrypted mismatch:\n got %q\nwant %q", plain[:len(payload)], payload)
	}
}

func TestEncrypt_RejectsBadKeys(t *testing.T) {
	ephemeral, _ := ecdh.P256().GenerateKey(rand.Reader)
	salt := make([]byte, 16)
	bad := Subscription{Endpoint: "https://push.example/x", P256dh: "!!notb64!!", Auth: "AAAA"}
	if _, err := encrypt([]byte("x"), bad, ephemeral, salt); err == nil {
		t.Fatal("expected error on undecodable p256dh")
	}
	bad2 := Subscription{Endpoint: "https://push.example/x", P256dh: base64.RawURLEncoding.EncodeToString([]byte("tooshort")), Auth: base64.RawURLEncoding.EncodeToString(make([]byte, 16))}
	if _, err := encrypt([]byte("x"), bad2, ephemeral, salt); err == nil {
		t.Fatal("expected error on malformed UA public key")
	}
}

// makeVAPID generates a VAPID keypair as the operator would (base64url public
// point + base64url 32-byte private scalar).
func makeVAPID(t *testing.T) (pub, priv string, ecKey *ecdsa.PrivateKey) {
	t.Helper()
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("vapid keygen: %v", err)
	}
	pubBytes := elliptic.Marshal(elliptic.P256(), k.PublicKey.X, k.PublicKey.Y)
	d := k.D.Bytes()
	// Left-pad the scalar to 32 bytes (a small D would otherwise be short).
	if len(d) < 32 {
		padded := make([]byte, 32)
		copy(padded[32-len(d):], d)
		d = padded
	}
	return base64.RawURLEncoding.EncodeToString(pubBytes),
		base64.RawURLEncoding.EncodeToString(d), k
}

func TestNewSender_RejectsMismatchedKeypair(t *testing.T) {
	pub, _, _ := makeVAPID(t)
	_, priv2, _ := makeVAPID(t)
	if _, err := NewSender("mailto:ops@threkir.test", pub, priv2, nil); err == nil {
		t.Fatal("expected mismatched VAPID keypair to be rejected")
	}
}

func TestNewSender_RejectsBadSubject(t *testing.T) {
	pub, priv, _ := makeVAPID(t)
	if _, err := NewSender("", pub, priv, nil); err == nil {
		t.Fatal("expected empty subject to be rejected")
	}
}

func TestSend_PostsEncryptedWithVapidHeader(t *testing.T) {
	pub, priv, ecKey := makeVAPID(t)

	var gotAuth, gotEncoding, gotTTL string
	var gotBody []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotEncoding = r.Header.Get("Content-Encoding")
		gotTTL = r.Header.Get("TTL")
		gotBody = make([]byte, r.ContentLength)
		_, _ = r.Body.Read(gotBody)
		w.WriteHeader(http.StatusCreated)
	}))
	defer srv.Close()

	sender, err := NewSender("mailto:ops@threkir.test", pub, priv, srv.Client())
	if err != nil {
		t.Fatalf("NewSender: %v", err)
	}
	sub, uaPriv := newUASubscription(t, srv.URL+"/push/1")
	authSecret, _ := base64.RawURLEncoding.DecodeString(sub.Auth)

	payload := []byte(`{"title":"hi"}`)
	status, err := sender.Send(context.Background(), sub, payload)
	if err != nil {
		t.Fatalf("Send: %v", err)
	}
	if status != http.StatusCreated {
		t.Errorf("status = %d, want 201", status)
	}
	if gotEncoding != "aes128gcm" {
		t.Errorf("Content-Encoding = %q", gotEncoding)
	}
	if gotTTL == "" {
		t.Errorf("TTL header missing")
	}
	if !strings.HasPrefix(gotAuth, "vapid t=") || !strings.Contains(gotAuth, ", k="+pub) {
		t.Errorf("Authorization header malformed: %q", gotAuth)
	}

	// The JWT in the header verifies against the public key with the right aud.
	tokenStr := strings.TrimPrefix(strings.Split(gotAuth, ", k=")[0], "vapid t=")
	claims := jwt.MapClaims{}
	_, err = jwt.ParseWithClaims(tokenStr, claims, func(_ *jwt.Token) (interface{}, error) {
		return &ecKey.PublicKey, nil
	}, jwt.WithValidMethods([]string{"ES256"}))
	if err != nil {
		t.Fatalf("VAPID JWT does not verify: %v", err)
	}
	wantAud := strings.TrimSuffix(srv.URL, "/")
	if claims["aud"] != wantAud {
		t.Errorf("aud = %v, want %v", claims["aud"], wantAud)
	}
	if claims["sub"] != "mailto:ops@threkir.test" {
		t.Errorf("sub = %v", claims["sub"])
	}

	// And the body the server received decrypts to the original payload.
	plain := uaDecryptWith(t, gotBody, uaPriv, authSecret)
	if string(plain[:len(payload)]) != string(payload) {
		t.Errorf("server body decrypt mismatch: %q", plain)
	}
}

func TestSend_ReturnsStatusForPruneAndRetry(t *testing.T) {
	pub, priv, _ := makeVAPID(t)
	for _, code := range []int{http.StatusGone, http.StatusNotFound, http.StatusTooManyRequests, http.StatusInternalServerError} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(code)
		}))
		sender, _ := NewSender("mailto:ops@threkir.test", pub, priv, srv.Client())
		sub, _ := newUASubscription(t, srv.URL+"/push")
		status, err := sender.Send(context.Background(), sub, []byte(`{"title":"x"}`))
		if err != nil {
			t.Fatalf("Send(%d): %v", code, err)
		}
		if status != code {
			t.Errorf("status = %d, want %d", status, code)
		}
		srv.Close()
	}
}

func TestSend_TransportErrorReturnsZeroStatus(t *testing.T) {
	pub, priv, _ := makeVAPID(t)
	srv := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) {}))
	client := srv.Client()
	srv.Close() // server is down → dial fails

	sender, _ := NewSender("mailto:ops@threkir.test", pub, priv, client)
	sub, _ := newUASubscription(t, srv.URL+"/push")
	status, err := sender.Send(context.Background(), sub, []byte(`{"title":"x"}`))
	if err == nil {
		t.Fatal("expected transport error")
	}
	if status != 0 {
		t.Errorf("status = %d, want 0 on transport failure", status)
	}
}

func TestDecodeB64_AcceptsPaddedAndRaw(t *testing.T) {
	raw := []byte{0x01, 0x02, 0x03, 0x04, 0x05}
	for _, s := range []string{
		base64.RawURLEncoding.EncodeToString(raw),
		base64.URLEncoding.EncodeToString(raw),
		base64.StdEncoding.EncodeToString(raw),
	} {
		got, err := decodeB64(s)
		if err != nil {
			t.Fatalf("decode %q: %v", s, err)
		}
		if string(got) != string(raw) {
			t.Errorf("decode %q = %v", s, got)
		}
	}
	if _, err := decodeB64(""); err == nil {
		t.Error("empty string should error")
	}
}
