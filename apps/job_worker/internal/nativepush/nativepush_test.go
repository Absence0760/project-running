package nativepush

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNewSender_NoCredentialsIsInert(t *testing.T) {
	s, err := NewSender(Config{}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if s != nil {
		t.Fatalf("a Sender with no credentials must be nil (fail-closed), got %#v", s)
	}
}

func TestNewSender_BadFCMServiceAccountFailsLoud(t *testing.T) {
	_, err := NewSender(Config{
		FCMServiceAccountJSON: []byte("{not json"),
		FCMProjectID:          "p",
	}, nil)
	if err == nil {
		t.Fatalf("a malformed service-account JSON must fail at construction")
	}
}

func TestNewSender_BadAPNSKeyFailsLoud(t *testing.T) {
	_, err := NewSender(Config{
		APNSKeyP8:  []byte("-----BEGIN PRIVATE KEY-----\nnotbase64\n-----END PRIVATE KEY-----"),
		APNSKeyID:  "k",
		APNSTeamID: "t",
		APNSTopic:  "com.x.app",
	}, nil)
	if err == nil {
		t.Fatalf("a malformed .p8 key must fail at construction")
	}
}

func TestStatusClassification(t *testing.T) {
	dead := []int{404, 410}
	for _, s := range dead {
		if !IsDeadToken(s) {
			t.Errorf("status %d should be a dead token", s)
		}
		if IsTransient(s) {
			t.Errorf("status %d should not be transient", s)
		}
	}
	transient := []int{429, 500, 502, 503}
	for _, s := range transient {
		if !IsTransient(s) {
			t.Errorf("status %d should be transient", s)
		}
		if IsDeadToken(s) {
			t.Errorf("status %d should not be a dead token", s)
		}
	}
	for _, s := range []int{200, 400, 403} {
		if IsDeadToken(s) || IsTransient(s) {
			t.Errorf("status %d should be neither dead nor transient", s)
		}
	}
}

// fakeServer mints a service-account-style FCM transport pointed at a test
// server so we can drive a full FCM send (OAuth2 token mint + messages:send)
// without touching Google.
func newTestFCMSender(t *testing.T, handler http.HandlerFunc) *Sender {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	pemKey := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})

	sa := map[string]string{
		"client_email": "svc@test.iam.gserviceaccount.com",
		"private_key":  string(pemKey),
		"token_uri":    srv.URL + "/token",
		"project_id":   "test-project",
	}
	saJSON, _ := json.Marshal(sa)

	fcm, err := newFCMTransport(saJSON, "test-project", srv.Client())
	if err != nil {
		t.Fatal(err)
	}
	// Redirect the send URL at the test server too.
	fcm.sendURL = srv.URL + "/send"
	return &Sender{fcm: fcm}
}

func TestSender_FCMRoundTrip(t *testing.T) {
	var gotAuth, gotBody string
	s := newTestFCMSender(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/token"):
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "ya29.test", "expires_in": 3600})
		case strings.HasSuffix(r.URL.Path, "/send"):
			gotAuth = r.Header.Get("Authorization")
			b, _ := io.ReadAll(r.Body)
			gotBody = string(b)
			w.WriteHeader(http.StatusOK)
		default:
			http.NotFound(w, r)
		}
	})

	status, err := s.Send(context.Background(), DeviceToken{Platform: "android", Token: "dev-tok"},
		Message{Title: "Hi", Body: "there", URL: "https://x/events/1", Tag: "notif-1"})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if status != http.StatusOK {
		t.Errorf("want 200, got %d", status)
	}
	if gotAuth != "Bearer ya29.test" {
		t.Errorf("send should carry the minted bearer, got %q", gotAuth)
	}
	if !strings.Contains(gotBody, `"token":"dev-tok"`) || !strings.Contains(gotBody, `"title":"Hi"`) {
		t.Errorf("send body missing token/title: %s", gotBody)
	}
	if !strings.Contains(gotBody, `"url":"https://x/events/1"`) {
		t.Errorf("send body should carry the deep-link url in data: %s", gotBody)
	}
}

func TestSender_FCMSurfaces404(t *testing.T) {
	s := newTestFCMSender(t, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/token") {
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "t", "expires_in": 3600})
			return
		}
		w.WriteHeader(http.StatusNotFound) // UNREGISTERED
	})
	status, err := s.Send(context.Background(), DeviceToken{Platform: "android", Token: "dead"}, Message{Title: "x"})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if !IsDeadToken(status) {
		t.Errorf("a 404 should classify as a dead token, got %d", status)
	}
}

// An iOS token with no APNs transport configured but FCM present routes through
// FCM (FCM proxies APNs for Apple).
func TestSender_IOSFallsBackToFCM(t *testing.T) {
	var sawSend bool
	s := newTestFCMSender(t, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/token") {
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "t", "expires_in": 3600})
			return
		}
		sawSend = true
		w.WriteHeader(http.StatusOK)
	})
	status, err := s.Send(context.Background(), DeviceToken{Platform: "ios", Token: "ios-tok"}, Message{Title: "x"})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if status != http.StatusOK || !sawSend {
		t.Errorf("iOS token with FCM-only config should route through FCM")
	}
}

// A platform with no transport at all reports ErrPlatformNotConfigured.
func TestSender_UnconfiguredPlatform(t *testing.T) {
	// APNs-only sender, an Android token has nowhere to go.
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	p8 := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	apns, err := newAPNSTransport(p8, "kid", "team", "com.x.app", true, http.DefaultClient)
	if err != nil {
		t.Fatal(err)
	}
	s := &Sender{apns: apns}
	if _, err := s.Send(context.Background(), DeviceToken{Platform: "android", Token: "a"}, Message{}); err == nil {
		t.Fatalf("an android token with APNs-only config should report not-configured")
	}
}
