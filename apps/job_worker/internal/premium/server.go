// Package premium hosts the Pro-only HTTP endpoints on the Go
// service:
//
//   - POST /v1/premium/vo2max         — Daniels VDOT from recent runs
//   - POST /v1/premium/race-predictor — Riegel from a representative
//     effort to a target distance
//   - POST /v1/premium/recovery       — CTL/ATL/TSB EWMA + advice
//   - POST /v1/premium/training-plan  — Riegel-derived pace targets
//   - phased weekly mileage
//
// Why these belong on the server (not the client):
//
//   - They're Pro-tier gated. The JWT verification + the
//     subscription_tier read need to happen server-side.
//   - The compute reads the user's run history; doing it on the
//     client means shipping every run to the browser. Server-side
//     keeps the read scoped to one process + one round-trip.
//   - When the formulas grow (ML-backed plan generator, etc.) the
//     server is where the dependencies live.
//
// All four endpoints share the same auth + Pro-check shape, factored
// into `requirePro` below. Pure compute (vdotFromRace, riegelPredict,
// recoveryAdvice, plan generator) is unit-tested without booting the
// HTTP host.
package premium

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Server wires the four Pro endpoints to the Supabase service-role
// client. Mounted from main.go on the same mux as /health and the
// other endpoints.
type Server struct {
	// JWTSecret is the Supabase project's HS256 signing key. When
	// empty the endpoints refuse every request (503) — same posture
	// as the live hub + data-export endpoints.
	JWTSecret []byte

	// Backend is the Supabase REST + run-data surface. Production
	// wires the worker's SupabaseClient adapter; tests substitute
	// a fake.
	Backend Backend

	Log *slog.Logger
}

// Backend is the Supabase REST surface Premium endpoints consume.
// Defined as a leaf interface so the package's tests can swap a
// fake without importing the worker's `internal` package.
type Backend interface {
	// FetchUserSubscriptionTier returns the user's tier from
	// `user_profiles.subscription_tier`. Recognised values mirror
	// the schema's CHECK constraint: free / pro / lifetime.
	// Anything else falls back to free.
	FetchUserSubscriptionTier(ctx context.Context, userID string) (string, error)

	// FetchPremiumRuns reads the user's runs in a given time
	// window (or all-time if `since` is zero). Projection is
	// minimal — Premium endpoints don't need the full row, just
	// the bits the formulas consume.
	FetchPremiumRuns(ctx context.Context, userID string, since time.Time, limit int) ([]PremiumRun, error)
}

// PremiumRun is the minimal projection the formulas need.
// `metadata.avg_bpm` is the HR signal for TRIMP; absent → fall back
// to a distance-based stress score.
type PremiumRun struct {
	StartedAt string  `json:"started_at"`
	DistanceM float64 `json:"distance_m"`
	DurationS int     `json:"duration_s"`
	// activity_type is a real column now (F3 / 20261207_001); the VDOT
	// qualifier reads it directly instead of metadata->>'activity_type'.
	ActivityType string                 `json:"activity_type"`
	Metadata     map[string]interface{} `json:"metadata"`
}

// RegisterRoutes mounts the four routes on [mux].
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/v1/premium/vo2max", s.wrap(s.handleVO2Max))
	mux.HandleFunc("/v1/premium/race-predictor", s.wrap(s.handleRacePredictor))
	mux.HandleFunc("/v1/premium/recovery", s.wrap(s.handleRecovery))
	mux.HandleFunc("/v1/premium/training-plan", s.wrap(s.handleTrainingPlan))
}

// wrap is the shared auth + Pro-check + method-gate wrapper. Each
// handler runs only when the request passes all three gates.
func (s *Server) wrap(h func(http.ResponseWriter, *http.Request, string)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if len(s.JWTSecret) == 0 {
			s.log().Error("premium: JWT secret not configured; refusing")
			http.Error(w, `{"error":"premium_not_configured"}`, http.StatusServiceUnavailable)
			return
		}
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, `{"error":"method_not_allowed"}`, http.StatusMethodNotAllowed)
			return
		}
		userID, err := s.extractUserID(r)
		if err != nil {
			http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusUnauthorized)
			return
		}
		tier, err := s.Backend.FetchUserSubscriptionTier(r.Context(), userID)
		if err != nil {
			s.log().Error("premium: tier lookup failed", "err", err, "user_id", userID)
			http.Error(w, `{"error":"tier_lookup_failed"}`, http.StatusInternalServerError)
			return
		}
		if !isProTier(tier) {
			http.Error(w, `{"error":"pro_required"}`, http.StatusPaymentRequired)
			return
		}
		h(w, r, userID)
	}
}

