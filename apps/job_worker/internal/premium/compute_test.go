package premium

import (
	"math"
	"testing"
	"time"
)

// ---- VDOT ----

func TestVDotFromRace_KnownValues(t *testing.T) {
	// 20:00 5k → VDOT ≈ 50 (Daniels' formula, mirrors web's
	// fitness.test.ts; range 48-52). Daniels' lookup table differs
	// by a couple of points from the closed-form; tolerance reflects
	// that.
	got := VDotFromRace(5000, 20*60)
	if got < 48 || got > 52 {
		t.Errorf("VDOT for 20:00 5k = %.2f, want ≈ 50", got)
	}
	// 3:00 marathon → VDOT ≈ 53-54. Same tolerance.
	got = VDotFromRace(42195, 3*60*60)
	if got < 52 || got > 56 {
		t.Errorf("VDOT for 3:00 marathon = %.2f, want ≈ 54", got)
	}
}

func TestVDotFromRace_ZeroInputs(t *testing.T) {
	if got := VDotFromRace(0, 100); got != 0 {
		t.Errorf("VDOT for 0m = %v, want 0", got)
	}
	if got := VDotFromRace(5000, 0); got != 0 {
		t.Errorf("VDOT for 0s = %v, want 0", got)
	}
}

func TestBestVDotFromRuns_PicksHighestVDot(t *testing.T) {
	runs := []PremiumRun{
		{StartedAt: "2026-05-01", DistanceM: 5000, DurationS: 1800}, // 30 min 5k (slow)
		{StartedAt: "2026-05-05", DistanceM: 5000, DurationS: 1200}, // 20 min 5k (fast)
		{StartedAt: "2026-05-08", DistanceM: 2000, DurationS: 800},  // too short, ignored
	}
	res := BestVDotFromRuns(runs)
	if res.QualifyingRuns != 2 {
		t.Errorf("qualifying runs = %d, want 2", res.QualifyingRuns)
	}
	if res.BestDurationS != 1200 {
		t.Errorf("best duration = %d, want 1200", res.BestDurationS)
	}
	if res.VDOT < 46 || res.VDOT > 50 {
		t.Errorf("best VDOT = %.2f, expected ≈ 48 for 20:00 5k", res.VDOT)
	}
}

func TestBestVDotFromRuns_IgnoresNonRunActivities(t *testing.T) {
	runs := []PremiumRun{
		{DistanceM: 5000, DurationS: 1200, Metadata: map[string]any{"activity_type": "cycle"}},
		{DistanceM: 5000, DurationS: 1500, Metadata: map[string]any{"activity_type": "run"}},
	}
	res := BestVDotFromRuns(runs)
	if res.QualifyingRuns != 1 {
		t.Errorf("cycle should be filtered; qualifying = %d, want 1", res.QualifyingRuns)
	}
	if res.BestDurationS != 1500 {
		t.Errorf("expected the runlike one to win")
	}
}

func TestBestVDotFromRuns_EmptyReturnsZero(t *testing.T) {
	res := BestVDotFromRuns(nil)
	if res.QualifyingRuns != 0 || res.VDOT != 0 {
		t.Errorf("empty runs = %+v, want zero result", res)
	}
}

// ---- Riegel ----

func TestRiegelPredict_KnownValues(t *testing.T) {
	// 20 min 5k → predicted half-marathon ≈ ? Riegel: 1200 * (21097.5/5000)^1.06
	got := RiegelPredict(5000, 1200, 21097.5, 1.06)
	// hand calc: 1200 * 4.2195^1.06 ≈ 1200 * 4.55 ≈ 5460
	if got < 5350 || got > 5600 {
		t.Errorf("Riegel 5k→half = %.0fs, expected ≈ 5460", got)
	}
}

func TestRiegelPredict_DefaultsExponent(t *testing.T) {
	got := RiegelPredict(5000, 1200, 10000, 0) // exponent=0 → default 1.06
	want := RiegelPredict(5000, 1200, 10000, 1.06)
	if math.Abs(got-want) > 0.01 {
		t.Errorf("exponent=0 should default; got %v, want %v", got, want)
	}
}

