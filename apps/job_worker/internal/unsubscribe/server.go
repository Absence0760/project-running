// Package unsubscribe is the unauthenticated RFC 8058 one-click unsubscribe
// endpoint for the engagement-mail streams (the weekly digest + the lifecycle
// drip). A logged-out recipient clicking the List-Unsubscribe link (or a mail
// client honouring List-Unsubscribe-Post) hits the per-stream path with a
// stateless keyed-HMAC token; the server verifies it and, on success, flips
// that stream's opt-in pref to 'off' AND inserts an email_suppressions row
// (reason 'unsubscribe').
//
// No auth header, no session — the token IS the credential. It's a keyed HMAC
// over (stream, user_id) with the operator secret (WEEKLY_DIGEST_UNSUB_SECRET,
// shared across streams), so it can't be forged, can't be replayed from one
// stream to another (the stream namespaces the MAC), and leaks no PII (the
// user id is the MAC input + a query param, not recoverable from the token
// alone). Fail-closed on a missing/empty/bad token: 400, no DB write.
//
// Belt-and-braces on success: BOTH the per-stream pref flip AND the
// suppression insert run. The pref is the user-facing per-stream toggle; the
// suppression row is the address-keyed hard-block the engagement handlers
// consult independently, so even a future builder that ignored the pref still
// can't email an unsubscribed address — and the suppression covers EVERY
// stream (an unsubscribe from one engagement mail also blocks the others to
// that address, the safe default).
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
	// SetLifecycleDripPrefOff flips user_settings.prefs.email_lifecycle_drip
	// to 'off' for the user (upserting the settings row if absent).
	SetLifecycleDripPrefOff(ctx context.Context, userID string) error
	// InsertEmailSuppression adds the address to email_suppressions with the
	// given reason. Idempotent on the email primary key.
	InsertEmailSuppression(ctx context.Context, email, reason string) error
	// FetchUserEmail resolves the user's address (for the suppression row).
	// Returns "" + nil when there's no address on file.
	FetchUserEmail(ctx context.Context, userID string) (string, error)
}

// Server wires the unsubscribe endpoints. Mounted from main.go on the same
// mux as /health.
type Server struct {
	// Secret keys the unsubscribe HMAC. When empty every endpoint refuses
	// every request (503) — the engagement mail can't have minted a valid
	// token without it either, so this is the consistent fail-closed posture.
	Secret  string
	Backend Backend
	Log     *slog.Logger
}

// stream bundles one engagement-mail stream's unsubscribe wiring: its token
// scope (namespacing the MAC), the path it's mounted at, and the pref-flip it
// performs on success. Keeping the per-stream difference in data means the
// handler body is shared — adding a stream is one entry here.
type stream struct {
	scope   string
	path    string
	prefOff func(context.Context, Backend, string) error
	okMsg   string
}

func (s *Server) streams() []stream {
	return []stream{
		{
			scope:   digesttoken.StreamWeeklyDigest,
			path:    "/unsubscribe/weekly-digest",
			prefOff: func(ctx context.Context, b Backend, uid string) error { return b.SetWeeklyDigestPrefOff(ctx, uid) },
			okMsg:   "You've been unsubscribed from the weekly digest.",
		},
		{
			scope:   digesttoken.StreamLifecycleDrip,
			path:    "/unsubscribe/lifecycle-drip",
			prefOff: func(ctx context.Context, b Backend, uid string) error { return b.SetLifecycleDripPrefOff(ctx, uid) },
			okMsg:   "You've been unsubscribed from these reminders.",
		},
	}
}

// RegisterRoutes mounts one endpoint per engagement-mail stream. Each accepts
// both GET (a plain click from the email footer link) and POST (RFC 8058
// List-Unsubscribe-Post one-click from a mail client).
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	for _, st := range s.streams() {
		st := st
		mux.HandleFunc(st.path, func(w http.ResponseWriter, r *http.Request) {
			s.handle(w, r, st)
		})
	}
}

func (s *Server) handle(w http.ResponseWriter, r *http.Request, st stream) {
	if s.Secret == "" {
		s.log().Error("unsubscribe: secret not configured; refusing", "stream", st.scope)
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

	// Fail-closed verify: empty/missing/bad token, or a token minted for a
	// DIFFERENT stream → 400, no DB write.
	if !digesttoken.Verify(s.Secret, st.scope, userID, token) {
		s.log().Warn("unsubscribe: token verification failed", "stream", st.scope)
		http.Error(w, "invalid or missing unsubscribe token", http.StatusBadRequest)
		return
	}

	// Flip the per-stream pref off. A failure here is a 500 so a mail client
	// retries — we don't want to claim success without recording the opt-out.
	if err := st.prefOff(r.Context(), s.Backend, userID); err != nil {
		s.log().Error("unsubscribe: pref flip failed", "err", err, "user_id", userID, "stream", st.scope)
		http.Error(w, "could not process unsubscribe", http.StatusInternalServerError)
		return
	}

	// Belt-and-braces hard block: insert the suppression row keyed by the
	// address. A missing address (phone-only / deleted) just skips the
	// suppression insert — the pref flip already opted them out.
	email, err := s.Backend.FetchUserEmail(r.Context(), userID)
	if err != nil {
		s.log().Error("unsubscribe: address lookup failed", "err", err, "user_id", userID, "stream", st.scope)
		http.Error(w, "could not process unsubscribe", http.StatusInternalServerError)
		return
	}
	if email != "" {
		if err := s.Backend.InsertEmailSuppression(r.Context(), email, "unsubscribe"); err != nil {
			s.log().Error("unsubscribe: suppression insert failed", "err", err, "user_id", userID, "stream", st.scope)
			http.Error(w, "could not process unsubscribe", http.StatusInternalServerError)
			return
		}
	}

	s.log().Info("unsubscribe: opt-out recorded", "user_id", userID, "stream", st.scope)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(st.okMsg))
}

func (s *Server) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}
