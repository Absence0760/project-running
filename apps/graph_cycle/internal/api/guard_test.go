package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
}

func TestGuardHealthAlwaysOpen(t *testing.T) {
	h := Guard("secret", okHandler())
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("/health behind guard = %d, want 200", rec.Code)
	}
}

func TestGuardRequiresMatchingKey(t *testing.T) {
	h := Guard("secret", okHandler())

	// No header → 403.
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/cycle", nil))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("missing key = %d, want 403", rec.Code)
	}

	// Wrong header → 403.
	rec = httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/cycle", nil)
	req.Header.Set("X-Engine-Key", "wrong")
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("wrong key = %d, want 403", rec.Code)
	}

	// Right header → through.
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/cycle", nil)
	req.Header.Set("X-Engine-Key", "secret")
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("correct key = %d, want 200", rec.Code)
	}
}

func TestGuardFailsClosedOnEmptyKey(t *testing.T) {
	h := Guard("", okHandler())

	// /health still open even with no key.
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("/health with empty key = %d, want 200", rec.Code)
	}

	// A guarded route with an empty configured key rejects everything —
	// including a request that sends an empty header (which must NOT match).
	rec = httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/cycle", nil)
	req.Header.Set("X-Engine-Key", "")
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("empty configured key = %d, want 403 (fail closed)", rec.Code)
	}
}
