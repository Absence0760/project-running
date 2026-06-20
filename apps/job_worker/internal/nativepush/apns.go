package nativepush

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"

	jwt "github.com/golang-jwt/jwt/v5"
)

const (
	apnsProdHost    = "https://api.push.apple.com"
	apnsSandboxHost = "https://api.sandbox.push.apple.com"
)

// apnsTransport sends to APNs over HTTP/2 with token-based (.p8) auth. The
// provider JWT (ES256, claims iss=teamID, kid=keyID) is reused for up to ~50
// minutes per Apple's guidance (must be refreshed at least hourly, no more
// than once every 20 minutes), so we cache it and re-sign on a ~45-minute
// cadence.
type apnsTransport struct {
	signKey *ecdsa.PrivateKey
	keyID   string
	teamID  string
	topic   string
	host    string
	http    *http.Client
	now     func() time.Time

	mu     sync.Mutex
	jwt    string
	jwtExp time.Time
}

func newAPNSTransport(keyP8 []byte, keyID, teamID, topic string, sandbox bool, httpClient *http.Client) (*apnsTransport, error) {
	key, err := parseECPrivateKey(keyP8)
	if err != nil {
		return nil, fmt.Errorf("nativepush/apns: %w", err)
	}
	host := apnsProdHost
	if sandbox {
		host = apnsSandboxHost
	}
	return &apnsTransport{
		signKey: key,
		keyID:   keyID,
		teamID:  teamID,
		topic:   topic,
		host:    host,
		http:    httpClient,
		now:     time.Now,
	}, nil
}

// apnsPayload is the APNs notification body. The aps.alert renders the system
// notification; url/tag are custom keys the iOS app reads to deep-link + dedupe
// (the tap handler routes off `url`; `apns-collapse-id` coalesces, set from the
// tag in the header below).
type apnsPayload struct {
	APS apnsAPS `json:"aps"`
	URL string  `json:"url,omitempty"`
	Tag string  `json:"tag,omitempty"`
}

type apnsAPS struct {
	Alert apnsAlert `json:"alert"`
	Sound string    `json:"sound,omitempty"`
}

type apnsAlert struct {
	Title string `json:"title"`
	Body  string `json:"body,omitempty"`
}

func (t *apnsTransport) send(ctx context.Context, token string, msg Message) (int, error) {
	jwtTok, err := t.providerToken()
	if err != nil {
		return 0, err
	}

	body, err := json.Marshal(apnsPayload{
		APS: apnsAPS{Alert: apnsAlert{Title: msg.Title, Body: msg.Body}, Sound: "default"},
		URL: msg.URL,
		Tag: msg.Tag,
	})
	if err != nil {
		return 0, fmt.Errorf("nativepush/apns: marshal: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, t.host+"/3/device/"+token, bytes.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("nativepush/apns: build request: %w", err)
	}
	req.Header.Set("authorization", "bearer "+jwtTok)
	req.Header.Set("apns-topic", t.topic)
	req.Header.Set("apns-push-type", "alert")
	if msg.Tag != "" {
		// APNs collapse-id is capped at 64 bytes; the tag (notif-<uuid>) fits.
		req.Header.Set("apns-collapse-id", msg.Tag)
	}

	resp, err := t.http.Do(req)
	if err != nil {
		return 0, fmt.Errorf("nativepush/apns: POST: %w", err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode, nil
}

// providerToken returns a cached ES256 provider JWT, re-signing when the cache
// is empty or older than ~45 minutes.
func (t *apnsTransport) providerToken() (string, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	if t.jwt != "" && now.Before(t.jwtExp) {
		return t.jwt, nil
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"iss": t.teamID,
		"iat": now.Unix(),
	})
	tok.Header["kid"] = t.keyID
	signed, err := tok.SignedString(t.signKey)
	if err != nil {
		return "", fmt.Errorf("nativepush/apns: sign provider token: %w", err)
	}
	t.jwt = signed
	t.jwtExp = now.Add(45 * time.Minute)
	return signed, nil
}

// parseECPrivateKey parses a PEM-encoded PKCS#8 EC private key (the form an
// APNs .p8 key file carries).
func parseECPrivateKey(p8 []byte) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode(p8)
	if block == nil {
		return nil, fmt.Errorf(".p8 key is not valid PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf(".p8 key is not PKCS#8: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf(".p8 key is not an EC private key")
	}
	return key, nil
}
