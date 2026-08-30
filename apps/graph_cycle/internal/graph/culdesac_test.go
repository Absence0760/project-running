package graph

import (
	"context"
	"math"
	"testing"
)

func stubGridStart() (lat, lng float64) {
	return 40.0 + 4*metresToDegLat(100), -77.0 + 4*metresToDegLng(100, 40.0)
}

func TestCulDeSacAddsStubsAndCreditsThem(t *testing.T) {
	g, _ := BuildTestStubGrid(9, 9, 100, 40.0, -77.0, 0.4)
	lat, lng := stubGridStart()

	plain := g.SearchCycle(context.Background(), lat, lng, 1200, PrefNone)
	if plain.Best == nil {
		t.Fatal("expected an unpreferenced loop")
	}
	if plain.Best.stubM != 0 || plain.PreferredShare != 0 {
		t.Fatal("cul-de-sac mode is off by default; no loop may be credited stubs without it")
	}

	res := g.SearchCycle(context.Background(), lat, lng, 1200, PrefCulDeSac)
	if res.Best == nil {
		t.Fatal("expected a loop under cul-de-sac mode")
	}
	if res.Applied != PrefCulDeSac {
		t.Fatalf("applied = %d", res.Applied)
	}
	if res.Best.stubM <= 0 {
		t.Fatal("a lattice with a dead end off every node must yield a stubbed loop")
	}
	if math.Abs(res.PreferredShare-res.Best.stubM/res.Best.DistanceM) > 1e-12 {
		t.Fatalf("reported share %.6f is not the stub share", res.PreferredShare)
	}
	// The served loop is still a loop, still closes, and is still measured from
	// its own geometry.
	if res.Best.AreaEfficiency < spurFloor {
		t.Fatalf("stubbed loop efficiency %.3f fell below the spur floor", res.Best.AreaEfficiency)
	}
	if math.Abs(res.Best.DistanceM-g.pathLengthM(res.Best.path)) > 1e-6 {
		t.Fatal("stubbed distance must be re-measured from geometry")
	}
	first, last := res.Best.Coords[0], res.Best.Coords[len(res.Best.Coords)-1]
	if haversineM(first.Lat, first.Lng, last.Lat, last.Lng) > 1 {
		t.Fatal("a stubbed loop must still close back at the start")
	}
}

func TestCulDeSacRespectsItsCaps(t *testing.T) {
	g, _ := BuildTestStubGrid(9, 9, 100, 40.0, -77.0, 0.4)
	lat, lng := stubGridStart()
	for _, target := range []float64{600, 800, 1200, 1600, 2000} {
		res := g.SearchCycle(context.Background(), lat, lng, target, PrefCulDeSac)
		if res.Best == nil {
			continue
		}
		if res.Best.stubM > culDeSacShareOfTarget*target+1e-9 {
			t.Fatalf("target %.0f: credited %.1f m of stub, cap is %.1f",
				target, res.Best.stubM, culDeSacShareOfTarget*target)
		}
		deadEnds := 0
		for _, n := range res.Best.path {
			if g.degree(n) == 1 {
				deadEnds++
			}
		}
		if deadEnds > culDeSacMaxStubs {
			t.Fatalf("target %.0f: %d dead ends on the loop, cap is %d", target, deadEnds, culDeSacMaxStubs)
		}
	}
}

func TestCulDeSacOnlyLengthensTowardsTarget(t *testing.T) {
	// A loop already at or past target gains nothing from a spur, so it must
	// not be given one — the mode credits distance, it does not manufacture it.
	g, _ := BuildTestStubGrid(9, 9, 100, 40.0, -77.0, 0.4)
	lat, lng := stubGridStart()
	res := g.SearchCycle(context.Background(), lat, lng, 1200, PrefCulDeSac)
	if res.Best == nil {
		t.Fatal("expected a loop")
	}
	if res.Best.DistanceM > 1200 {
		t.Fatalf("stubs pushed the loop past target: %.1f m", res.Best.DistanceM)
	}
}

func TestFindQuietStubSkipsArterialDeadEnds(t *testing.T) {
	// One node with two dead ends: an arterial one and a residential one. Only
	// the quiet one is a cul-de-sac worth running down.
	b := newBuilder()
	b.addNode(0, Coord{Lat: 0, Lng: 0})
	b.addNode(1, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b.addNode(2, Coord{Lat: metresToDegLat(100), Lng: 0})
	b.addNode(3, Coord{Lat: -metresToDegLat(100), Lng: 0})
	b.addSegment(0, 1, classResidential) // the loop this stub would hang off
	b.addSegment(0, 2, classArterial)    // arterial dead end
	b.addSegment(0, 3, classResidential) // quiet dead end
	g := b.finalize()

	onLoop := map[int32]struct{}{0: {}, 1: {}}
	stub := g.findQuietStub(0, onLoop, map[int32]struct{}{})
	if len(stub) != 2 || stub[1] != 3 {
		t.Fatalf("stub = %v, want the residential dead end (node index 3)", stub)
	}
	// Claim it and the arterial one must still not be offered.
	if s := g.findQuietStub(0, onLoop, map[int32]struct{}{3: {}}); s != nil {
		t.Fatalf("stub = %v, want none — the only other dead end is arterial", s)
	}
}

func TestFindQuietStubRefusesAnOverlongSpur(t *testing.T) {
	b := newBuilder()
	b.addNode(0, Coord{Lat: 0, Lng: 0})
	b.addNode(1, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b.addNode(2, Coord{Lat: metresToDegLat(culDeSacMaxStubM + 50), Lng: 0})
	b.addSegment(0, 1, classResidential)
	b.addSegment(0, 2, classResidential)
	g := b.finalize()

	if s := g.findQuietStub(0, map[int32]struct{}{0: {}, 1: {}}, map[int32]struct{}{}); s != nil {
		t.Fatalf("stub = %v, want none — the dead end is past the length cap", s)
	}
}
