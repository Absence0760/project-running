package internal

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Storage answers a sign request with a path relative to the STORAGE
// API — `/object/sign/...`, no `/storage/v1` on it — so a client that
// fronts it with the project base URL alone produces a 404 on every
// download. Verified against the local stack, which returns exactly
// this shape.
func TestCreateSignedURL_AddsTheStorageApiPrefix(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"signedURL":"/object/sign/exports/u/x.zip?token=abc"}`))
	}))
	defer srv.Close()

	c := NewSupabaseClient(srv.URL, "service-key")
	got, err := c.CreateSignedURL(context.Background(), "u/x.zip", 600)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	want := srv.URL + "/storage/v1/object/sign/exports/u/x.zip?token=abc"
	if got != want {
		t.Fatalf("url=%q, want %q", got, want)
	}
}

// A deployment whose storage service already includes the prefix must
// not have it added twice.
func TestCreateSignedURL_DoesNotDoublePrefix(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"signedURL":"/storage/v1/object/sign/exports/u/x.zip?token=abc"}`))
	}))
	defer srv.Close()

	c := NewSupabaseClient(srv.URL, "service-key")
	got, err := c.CreateSignedURL(context.Background(), "u/x.zip", 600)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	if strings.Count(got, "/storage/v1") != 1 {
		t.Fatalf("url=%q, want exactly one /storage/v1", got)
	}
}
