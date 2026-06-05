// Package webpush is a dependency-light Web Push (RFC 8030) sender: VAPID
// request signing (RFC 8292) + aes128gcm message encryption (RFC 8291 over
// RFC 8188). It is the server leg of the web-push channel — the browser
// subscribe path (apps/web/src/lib/util/push.ts) stores a subscription on
// user_device_settings.prefs.push_subscription, and the worker's
// handler_web_push.go sends through this package.
//
// Built on the standard library (crypto/ecdh, crypto/hkdf, crypto/aes) plus
// golang-jwt (already a worker dependency) for the ES256 VAPID JWT — no
// third-party web-push library. Web Push encryption is a small, stable spec;
// vendoring a library for it would add a supply-chain surface for ~150 lines
// of stdlib crypto.
package webpush

import (
	"bytes"
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
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"time"

	jwt "github.com/golang-jwt/jwt/v5"
)

// Subscription is the browser-minted PushSubscription the client persisted.
// Mirrors StoredPushSubscription in apps/web/src/lib/util/push.ts: Endpoint
// is the push-service URL, P256dh + Auth are the user-agent's ECDH public key
// and auth secret (base64url, padding optional).
type Subscription struct {
	Endpoint string
	P256dh   string
	Auth     string
}

// Sender holds the VAPID identity + HTTP client. One instance is shared by
// the worker; Send is safe for concurrent use (it allocates a fresh
// ephemeral key + salt per message and never mutates the Sender).
type Sender struct {
	subject   string // VAPID `sub` claim — "mailto:..." or an https origin
	publicB64 string // VAPID public key, base64url-raw — the `k=` param + applicationServerKey the client subscribed with
	priv      *ecdsa.PrivateKey
	http      *http.Client
	ttl       int
	// now is the clock for the JWT exp claim; overridable in tests.
	now func() time.Time
}

// NewSender parses the VAPID keypair (public: base64url uncompressed P-256
// point; private: base64url 32-byte scalar) and returns a ready Sender.
// Validates that the private scalar derives the supplied public point so a
// mismatched pair fails at startup, not silently per-send.
func NewSender(subject, vapidPublicB64, vapidPrivateB64 string, httpClient *http.Client) (*Sender, error) {
	if subject == "" {
		return nil, fmt.Errorf("webpush: VAPID subject required")
	}
	pubBytes, err := decodeB64(vapidPublicB64)
	if err != nil {
		return nil, fmt.Errorf("webpush: bad VAPID public key: %w", err)
	}
	if len(pubBytes) != 65 || pubBytes[0] != 0x04 {
		return nil, fmt.Errorf("webpush: VAPID public key must be a 65-byte uncompressed P-256 point, got %d bytes", len(pubBytes))
	}
	dBytes, err := decodeB64(vapidPrivateB64)
	if err != nil {
		return nil, fmt.Errorf("webpush: bad VAPID private key: %w", err)
	}
	if len(dBytes) == 0 || len(dBytes) > 32 {
		return nil, fmt.Errorf("webpush: VAPID private key must be a 32-byte scalar, got %d bytes", len(dBytes))
	}
	priv := new(ecdsa.PrivateKey)
	priv.Curve = elliptic.P256()
	priv.D = new(big.Int).SetBytes(dBytes)
	priv.PublicKey.X, priv.PublicKey.Y = elliptic.P256().ScalarBaseMult(dBytes)
	derived := elliptic.Marshal(elliptic.P256(), priv.PublicKey.X, priv.PublicKey.Y) //nolint:staticcheck // crypto/ecdh has no Marshal; this is the documented path
	if !bytes.Equal(derived, pubBytes) {
		return nil, fmt.Errorf("webpush: VAPID private key does not match the public key")
	}

	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &Sender{
		subject:   subject,
		publicB64: base64.RawURLEncoding.EncodeToString(pubBytes),
		priv:      priv,
		http:      httpClient,
		ttl:       86400,
		now:       time.Now,
	}, nil
}

// Send encrypts payload for sub and POSTs it to the push service. Returns the
// HTTP status code (so the caller can prune a 404/410 subscription, retry a
// 429/5xx, and drop a 4xx) and a non-nil error only on a transport failure
// (status 0) or an encryption/sign failure before the request leaves.
//
// payload is the cleartext the service worker receives — the
// {title, body?, url?, tag?} JSON contract documented in apps/web/static/sw.js.
func (s *Sender) Send(ctx context.Context, sub Subscription, payload []byte) (int, error) {
	ephemeral, err := ecdh.P256().GenerateKey(rand.Reader)
	if err != nil {
		return 0, fmt.Errorf("webpush: ephemeral key: %w", err)
	}
	salt := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return 0, fmt.Errorf("webpush: salt: %w", err)
	}
	body, err := encrypt(payload, sub, ephemeral, salt)
	if err != nil {
		return 0, err
	}
	auth, err := s.vapidAuthHeader(sub.Endpoint)
	if err != nil {
		return 0, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, sub.Endpoint, bytes.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("webpush: build request: %w", err)
	}
	req.Header.Set("Content-Encoding", "aes128gcm")
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("TTL", fmt.Sprintf("%d", s.ttl))
	req.Header.Set("Authorization", auth)

	resp, err := s.http.Do(req)
	if err != nil {
		return 0, fmt.Errorf("webpush: POST %s: %w", endpointHost(sub.Endpoint), err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode, nil
}

// vapidAuthHeader builds the `vapid t=<jwt>, k=<pubkey>` Authorization value
// for the push service the endpoint belongs to (RFC 8292 §3). The JWT's `aud`
// is the endpoint's scheme://host; `exp` is bounded to 12 h (well under the
// 24 h ceiling); `sub` is the configured contact.
func (s *Sender) vapidAuthHeader(endpoint string) (string, error) {
	u, err := url.Parse(endpoint)
	if err != nil {
		return "", fmt.Errorf("webpush: bad endpoint: %w", err)
	}
	aud := u.Scheme + "://" + u.Host
	now := s.now()
	tok := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"aud": aud,
		"exp": now.Add(12 * time.Hour).Unix(),
		"sub": s.subject,
	})
	signed, err := tok.SignedString(s.priv)
	if err != nil {
		return "", fmt.Errorf("webpush: sign VAPID JWT: %w", err)
	}
	return "vapid t=" + signed + ", k=" + s.publicB64, nil
}

