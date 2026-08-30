package graph

import (
	"math"
	"math/rand"
	"sort"
	"testing"
)

// pinTargets spans the accepted input range. The server rejects a
// targetDistanceM outside (0, 100 000] (maxTargetDistanceM, internal/api), which
// the graph package cannot import back.
var pinTargets = []float64{1, 10, 100, 500, 1000, 4500, 10_000, 25_000, 50_000}

const maxPinTarget = 100_000.0

// legacySelect is the two-branch selection the sidecar shipped with, kept
// verbatim as the reference the scoring rewrite is measured against. A rewrite
// that silently changed the default generator would be invisible to the web
// suite, which only ever sees a loop come back.
func legacySelect(cands []*Loop, targetM float64) CycleResult {
	clean := make([]*Loop, 0, len(cands))
	for _, c := range cands {
		if c.AreaEfficiency >= spurFloor {
			clean = append(clean, c)
		}
	}
	if len(clean) == 0 {
		return CycleResult{}
	}
	sort.SliceStable(clean, func(i, j int) bool {
		if clean[i].DistanceM != clean[j].DistanceM {
			return clean[i].DistanceM < clean[j].DistanceM
		}
		return clean[i].AreaEfficiency > clean[j].AreaEfficiency
	})
	var largest *Loop
	for _, c := range clean {
		if largest == nil || c.DistanceM > largest.DistanceM {
			largest = c
		}
	}
	band := distanceBand * targetM
	var within []*Loop
	for _, c := range clean {
		if math.Abs(c.DistanceM-targetM) <= band {
			within = append(within, c)
		}
	}
	var best *Loop
	if len(within) > 0 {
		best = within[0]
		for _, c := range within[1:] {
			if c.AreaEfficiency > best.AreaEfficiency+1e-9 ||
				(math.Abs(c.AreaEfficiency-best.AreaEfficiency) <= 1e-9 &&
					math.Abs(c.DistanceM-targetM) < math.Abs(best.DistanceM-targetM)) {
				best = c
			}
		}
	} else {
		best = clean[0]
		bestDelta := math.Abs(best.DistanceM - targetM)
		for _, c := range clean[1:] {
			delta := math.Abs(c.DistanceM - targetM)
			if delta < bestDelta-1e-9 ||
				(math.Abs(delta-bestDelta) <= 1e-9 && c.AreaEfficiency > best.AreaEfficiency) {
				best = c
				bestDelta = delta
			}
		}
	}
	return CycleResult{Best: best, LargestClean: largest}
}

func TestSelectLoopsUnpreferencedMatchesShippedContract(t *testing.T) {
	square := []Coord{{Lng: 0, Lat: 0}, {Lng: 0, Lat: 1}, {Lng: 1, Lat: 1}, {Lng: 1, Lat: 0}}
	// 4 corpus shapes x 10 target cells x 20 000 candidate sets = 800 000 sets,
	// spanning the whole accepted input range. Measured divergence from
	// legacySelect: 0. The range is half the pin: the rewrite this guards
	// shipped with both tie-breaks scaled below one ULP of the term they were
	// added to, which on the tied-distance corpus diverged on 0% of sets below
	// a 4.5 km target and up to 5.5% at the 100 km cap, so a pin drawing only
	// small targets certified the one stretch that could not fail.
	//
	// What it cannot cover: candidate pairs whose roundness differs by O(1e-9).
	// The old comparison called that a tie, which made it non-transitive, so no
	// scalar score reproduces it; the residual there separates loops agreeing on
	// roundness to 2.5e-9 and on distance-to-target to 9 micrometres.
	const trialsPerCell = 20_000
	for _, shape := range []string{"continuous", "coarse", "tiedDistance", "tiedRoundness"} {
		for cell := 0; cell <= len(pinTargets); cell++ {
			rng := rand.New(rand.NewSource(11))
			for trial := 0; trial < trialsPerCell; trial++ {
				target := 0.0
				if cell < len(pinTargets) {
					target = pinTargets[cell]
				} else {
					// The rest of the range, logarithmically so the metre-scale
					// end is sampled as densely as the kilometre-scale one.
					target = maxPinTarget * math.Pow(10, -5*rng.Float64())
				}
				n := 1 + rng.Intn(8)
				cands := make([]*Loop, n)
				sharedD := target * (0.4 + rng.Float64()*1.6)
				sharedEff := rng.Float64()
				for i := range cands {
					d, eff := target*(0.4+rng.Float64()*1.6), rng.Float64()
					switch shape {
					case "coarse":
						d, eff = target*(0.5+0.25*float64(rng.Intn(5))), 0.25*float64(rng.Intn(5))
					case "tiedDistance":
						d = sharedD
					case "tiedRoundness":
						eff = sharedEff
					}
					cands[i] = &Loop{Coords: square, DistanceM: d, AreaEfficiency: eff}
				}
				got := selectLoops(cands, target, PrefNone)
				want := legacySelect(cands, target)
				if got.Best != want.Best {
					t.Fatalf("%s cell %d trial %d (target %.3f): best diverged from the shipped contract", shape, cell, trial, target)
				}
				if got.LargestClean != want.LargestClean {
					t.Fatalf("%s cell %d trial %d (target %.3f): largestClean diverged", shape, cell, trial, target)
				}
			}
		}
	}
}

