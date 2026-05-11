package premium

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testJWTSecret = "test-jwt-secret"

type fakeBackend struct {
	tier        string
	tierErr     error
	tierByUser  map[string]string
	runs        []PremiumRun
	runsErr     error
	lastUserID  string
	lastSince   time.Time
	lastLimit   int
	tierCalls   int
	runsCalls   int
}

func (f *fakeBackend) FetchUserSubscriptionTier(_ context.Context, userID string) (string, error) {
	f.tierCalls++
	if f.tierErr != nil {
		return "", f.tierErr
	}
	if t, ok := f.tierByUser[userID]; ok {
		return t, nil
	}
	if f.tier != "" {
		return f.tier, nil
	}
	return "free", nil
}

func (f *fakeBackend) FetchPremiumRuns(_ context.Context, userID string, since time.Time, limit int) ([]PremiumRun, error) {
	f.runsCalls++
	f.lastUserID = userID
	f.lastSince = since
	f.lastLimit = limit
	if f.runsErr != nil {
		return nil, f.runsErr
	}
	return f.runs, nil
}

func signTestToken(t *testing.T, sub string, expDelta int) string {
	t.Helper()
	claims := jwt.MapClaims{"sub": sub}
	if expDelta != 0 {
		claims["exp"] = time.Now().Add(time.Duration(expDelta) * time.Second).Unix()
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	s, err := tok.SignedString([]byte(testJWTSecret))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func signTestTokenWith(t *testing.T, method jwt.SigningMethod, claims jwt.MapClaims, key interface{}) string {
	t.Helper()
	tok := jwt.NewWithClaims(method, claims)
	s, err := tok.SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func newTestServer(t *testing.T, srv *Server) (string, func()) {
	t.Helper()
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	return ts.URL, ts.Close
}

func newProServer(t *testing.T, be *fakeBackend) (string, func()) {
	t.Helper()
	srv := &Server{
		JWTSecret: []byte(testJWTSecret),
		Backend:   be,
	}
	return newTestServer(t, srv)
}

// postJSON is a small helper to issue an authenticated POST to a
// premium endpoint. Pass empty `bearer` to omit the Authorization
// header (used by the missing-auth tests).
func postJSON(t *testing.T, base, path, bearer, body string) *http.Response {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, base+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// ---------------- Auth + gating tests ----------------

func TestServer_MissingJwtSecretIs503(t *testing.T) {
	srv := &Server{Backend: &fakeBackend{}} // no JWTSecret
	base, teardown := newTestServer(t, srv)
	defer teardown()

	for _, path := range []string{
		"/v1/premium/vo2max",
		"/v1/premium/race-predictor",
		"/v1/premium/recovery",
		"/v1/premium/training-plan",
	} {
		resp := postJSON(t, base, path, "", "{}")
		if resp.StatusCode != http.StatusServiceUnavailable {
			t.Errorf("%s without JWT secret = %d, want 503", path, resp.StatusCode)
		}
		resp.Body.Close()
	}
}

func TestServer_GetIs405(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	resp, err := http.Get(base + "/v1/premium/vo2max")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("GET vo2max = %d, want 405", resp.StatusCode)
	}
	if resp.Header.Get("Allow") != "POST" {
		t.Errorf("Allow header = %q, want POST", resp.Header.Get("Allow"))
	}
}

func TestServer_MissingBearerIs401(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	resp := postJSON(t, base, "/v1/premium/vo2max", "", "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("missing bearer = %d, want 401", resp.StatusCode)
	}
}

func TestServer_InvalidTokenIs401(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	resp := postJSON(t, base, "/v1/premium/vo2max", "not.a.token", "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("invalid token = %d, want 401", resp.StatusCode)
	}
}

func TestServer_TokenSignedWithWrongKeyIs401(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	bad := signTestTokenWith(t, jwt.SigningMethodHS256, jwt.MapClaims{"sub": "u1"}, []byte("wrong-key"))
	resp := postJSON(t, base, "/v1/premium/vo2max", bad, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("wrong-key token = %d, want 401", resp.StatusCode)
	}
}

func TestServer_ExpiredTokenIs401(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", -3600) // 1h in the past
	resp := postJSON(t, base, "/v1/premium/vo2max", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("expired token = %d, want 401", resp.StatusCode)
	}
}

func TestServer_FreeTierIs402(t *testing.T) {
	be := &fakeBackend{tier: "free"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "free-user", 3600)
	resp := postJSON(t, base, "/v1/premium/vo2max", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusPaymentRequired {
		t.Errorf("free tier = %d, want 402", resp.StatusCode)
	}
}

func TestServer_UnknownTierFallsBackToFree(t *testing.T) {
	be := &fakeBackend{tier: "scrambled"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/vo2max", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusPaymentRequired {
		t.Errorf("unknown tier should fall back to free (402); got %d", resp.StatusCode)
	}
}

func TestServer_LifetimeTierAccepted(t *testing.T) {
	be := &fakeBackend{
		tier: "lifetime",
		runs: []PremiumRun{
			{StartedAt: "2026-05-05", DistanceM: 5000, DurationS: 1200},
		},
	}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "lifer", 3600)
	resp := postJSON(t, base, "/v1/premium/vo2max", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("lifetime tier should be accepted; got %d", resp.StatusCode)
	}
}

func TestServer_TierLookupErrorIs500(t *testing.T) {
	be := &fakeBackend{tierErr: errors.New("supabase boom")}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/vo2max", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusInternalServerError {
		t.Errorf("tier lookup error = %d, want 500", resp.StatusCode)
	}
}

// ---------------- VO2 max endpoint ----------------

func TestServer_VO2Max_HappyPath(t *testing.T) {
	be := &fakeBackend{
		tier: "pro",
		runs: []PremiumRun{
			{StartedAt: "2026-05-01", DistanceM: 5000, DurationS: 1800}, // slow
			{StartedAt: "2026-05-05", DistanceM: 5000, DurationS: 1200}, // fast
		},
	}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/vo2max", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("vo2max happy path = %d, want 200", resp.StatusCode)
	}
	var got VO2MaxResponse
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.VDOT < 46 || got.VDOT > 52 {
		t.Errorf("VDOT = %.2f, want ≈ 50", got.VDOT)
	}
	if got.QualifyingRuns != 2 {
		t.Errorf("qualifying runs = %d, want 2", got.QualifyingRuns)
	}
	if got.BestDurationS != 1200 {
		t.Errorf("best duration = %d, want 1200 (the faster run)", got.BestDurationS)
	}
}

func TestServer_VO2Max_NoQualifyingRunsIs404(t *testing.T) {
	be := &fakeBackend{
		tier: "pro",
		runs: []PremiumRun{
			{DistanceM: 1000, DurationS: 300}, // too short
		},
	}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/vo2max", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("no qualifying runs = %d, want 404", resp.StatusCode)
	}
}

