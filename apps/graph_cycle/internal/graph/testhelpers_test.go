package graph

// gridGraph builds a rows×cols lattice of nodes spaced spacingM apart, with
// every node joined to its right and down neighbour. The result is a dense,
// loop-rich foot graph — the controlled stand-in for a regular city grid that
// lets the cycle search be tested without a PBF. Node (r,c) gets synthetic OSM
// id r*cols+c.
func gridGraph(rows, cols int, spacingM, originLat, originLng float64) *Graph {
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
	return b.finalize()
}

// lineGraph builds a straight chain of n nodes spaced spacingM apart — a
// deliberately loop-POOR graph (the only way back from any node is the way you
// came), used to assert the search reports loop-poor rather than inventing a
// spur.
func lineGraph(n int, spacingM, originLat, originLng float64) *Graph {
	b := newBuilder()
	dLng := metresToDegLng(spacingM, originLat)
	for i := 0; i < n; i++ {
		b.addNode(int64(i), Coord{Lat: originLat, Lng: originLng + float64(i)*dLng})
		if i > 0 {
			b.addSegment(int64(i-1), int64(i))
		}
	}
	return b.finalize()
}
