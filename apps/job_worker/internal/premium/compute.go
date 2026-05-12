package premium

import (
	"math"
	"strings"
	"time"
)

// realNow returns the current wall-clock time. Indirected through
// `nowFn` so tests can pin "today" to a deterministic instant.
func realNow() time.Time { return time.Now().UTC() }

// Pure compute helpers. Mirror the formulas in
// apps/web/src/lib/training.ts, fitness.ts, and training_load.ts so
// the Pro endpoints write byte-equivalent numbers to what the web
// dashboards show. Each helper is exported + side-effect-free so
// tests can pin the math without booting the HTTP host.

// ---------------- VDOT (Daniels) ----------------

// VDotFromRace computes Daniels VDOT from a single race effort.
//
//	vo2 = -4.6 + 0.182258 v + 0.000104 v²    (v in metres/min)
//	pct = 0.8 + 0.1894393 e^(-0.012778 T) + 0.2989558 e^(-0.1932605 T)   (T in minutes)
//	vdot = vo2 / pct
//
// Source: Daniels, J. — Daniels' Running Formula, 3rd ed.
func VDotFromRace(distanceM, timeSec float64) float64 {
	if distanceM <= 0 || timeSec <= 0 {
		return 0
	}
	minutes := timeSec / 60
	v := distanceM / minutes
	vo2 := -4.6 + 0.182258*v + 0.000104*v*v
	pct := 0.8 +
		0.1894393*math.Exp(-0.012778*minutes) +
		0.2989558*math.Exp(-0.1932605*minutes)
	if pct <= 0 {
		return 0
	}
	return vo2 / pct
}

// VO2MaxFromRace is the numerator of the VDOT calc — the running
// vo2 estimate at the race pace. Exposed separately so the
// /v1/premium/vo2max endpoint can surface both numbers (some users
// want the raw vo2; some want VDOT).
func VO2MaxFromRace(distanceM, timeSec float64) float64 {
	if distanceM <= 0 || timeSec <= 0 {
		return 0
	}
	minutes := timeSec / 60
	v := distanceM / minutes
	return -4.6 + 0.182258*v + 0.000104*v*v
}

// BestVDotFromRuns finds the run that yields the highest VDOT among
// those that qualify. Mirrors the web `currentVdot` qualifier shape:
// distance ≥ 3 km, duration ≥ 5 min, activity_type either absent or
// in {run, walk, hike}. The wrist's recorder writes
// `metadata.activity_type`; legacy rows without it are admitted on
// the assumption that no-tag runs are runs.
func BestVDotFromRuns(runs []PremiumRun) VO2MaxResponse {
	const minDistanceM = 3000
	const minDurationS = 300
	best := VO2MaxResponse{}
	count := 0
	for _, r := range runs {
		if !isRunlike(r) {
			continue
		}
		if r.DistanceM < minDistanceM || r.DurationS < minDurationS {
			continue
		}
		count++
		v := VDotFromRace(r.DistanceM, float64(r.DurationS))
		if v > best.VDOT {
			best.VDOT = v
			best.BestVO2Max = VO2MaxFromRace(r.DistanceM, float64(r.DurationS))
			best.BestDistanceM = r.DistanceM
			best.BestDurationS = r.DurationS
		}
	}
	best.QualifyingRuns = count
	return best
}

func isRunlike(r PremiumRun) bool {
	if r.Metadata == nil {
		return true
	}
	switch t := r.Metadata["activity_type"].(type) {
	case string:
		lt := strings.ToLower(t)
		return lt == "" || lt == "run" || lt == "walk" || lt == "hike"
	default:
		return true
	}
}

// ---------------- Riegel ----------------

// RiegelPredict t2 = t1 · (d2/d1)^exponent. Default exponent 1.06
// per Riegel 1981 — accurate within 1-2 % across 5k → marathon for
// most runners.
func RiegelPredict(knownDistanceM, knownTimeSec, targetDistanceM, exponent float64) float64 {
	if knownDistanceM <= 0 || knownTimeSec <= 0 || targetDistanceM <= 0 {
		return 0
	}
	if exponent <= 0 {
		exponent = 1.06
	}
	return knownTimeSec * math.Pow(targetDistanceM/knownDistanceM, exponent)
}

// ---------------- Training load (CTL / ATL / TSB) ----------------

