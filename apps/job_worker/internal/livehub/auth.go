package livehub

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/Absence0760/project-running/apps/job_worker/internal/supajwt"
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
//     JWT is required and `sub` must equal `runs.user_id`. An
//     AUTHENTICATED viewer whom the run owner has blocked (in either
//     direction) is denied even on a public run — the live stream is
//     a social surface and honours the same `is_blocked_either_way`
//     predicate as kudos / comments / follows / segment boards / the
//     profile page. An anon viewer carries no identity to block, so a
//     public run stays anon-viewable (matching `public_profile_by_id`,
//     which allows `auth.uid() IS NULL`).
//
// Token verification is delegated to [supajwt.Verifier], which covers
// both the legacy shared-secret (HS256) projects and projects migrated
// to asymmetric JWT signing keys (ES256/RS256 via the project's JWKS).
// The run-meta lookup goes through [Hub.LoadRunMeta] so a hot runner's
// push path is one in-memory map lookup after the first hit per run.
//
// A missing run row (RunMeta returns nil, nil) denies — we'd rather
// drop a publish than create a phantom room for a runID the database
// has never seen.
type JWTAuthorizer struct {
	// Verifier resolves a bearer token to its `sub` claim. Built in
	// main.go from SUPABASE_JWT_SECRET and/or the project's JWKS.
	Verifier *supajwt.Verifier

	// Hub + Fetcher resolve the run owner / public flag. The
	// authorizer never touches Supabase directly — it goes through
	// the room cache so a hot publisher's per-second push is a
	// single map lookup after warm-up. `Hub` is the LivePubSub
	// interface so either the in-process broker or the Redis-backed
	// variant can plug in here.
	Hub     LivePubSub
	Fetcher RunMetaFetcher

	// Blocks resolves whether a spectator is blocked (either direction)
	// relative to the run owner. Wired in main.go to a
	// [SupabaseBlockChecker]. When nil the block gate on public-run
	// subscribe/snapshot fails closed — an authenticated non-owner
	// viewer is denied because block status can't be determined — so a
	// misconfiguration can't silently reopen the leak. Anon viewers and
	// the owner never reach the block check.
	Blocks BlockChecker
}

// NewJWTAuthorizer is the wiring helper main.go uses. Returns nil when
// the verifier has no key material at all — caller falls back to the
// permissive (dev) authorizer rather than booting up insecure.
func NewJWTAuthorizer(v *supajwt.Verifier, hub LivePubSub, fetcher RunMetaFetcher) *JWTAuthorizer {
	if !v.Enabled() {
		return nil
	}
	return &JWTAuthorizer{
		Verifier: v,
		Hub:      hub,
		Fetcher:  fetcher,
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
		if meta.IsPublic {
			// Public runs are readable anonymously — a spectator can open
			// the share URL without an account. But an AUTHENTICATED
			// viewer the owner has blocked (either direction) must not be
			// able to watch the live GPS stream, matching every other
			// social surface. A viewer with no verifiable identity is an
			// anon spectator and carries no block relationship to check.
			sub, err := a.extractSub(r)
			if err != nil {
				// No/invalid token → anon spectator of a public run. A
				// public run is anon-viewable regardless, so this is not
				// weaker than the prior behaviour; the block gate only
				// bites a viewer who presents a valid identity, exactly
				// as the SQL predicate only bites a non-null auth.uid().
				return nil
			}
			if sub == meta.UserID {
				// Owner watching their own public run.
				return nil
			}
			if a.Blocks == nil {
				// Fail-closed: block status can't be determined.
				return errors.New("auth: block check unavailable")
			}
			blocked, err := a.Blocks.IsBlockedEitherWay(r.Context(), sub, meta.UserID)
			if err != nil {
				return errors.New("auth: block check failed")
			}
			if blocked {
				return errors.New("auth: blocked by run owner")
			}
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

// extractSub parses the Authorization header and returns the verified
// `sub` claim (the Supabase user_id).
func (a *JWTAuthorizer) extractSub(r *http.Request) (string, error) {
	raw := bearerToken(r)
	if raw == "" {
		return "", errors.New("auth: missing bearer token")
	}
	sub, err := a.Verifier.Subject(raw)
	if err != nil {
		return "", errors.New("auth: invalid token")
	}
	return sub, nil
}

// bearerToken pulls the raw token out of an `Authorization: Bearer
// <jwt>` header. Returns "" when absent or malformed — the caller
// produces the 403, so this is a pure parse helper.
//
// Scheme comparison is case-insensitive per RFC 7235 §2.1: clients
// in the wild send `bearer`, `BEARER`, etc. Audit/livehub M9.
//
// Browser WebSocket clients can't set arbitrary headers on the
// `Upgrade` request — fall back to `?token=<jwt>` for GET requests
// (subscribe + snapshot only — push always requires the header,
// since a mobile / server caller can set headers freely and we
// don't want pings logged in webserver access logs). The token-
// in-URL is acceptable for WS subscribe because the client owns
// the URL and there's no third-party redirect surface.
// Audit/livehub C1.
//
// SECURITY: any code in this file (or in server.go) that logs a
// request URL MUST scrub the `token` query parameter before emitting
// — the JWT grants the same access as a session cookie. The handler
// path today never logs r.URL; the audit/owasp May 2026 High #2b
// pin is the standing reminder. Fly.io's edge access logs are
// considered secret-bearing for the live-hub app; redaction in the
// Fly log pipeline is an operator task documented in fly.toml.
func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) >= 7 && strings.EqualFold(h[:7], "Bearer ") {
		return strings.TrimSpace(h[7:])
	}
	// GET-only querystring fallback for WS subscribe + snapshot.
	if r.Method == http.MethodGet {
		if q := r.URL.Query().Get("token"); q != "" {
			return strings.TrimSpace(q)
		}
	}
	return ""
}

// Compile-time check that JWTAuthorizer.Authorize matches the
// [Server.Authorizer] callback shape. The cast doesn't run at
// runtime; it just refuses to compile if the signatures drift.
var _ func(*http.Request, string, AuthAction) error = (*JWTAuthorizer)(nil).Authorize
