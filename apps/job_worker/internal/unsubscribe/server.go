// Package unsubscribe is the unauthenticated RFC 8058 one-click unsubscribe
// endpoint for the weekly-digest engagement mail. A logged-out recipient
// clicking the List-Unsubscribe link (or a mail client honouring
// List-Unsubscribe-Post) hits this with a stateless keyed-HMAC token; the
// server verifies it and, on success, flips the opt-in pref to 'off' AND
// inserts an email_suppressions row (reason 'unsubscribe').
//
// No auth header, no session — the token IS the credential. It's a keyed
// HMAC over (user_id, 'weekly_digest') with the operator secret
// (WEEKLY_DIGEST_UNSUB_SECRET), so it can't be forged and leaks no PII (the
// user id is the MAC input + a query param, not recoverable from the token
// alone). Fail-closed on a missing/empty/bad token: 400, no DB write.
//
// Belt-and-braces on success: BOTH the pref flip AND the suppression insert
// run. The pref is the user-facing toggle; the suppression row is the
// hard-block the digest handler consults independently, so even a future
// builder that ignored the pref still can't email an unsubscribed address.
package unsubscribe

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/Absence0760/project-running/apps/job_worker/internal/digesttoken"
)

// Backend is the Supabase surface the endpoint exercises. Leaf interface so
// the package tests without importing `internal`. *SupabaseClient satisfies
// it via the adapter in main.go.
type Backend interface {
	// SetWeeklyDigestPrefOff flips user_settings.prefs.email_weekly_digest
	// to 'off' for the user (upserting the settings row if absent).
	SetWeeklyDigestPrefOff(ctx context.Context, userID string) error
	// InsertEmailSuppression adds the address to email_suppressions with the
	// given reason. Idempotent on the email primary key.
	InsertEmailSuppression(ctx context.Context, email, reason string) error
	// FetchUserEmail resolves the user's address (for the suppression row).
	// Returns "" + nil when there's no address on file.
	FetchUserEmail(ctx context.Context, userID string) (string, error)
}

// Server wires the unsubscribe endpoint. Mounted from main.go on the same
// mux as /health.
type Server struct {
	// Secret keys the unsubscribe HMAC. When empty the endpoint refuses
	// every request (503) — the digest can't have minted a valid token
	// without it either, so this is the consistent fail-closed posture.
	Secret string
	Backend Backend
	Log     *slog.Logger
}

// RegisterRoutes mounts the unsubscribe endpoint. Accepts both GET (a plain
// click from the email footer link) and POST (RFC 8058 List-Unsubscribe-Post
// one-click from a mail client).
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/unsubscribe/weekly-digest", s.handle)
}

func (s *Server) handle(w http.ResponseWriter, r *http.Request) {
	if s.Secret == "" {
		s.log().Error("unsubscribe: secret not configured; refusing")
		http.Error(w, "unsubscribe not configured", http.StatusServiceUnavailable)
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodPost {
		w.Header().Set("Allow", "GET, POST")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Token + user id come from the query string (the footer link) for GET;
	// for an RFC 8058 POST the body is `List-Unsubscribe=One-Click`, so the
	// addressing still rides the URL query the mail client was given.
	userID := r.URL.Query().Get("u")
	token := r.URL.Query().Get("t")

	// Fail-closed verify: empty/missing/bad token → 400, no DB write.
	if !digesttoken.Verify(s.Secret, userID, token) {
		s.log().Warn("unsubscribe: token verification failed")
		http.Error(w, "invalid or missing unsubscribe token", http.StatusBadRequest)
		return
	}

	// Flip the pref off. A failure here is a 500 so a mail client retries —
	// we don't want to claim success without recording the opt-out.
	if err := s.Backend.SetWeeklyDigestPrefOff(r.Context(), userID); err != nil {
		s.log().Error("unsubscribe: pref flip failed", "err", err, "user_id", userID)
		http.Error(w, "could not process unsubscribe", http.StatusInternalServerError)
		return
	}

	// Belt-and-braces hard block: insert the suppression row keyed by the
	// address. A missing address (phone-only / deleted) just skips the
	// suppression insert — the pref flip already opted them out.
	email, err := s.Backend.FetchUserEmail(r.Context(), userID)
	if err != nil {
		s.log().Error("unsubscribe: address lookup failed", "err", err, "user_id", userID)
		http.Error(w, "could not process unsubscribe", http.StatusInternalServerError)
		return
	}
	if email != "" {
		if err := s.Backend.InsertEmailSuppression(r.Context(), email, "unsubscribe"); err != nil {
			s.log().Error("unsubscribe: suppression insert failed", "err", err, "user_id", userID)
			http.Error(w, "could not process unsubscribe", http.StatusInternalServerError)
			return
		}
	}

	s.log().Info("unsubscribe: weekly digest opt-out recorded", "user_id", userID)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("You've been unsubscribed from the weekly digest."))
}

func (s *Server) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}
