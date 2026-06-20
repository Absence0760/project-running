// Package nativepush is a dependency-light native-push sender: FCM HTTP v1 for
// Android tokens and APNs HTTP/2 for iOS tokens, behind one Sender that routes
// on the device platform. It is the server leg of the native-push channel — the
// mobile clients register a device token on user_settings' device_tokens via
// the api_client, and the worker's handler_native_push.go sends through this
// package. Sibling of internal/webpush (the browser leg).
//
// Built on the standard library (crypto/ecdh-free: ES256 via crypto/ecdsa for
// APNs, RSA service-account signing reused from golang-jwt for FCM's OAuth2)
// plus golang-jwt — already a worker dependency. No Firebase Admin SDK: FCM
// HTTP v1 is a single OAuth2-bearer POST and APNs is a single JWT-authed
// HTTP/2 POST; vendoring the Admin SDK (a large transitive surface) for ~200
// lines of stdlib + one JWT is not worth the supply-chain cost — the same call
// the webpush package made for Web Push.
//
// Fail-closed: NewSender returns (nil, nil) when neither transport is
// configured, so main.go can leave Worker.NativePush nil and the handler
// drains native_push jobs to done without sending (rows stay pending for a
// later credentialed deploy). A partially-configured Sender (only FCM, or only
// APNs) sends what it can and reports an unconfigured platform via
// ErrPlatformNotConfigured so the handler treats it as "leave pending", never
// a hard failure.
package nativepush

import (
	"context"
	"errors"
	"net/http"
)

// DeviceToken is one registered device, projected from the device_tokens row.
// Platform routes the send: "android" → FCM, "ios" → APNs. Token is the
// platform-minted registration token.
type DeviceToken struct {
	Platform string
	Token    string
}

// Message is the localized notification to deliver. Title/Body surface as the
// system notification; URL is the deep link the tap handler opens; Tag (== the
// notification id) coalesces a retry so a duplicate replaces rather than
// stacks. Mirrors the {title, body, url, tag} contract the webpush payload uses
// so the two channels render identically from the shared catalogue.
type Message struct {
	Title string
	Body  string
	URL   string
	Tag   string
}

// transport is the per-platform leaf both FCM and APNs implement. Returns the
// provider HTTP status (so the handler can prune a dead token on 404/410/
// UNREGISTERED, retry a 429/5xx) and a non-nil error only on a transport
// failure before the request completes.
type transport interface {
	send(ctx context.Context, token string, msg Message) (int, error)
}

// ErrPlatformNotConfigured is returned by Send when a device's platform has no
// configured transport (e.g. APNs keys unset but an iOS token shows up). The
// handler treats it as "leave this device pending", not a delivery failure —
// the credential gate is per-platform.
var ErrPlatformNotConfigured = errors.New("nativepush: platform transport not configured")

// Sender routes a Send to the FCM or APNs transport by platform. Either leaf
// may be nil (that platform isn't configured); a Sender with both nil is never
// constructed — NewSender returns (nil, nil) in that case so the worker stays
// fully inert.
type Sender struct {
	fcm  transport
	apns transport
}

// Config carries the operator credentials. An empty group leaves that
// transport unconfigured. Both empty → NewSender returns (nil, nil).
type Config struct {
	// FCM HTTP v1 — the service-account JSON + project id.
	FCMServiceAccountJSON []byte
	FCMProjectID          string

	// APNs HTTP/2 — the .p8 signing key (PEM), its key id, the team id, and
	// the app's bundle id (the apns-topic). UseSandbox routes at the
	// api.sandbox.push.apple.com host for development builds.
	APNSKeyP8   []byte
	APNSKeyID   string
	APNSTeamID  string
	APNSTopic   string
	APNSSandbox bool
}

// NewSender builds a Sender from whatever credentials are present. Returns
// (nil, nil) when neither transport is configured — the fail-closed default
// the worker relies on. A configured-but-invalid credential (bad .p8, bad
// service-account JSON) returns a non-nil error so a deploy misconfiguration
// fails loudly at startup rather than silently dropping every push.
func NewSender(cfg Config, httpClient *http.Client) (*Sender, error) {
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	s := &Sender{}
	if len(cfg.FCMServiceAccountJSON) > 0 && cfg.FCMProjectID != "" {
		fcm, err := newFCMTransport(cfg.FCMServiceAccountJSON, cfg.FCMProjectID, httpClient)
		if err != nil {
			return nil, err
		}
		s.fcm = fcm
	}
	if len(cfg.APNSKeyP8) > 0 && cfg.APNSKeyID != "" && cfg.APNSTeamID != "" && cfg.APNSTopic != "" {
		apns, err := newAPNSTransport(cfg.APNSKeyP8, cfg.APNSKeyID, cfg.APNSTeamID, cfg.APNSTopic, cfg.APNSSandbox, httpClient)
		if err != nil {
			return nil, err
		}
		s.apns = apns
	}
	if s.fcm == nil && s.apns == nil {
		return nil, nil
	}
	return s, nil
}

// Send delivers msg to one device, routed by platform. Returns the provider
// HTTP status + nil on a completed request (whatever the status), or
// ErrPlatformNotConfigured when that platform has no transport (the per-
// platform credential gate). Android and any unknown platform route to FCM
// (FCM is the canonical transport); "ios" routes to APNs when configured.
func (s *Sender) Send(ctx context.Context, token DeviceToken, msg Message) (int, error) {
	switch token.Platform {
	case "ios":
		if s.apns != nil {
			return s.apns.send(ctx, token.Token, msg)
		}
		// No direct APNs configured — fall back to FCM if it's wired (FCM
		// proxies APNs for iOS), else report unconfigured.
		if s.fcm != nil {
			return s.fcm.send(ctx, token.Token, msg)
		}
		return 0, ErrPlatformNotConfigured
	default: // "android" and anything else
		if s.fcm != nil {
			return s.fcm.send(ctx, token.Token, msg)
		}
		return 0, ErrPlatformNotConfigured
	}
}

// IsDeadToken reports whether a provider status means the token is gone and
// should be pruned. FCM HTTP v1 returns 404 (UNREGISTERED) for a stale token;
// APNs returns 410 (Unregistered). Both are terminal for that registration.
func IsDeadToken(status int) bool {
	return status == http.StatusNotFound || status == http.StatusGone
}

// IsTransient reports whether a provider status warrants a job retry (the push
// service is throttling or down). 429 + any 5xx defer.
func IsTransient(status int) bool {
	return status == http.StatusTooManyRequests || status >= 500
}
