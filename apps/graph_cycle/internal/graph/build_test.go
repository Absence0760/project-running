package graph

import (
	"math"
	"testing"

	"github.com/paulmach/osm"
)

func tags(kv ...string) osm.Tags {
	var t osm.Tags
	for i := 0; i+1 < len(kv); i += 2 {
		t = append(t, osm.Tag{Key: kv[i], Value: kv[i+1]})
	}
	return t
}

func TestFootAllowed(t *testing.T) {
	cases := []struct {
		name string
		tags osm.Tags
		want bool
	}{
		{"residential", tags("highway", "residential"), true},
		{"footway", tags("highway", "footway"), true},
		{"path", tags("highway", "path"), true},
		{"motorway excluded", tags("highway", "motorway"), false},
		{"trunk excluded", tags("highway", "trunk"), false},
		{"no highway", tags("building", "yes"), false},
		{"foot=no on residential", tags("highway", "residential", "foot", "no"), false},
		{"foot=yes on trunk overrides", tags("highway", "trunk", "foot", "yes"), true},
		{"access=private", tags("highway", "service", "access", "private"), false},
		{"foot=designated wins over access=private", tags("highway", "path", "access", "private", "foot", "designated"), true},
		{"unknown highway value", tags("highway", "elevator"), false},
		// construction/proposed are absent from OSRM foot.lua entirely — a
		// pedestrian-detour foot=yes must NOT route through them.
		{"construction with foot=yes still excluded", tags("highway", "construction", "foot", "yes"), false},
		{"proposed with foot=designated still excluded", tags("highway", "proposed", "foot", "designated"), false},
	}
	for _, c := range cases {
		if got := footAllowed(c.tags); got != c.want {
			t.Errorf("%s: footAllowed = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestBuilderDedupAndCSR(t *testing.T) {
	// A 3-node triangle, with one segment added twice (both orientations) to
	// prove dedup. Expect 3 nodes, 3 undirected segments → 6 directed edges.
	b := newBuilder()
	b.addNode(1, Coord{Lat: 0, Lng: 0})
	b.addNode(2, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b.addNode(3, Coord{Lat: metresToDegLat(100), Lng: 0})
	b.addSegment(1, 2)
	b.addSegment(2, 1) // duplicate (reverse) — should be ignored
	b.addSegment(2, 3)
	b.addSegment(3, 1)
	b.addSegment(1, 1) // self-loop — ignored
	g := b.finalize()

	if g.NumNodes() != 3 {
		t.Fatalf("nodes = %d, want 3", g.NumNodes())
	}
	if g.NumEdges() != 6 {
		t.Fatalf("directed edges = %d, want 6 (3 undirected × 2)", g.NumEdges())
	}
	// Every node should have degree ≥ 1 and CSR ranges must be well-formed.
	for i := int32(0); i < int32(g.NumNodes()); i++ {
		if g.edgeHead[i] > g.edgeHead[i+1] {
			t.Fatalf("CSR head not monotonic at %d", i)
		}
	}
}

func TestNearestNode(t *testing.T) {
	g := gridGraph(5, 5, 100, 40.0, -77.0)
	// Query a point a few metres off node (2,2).
	id := int64(2*5 + 2)
	want := g // capture
	wantIdx, ok := want.NearestNode(40.0+2*metresToDegLat(100)+metresToDegLat(3), -77.0+2*metresToDegLng(100, 40))
	if !ok {
		t.Fatal("NearestNode found nothing")
	}
	// The builder assigned dense indices in insertion order = grid scan order,
	// so node (2,2)'s dense index equals its synthetic id here.
	if int64(wantIdx) != id {
		t.Fatalf("nearest idx = %d, want %d", wantIdx, id)
	}
}

func TestNearestNodeEmpty(t *testing.T) {
	g := newBuilder().finalize()
	if _, ok := g.NearestNode(0, 0); ok {
		t.Fatal("empty graph should report no nearest node")
	}
}

// TestNearestNodeMatchesBruteForceHighLat pins the ring-termination invariant
// that broke at latitudes far from the graph mean. Southern anchor nodes drag
// meanLat well below a northern query cluster, so the grid's cellLng (sized at
// meanLat) is metres-wider than a cell at the query latitude — the exact
// condition under which the old flat-gridCellM inner-edge estimate terminated
// early and returned a node that wasn't actually nearest. NearestNode must match
// a brute-force scan at every query point.
func TestNearestNodeMatchesBruteForceHighLat(t *testing.T) {
	b := newBuilder()
	// Southern anchors: pull meanLat far below the northern cluster.
	for i := 0; i < 200; i++ {
		b.addNode(int64(100000+i), Coord{Lat: 0, Lng: float64(i) * 0.0005})
	}
	// Northern cluster at 60°N, ~120 m grid, several columns so a query between
	// columns has a non-trivial nearest.
	var k int64
	for r := 0; r < 8; r++ {
		for c := 0; c < 8; c++ {
			b.addNode(k, Coord{
				Lat: 60.0 + float64(r)*metresToDegLat(120),
				Lng: -1.0 + float64(c)*metresToDegLng(120, 60),
			})
			k++
		}
	}
	g := b.finalize()

	bruteNearestDist := func(qLat, qLng float64) float64 {
		best := math.Inf(1)
		for i := int32(0); i < int32(g.NumNodes()); i++ {
			if d := haversineM(qLat, qLng, g.lat[i], g.lng[i]); d < best {
				best = d
			}
		}
		return best
	}

	for qi := 0; qi < 7; qi++ {
		for qj := 0; qj < 7; qj++ {
			qLat := 60.0 + (float64(qi)+0.5)*metresToDegLat(120)
			qLng := -1.0 + (float64(qj)+0.5)*metresToDegLng(120, 60)
			got, ok := g.NearestNode(qLat, qLng)
			if !ok {
				t.Fatalf("query (%.5f,%.5f): no nearest", qLat, qLng)
			}
			gotD := haversineM(qLat, qLng, g.lat[got], g.lng[got])
			// Compare by distance, not index, so ties are acceptable.
			if math.Abs(gotD-bruteNearestDist(qLat, qLng)) > 1e-6 {
				t.Fatalf("query (%.5f,%.5f): NearestNode dist %.4f != brute-force %.4f",
					qLat, qLng, gotD, bruteNearestDist(qLat, qLng))
			}
		}
	}
}
