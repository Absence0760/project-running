package livehub

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"
)

// JWTAuthorizer plugs into [Server.Authorizer] to enforce the live
// hub's auth contract:
//
//   - POST /v1/live/{run_id}/push — Bearer JWT required, the JWT's
//     `sub` must equal `runs.user_id`. The recorder is the only
//     legitimate publisher; anyone else gets 403 even if they know
//     the run id. **No anon fall-through.**
//   - GET  /v1/live/{run_id}/subscribe (WS) and /snapshot —
//     anon is allowed when `runs.is_public=true`; otherwise a Bearer
//     JWT is required and `sub` must equal `runs.user_id`.
//
// Supabase issues HS256 tokens signed with the project's
// `SUPABASE_JWT_SECRET`. Verification + `sub` extraction is done
// here; the run-meta lookup goes through [Hub.LoadRunMeta] so a hot
// runner's push path is one in-memory map lookup after the first
// hit per run.
//
// A missing run row (RunMeta returns nil, nil) denies — we'd rather
// drop a publish than create a phantom room for a runID the database
// has never seen.
type JWTAuthorizer struct {
	// JWTSecret is the bytes the Supabase project signs tokens with.
	// Sourced from the `SUPABASE_JWT_SECRET` environment variable.
	JWTSecret []byte

	// Hub + Fetcher resolve the run owner / public flag. The
	// authorizer never touches Supabase directly — it goes through
	// the room cache so a hot publisher's per-second push is a
	// single map lookup after warm-up.
	Hub     *Hub
	Fetcher RunMetaFetcher
}

// NewJWTAuthorizer is the wiring helper main.go uses. Returns nil
// when [secret] is empty — caller falls back to the permissive
// (dev) authorizer in that case rather than booting up insecure.
func NewJWTAuthorizer(secret string, hub *Hub, fetcher RunMetaFetcher) *JWTAuthorizer {
	if secret == "" {
		return nil
	}
	return &JWTAuthorizer{
		JWTSecret: []byte(secret),
		Hub:       hub,
		Fetcher:   fetcher,
	}
}

// Authorize is the [Server.Authorizer]-shaped callback. Returns nil
// to allow, a non-nil error (becomes the 403 body) to deny.
func (a *JWTAuthorizer) Authorize(r *http.Request, runID string, action AuthAction) error {
	meta, err := a.Hub.LoadRunMeta(r.Context(), runID, a.Fetcher)
	if err != nil {
		return fmt.Errorf("auth: run lookup failed")
	}
	if meta == nil {
		return errors.New("auth: unknown run")
	}

	switch action {
	case ActionPush:
		// Publishes are owner-only. No anon path. Even a public run
		// is owner-only on the publish side — the recorder is the
		// single legitimate writer.
		sub, err := a.extractSub(r)
		if err != nil {
			return err
		}
		if sub != meta.UserID {
			return errors.New("auth: not the run owner")
		}
		return nil

	case ActionSubscribe, ActionSnapshot:
		// Public runs are readable anonymously. Skip the JWT check
		// entirely in that case so a spectator can open the share
		// URL without an account.
		if meta.IsPublic {
			return nil
		}
		// Private run → owner-only.
		sub, err := a.extractSub(r)
		if err != nil {
			return err
		}
		if sub != meta.UserID {
			return errors.New("auth: not the run owner")
		}
		return nil
	}
	return fmt.Errorf("auth: unknown action %q", action)
}

// extractSub parses the Authorization header, verifies the HS256
// signature with [JWTSecret], checks expiry, and returns the `sub`
// claim (the Supabase user_id).
func (a *JWTAuthorizer) extractSub(r *http.Request) (string, error) {
	raw := bearerToken(r)
	if raw == "" {
		return "", errors.New("auth: missing bearer token")
	}
	tok, err := jwt.Parse(raw, func(t *jwt.Token) (interface{}, error) {
		// Reject any alg the issuer wouldn't sign with — defends
		// against the classic alg-confusion attack where a forged
		// token claims `alg: none` or an RS256 token gets verified
		// against the HMAC secret.
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return a.JWTSecret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil {
		return "", fmt.Errorf("auth: invalid token")
	}
	if !tok.Valid {
		return "", errors.New("auth: invalid token")
	}
	claims, ok := tok.Claims.(jwt.MapClaims)
	if !ok {
		return "", errors.New("auth: invalid claims")
	}
	subClaim, ok := claims["sub"].(string)
	if !ok || subClaim == "" {
		return "", errors.New("auth: missing sub claim")
	}
	return subClaim, nil
}

// bearerToken pulls the raw token out of an `Authorization: Bearer
// <jwt>` header. Returns "" when absent or malformed — the caller
// produces the 403, so this is a pure parse helper.
func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if h == "" {
		return ""
	}
	const prefix = "Bearer "
	if !strings.HasPrefix(h, prefix) {
		return ""
	}
	return strings.TrimSpace(h[len(prefix):])
}

// Compile-time check that JWTAuthorizer.Authorize matches the
// [Server.Authorizer] callback shape. The cast doesn't run at
// runtime; it just refuses to compile if the signatures drift.
var _ func(*http.Request, string, AuthAction) error = (*JWTAuthorizer)(nil).Authorize
