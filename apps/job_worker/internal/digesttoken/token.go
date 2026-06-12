// Package digesttoken is the stateless, keyed-HMAC unsubscribe token for
// the weekly-digest engagement mail (RFC 8058 one-click unsubscribe).
//
// Design (migration 20270108_001 + docs/features/email.md § Engagement):
// the token is an HMAC-SHA256 over the constant string
// "weekly_digest:<user_id>", keyed by an operator secret, base64url-encoded.
// It carries NO PII (the user id is the HMAC INPUT, not the payload — you
// cannot recover it from the token) and needs NO token table — the
// unsubscribe endpoint is handed the user id alongside the token and
// recomputes the expected MAC to verify, in constant time.
//
// Why a keyed MAC and not a random nonce in a table: the digest builder
// must mint a fresh unsubscribe URL for every recipient on every send
// without a round-trip to persist a nonce, and a logged-out click must
// verify without a DB read on the hot path. A stateless MAC gives both —
// the only state is the single operator secret.
//
// Fail-closed: an empty secret, an empty user id, a malformed token, or a
// MAC mismatch all return false from Verify. The unsubscribe endpoint
// treats every false as a hard refuse.
package digesttoken

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
)

// scope namespaces the MAC so a token minted for the weekly digest can
// never be replayed against a hypothetical future keyed-MAC unsubscribe
// for a different mail stream signed with the same secret.
const scope = "weekly_digest"

// Mint returns the base64url unsubscribe token for a user. An empty secret
// or user id yields "" so a misconfigured builder produces an obviously
// invalid (un-verifiable) link rather than a forgeable one.
func Mint(secret, userID string) string {
	if secret == "" || userID == "" {
		return ""
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(scope + ":" + userID))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

// Verify reports whether token is the valid unsubscribe token for userID
// under secret. Constant-time comparison (hmac.Equal) so a caller can't
// time-probe the MAC byte by byte. Fails closed on any empty input or a
// token that isn't valid base64url.
func Verify(secret, userID, token string) bool {
	if secret == "" || userID == "" || token == "" {
		return false
	}
	got, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(scope + ":" + userID))
	return hmac.Equal(got, mac.Sum(nil))
}