func TestServer_VO2Max_RunsFetchErrorIs500(t *testing.T) {
	be := &fakeBackend{tier: "pro", runsErr: errors.New("PostgREST 500")}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/vo2max", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusInternalServerError {
		t.Errorf("runs fetch error = %d, want 500", resp.StatusCode)
	}
}

// ---------------- Race predictor endpoint ----------------

func TestServer_RacePredictor_HappyPath(t *testing.T) {
	be := &fakeBackend{
		tier: "pro",
		runs: []PremiumRun{
			{StartedAt: "2026-05-05", DistanceM: 5000, DurationS: 1200},
		},
	}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/race-predictor", tok,
		`{"target_distance_m":21097.5}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("race-predictor happy path = %d, want 200", resp.StatusCode)
	}
	var got RacePredictorResponse
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	// Riegel 5k 20:00 → half ≈ 5460s (≈ 1:31).
	if got.PredictedTimeS < 5300 || got.PredictedTimeS > 5600 {
		t.Errorf("predicted half = %ds, want ≈ 5460", got.PredictedTimeS)
	}
	if got.Exponent != 1.06 {
		t.Errorf("default exponent = %.2f, want 1.06", got.Exponent)
	}
}

func TestServer_RacePredictor_HonoursCustomExponent(t *testing.T) {
	be := &fakeBackend{
		tier: "pro",
		runs: []PremiumRun{
			{DistanceM: 5000, DurationS: 1200},
		},
	}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/race-predictor", tok,
		`{"target_distance_m":10000,"exponent":1.08}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	var got RacePredictorResponse
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.Exponent != 1.08 {
		t.Errorf("custom exponent = %.2f, want 1.08", got.Exponent)
	}
}

func TestServer_RacePredictor_MissingTargetIs400(t *testing.T) {
	be := &fakeBackend{tier: "pro", runs: []PremiumRun{{DistanceM: 5000, DurationS: 1200}}}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/race-predictor", tok, `{}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("missing target distance = %d, want 400", resp.StatusCode)
	}
}

func TestServer_RacePredictor_BadJSONIs400(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/race-predictor", tok, `not json`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("bad JSON = %d, want 400", resp.StatusCode)
	}
}

