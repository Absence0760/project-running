package supakey

import (
	"net/http"
	"testing"
)

func TestLegacyJWTKeySendsBothHeaders(t *testing.T) {
	h := http.Header{}
	SetAuthHeaders(h, "eyJhbGciOiJIUzI1NiJ9.legacy.sig")
	if got := h.Get("apikey"); got != "eyJhbGciOiJIUzI1NiJ9.legacy.sig" {
		t.Errorf("apikey=%q", got)
	}
	if got := h.Get("Authorization"); got != "Bearer eyJhbGciOiJIUzI1NiJ9.legacy.sig" {
		t.Errorf("Authorization=%q", got)
	}
}

func TestSecretKeySendsApikeyOnly(t *testing.T) {
	h := http.Header{}
	SetAuthHeaders(h, "sb_secret_abc123")
	if got := h.Get("apikey"); got != "sb_secret_abc123" {
		t.Errorf("apikey=%q", got)
	}
	if got := h.Get("Authorization"); got != "" {
		t.Errorf("Authorization must be absent for a secret key; got %q", got)
	}
}

func TestPublishableKeySendsApikeyOnly(t *testing.T) {
	h := http.Header{}
	SetAuthHeaders(h, "sb_publishable_abc123")
	if got := h.Get("Authorization"); got != "" {
		t.Errorf("Authorization must be absent for a publishable key; got %q", got)
	}
}

func TestDoesNotClobberExistingAuthorizationForNewKeys(t *testing.T) {
	// A caller that already set a user JWT bearer must keep it when the
	// apikey is new-format — SetAuthHeaders only adds the bearer for
	// legacy keys, it never deletes.
	h := http.Header{}
	h.Set("Authorization", "Bearer user-jwt")
	SetAuthHeaders(h, "sb_secret_abc123")
	if got := h.Get("Authorization"); got != "Bearer user-jwt" {
		t.Errorf("Authorization=%q", got)
	}
}
