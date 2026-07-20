// Package supajwt verifies Supabase user access tokens.
//
// Supabase projects sign user tokens one of two ways. Legacy projects
// use a shared HS256 secret (`SUPABASE_JWT_SECRET`), which the verifier
// holds directly. Projects migrated to JWT signing keys use asymmetric
// keys (ES256 / RS256) whose PUBLIC halves are published at
// `<project>/auth/v1/.well-known/jwks.json` — there is no shared secret
// to hold, so verification means fetching the JWKS and matching the
// token's `kid`.
//
// Both paths coexist deliberately: the local dev stack and CI issue
// HS256 tokens, while the production project is on ES256.
package supajwt

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

// jwksPath is appended to the project URL. GoTrue serves the project's
// public signing keys here; the document is public by design.
const jwksPath = "/auth/v1/.well-known/jwks.json"

// defaultMinRefresh throttles re-fetching after a `kid` miss. Without
// it, a caller spraying tokens bearing random `kid`s would turn every
// request into an outbound HTTP fetch — a free amplification channel
// against both us and the Supabase auth endpoint.
const defaultMinRefresh = 5 * time.Minute

// JWKS caches a project's public signing keys, refreshing when a token
// presents an unrecognised `kid` so that a key rotation heals without a
// redeploy.
type JWKS struct {
	url  string
	http *http.Client

	// minRefresh is the floor between two network fetches triggered by
	// a cache miss. A successful fetch resets the clock.
	minRefresh time.Duration

	mu        sync.RWMutex
	keys      map[string]crypto.PublicKey
	lastFetch time.Time
}

// NewJWKS builds a key set for a Supabase project URL
// (`https://<ref>.supabase.co`). Passing an empty URL returns nil so
// callers can treat "no asymmetric verification configured" as a
// nil-check rather than a sentinel.
func NewJWKS(projectURL string, hc *http.Client) *JWKS {
	if projectURL == "" {
		return nil
	}
	if hc == nil {
		hc = &http.Client{Timeout: 10 * time.Second}
	}
	return &JWKS{
		url:        strings.TrimRight(projectURL, "/") + jwksPath,
		http:       hc,
		minRefresh: defaultMinRefresh,
		keys:       map[string]crypto.PublicKey{},
	}
}

// Key returns the public key for kid, fetching the JWKS if the kid is
// unknown and the refresh throttle allows it.
func (j *JWKS) Key(kid string) (crypto.PublicKey, error) {
	if kid == "" {
		return nil, errors.New("token has no kid")
	}
	j.mu.RLock()
	k, ok := j.keys[kid]
	stale := time.Since(j.lastFetch) >= j.minRefresh
	j.mu.RUnlock()
	if ok {
		return k, nil
	}
	if !stale {
		// Recently refreshed and still no match: the kid is bogus
		// rather than newly rotated. Refusing here is what keeps an
		// unknown-kid flood from becoming an outbound request flood.
		return nil, fmt.Errorf("unknown kid %q", kid)
	}
	if err := j.refresh(); err != nil {
		return nil, err
	}
	j.mu.RLock()
	defer j.mu.RUnlock()
	if k, ok := j.keys[kid]; ok {
		return k, nil
	}
	return nil, fmt.Errorf("unknown kid %q", kid)
}

// refresh replaces the cached key set. The timestamp advances even on
// failure so a hard-down JWKS endpoint can't be used to drive one
// outbound fetch per inbound request.
func (j *JWKS) refresh() error {
	j.mu.Lock()
	j.lastFetch = time.Now()
	j.mu.Unlock()

	resp, err := j.http.Get(j.url)
	if err != nil {
		return fmt.Errorf("jwks fetch: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("jwks fetch: status %d", resp.StatusCode)
	}
	var doc struct {
		Keys []jwk `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&doc); err != nil {
		return fmt.Errorf("jwks decode: %w", err)
	}
	parsed := make(map[string]crypto.PublicKey, len(doc.Keys))
	for _, k := range doc.Keys {
		// A signing key with no kid can't be matched against a token
		// header, and a key we can't parse is not a key we should
		// silently treat as absent-but-fine. Skip both; a token
		// bearing that kid then fails closed.
		if k.Kid == "" {
			continue
		}
		pub, err := k.publicKey()
		if err != nil {
			continue
		}
		parsed[k.Kid] = pub
	}
	if len(parsed) == 0 {
		return errors.New("jwks contained no usable keys")
	}
	j.mu.Lock()
	j.keys = parsed
	j.mu.Unlock()
	return nil
}

// jwk is the subset of RFC 7517 we consume: EC and RSA public keys.
type jwk struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Crv string `json:"crv"`
	X   string `json:"x"`
	Y   string `json:"y"`
	N   string `json:"n"`
	E   string `json:"e"`
}

func (k jwk) publicKey() (crypto.PublicKey, error) {
	switch k.Kty {
	case "EC":
		return k.ecKey()
	case "RSA":
		return k.rsaKey()
	default:
		return nil, fmt.Errorf("unsupported kty %q", k.Kty)
	}
}

func (k jwk) ecKey() (crypto.PublicKey, error) {
	var curve elliptic.Curve
	switch k.Crv {
	case "P-256":
		curve = elliptic.P256()
	case "P-384":
		curve = elliptic.P384()
	case "P-521":
		curve = elliptic.P521()
	default:
		return nil, fmt.Errorf("unsupported crv %q", k.Crv)
	}
	x, err := b64uint(k.X)
	if err != nil {
		return nil, err
	}
	y, err := b64uint(k.Y)
	if err != nil {
		return nil, err
	}
	pub := &ecdsa.PublicKey{Curve: curve, X: x, Y: y}
	if !curve.IsOnCurve(x, y) {
		return nil, errors.New("ec point not on curve")
	}
	return pub, nil
}

func (k jwk) rsaKey() (crypto.PublicKey, error) {
	n, err := b64uint(k.N)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(k.E)
	if err != nil {
		return nil, fmt.Errorf("rsa exponent: %w", err)
	}
	if len(eBytes) == 0 || len(eBytes) > 8 {
		return nil, errors.New("rsa exponent out of range")
	}
	padded := make([]byte, 8)
	copy(padded[8-len(eBytes):], eBytes)
	e := binary.BigEndian.Uint64(padded)
	if e < 3 || e > 1<<31-1 {
		return nil, errors.New("rsa exponent out of range")
	}
	return &rsa.PublicKey{N: n, E: int(e)}, nil
}

func b64uint(s string) (*big.Int, error) {
	if s == "" {
		return nil, errors.New("empty key parameter")
	}
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return nil, fmt.Errorf("base64url: %w", err)
	}
	return new(big.Int).SetBytes(b), nil
}