// TrainingLoad walks the runs forward in time, computes a per-run
// stress score (TRIMP when avg_bpm + rest/max HR are available;
// distance proxy otherwise), and runs two EWMAs:
//
//	CTL — chronic training load, halflife 42 days (fitness)
//	ATL — acute training load, halflife 7 days (fatigue)
//	TSB = CTL - ATL (form / freshness)
//
// Mirrors apps/web/src/lib/training_load.ts. The web reads
// `resting_hr_bpm` + `max_hr_bpm` from user_settings.prefs; here we
// don't have those (yet) so the calc always falls through to the
// distance-proxy branch. Future enhancement: thread the prefs through
// the Backend so the TRIMP branch can light up for HR-recorded runs.
func TrainingLoad(runs []PremiumRun) (ctl, atl, tsb float64) {
	if len(runs) == 0 {
		return 0, 0, 0
	}
	// Group by day; aggregate stress per day.
	daily := make(map[string]float64)
	for _, r := range runs {
		day := r.StartedAt
		if len(day) >= 10 {
			day = day[:10]
		}
		daily[day] += stressOf(r)
	}
	// Build a 90-day series ending today.
	const days = 90
	scores := make([]float64, days)
	// Map day → index. Use a simple iso-date walk-back from "today".
	// We don't have a clock injection here; for a deterministic test
	// path, the helper splits into `trainingLoadFromDaily` below.
	now := nowFn()
	for i := 0; i < days; i++ {
		d := now.AddDate(0, 0, -(days - 1 - i)).Format("2006-01-02")
		scores[i] = daily[d]
	}
	return trainingLoadFromSeries(scores)
}

// trainingLoadFromSeries is the testable EWMA core. Pure: takes a
// daily stress series, returns the final CTL/ATL/TSB.
func trainingLoadFromSeries(series []float64) (ctl, atl, tsb float64) {
	const (
		ctlHalflife = 42.0
		atlHalflife = 7.0
	)
	ctlAlpha := 1 - math.Pow(0.5, 1/ctlHalflife)
	atlAlpha := 1 - math.Pow(0.5, 1/atlHalflife)
	for _, s := range series {
		ctl = ctl + ctlAlpha*(s-ctl)
		atl = atl + atlAlpha*(s-atl)
	}
	return ctl, atl, ctl - atl
}

// stressOf is the per-run stress score. Coggan-style TRIMP would
// need `resting_hr_bpm` + `max_hr_bpm` (not on PremiumRun yet); for
// now we always use the distance proxy — easy 5k = ~50, marathon
// pace easy = ~150, long slow distance = scales with km.
func stressOf(r PremiumRun) float64 {
	if r.DistanceM <= 0 || r.DurationS <= 0 {
		return 0
	}
	// Distance proxy: 10 stress points per km. Easy 5k = 50; half
	// marathon = 211; matches the web's distance-fallback ladder.
	return r.DistanceM / 100
}

// nowFn is overridable in tests; defaults to time.Now via the var
// trick so tests can pin a fake "today".
var nowFn = realNow

// RecoveryAdvice maps the form (TSB) + fitness (CTL) signals to a
// one-line recommendation. Mirrors apps/web/src/lib/fitness.ts's
// `recoveryAdvice` thresholds.
func RecoveryAdvice(tsb, ctl float64) string {
	if ctl < 5 {
		return "Not enough recent training to advise — keep building base."
	}
	switch {
	case tsb > 15:
		return "Fresh and ready — good day to race or hit a hard workout."
	case tsb > 5:
		return "Well recovered — workouts will land cleanly."
	case tsb > -10:
		return "Normal training stress — listen to perceived effort."
	case tsb > -20:
		return "Accumulating fatigue — consider an easy day or a rest day."
	default:
		return "Heavily fatigued — take a recovery day before your next hard session."
	}
}

// ---------------- Training plan generator ----------------

// GeneratePlanInput is the request shape for /v1/premium/training-plan.
type GeneratePlanInput struct {
	GoalDistanceM float64
	Recent5kSec   int
	Weeks         int
	DaysPerWeek   int
}

// TrainingPaces are the four target paces a plan ships — seconds per km.
type TrainingPaces struct {
	EasySecPerKm     int `json:"easy_sec_per_km"`
	MarathonSecPerKm int `json:"marathon_sec_per_km"`
	TempoSecPerKm    int `json:"tempo_sec_per_km"`
	IntervalSecPerKm int `json:"interval_sec_per_km"`
}

// PlanWeek is one week of the generated plan.
type PlanWeek struct {
	WeekNumber       int    `json:"week_number"`
	Phase            string `json:"phase"` // base / build / peak / taper / race
	TargetDistanceM  int    `json:"target_distance_m"`
	KeyWorkout       string `json:"key_workout"`
}

// GeneratedPlan is what the endpoint returns.
type GeneratedPlan struct {
	GoalDistanceM   float64       `json:"goal_distance_m"`
	GoalTimeS       int           `json:"goal_time_s"`
	Weeks           int           `json:"weeks"`
	DaysPerWeek     int           `json:"days_per_week"`
	Paces           TrainingPaces `json:"paces"`
	Weekly          []PlanWeek    `json:"weekly"`
	BaseWeeklyKm    int           `json:"base_weekly_km"`
	PeakWeeklyKm    int           `json:"peak_weekly_km"`
}

