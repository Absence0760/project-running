package graph

import (
	"context"
	"math"
	"testing"
)

func TestPrefCostIsAlwaysSoft(t *testing.T) {
	b := newBuilder()
	b.addNode(0, Coord{Lat: 0, Lng: 0})
	b.addNode(1, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b.addNode(2, Coord{Lat: metresToDegLat(100), Lng: 0})
	b.addNode(3, Coord{Lat: -metresToDegLat(100), Lng: 0})
	b.addSegment(0, 1, classArterial)
	b.addSegment(0, 2, classResidential)
	b.addSegment(0, 3, classFootFirst|attrGreen)
	g := b.finalize()

	for _, pref := range []Preference{PrefNone, PrefQuiet, PrefScenic, PrefCulDeSac} {
		for e := int32(0); e < int32(g.NumEdges()); e++ {
			c := g.prefCost(e, pref)
			// Soft only: a zero or infinite multiplier would let a preference
			// remove an edge and disconnect an otherwise buildable network.
			if !(c > 0) || math.IsInf(c, 0) || math.IsNaN(c) {
				t.Fatalf("pref %d edge %d cost = %v, want finite and positive", pref, e, c)
			}
		}
	}
	if g.prefCost(0, PrefNone) != 1 {
		t.Fatal("PrefNone must leave every edge at its true length")
	}
}

// splitGridCentre is the middle node of a BuildTestSplitGrid lattice: the
// boundary between the arterial west and the quiet, green east.
func splitGridCentre(rows, cols int, spacingM, originLat, originLng float64) (lat, lng float64) {
	return originLat + float64(rows/2)*metresToDegLat(spacingM),
		originLng + float64(cols/2)*metresToDegLng(spacingM, originLat)
}

// sweepTargets is a spread of loop lengths a 13x13 lattice at 100 m spacing can
// actually serve, so a preference is judged over a field of choices rather than
// on one lucky target.
var sweepTargets = []float64{400, 600, 800, 1000, 1200, 1600, 2000, 2400}

func TestPreferenceSteersOntoPreferredEdges(t *testing.T) {
	// The same lattice with the preferred half mirrored, so nothing about the
	// geometry can favour one answer. The unweighted search is blind to the
	// attribution and must pick the same loops on both; the weighted one must
	// end up on more preferred road than it does.
	for _, preferEast := range []bool{true, false} {
		g, _ := BuildTestSplitGrid(13, 13, 100, 40.0, -77.0, preferEast)
		lat := 40.0 + 6*metresToDegLat(100)
		lng := -77.0 + 6*metresToDegLng(100, 40.0)

		for _, pref := range []Preference{PrefQuiet, PrefScenic} {
			plainShare, prefShare := 0.0, 0.0
			for _, target := range sweepTargets {
				plain := g.SearchCycle(context.Background(), lat, lng, target, PrefNone)
				res := g.SearchCycle(context.Background(), lat, lng, target, pref)
				if plain.Best == nil || res.Best == nil {
					t.Fatalf("east=%v pref=%d target=%.0f: expected a loop on a dense grid", preferEast, pref, target)
				}
				if plain.Applied != PrefNone || plain.PreferredShare != 0 {
					t.Fatalf("unpreferenced result claimed applied=%d share=%v", plain.Applied, plain.PreferredShare)
				}
				if res.Applied != pref {
					t.Fatalf("east=%v pref=%d: applied = %d", preferEast, pref, res.Applied)
				}
				if math.Abs(res.PreferredShare-res.Best.share) > 1e-12 {
					t.Fatalf("reported share %.6f != the winner %.6f", res.PreferredShare, res.Best.share)
				}
				plainShare += g.preferredShare(plain.Best, pref)
				prefShare += res.PreferredShare
			}
			if prefShare <= plainShare {
				t.Fatalf("east=%v pref=%d: preferred share over the sweep %.3f did not beat the unpreferenced %.3f",
					preferEast, pref, prefShare, plainShare)
			}
		}
	}
}

func TestPreferenceNeverDeniesALoop(t *testing.T) {
	// The contract: a preference is an enhancement. Wherever the unweighted
	// search finds a loop, the weighted search must serve one too — either its
	// own, or the unweighted retry's.
	grid, _ := BuildTestGrid(9, 9, 100, 40.0, -77.0)
	split, _ := BuildTestSplitGrid(9, 9, 100, 40.0, -77.0, true)
	stub, _ := BuildTestStubGrid(9, 9, 100, 40.0, -77.0, 0.4)
	lat, lng := splitGridCentre(9, 9, 100, 40.0, -77.0)

	for gi, g := range []*Graph{grid, split, stub} {
		for _, target := range []float64{400, 800, 1200, 2000, 3000} {
			plain := g.SearchCycle(context.Background(), lat, lng, target, PrefNone)
			if plain.Best == nil {
				continue
			}
			for _, pref := range []Preference{PrefQuiet, PrefScenic, PrefCulDeSac} {
				res := g.SearchCycle(context.Background(), lat, lng, target, pref)
				if res.Best == nil {
					t.Fatalf("graph %d target %.0f pref %d: preference denied a loop the plain search found", gi, target, pref)
				}
			}
		}
	}
}

func TestLoopPoorStartReportsNoPreference(t *testing.T) {
	g, _ := BuildTestLine(30, 100, 40.0, -77.0)
	res := g.SearchCycle(context.Background(), 40.0, -77.0, 1000, PrefQuiet)
	if res.Best != nil {
		t.Fatal("a line graph is loop-poor under any preference")
	}
	if res.Applied != PrefNone || res.PreferredShare != 0 {
		t.Fatalf("loop-poor result claimed applied=%d share=%v", res.Applied, res.PreferredShare)
	}
}

func TestPreferredLoopLengthComesFromGeometry(t *testing.T) {
	// The weighted cost is not metres. A served loop's distance must still be
	// re-measured from its geometry, exactly as the reuse penalty already
	// required.
	g, _ := BuildTestSplitGrid(9, 9, 100, 40.0, -77.0, true)
	lat, lng := splitGridCentre(9, 9, 100, 40.0, -77.0)
	res := g.SearchCycle(context.Background(), lat, lng, 800, PrefQuiet)
	if res.Best == nil {
		t.Fatal("expected a loop")
	}
	if math.Abs(res.Best.DistanceM-g.pathLengthM(res.Best.path)) > 1e-6 {
		t.Fatalf("reported %.3f m, geometry measures %.3f m", res.Best.DistanceM, g.pathLengthM(res.Best.path))
	}
}