// encrypt builds the aes128gcm message body (RFC 8291 message encryption over
// the RFC 8188 framing). ephemeral + salt are parameters so a test can pin a
// deterministic ciphertext and round-trip-decrypt it; Send supplies fresh
// random ones.
//
// Body layout (single record, RFC 8188 §2.1):
//
//	salt(16) | rs(4, big-endian) | idlen(1) | keyid(=as_public, 65) | ciphertext
func encrypt(payload []byte, sub Subscription, ephemeral *ecdh.PrivateKey, salt []byte) ([]byte, error) {
	authSecret, err := decodeB64(sub.Auth)
	if err != nil {
		return nil, fmt.Errorf("webpush: bad subscription auth: %w", err)
	}
	uaPubBytes, err := decodeB64(sub.P256dh)
	if err != nil {
		return nil, fmt.Errorf("webpush: bad subscription p256dh: %w", err)
	}
	uaPub, err := ecdh.P256().NewPublicKey(uaPubBytes)
	if err != nil {
		return nil, fmt.Errorf("webpush: bad subscription public key: %w", err)
	}
	asPubBytes := ephemeral.PublicKey().Bytes() // 65-byte uncompressed point

	shared, err := ephemeral.ECDH(uaPub)
	if err != nil {
		return nil, fmt.Errorf("webpush: ECDH: %w", err)
	}

	// RFC 8291 §3.4 — derive the IKM for the content encryption from the
	// ECDH secret, keyed by the UA auth secret.
	keyInfo := bytes.Join([][]byte{
		[]byte("WebPush: info\x00"), uaPubBytes, asPubBytes,
	}, nil)
	ikm, err := hkdf.Key(sha256.New, shared, authSecret, string(keyInfo), 32)
	if err != nil {
		return nil, fmt.Errorf("webpush: derive ikm: %w", err)
	}

	// RFC 8188 §2.2 — derive CEK + nonce from the IKM keyed by the record salt.
	prk, err := hkdf.Extract(sha256.New, ikm, salt)
	if err != nil {
		return nil, fmt.Errorf("webpush: hkdf extract: %w", err)
	}
	cek, err := hkdf.Expand(sha256.New, prk, "Content-Encoding: aes128gcm\x00", 16)
	if err != nil {
		return nil, fmt.Errorf("webpush: derive cek: %w", err)
	}
	nonce, err := hkdf.Expand(sha256.New, prk, "Content-Encoding: nonce\x00", 12)
	if err != nil {
		return nil, fmt.Errorf("webpush: derive nonce: %w", err)
	}

	block, err := aes.NewCipher(cek)
	if err != nil {
		return nil, fmt.Errorf("webpush: aes: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("webpush: gcm: %w", err)
	}

	// Single, last record: payload followed by the 0x02 final-record
	// delimiter (RFC 8188 §2). No extra zero padding needed.
	plaintext := append(append([]byte{}, payload...), 0x02)
	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)

	const recordSize = 4096
	header := make([]byte, 0, 16+4+1+len(asPubBytes)+len(ciphertext))
	header = append(header, salt...)
	rs := make([]byte, 4)
	binary.BigEndian.PutUint32(rs, recordSize)
	header = append(header, rs...)
	header = append(header, byte(len(asPubBytes)))
	header = append(header, asPubBytes...)
	header = append(header, ciphertext...)
	return header, nil
}

// decodeB64 accepts base64url with or without padding (browsers send raw
// base64url; some libraries pad), and tolerates the standard alphabet too.
func decodeB64(s string) ([]byte, error) {
	if s == "" {
		return nil, fmt.Errorf("empty")
	}
	for _, enc := range []*base64.Encoding{
		base64.RawURLEncoding, base64.URLEncoding,
		base64.RawStdEncoding, base64.StdEncoding,
	} {
		if b, err := enc.DecodeString(s); err == nil {
			return b, nil
		}
	}
	return nil, fmt.Errorf("not valid base64")
}

func endpointHost(endpoint string) string {
	if u, err := url.Parse(endpoint); err == nil {
		return u.Host
	}
	return endpoint
}