// GeneratePlan ports the Riegel-pace + phased-weekly-mileage
// generator from apps/web/src/lib/training.ts. Phases:
//
//	1..floor(weeks·0.5)              base   — easy mileage build
//	floor(0.5)..floor(0.75)          build  — tempo + intervals
//	floor(0.75)..weeks-1             peak   — race-pace work
//	weeks                            taper  — drop volume to ~60 %
//	(last week is always taper / race-week)
//
// Per-week target mileage progresses from BaseWeeklyKm to
// PeakWeeklyKm over the build phase, then tapers. Pace targets come
// from Riegel-predicted goal pace.
func GeneratePlan(input GeneratePlanInput) GeneratedPlan {
	weeks := input.Weeks
	if weeks < 4 {
		weeks = 4
	}
	if weeks > 24 {
		weeks = 24
	}
	dpw := input.DaysPerWeek
	if dpw < 3 {
		dpw = 3
	}
	if dpw > 7 {
		dpw = 7
	}
	goalDist := input.GoalDistanceM
	if goalDist <= 0 {
		goalDist = 10_000
	}
	goalTimeSec := int(math.Round(RiegelPredict(5000, float64(input.Recent5kSec), goalDist, 1.06)))
	goalPace := float64(goalTimeSec) / (goalDist / 1000)

	// Pace targets — Riegel-derived multipliers calibrated against
	// Daniels' percentages (E=70%, M=84%, T=88%, I=98% of VDOT).
	// Multipliers of goal pace map within ~5 s/km of Daniels for
	// typical runners and require no lookup table.
	paces := TrainingPaces{
		EasySecPerKm:     int(math.Round(goalPace * 1.30)),
		MarathonSecPerKm: int(math.Round(goalPace * 1.05)),
		TempoSecPerKm:    int(math.Round(goalPace * 0.97)),
		IntervalSecPerKm: int(math.Round(goalPace * 0.92)),
	}

	// Mileage progression: base = 30 km/wk for the 5k/10k goals,
	// 45 for half, 60 for marathon. Peak ~ 1.5×.
	baseKm := 30
	if goalDist >= 21_000 {
		baseKm = 45
	}
	if goalDist >= 42_000 {
		baseKm = 60
	}
	peakKm := baseKm + baseKm/2

	baseEnd := weeks / 2
	buildEnd := (weeks * 3) / 4
	// Pre-allocate to the constant ceiling rather than to `weeks` —
	// `weeks` is already clamped to [4, 24], but CodeQL follows the
	// user-input taint through `make` regardless of intervening
	// clamps or `min()` calls. A literal capacity severs the data
	// flow entirely; the unused tail (when weeks < 24) is one PlanWeek
	// struct per missing week, ~hundreds of bytes total. The for-loop
	// below only appends `weeks` entries so the slice length is right.
	const maxPlanWeeks = 24
	weekly := make([]PlanWeek, 0, maxPlanWeeks)
	for w := 1; w <= weeks; w++ {
		var phase, key string
		var km int
		switch {
		case w == weeks:
			phase, key, km = "race", "Race / goal effort", baseKm/2
		case w == weeks-1:
			phase, key, km = "taper", "Drop volume; sharpen pace", int(float64(peakKm)*0.65)
		case w > buildEnd:
			// peak
			progress := float64(w-buildEnd) / float64(weeks-1-buildEnd)
			phase = "peak"
			key = "Race-pace + tempo"
			km = int(math.Round(float64(baseKm) + float64(peakKm-baseKm)*math.Min(1, progress)))
		case w > baseEnd:
			// build
			progress := float64(w-baseEnd) / float64(buildEnd-baseEnd)
			phase = "build"
			key = "Tempo + intervals"
			km = int(math.Round(float64(baseKm) + float64(peakKm-baseKm)*progress*0.7))
		default:
			// base
			progress := float64(w-1) / float64(max(1, baseEnd-1))
			phase = "base"
			key = "Easy mileage + 1 stride day"
			km = int(math.Round(float64(baseKm) * (0.7 + 0.3*progress)))
		}
		weekly = append(weekly, PlanWeek{
			WeekNumber: w, Phase: phase,
			TargetDistanceM: km * 1000,
			KeyWorkout:      key,
		})
	}
	return GeneratedPlan{
		GoalDistanceM: goalDist,
		GoalTimeS:     goalTimeSec,
		Weeks:         weeks,
		DaysPerWeek:   dpw,
		Paces:         paces,
		Weekly:        weekly,
		BaseWeeklyKm:  baseKm,
		PeakWeeklyKm:  peakKm,
	}
}