func TestRiegelPredict_ZeroInputs(t *testing.T) {
	if got := RiegelPredict(0, 1200, 10000, 1.06); got != 0 {
		t.Errorf("zero source distance must return 0; got %v", got)
	}
	if got := RiegelPredict(5000, 0, 10000, 1.06); got != 0 {
		t.Errorf("zero source time must return 0; got %v", got)
	}
	if got := RiegelPredict(5000, 1200, 0, 1.06); got != 0 {
		t.Errorf("zero target distance must return 0; got %v", got)
	}
}

// ---- Training load ----

func TestTrainingLoadFromSeries_EasyWeekProducesLowFatigue(t *testing.T) {
	// 90 zeros + one easy 5k (stress=50) on day 90.
	// ATL alpha = 1 - 0.5^(1/7) ≈ 0.0943, so ATL ≈ 50 × 0.0943 ≈ 4.71.
	// CTL alpha = 1 - 0.5^(1/42) ≈ 0.0164, so CTL ≈ 50 × 0.0164 ≈ 0.82.
	// TSB = CTL - ATL ≈ -3.9 (fatigued by a single recent run).
	series := make([]float64, 90)
	series[89] = 50
	ctl, atl, tsb := trainingLoadFromSeries(series)
	if atl < 4 || atl > 6 {
		t.Errorf("ATL = %.2f, want ≈ 4.71", atl)
	}
	if ctl < 0.3 || ctl > 1.5 {
		t.Errorf("CTL = %.2f, want ≈ 0.82", ctl)
	}
	if tsb > 0 {
		t.Errorf("TSB after one recent run should be negative; got %.2f", tsb)
	}
}

func TestTrainingLoadFromSeries_TaperRaisesTSB(t *testing.T) {
	// Heavy training then a taper week. The taper should leave
	// TSB positive (fitness > fatigue) as the ATL bleeds off
	// faster than the CTL.
	series := make([]float64, 90)
	for i := 0; i < 80; i++ {
		series[i] = 80 // ~daily moderate stress
	}
	// last 10 days: rest
	for i := 80; i < 90; i++ {
		series[i] = 0
	}
	_, _, tsb := trainingLoadFromSeries(series)
	if tsb < 5 {
		t.Errorf("post-taper TSB should be >5; got %.2f", tsb)
	}
}

func TestTrainingLoadFromSeries_EmptyReturnsZero(t *testing.T) {
	ctl, atl, tsb := trainingLoadFromSeries(nil)
	if ctl != 0 || atl != 0 || tsb != 0 {
		t.Errorf("empty series should return zero; got ctl=%v atl=%v tsb=%v", ctl, atl, tsb)
	}
}

func TestTrainingLoad_DailyAggregation(t *testing.T) {
	// Two runs on the same day → stress sums. Fake "today" to
	// 2026-05-11 so the iso day matches the test data.
	old := nowFn
	defer func() { nowFn = old }()
	nowFn = func() time.Time {
		return time.Date(2026, 5, 11, 0, 0, 0, 0, time.UTC)
	}
	runs := []PremiumRun{
		{StartedAt: "2026-05-11T07:00:00Z", DistanceM: 5000, DurationS: 1500}, // stress 50
		{StartedAt: "2026-05-11T19:00:00Z", DistanceM: 3000, DurationS: 1000}, // stress 30
	}
	ctl, atl, _ := TrainingLoad(runs)
	// Combined day stress = 80; series has zeros up to today
	// + one 80 today. ATL with halflife-7: 80 * (1 - 0.5^(1/7)) ≈ 7.6.
	// CTL with halflife-42: 80 * (1 - 0.5^(1/42)) ≈ 1.3.
	if atl < 6 || atl > 10 {
		t.Errorf("two same-day runs ATL = %.2f, want ≈ 7.6", atl)
	}
	if ctl < 1 || ctl > 2 {
		t.Errorf("CTL = %.2f, want ≈ 1.3", ctl)
	}
}

// ---- Recovery advice ----