// isProTier mirrors the web's tier check — `pro` + `lifetime` count
// as Pro; anything else (including unknown values) falls back to
// free. Keeps a typo in a future tier value from accidentally
// granting Pro access.
func isProTier(tier string) bool {
	return tier == "pro" || tier == "lifetime"
}

func (s *Server) extractUserID(r *http.Request) (string, error) {
	raw := bearerToken(r)
	if raw == "" {
		return "", errors.New("missing_bearer")
	}
	tok, err := jwt.Parse(raw, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected alg: %v", t.Header["alg"])
		}
		return s.JWTSecret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil || !tok.Valid {
		return "", errors.New("invalid_token")
	}
	claims, ok := tok.Claims.(jwt.MapClaims)
	if !ok {
		return "", errors.New("invalid_claims")
	}
	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return "", errors.New("missing_sub")
	}
	return sub, nil
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(h, prefix) {
		return ""
	}
	return strings.TrimSpace(h[len(prefix):])
}

func (s *Server) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// readJSON is a small body-cap helper shared by the four handlers.
// Each endpoint accepts a body up to 1 KiB (request shapes are
// tiny). DisallowUnknownFields catches typos / forward-compat
// drift.
func readJSON[T any](r *http.Request, w http.ResponseWriter, out *T, maxBytes int64) error {
	if maxBytes <= 0 {
		maxBytes = 1024
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBytes))
	dec.DisallowUnknownFields()
	if err := dec.Decode(out); err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	return nil
}

// ---------------- /v1/premium/vo2max ----------------

// VO2MaxResponse is the JSON shape the vo2max endpoint returns.
type VO2MaxResponse struct {
	VDOT           float64 `json:"vdot"`
	BestVO2Max     float64 `json:"vo2_max"`
	QualifyingRuns int     `json:"qualifying_runs_count"`
	BestDistanceM  float64 `json:"best_distance_m"`
	BestDurationS  int     `json:"best_duration_s"`
}

