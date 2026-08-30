package graph

import (
	"math"
	"math/rand"
	"sort"
	"testing"
)

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
	rng := rand.New(rand.NewSource(11))
	// Two corpora: continuous values, and values drawn from a coarse grid so
	// exact ties on distance and on roundness are common.
	for _, coarse := range []bool{false, true} {
		for trial := 0; trial < 4000; trial++ {
			target := 500 + rng.Float64()*4000
			n := 1 + rng.Intn(8)
			cands := make([]*Loop, n)
			for i := range cands {
				d := target * (0.4 + rng.Float64()*1.6)
				eff := rng.Float64()
				if coarse {
					d = target * (0.5 + 0.25*float64(rng.Intn(5)))
					eff = 0.25 * float64(rng.Intn(5))
				}
				cands[i] = &Loop{Coords: square, DistanceM: d, AreaEfficiency: eff}
			}
			got := selectLoops(cands, target, PrefNone)
			want := legacySelect(cands, target)
			if got.Best != want.Best {
				t.Fatalf("coarse=%v trial %d: best diverged from the shipped contract (target %.1f)", coarse, trial, target)
			}
			if got.LargestClean != want.LargestClean {
				t.Fatalf("coarse=%v trial %d: largestClean diverged", coarse, trial)
			}
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