func TestRecoveryAdvice_Bands(t *testing.T) {
	cases := []struct {
		tsb, ctl float64
		wantSub  string // substring of the advice
	}{
		{0, 3, "Not enough recent training"},
		{20, 30, "Fresh and ready"},
		{10, 30, "Well recovered"},
		{0, 30, "Normal training stress"},
		{-15, 30, "Accumulating fatigue"},
		{-30, 30, "Heavily fatigued"},
	}
	for _, c := range cases {
		got := RecoveryAdvice(c.tsb, c.ctl)
		if !contains(got, c.wantSub) {
			t.Errorf("advice for tsb=%v ctl=%v: %q, want substring %q", c.tsb, c.ctl, got, c.wantSub)
		}
	}
}

func contains(s, sub string) bool {
	return len(sub) == 0 || (len(s) >= len(sub) && indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

// ---- Plan generator ----

func TestGeneratePlan_ShapeFor10k(t *testing.T) {
	plan := GeneratePlan(GeneratePlanInput{
		GoalDistanceM: 10000,
		Recent5kSec:   1200, // 20:00 5k
		Weeks:         8,
		DaysPerWeek:   5,
	})
	if plan.Weeks != 8 || plan.DaysPerWeek != 5 {
		t.Errorf("plan dims off: %+v", plan)
	}
	if plan.GoalTimeS < 2400 || plan.GoalTimeS > 2700 {
		t.Errorf("predicted 10k for 20:00 5k = %ds, want ≈ 2520 (Riegel)", plan.GoalTimeS)
	}
	if len(plan.Weekly) != 8 {
		t.Errorf("expected 8 weekly entries; got %d", len(plan.Weekly))
	}
	// Last week is race / taper.
	if plan.Weekly[7].Phase != "race" {
		t.Errorf("final week phase = %q, want 'race'", plan.Weekly[7].Phase)
	}
	if plan.Weekly[6].Phase != "taper" {
		t.Errorf("second-to-last week phase = %q, want 'taper'", plan.Weekly[6].Phase)
	}
	// Pace ladder: easy > marathon > tempo > interval.
	p := plan.Paces
	if !(p.EasySecPerKm > p.MarathonSecPerKm && p.MarathonSecPerKm > p.TempoSecPerKm && p.TempoSecPerKm > p.IntervalSecPerKm) {
		t.Errorf("pace ladder out of order: %+v", p)
	}
}

func TestGeneratePlan_MarathonHasHigherBaseMileage(t *testing.T) {
	marathon := GeneratePlan(GeneratePlanInput{GoalDistanceM: 42_195, Recent5kSec: 1200, Weeks: 16})
	tenK := GeneratePlan(GeneratePlanInput{GoalDistanceM: 10_000, Recent5kSec: 1200, Weeks: 8})
	if marathon.BaseWeeklyKm <= tenK.BaseWeeklyKm {
		t.Errorf("marathon base should exceed 10k base; got %d vs %d", marathon.BaseWeeklyKm, tenK.BaseWeeklyKm)
	}
}

func TestGeneratePlan_PeakMileageExceedsBase(t *testing.T) {
	plan := GeneratePlan(GeneratePlanInput{GoalDistanceM: 21_097.5, Recent5kSec: 1200, Weeks: 12})
	if plan.PeakWeeklyKm <= plan.BaseWeeklyKm {
		t.Errorf("peak should exceed base; got peak=%d base=%d", plan.PeakWeeklyKm, plan.BaseWeeklyKm)
	}
}

func TestGeneratePlan_WeekCountClampedToReasonableRange(t *testing.T) {
	// 2 weeks → clamped up to 4 (minimum).
	p1 := GeneratePlan(GeneratePlanInput{GoalDistanceM: 10000, Recent5kSec: 1200, Weeks: 2})
	if p1.Weeks != 4 {
		t.Errorf("Weeks=2 should clamp to 4; got %d", p1.Weeks)
	}
	// 100 weeks → clamped down to 24.
	p2 := GeneratePlan(GeneratePlanInput{GoalDistanceM: 10000, Recent5kSec: 1200, Weeks: 100})
	if p2.Weeks != 24 {
		t.Errorf("Weeks=100 should clamp to 24; got %d", p2.Weeks)
	}
}

func TestStressOf_ZeroForZeroDistance(t *testing.T) {
	if got := stressOf(PremiumRun{DistanceM: 0, DurationS: 100}); got != 0 {
		t.Errorf("zero distance must give zero stress; got %v", got)
	}
}