func TestServer_RacePredictor_NoQualifyingRunsIs404(t *testing.T) {
	be := &fakeBackend{tier: "pro", runs: nil}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/race-predictor", tok,
		`{"target_distance_m":10000}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("no qualifying runs = %d, want 404", resp.StatusCode)
	}
}

// ---------------- Recovery endpoint ----------------

func TestServer_Recovery_HappyPath(t *testing.T) {
	// Pin "today" so the daily aggregation lands on the test data.
	old := nowFn
	defer func() { nowFn = old }()
	nowFn = func() time.Time { return time.Date(2026, 5, 11, 0, 0, 0, 0, time.UTC) }

	be := &fakeBackend{
		tier: "pro",
		runs: []PremiumRun{
			{StartedAt: "2026-05-11T07:00:00Z", DistanceM: 5000, DurationS: 1500},
		},
	}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/recovery", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("recovery happy path = %d, want 200", resp.StatusCode)
	}
	var got RecoveryResponse
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.Advice == "" {
		t.Errorf("advice should not be empty")
	}
	if got.ATL <= 0 {
		t.Errorf("ATL should be > 0 after one run; got %.2f", got.ATL)
	}
}

func TestServer_Recovery_EmptyRunsReturnsZeros(t *testing.T) {
	be := &fakeBackend{tier: "pro", runs: nil}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/recovery", tok, "{}")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("empty runs = %d, want 200", resp.StatusCode)
	}
	var got RecoveryResponse
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.CTL != 0 || got.ATL != 0 || got.TSB != 0 {
		t.Errorf("empty runs should give zeros; got %+v", got)
	}
	if !strings.Contains(got.Advice, "Not enough") {
		t.Errorf("advice for ctl=0 should be 'not enough'; got %q", got.Advice)
	}
}

// ---------------- Training plan endpoint ----------------

func TestServer_TrainingPlan_HappyPath_10k(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/training-plan", tok,
		`{"goal_event":"distance_10k","recent_5k_sec":1200,"weeks":8,"days_per_week":5}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("training-plan happy path = %d, want 200", resp.StatusCode)
	}
	var got GeneratedPlan
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.Weeks != 8 || got.DaysPerWeek != 5 {
		t.Errorf("plan dims off: weeks=%d dpw=%d", got.Weeks, got.DaysPerWeek)
	}
	if len(got.Weekly) != 8 {
		t.Errorf("expected 8 weekly entries; got %d", len(got.Weekly))
	}
	if got.GoalDistanceM != 10000 {
		t.Errorf("goal distance = %v, want 10000", got.GoalDistanceM)
	}
}

func TestServer_TrainingPlan_DefaultsForMissingFields(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/training-plan", tok,
		`{"goal_event":"distance_half","recent_5k_sec":1200}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	var got GeneratedPlan
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.Weeks != 12 { // default for half
		t.Errorf("default weeks for half = %d, want 12", got.Weeks)
	}
	if got.DaysPerWeek != 4 { // default
		t.Errorf("default days per week = %d, want 4", got.DaysPerWeek)
	}
}

func TestServer_TrainingPlan_CustomGoalDistance(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/training-plan", tok,
		`{"goal_event":"custom","goal_distance_m":15000,"recent_5k_sec":1200}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("custom goal = %d, want 200", resp.StatusCode)
	}
	var got GeneratedPlan
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.GoalDistanceM != 15000 {
		t.Errorf("custom goal distance = %v, want 15000", got.GoalDistanceM)
	}
}

func TestServer_TrainingPlan_MissingRecent5kIs400(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/training-plan", tok,
		`{"goal_event":"distance_10k"}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("missing recent_5k_sec = %d, want 400", resp.StatusCode)
	}
}

func TestServer_TrainingPlan_MissingGoalEventIs400(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/training-plan", tok,
		`{"recent_5k_sec":1200}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("missing goal_event = %d, want 400", resp.StatusCode)
	}
}

func TestServer_TrainingPlan_UnknownGoalEventIs400(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/training-plan", tok,
		`{"goal_event":"distance_ultra","recent_5k_sec":1200}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("unknown goal_event = %d, want 400", resp.StatusCode)
	}
}

func TestServer_TrainingPlan_CustomEventWithoutDistanceIs400(t *testing.T) {
	be := &fakeBackend{tier: "pro"}
	base, teardown := newProServer(t, be)
	defer teardown()

	tok := signTestToken(t, "u1", 3600)
	resp := postJSON(t, base, "/v1/premium/training-plan", tok,
		`{"goal_event":"custom","recent_5k_sec":1200}`)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("custom without distance = %d, want 400", resp.StatusCode)
	}
}
