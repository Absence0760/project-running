package graph

import (
	"math"
	"testing"
)

func TestSearchCycleFindsCleanLoop(t *testing.T) {
	// A 9×9 grid at 100 m spacing is loop-rich. From the centre, ask for an
	// 800 m loop (a 2×2 block of cells has an 800 m perimeter). Expect a clean,
	// in-band, round loop.
	g := gridGraph(9, 9, 100, 40.0, -77.0)
	cLat := 40.0 + 4*metresToDegLat(100)
	cLng := -77.0 + 4*metresToDegLng(100, 40)

	res := g.SearchCycle(cLat, cLng, 800)
	if res.Best == nil {
		t.Fatal("expected a loop in a dense grid, got loop-poor")
	}
	if res.Best.AreaEfficiency < spurFloor {
		t.Fatalf("best efficiency = %.3f, below spur floor", res.Best.AreaEfficiency)
	}
	// Within ±15% of target.
	if math.Abs(res.Best.DistanceM-800) > 0.15*800 {
		t.Fatalf("best loop = %.0f m, target 800 (±15%%)", res.Best.DistanceM)
	}
	// Loop geometry must close back near the start.
	first := res.Best.Coords[0]
	last := res.Best.Coords[len(res.Best.Coords)-1]
	if haversineM(first.Lat, first.Lng, last.Lat, last.Lng) > 1 {
		t.Fatalf("loop does not close: first %v last %v", first, last)
	}
	if res.LargestClean == nil {
		t.Fatal("expected a largest-clean loop alongside best")
	}
}

func TestSearchCycleLoopPoor(t *testing.T) {
	// A straight line has no second way home: every "loop" is an out-and-back
	// spur, so the search must report loop-poor (Best nil).
	g := lineGraph(30, 100, 40.0, -77.0)
	res := g.SearchCycle(40.0, -77.0, 1000)
	if res.Best != nil {
		t.Fatalf("line graph should be loop-poor, got %.0f m loop (eff %.3f)",
			res.Best.DistanceM, res.Best.AreaEfficiency)
	}
}

func TestSearchCycleOffGraph(t *testing.T) {
	g := newBuilder().finalize()
	res := g.SearchCycle(0, 0, 1000)
	if res.Best != nil || res.LargestClean != nil {
		t.Fatal("empty graph must yield an all-nil result")
	}
}

func TestSelectLoopsInBandPicksRoundest(t *testing.T) {
	// Two in-band loops: pick the rounder one even if it's slightly farther
	// from target.
	square := func(half float64) []Coord {
		d := metresToDegLat(half)
		return []Coord{{0, 0}, {0, d}, {d, d}, {d, 0}}
	}
	rounder := &Loop{Coords: square(100), DistanceM: 820, AreaEfficiency: 0.78}
	flatter := &Loop{Coords: square(100), DistanceM: 800, AreaEfficiency: 0.30}
	res := selectLoops([]*Loop{flatter, rounder}, 800)
	if res.Best != rounder {
		t.Fatalf("expected the rounder in-band loop, got eff %.2f", res.Best.AreaEfficiency)
	}
}

func TestSelectLoopsNoneInBandPicksClosest(t *testing.T) {
	near := &Loop{Coords: []Coord{{0, 0}, {0, 1}, {1, 1}, {1, 0}}, DistanceM: 1300, AreaEfficiency: 0.5}
	far := &Loop{Coords: []Coord{{0, 0}, {0, 1}, {1, 1}, {1, 0}}, DistanceM: 2000, AreaEfficiency: 0.9}
	// Target 1000, band ±150 → neither in band; closest-to-target wins.
	res := selectLoops([]*Loop{far, near}, 1000)
	if res.Best != near {
		t.Fatalf("expected the closest-to-target loop (1300 m), got %.0f m", res.Best.DistanceM)
	}
	// Largest clean is the longer one regardless of selection.
	if res.LargestClean != far {
		t.Fatalf("largest clean = %.0f m, want 2000", res.LargestClean.DistanceM)
	}
}

func TestSelectLoopsAllSpurs(t *testing.T) {
	spur := &Loop{Coords: []Coord{{0, 0}, {0, 1}, {0, 0}}, DistanceM: 1000, AreaEfficiency: 0.01}
	res := selectLoops([]*Loop{spur}, 1000)
	if res.Best != nil || res.LargestClean != nil {
		t.Fatal("a field of spurs must select nothing")
	}
}