// TestScoreLoopTieBreaksSurviveTheirOwnScale pins directly what the corpus above
// can only find statistically: each branch's tie-break has to be representable
// at the magnitude of the term it is added to, or it rounds away and the
// objective it exists to decide silently reverses.
func TestScoreLoopTieBreaksSurviveTheirOwnScale(t *testing.T) {
	square := []Coord{{Lng: 0, Lat: 0}, {Lng: 0, Lat: 1}, {Lng: 1, Lat: 1}, {Lng: 1, Lat: 0}}

	// Out of band, exact tie on distance: the rounder loop wins. At this target
	// one ULP of the delta is 3.6e-12, so a tie-break in metres has nothing left.
	target := 50_000.0
	blunt := &Loop{Coords: square, DistanceM: 25_000, AreaEfficiency: 0.20}
	round := &Loop{Coords: square, DistanceM: 75_000, AreaEfficiency: 0.99}
	if res := selectLoops([]*Loop{blunt, round}, target, PrefNone); res.Best != round {
		t.Fatal("out of band, two loops equidistant from target: the rounder one must win")
	}

	// In band, exact tie on roundness: the closer loop wins, at every distance
	// the band holds rather than at the two the scores used to collapse onto.
	target = 1000.0
	scores := map[float64]struct{}{}
	for i := 0; i <= 150; i++ {
		d := target - float64(i)*(distanceBand*target/150)
		scores[scoreLoop(&Loop{Coords: square, DistanceM: d, AreaEfficiency: 0.5}, target, PrefNone)] = struct{}{}
	}
	if len(scores) != 151 {
		t.Fatalf("151 in-band distances collapsed onto %d scores", len(scores))
	}
	for i := 0; i < 6; i++ {
		for j := 0; j < 6; j++ {
			if i == j {
				continue
			}
			a := &Loop{Coords: square, DistanceM: target - float64(i)*25, AreaEfficiency: 0.5}
			b := &Loop{Coords: square, DistanceM: target - float64(j)*25, AreaEfficiency: 0.5}
			want := a
			if j < i {
				want = b
			}
			if res := selectLoops([]*Loop{a, b}, target, PrefNone); res.Best != want {
				t.Fatalf("in band, equal roundness: kept the loop %.0f m from target over the one %.0f m from it",
					math.Abs(res.Best.DistanceM-target), math.Abs(want.DistanceM-target))
			}
		}
	}
}

// TestScoreLoopBandsNeverCross pins the separation that lets the in-band bonus
// go: the worst loop the band can hold must outrank the best one outside it,
// under every preference, or a preference could buy its way across.
func TestScoreLoopBandsNeverCross(t *testing.T) {
	square := []Coord{{Lng: 0, Lat: 0}, {Lng: 0, Lat: 1}, {Lng: 1, Lat: 1}, {Lng: 1, Lat: 0}}
	const target = 1000.0
	edge := target * (1 + distanceBand)
	worstIn := &Loop{Coords: square, DistanceM: edge, AreaEfficiency: spurFloor, share: 0}
	bestOut := &Loop{Coords: square, DistanceM: math.Nextafter(edge, math.Inf(1)), AreaEfficiency: 1, share: 1}
	for _, pref := range []Preference{PrefNone, PrefQuiet, PrefScenic, PrefCulDeSac} {
		in := scoreLoop(worstIn, target, pref)
		out := scoreLoop(bestOut, target, pref)
		if in <= out {
			t.Fatalf("pref %d: worst in-band %.9f does not outrank best out-of-band %.9f", pref, in, out)
		}
	}
}

func TestSelectLoopsPreferenceBreaksATie(t *testing.T) {
	square := []Coord{{Lng: 0, Lat: 0}, {Lng: 0, Lat: 1}, {Lng: 1, Lat: 1}, {Lng: 1, Lat: 0}}
	// Both in band and equally long; the arterial one is slightly rounder.
	arterial := &Loop{Coords: square, DistanceM: 1000, AreaEfficiency: 0.50, share: 0}
	quiet := &Loop{Coords: square, DistanceM: 1000, AreaEfficiency: 0.45, share: 1}

	if res := selectLoops([]*Loop{arterial, quiet}, 1000, PrefNone); res.Best != arterial {
		t.Fatal("with no preference the rounder loop must still win")
	}
	if res := selectLoops([]*Loop{arterial, quiet}, 1000, PrefQuiet); res.Best != quiet {
		t.Fatal("a fully preferred loop must outrank one 0.05 rounder")
	}
	// But not at any price. With nothing in band the field is judged on
	// distance, and a fully preferred loop may buy only one band's width of
	// error — so the loop 700 m closer to target still wins.
	near := &Loop{Coords: square, DistanceM: 1300, AreaEfficiency: 0.50, share: 0}
	far := &Loop{Coords: square, DistanceM: 2000, AreaEfficiency: 0.50, share: 1}
	if res := selectLoops([]*Loop{near, far}, 1000, PrefQuiet); res.Best != near {
		t.Fatal("a preference must not buy a loop the runner did not ask for the length of")
	}
}
