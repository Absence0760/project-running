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

	for _, pref := range []Preference{PrefNone, PrefQuiet, PrefScenic} {
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

func TestPreferenceSteersOntoPreferredEdges(t *testing.T) {
	g, _ := BuildTestSplitGrid(9, 9, 100, 40.0, -77.0)
	lat, lng := splitGridCentre(9, 9, 100, 40.0, -77.0)

	plain := g.SearchCycle(context.Background(), lat, lng, 800, PrefNone)
	if plain.Best == nil {
		t.Fatal("expected an unpreferenced loop on a dense grid")
	}
	if plain.Applied != PrefNone || plain.PreferredShare != 0 {
		t.Fatalf("unpreferenced result claimed applied=%d share=%v", plain.Applied, plain.PreferredShare)
	}

	for _, pref := range []Preference{PrefQuiet, PrefScenic} {
		res := g.SearchCycle(context.Background(), lat, lng, 800, pref)
		if res.Best == nil {
			t.Fatalf("pref %d: expected a loop", pref)
		}
		if res.Applied != pref {
			t.Fatalf("pref %d: applied = %d", pref, res.Applied)
		}
		got := g.preferredShare(res.Best, pref)
		base := g.preferredShare(plain.Best, pref)
		if got <= base {
			t.Fatalf("pref %d: preferred share %.3f did not improve on the unpreferenced %.3f", pref, got, base)
		}
		if math.Abs(res.PreferredShare-got) > 1e-12 {
			t.Fatalf("pref %d: reported share %.6f != measured %.6f", pref, res.PreferredShare, got)
		}
	}
}

func TestPreferenceNeverDeniesALoop(t *testing.T) {
	// The contract: a preference is an enhancement. Wherever the unweighted
	// search finds a loop, the weighted search must serve one too — either its
	// own, or the unweighted retry's.
	grid, _ := BuildTestGrid(9, 9, 100, 40.0, -77.0)
	split, _ := BuildTestSplitGrid(9, 9, 100, 40.0, -77.0)
	stub, _ := BuildTestStubGrid(9, 9, 100, 40.0, -77.0, 0.4)
	lat, lng := splitGridCentre(9, 9, 100, 40.0, -77.0)

	for gi, g := range []*Graph{grid, split, stub} {
		for _, target := range []float64{400, 800, 1200, 2000, 3000} {
			plain := g.SearchCycle(context.Background(), lat, lng, target, PrefNone)
			if plain.Best == nil {
				continue
			}
			for _, pref := range []Preference{PrefQuiet, PrefScenic} {
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
	g, _ := BuildTestSplitGrid(9, 9, 100, 40.0, -77.0)
	lat, lng := splitGridCentre(9, 9, 100, 40.0, -77.0)
	res := g.SearchCycle(context.Background(), lat, lng, 800, PrefQuiet)
	if res.Best == nil {
		t.Fatal("expected a loop")
	}
	if math.Abs(res.Best.DistanceM-g.pathLengthM(res.Best.path)) > 1e-6 {
		t.Fatalf("reported %.3f m, geometry measures %.3f m", res.Best.DistanceM, g.pathLengthM(res.Best.path))
	}
}
