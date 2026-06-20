// Package digesttoken is the stateless, keyed-HMAC unsubscribe token for the
// engagement-mail streams (RFC 8058 one-click unsubscribe). It serves both the
// weekly digest and the lifecycle drip — one MAC mechanism, namespaced per
// stream so a token minted for one stream can never verify against another.
//
// Design (migration 20270108_001 + docs/features/email.md § Engagement):
// the token is an HMAC-SHA256 over the constant string "<stream>:<user_id>",
// keyed by an operator secret, base64url-encoded. It carries NO PII (the user
// id is the HMAC INPUT, not the payload — you cannot recover it from the
// token) and needs NO token table — the unsubscribe endpoint is handed the
// user id alongside the token and recomputes the expected MAC to verify, in
// constant time.
//
// Why a keyed MAC and not a random nonce in a table: the builder must mint a
// fresh unsubscribe URL for every recipient on every send without a round-trip
// to persist a nonce, and a logged-out click must verify without a DB read on
// the hot path. A stateless MAC gives both — the only state is the single
// operator secret.
//
// Fail-closed: an empty secret, an empty user id, an empty stream, a malformed
// token, or a MAC mismatch all return false from Verify. The unsubscribe
// endpoint treats every false as a hard refuse.
package digesttoken

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
)

// Stream namespaces the MAC so a token minted for one engagement stream can
// never be replayed against another signed with the same secret. New streams
// add a const here; the value is part of the signed input, so it must stay
// stable once minted links are in the wild.
const (
	StreamWeeklyDigest  = "weekly_digest"
	StreamLifecycleDrip = "lifecycle_drip"
)

// Mint returns the base64url unsubscribe token for a user on a stream. An
// empty secret, user id, or stream yields "" so a misconfigured builder
// produces an obviously invalid (un-verifiable) link rather than a forgeable
// one.
func Mint(secret, stream, userID string) string {
	if secret == "" || stream == "" || userID == "" {
		return ""
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(stream + ":" + userID))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

// Verify reports whether token is the valid unsubscribe token for userID on
// stream under secret. Constant-time comparison (hmac.Equal) so a caller can't
// time-probe the MAC byte by byte. Fails closed on any empty input or a token
// that isn't valid base64url.
func Verify(secret, stream, userID, token string) bool {
	if secret == "" || stream == "" || userID == "" || token == "" {
		return false
	}
	got, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(stream + ":" + userID))
	return hmac.Equal(got, mac.Sum(nil))
}
