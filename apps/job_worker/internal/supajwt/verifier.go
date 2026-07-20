package supajwt

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/golang-jwt/jwt/v5"
)

// Verifier supplies the [jwt.Keyfunc] and the allowed-algorithm list
// every Supabase-token-verifying endpoint in this binary shares (the
// live hub, the data-export endpoint, and the premium endpoints).
//
// It resolves a token against whichever signing scheme the project
// actually uses, and — crucially — advertises ONLY the algorithms it can
// actually verify. An algorithm with no configured key material never
// reaches [jwt.Parse]'s method allow-list, so it cannot be presented as
// a bypass.
type Verifier struct {
	secret []byte
	jwks   *JWKS
}

// New builds a verifier from whichever material is available.
//
// secret is the legacy `SUPABASE_JWT_SECRET` (HS256); projectURL is the
// Supabase project base URL, which yields the JWKS endpoint for the
// asymmetric (ES256 / RS256) path. Either may be empty. When both are,
// the verifier reports [Verifier.Enabled] false and the caller is
// expected to refuse to serve authenticated traffic.
func New(secret, projectURL string, hc *http.Client) *Verifier {
	v := &Verifier{jwks: NewJWKS(projectURL, hc)}
	if secret != "" {
		v.secret = []byte(secret)
	}
	return v
}

// Enabled reports whether any verification path is configured.
func (v *Verifier) Enabled() bool {
	return v != nil && (len(v.secret) > 0 || v.jwks != nil)
}

// Methods is the allow-list to hand [jwt.WithValidMethods]. It contains
// only algorithms backed by configured key material.
func (v *Verifier) Methods() []string {
	if v == nil {
		return nil
	}
	var out []string
	if len(v.secret) > 0 {
		out = append(out, "HS256")
	}
	if v.jwks != nil {
		out = append(out, "ES256", "RS256")
	}
	return out
}

// Describe is a boot-log helper naming the active verification paths.
func (v *Verifier) Describe() string {
	switch {
	case !v.Enabled():
		return "disabled"
	case len(v.secret) > 0 && v.jwks != nil:
		return "JWKS (ES256/RS256) + shared secret (HS256)"
	case v.jwks != nil:
		return "JWKS (ES256/RS256)"
	default:
		return "shared secret (HS256)"
	}
}

// Keyfunc resolves a parsed token header to its verification key.
//
// The HMAC branch returns the shared secret and never a public key.
// That is what defeats the classic algorithm-confusion attack: a JWKS
// public key is, by definition, known to an attacker, so if it were ever
// returned here an attacker could HMAC-sign a token with it and be
// believed.
func (v *Verifier) Keyfunc() jwt.Keyfunc {
	return func(t *jwt.Token) (interface{}, error) {
		switch t.Method.(type) {
		case *jwt.SigningMethodHMAC:
			if len(v.secret) == 0 {
				return nil, errors.New("HS256 token but no shared secret configured")
			}
			return v.secret, nil
		case *jwt.SigningMethodECDSA, *jwt.SigningMethodRSA:
			if v.jwks == nil {
				return nil, errors.New("asymmetric token but no JWKS configured")
			}
			kid, _ := t.Header["kid"].(string)
			return v.jwks.Key(kid)
		default:
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
	}
}

// Subject verifies raw and returns its `sub` claim (the Supabase
// user id).
//
// An `exp` claim is REQUIRED: golang-jwt validates `exp` only when
// present, so a token omitting it would otherwise be valid forever.
// Supabase always issues short-lived tokens, so a token without `exp`
// is anomalous by construction.
func (v *Verifier) Subject(raw string) (string, error) {
	if !v.Enabled() {
		return "", errors.New("no verification key configured")
	}
	tok, err := jwt.Parse(raw, v.Keyfunc(),
		jwt.WithValidMethods(v.Methods()),
		jwt.WithExpirationRequired())
	if err != nil || !tok.Valid {
		return "", errors.New("invalid token")
	}
	claims, ok := tok.Claims.(jwt.MapClaims)
	if !ok {
		return "", errors.New("invalid claims")
	}
	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return "", errors.New("missing sub claim")
	}
	return sub, nil
}
