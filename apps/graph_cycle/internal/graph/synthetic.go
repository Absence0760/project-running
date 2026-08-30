package graph

// Synthetic graph constructors. These build deterministic toy foot graphs
// without a PBF — used by the unit tests across packages and handy for a local
// smoke of the HTTP server when no extract is loaded. They're cheap and pure;
// keeping them in the package (rather than a _test.go file) lets the api
// package's tests build a graph without depending on a fixture PBF.

// BuildTestGrid builds a rows×cols lattice spaced spacingM metres apart, every
// node joined to its right and down neighbour — a dense, loop-rich grid.
func BuildTestGrid(rows, cols int, spacingM, originLat, originLng float64) (*Graph, Stats) {
	b := newBuilder()
	dLat := metresToDegLat(spacingM)
	dLng := metresToDegLng(spacingM, originLat)
	id := func(r, c int) int64 { return int64(r*cols + c) }
	for r := 0; r < rows; r++ {
		for c := 0; c < cols; c++ {
			b.addNode(id(r, c), Coord{
				Lat: originLat + float64(r)*dLat,
				Lng: originLng + float64(c)*dLng,
			})
		}
	}
	for r := 0; r < rows; r++ {
		for c := 0; c < cols; c++ {
			if c+1 < cols {
				b.addSegment(id(r, c), id(r, c+1), classResidential)
			}
			if r+1 < rows {
				b.addSegment(id(r, c), id(r+1, c), classResidential)
			}
		}
	}
	g := b.finalize()
	return g, Stats{Nodes: g.NumNodes(), Edges: g.NumEdges(), Ways: rows*(cols-1) + (rows-1)*cols}
}

// BuildTestLine builds a straight chain of n nodes — a loop-POOR graph (the only
// way home is back the way you came).
func BuildTestLine(n int, spacingM, originLat, originLng float64) (*Graph, Stats) {
	b := newBuilder()
	dLng := metresToDegLng(spacingM, originLat)
	for i := 0; i < n; i++ {
		b.addNode(int64(i), Coord{Lat: originLat, Lng: originLng + float64(i)*dLng})
		if i > 0 {
			b.addSegment(int64(i-1), int64(i), classResidential)
		}
	}
	g := b.finalize()
	return g, Stats{Nodes: g.NumNodes(), Edges: g.NumEdges(), Ways: n - 1}
}

// BuildTestSplitGrid builds the same lattice as BuildTestGrid, but every
// segment lying wholly in the EASTERN half is attributed foot-first and green
// while the west is arterial — so a preference-weighted search has a
// measurably better half of the map to prefer, and an unweighted one has no
// reason to favour either.
func BuildTestSplitGrid(rows, cols int, spacingM, originLat, originLng float64) (*Graph, Stats) {
	b := newBuilder()
	dLat := metresToDegLat(spacingM)
	dLng := metresToDegLng(spacingM, originLat)
	id := func(r, c int) int64 { return int64(r*cols + c) }
	attrFor := func(c1, c2 int) uint8 {
		if c1 >= cols/2 && c2 >= cols/2 {
			return classFootFirst | attrGreen
		}
		return classArterial
	}
	for r := 0; r < rows; r++ {
		for c := 0; c < cols; c++ {
			b.addNode(id(r, c), Coord{
				Lat: originLat + float64(r)*dLat,
				Lng: originLng + float64(c)*dLng,
			})
		}
	}
	for r := 0; r < rows; r++ {
		for c := 0; c < cols; c++ {
			if c+1 < cols {
				b.addSegment(id(r, c), id(r, c+1), attrFor(c, c+1))
			}
			if r+1 < rows {
				b.addSegment(id(r, c), id(r+1, c), attrFor(c, c))
			}
		}
	}
	g := b.finalize()
	return g, Stats{Nodes: g.NumNodes(), Edges: g.NumEdges(), Ways: rows*(cols-1) + (rows-1)*cols}
}

// BuildTestStubGrid builds the BuildTestGrid lattice plus one degree-1 dead end
// hanging north-west off every lattice node, at stubFrac of the lattice spacing
// — the cul-de-sac fixture. Every node therefore has a short quiet spur
// available, which is what lets a loop be augmented wherever it happens to run.
func BuildTestStubGrid(rows, cols int, spacingM, originLat, originLng, stubFrac float64) (*Graph, Stats) {
	b := newBuilder()
	dLat := metresToDegLat(spacingM)
	dLng := metresToDegLng(spacingM, originLat)
	id := func(r, c int) int64 { return int64(r*cols + c) }
	stubID := func(r, c int) int64 { return int64(rows*cols + r*cols + c) }
	for r := 0; r < rows; r++ {
		for c := 0; c < cols; c++ {
			lat := originLat + float64(r)*dLat
			lng := originLng + float64(c)*dLng
			b.addNode(id(r, c), Coord{Lat: lat, Lng: lng})
			b.addNode(stubID(r, c), Coord{Lat: lat + stubFrac*dLat, Lng: lng - stubFrac*dLng})
		}
	}
	for r := 0; r < rows; r++ {
		for c := 0; c < cols; c++ {
			if c+1 < cols {
				b.addSegment(id(r, c), id(r, c+1), classResidential)
			}
			if r+1 < rows {
				b.addSegment(id(r, c), id(r+1, c), classResidential)
			}
			b.addSegment(id(r, c), stubID(r, c), classResidential)
		}
	}
	g := b.finalize()
	return g, Stats{Nodes: g.NumNodes(), Edges: g.NumEdges(), Ways: rows*(cols-1) + (rows-1)*cols + rows*cols}
}
