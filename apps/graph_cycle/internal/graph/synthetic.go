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
				b.addSegment(id(r, c), id(r, c+1))
			}
			if r+1 < rows {
				b.addSegment(id(r, c), id(r+1, c))
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
			b.addSegment(int64(i-1), int64(i))
		}
	}
	g := b.finalize()
	return g, Stats{Nodes: g.NumNodes(), Edges: g.NumEdges(), Ways: n - 1}
}
