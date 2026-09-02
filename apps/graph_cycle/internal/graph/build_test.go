package graph

import (
	"math"
	"math/rand"
	"testing"
	"time"

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

func TestRoleForWay(t *testing.T) {
	// The seam between the tag helpers and the graph: which of the two piles a
	// way lands in, and — the part nothing else pins — that a kept way carries
	// its own road class rather than the residential zero value.
	for _, c := range []struct {
		name string
		tags osm.Tags
		want wayRole
	}{
		{"park polygon", tags("leisure", "park"), wayRole{green: true}},
		{"forest polygon", tags("landuse", "forest"), wayRole{green: true}},
		{"lake", tags("natural", "water"), wayRole{green: true}},
		{"residential street", tags("highway", "residential"), wayRole{kept: true, class: classResidential}},
		{"service road", tags("highway", "service"), wayRole{kept: true, class: classResidential}},
		{"secondary road", tags("highway", "secondary"), wayRole{kept: true, class: classArterial}},
		{"tertiary link", tags("highway", "tertiary_link"), wayRole{kept: true, class: classArterial}},
		{"footway", tags("highway", "footway"), wayRole{kept: true, class: classFootFirst}},
		{"steps", tags("highway", "steps"), wayRole{kept: true, class: classFootFirst}},
		// foot=yes buys a trunk into the graph, but not out of its class: the
		// quiet preference exists to steer off exactly this road.
		{"trunk with foot=yes", tags("highway", "trunk", "foot", "yes"), wayRole{kept: true, class: classArterial}},
		// A footpath through a park is an edge, not a polygon — it earns green
		// from the raster, and dropping it into the green pile would delete it
		// from the routable network.
		{"footpath tagged park", tags("highway", "footway", "leisure", "park"), wayRole{kept: true, class: classFootFirst}},
		{"building", tags("building", "yes"), wayRole{}},
		{"motorway", tags("highway", "motorway"), wayRole{}},
	} {
		if got := roleForWay(c.tags); got != c.want {
			t.Errorf("%s: roleForWay = %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestAssembleAttributesEachSegment(t *testing.T) {
	// A 600 m park, one footpath crossing it, and one secondary road that only
	// clips its western edge. Both ways run west to east along the same
	// latitudes, so the difference in what each segment carries is entirely the
	// midpoint lookup and the way's own class.
	const lat, lng = 40.0, -77.0
	park := squareWay(lat, lng, 600)
	greenCoords := map[int64]Coord{}
	for i, c := range park {
		greenCoords[int64(100+i)] = c
	}
	gg := newGreenGrid(greenCoords)
	gg.markWay(park, true)

	dLng := metresToDegLng(300, lat)
	insideLat := lat + metresToDegLat(300)
	outsideLat := lat + metresToDegLat(3000)
	coords := map[int64]Coord{
		1: {Lat: insideLat, Lng: lng},
		2: {Lat: insideLat, Lng: lng + dLng},
		3: {Lat: outsideLat, Lng: lng},
		4: {Lat: outsideLat, Lng: lng + dLng},
	}
	g := assemble([]footWay{
		{nodes: []int64{1, 2}, class: classFootFirst},
		{nodes: []int64{3, 4}, class: classArterial},
	}, coords, gg)

	through, ok := g.attrBetween(0, 1)
	if !ok {
		t.Fatal("the park footpath is missing from the graph")
	}
	if through != classFootFirst|attrGreen {
		t.Errorf("footpath through the park = %#b, want foot-first + green", through)
	}
	away, ok := g.attrBetween(2, 3)
	if !ok {
		t.Fatal("the road outside the park is missing from the graph")
	}
	if away != classArterial {
		t.Errorf("road 3 km from the park = %#b, want arterial and not green", away)
	}
}

func TestAssembleBreaksAWayAtAMissingNode(t *testing.T) {
	// The second pass keeps coordinates only for referenced nodes, and a way can
	// still name one the extract cut off. The chain must break there rather than
	// join across the hole and invent a segment kilometres long.
	coords := map[int64]Coord{
		1: {Lat: 40.0, Lng: -77.0},
		3: {Lat: 40.0, Lng: -77.0 + metresToDegLng(2000, 40.0)},
	}
	g := assemble([]footWay{{nodes: []int64{1, 2, 3}, class: classResidential}}, coords, newGreenGrid(nil))
	if g.NumNodes() != 2 {
		t.Fatalf("nodes = %d, want the two the extract had coordinates for", g.NumNodes())
	}
	if g.NumEdges() != 0 {
		t.Fatalf("edges = %d, want none — the way's two ends are not adjacent", g.NumEdges())
	}
}

func TestBuilderDedupAndCSR(t *testing.T) {
	// A 3-node triangle, with one segment added twice (both orientations) to
	// prove dedup. Expect 3 nodes, 3 undirected segments → 6 directed edges.
	b := newBuilder()
	b.addNode(1, Coord{Lat: 0, Lng: 0})
	b.addNode(2, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b.addNode(3, Coord{Lat: metresToDegLat(100), Lng: 0})
	b.addSegment(1, 2, classResidential)
	b.addSegment(2, 1, classResidential) // duplicate (reverse) — should be ignored
	b.addSegment(2, 3, classResidential)
	b.addSegment(3, 1, classResidential)
	b.addSegment(1, 1, classResidential) // self-loop — ignored
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

// TestNearestNodeMatchesBruteForceSparseNetwork pins the ring-termination
// invariant on a SPARSE network, where cells the width of gridCellM are mostly
// empty. The ring sweep used to stop at the first ring that touched no
// populated cell once it already held a candidate — but on a sparse graph an
// empty ring routinely sits between the current best and a strictly closer node
// further out, so that rule returned the wrong snap node (hundreds of metres
// wrong, ~0.7% of queries over this generator). Every query must agree with a
// brute-force scan.
func TestNearestNodeMatchesBruteForceSparseNetwork(t *testing.T) {
	rng := rand.New(rand.NewSource(7))
	for trial := 0; trial < 300; trial++ {
		b := newBuilder()
		n := 3 + rng.Intn(12)
		for i := 0; i < n; i++ {
			b.addNode(int64(i), Coord{
				Lat: 51.5 + metresToDegLat(rng.Float64()*4000),
				Lng: -0.12 + metresToDegLng(rng.Float64()*4000, 51.5),
			})
		}
		for i := 1; i < n; i++ {
			b.addSegment(int64(i-1), int64(i), classResidential)
		}
		g := b.finalize()

		for q := 0; q < 40; q++ {
			qLat := 51.5 + metresToDegLat(rng.Float64()*4000)
			qLng := -0.12 + metresToDegLng(rng.Float64()*4000, 51.5)
			got, ok := g.NearestNode(qLat, qLng)
			if !ok {
				t.Fatalf("trial %d query %d: no nearest on a %d-node graph", trial, q, n)
			}
			want := math.Inf(1)
			for i := range g.lat {
				if d := haversineM(qLat, qLng, g.lat[i], g.lng[i]); d < want {
					want = d
				}
			}
			gotD := haversineM(qLat, qLng, g.lat[got], g.lng[got])
			if gotD > want+1e-6 {
				t.Fatalf("trial %d query %d: NearestNode dist %.1f m != brute-force %.1f m",
					trial, q, gotD, want)
			}
		}
	}
}

// TestNearestNodeOffExtractStaysBounded pins the cost of a query far outside the
// loaded extract — a runner whose start point is in a region the PBF doesn't
// cover. The sweep must skip straight to the extract instead of walking every
// 200 m ring in between: that walk is quadratic in the distance, so a
// continental-scale offset used to spin for minutes inside a request handler
// whose WriteTimeout is 30 s, with no cancellation.
func TestNearestNodeOffExtractStaysBounded(t *testing.T) {
	g := gridGraph(20, 20, 100, 51.5, -0.12)
	gr := g.grid

	// ~4000 km north of the extract.
	qLat, qLng := 51.5+metresToDegLat(4_000_000), -0.12
	cr, cc := gr.row(qLat), gr.col(qLng)

	first := gr.ringToExtent(cc, cr)
	last := gr.ringPastExtent(cc, cr)
	if first < 10_000 {
		t.Fatalf("expected the query to sit far outside the extract, first ring = %d", first)
	}
	// The number of rings that can hold data is the extract's own span, not the
	// distance to it. 20x20 nodes at 100 m spacing spans ~2 km = ~10 cells.
	if span := last - first; span > 64 {
		t.Fatalf("ring window spans %d rings; expected it bounded by the extract extent", span)
	}

	start := time.Now()
	got, ok := g.NearestNode(qLat, qLng)
	elapsed := time.Since(start)
	if !ok {
		t.Fatal("NearestNode found nothing for an off-extract query")
	}
	if elapsed > 2*time.Second {
		t.Fatalf("off-extract query took %s; the ring sweep is not bounded by the extract", elapsed)
	}
	// The northernmost row of the grid is nearest; every node in it is equidistant
	// in latitude, so only assert we snapped into that row.
	wantLat := 51.5 + 19*metresToDegLat(100)
	if math.Abs(g.lat[got]-wantLat) > 1e-9 {
		t.Fatalf("snapped to lat %.6f, want the extract's northern edge %.6f", g.lat[got], wantLat)
	}
}

// A non-finite query is not a wrong answer, it is an unbounded sweep:
// haversineM returns NaN so no candidate ever wins, the early break can never
// fire, and the ring range comes from an int32 conversion of NaN. Measured at
// 33 s on this 9x9 grid before the guard existed. Both /cycle and /nearest
// validate their inputs, but NearestNode is exported and must not depend on
// every caller remembering to.
func TestNearestNodeRefusesANonFiniteQuery(t *testing.T) {
	g, _ := BuildTestGrid(9, 9, 100, 40.0, -77.0)
	nan := math.NaN()
	inf := math.Inf(1)
	for _, c := range []struct {
		name     string
		lat, lng float64
	}{
		{"nan lat", nan, -77.0},
		{"nan lng", 40.0, nan},
		{"+inf lat", inf, -77.0},
		{"-inf lng", 40.0, math.Inf(-1)},
	} {
		done := make(chan struct{})
		var ok bool
		go func() {
			defer close(done)
			_, ok = g.NearestNode(c.lat, c.lng)
		}()
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			t.Fatalf("%s: NearestNode did not return within 2 s", c.name)
		}
		if ok {
			t.Errorf("%s: found a node for a non-finite query", c.name)
		}
	}

	// A finite query on the same grid still resolves, so the guard is not
	// refusing everything.
	if _, ok := g.NearestNode(40.0, -77.0); !ok {
		t.Fatal("a finite query stopped resolving")
	}
}
