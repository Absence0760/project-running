package graph

import (
	"math"
	"testing"
)

func TestShortestPathGrid(t *testing.T) {
	// 5×5 grid, 100 m spacing. Corner (0,0) to opposite corner (4,4): the
	// Manhattan distance is 8 hops × 100 m = 800 m.
	g := gridGraph(5, 5, 100, 40.0, -77.0)
	coords, dist, ok := g.ShortestPath(40.0, -77.0,
		40.0+4*metresToDegLat(100), -77.0+4*metresToDegLng(100, 40))
	if !ok {
		t.Fatal("no path corner-to-corner")
	}
	if math.Abs(dist-800) > 20 {
		t.Fatalf("path length = %.0f m, want ~800", dist)
	}
	if len(coords) < 2 {
		t.Fatalf("path has %d coords", len(coords))
	}
}

func TestDijkstraRadiusCap(t *testing.T) {
	g := gridGraph(10, 10, 100, 40.0, -77.0)
	src, _ := g.NearestNode(40.0, -77.0)
	// Cap at 250 m: only nodes within ~2 hops should be reached.
	distTo, _ := g.dijkstra(src, -1, 250, nil)
	for _, d := range distTo {
		if d > 250+1e-6 {
			t.Fatalf("reached a node at %.0f m beyond the 250 m cap", d)
		}
	}
	// And it should have reached at least the immediate neighbours.
	if len(distTo) < 4 {
		t.Fatalf("only %d nodes within 250 m, expected more", len(distTo))
	}
}

func TestDijkstraPenaltyReroutes(t *testing.T) {
	// Two parallel routes from A to B of equal hop length should let a penalty
	// on the direct route push the search onto the alternative. Build a tiny
	// graph: 0—1—2 (top) and 0—3—2 (bottom), all 100 m edges.
	b := newBuilder()
	b.addNode(0, Coord{Lat: 0, Lng: 0})
	b.addNode(1, Coord{Lat: metresToDegLat(100), Lng: 0})
	b.addNode(2, Coord{Lat: 2 * metresToDegLat(100), Lng: 0})
	b.addNode(3, Coord{Lat: metresToDegLat(100), Lng: metresToDegLng(100, 0)})
	b.addSegment(0, 1)
	b.addSegment(1, 2)
	b.addSegment(0, 3)
	b.addSegment(3, 2)
	g := b.finalize()

	// Unpenalised: either equal-length route is fine; assert reachable.
	_, prev := g.dijkstra(0, 2, math.Inf(1), nil)
	if reconstruct(prev, 0, 2) == nil {
		t.Fatal("no path 0→2")
	}

	// Penalise the top route (edges 0-1 and 1-2). The bottom route must win.
	penalised := map[uint64]struct{}{edgeKey(0, 1): {}, edgeKey(1, 2): {}}
	_, prev2 := g.dijkstra(0, 2, math.Inf(1), penalised)
	path := reconstruct(prev2, 0, 2)
	if path == nil {
		t.Fatal("penalised search found no path")
	}
	// Path should route through node 3 (the bottom), not node 1.
	via3 := false
	for _, n := range path {
		if n == 3 {
			via3 = true
		}
	}
	if !via3 {
		t.Fatalf("penalised path %v did not avoid the penalised top route", path)
	}
}

func TestReconstructUnreachable(t *testing.T) {
	prev := map[int32]int32{0: -1}
	if p := reconstruct(prev, 0, 9); p != nil {
		t.Fatalf("reconstruct to unreached node = %v, want nil", p)
	}
}