func (s *Server) handleVO2Max(w http.ResponseWriter, r *http.Request, userID string) {
	since := time.Now().Add(-90 * 24 * time.Hour)
	runs, err := s.Backend.FetchPremiumRuns(r.Context(), userID, since, 500)
	if err != nil {
		http.Error(w, `{"error":"runs_fetch_failed"}`, http.StatusInternalServerError)
		return
	}
	res := BestVDotFromRuns(runs)
	if res.QualifyingRuns == 0 {
		http.Error(w, `{"error":"no_qualifying_runs"}`, http.StatusNotFound)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// ---------------- /v1/premium/race-predictor ----------------

type racePredictorRequest struct {
	TargetDistanceM float64 `json:"target_distance_m"`
	Exponent        float64 `json:"exponent"`
}

type RacePredictorResponse struct {
	PredictedTimeS  int     `json:"predicted_time_s"`
	TargetDistanceM float64 `json:"target_distance_m"`
	SourceDistanceM float64 `json:"source_distance_m"`
	SourceTimeS     int     `json:"source_time_s"`
	VDOT            float64 `json:"vdot"`
	Exponent        float64 `json:"exponent"`
}

func (s *Server) handleRacePredictor(w http.ResponseWriter, r *http.Request, userID string) {
	var req racePredictorRequest
	if err := readJSON(r, w, &req, 1024); err != nil {
		http.Error(w, `{"error":"bad_body"}`, http.StatusBadRequest)
		return
	}
	if req.TargetDistanceM <= 0 {
		http.Error(w, `{"error":"target_distance_m must be positive"}`, http.StatusBadRequest)
		return
	}
	exponent := req.Exponent
	if exponent == 0 {
		exponent = 1.06 // Riegel default
	}
	since := time.Now().Add(-90 * 24 * time.Hour)
	runs, err := s.Backend.FetchPremiumRuns(r.Context(), userID, since, 500)
	if err != nil {
		http.Error(w, `{"error":"runs_fetch_failed"}`, http.StatusInternalServerError)
		return
	}
	best := BestVDotFromRuns(runs)
	if best.QualifyingRuns == 0 {
		http.Error(w, `{"error":"no_qualifying_runs"}`, http.StatusNotFound)
		return
	}
	predicted := RiegelPredict(best.BestDistanceM, float64(best.BestDurationS), req.TargetDistanceM, exponent)
	writeJSON(w, http.StatusOK, RacePredictorResponse{
		PredictedTimeS:  int(math.Round(predicted)),
		TargetDistanceM: req.TargetDistanceM,
		SourceDistanceM: best.BestDistanceM,
		SourceTimeS:     best.BestDurationS,
		VDOT:            best.VDOT,
		Exponent:        exponent,
	})
}

// ---------------- /v1/premium/recovery ----------------

// RecoveryResponse mirrors the web's recovery card on /dashboard.
type RecoveryResponse struct {
	CTL    float64 `json:"ctl"`
	ATL    float64 `json:"atl"`
	TSB    float64 `json:"tsb"`
	Advice string  `json:"advice"`
}

func (s *Server) handleRecovery(w http.ResponseWriter, r *http.Request, userID string) {
	since := time.Now().Add(-90 * 24 * time.Hour)
	runs, err := s.Backend.FetchPremiumRuns(r.Context(), userID, since, 500)
	if err != nil {
		http.Error(w, `{"error":"runs_fetch_failed"}`, http.StatusInternalServerError)
		return
	}
	ctl, atl, tsb := TrainingLoad(runs)
	writeJSON(w, http.StatusOK, RecoveryResponse{
		CTL: ctl, ATL: atl, TSB: tsb, Advice: RecoveryAdvice(tsb, ctl),
	})
}

// ---------------- /v1/premium/training-plan ----------------

type trainingPlanRequest struct {
	GoalEvent     string  `json:"goal_event"`      // 5k / 10k / half / full / custom
	GoalDistanceM float64 `json:"goal_distance_m"` // honoured when goal_event=custom
	Recent5kSec   int     `json:"recent_5k_sec"`
	Weeks         int     `json:"weeks"`         // 0 → default per goal
	DaysPerWeek   int     `json:"days_per_week"` // 0 → 4
}

func (s *Server) handleTrainingPlan(w http.ResponseWriter, r *http.Request, userID string) {
	_ = userID // currently unused — the plan generator is pure (no user runs read).
	var req trainingPlanRequest
	if err := readJSON(r, w, &req, 1024); err != nil {
		http.Error(w, `{"error":"bad_body"}`, http.StatusBadRequest)
		return
	}
	if req.Recent5kSec <= 0 {
		http.Error(w, `{"error":"recent_5k_sec must be positive"}`, http.StatusBadRequest)
		return
	}
	dist, err := goalDistance(req.GoalEvent, req.GoalDistanceM)
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusBadRequest)
		return
	}
	weeks := req.Weeks
	if weeks <= 0 {
		weeks = defaultPlanWeeks(req.GoalEvent)
	}
	dpw := req.DaysPerWeek
	if dpw <= 0 {
		dpw = 4
	}
	plan := GeneratePlan(GeneratePlanInput{
		GoalDistanceM: dist,
		Recent5kSec:   req.Recent5kSec,
		Weeks:         weeks,
		DaysPerWeek:   dpw,
	})
	writeJSON(w, http.StatusOK, plan)
}

func goalDistance(event string, custom float64) (float64, error) {
	switch event {
	case "distance_5k":
		return 5000, nil
	case "distance_10k":
		return 10_000, nil
	case "distance_half":
		return 21_097.5, nil
	case "distance_full":
		return 42_195, nil
	case "custom":
		if custom <= 0 {
			return 0, errors.New("goal_distance_m required for custom event")
		}
		return custom, nil
	case "":
		return 0, errors.New("goal_event required")
	default:
		return 0, fmt.Errorf("unknown goal_event %q", event)
	}
}

func defaultPlanWeeks(event string) int {
	switch event {
	case "distance_5k", "distance_10k":
		return 8
	case "distance_half":
		return 12
	case "distance_full":
		return 16
	default:
		return 12
	}
}
