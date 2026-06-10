package graph

import "math"

// grid is a uniform lat/lng bucket index over the graph's nodes, used to answer
// NearestNode without scanning every node. Cells are ~gridCellM metres on a
// side; a query scans its own cell then expands ring by ring until it has a
// candidate and the ring can no longer hold anything closer.
type grid struct {
	cellLat float64 // cell height in degrees
	cellLng float64 // cell width in degrees (at the graph's mean latitude)
	minLat  float64
	minLng  float64
	cells   map[int64][]int32
}

// gridCellM is the target cell size. A few hundred metres keeps each bucket
// small in dense cities while bounding the ring count over sparse extracts.
const gridCellM = 200.0

func buildGrid(lat, lng []float64) *grid {
	if len(lat) == 0 {
		return &grid{cells: map[int64][]int32{}}
	}
	minLat, minLng := math.Inf(1), math.Inf(1)
	sumLat := 0.0
	for i := range lat {
		if lat[i] < minLat {
			minLat = lat[i]
		}
		if lng[i] < minLng {
			minLng = lng[i]
		}
		sumLat += lat[i]
	}
	meanLat := sumLat / float64(len(lat))
	g := &grid{
		cellLat: metresToDegLat(gridCellM),
		cellLng: metresToDegLng(gridCellM, meanLat),
		minLat:  minLat,
		minLng:  minLng,
		cells:   make(map[int64][]int32),
	}
	for i := range lat {
		key := g.cellKey(g.col(lng[i]), g.row(lat[i]))
		g.cells[key] = append(g.cells[key], int32(i))
	}
	return g
}

func (g *grid) row(lat float64) int32 { return int32(math.Floor((lat - g.minLat) / g.cellLat)) }
func (g *grid) col(lng float64) int32 { return int32(math.Floor((lng - g.minLng) / g.cellLng)) }
func (g *grid) cellKey(col, row int32) int64 {
	return int64(row)<<32 | int64(uint32(col))
}

// NearestNode returns the index of the graph node closest to (lat, lng) and
// whether the graph had any nodes at all. Ties resolve to the lower index.
func (g *Graph) NearestNode(lat, lng float64) (int32, bool) {
	if g.NumNodes() == 0 {
		return 0, false
	}
	gr := g.grid
	cr := gr.row(lat)
	cc := gr.col(lng)

	best := int32(-1)
	bestD := math.Inf(1)

	// Expand ring radius until we've found a candidate AND the inner edge of
	// the next ring is farther than the best candidate (so no closer node can
	// hide further out). Cell size in metres bounds that comparison.
	for ring := int32(0); ; ring++ {
		found := scanRing(gr, cc, cr, ring, func(idx int32) {
			d := haversineM(lat, lng, g.lat[idx], g.lng[idx])
			if d < bestD {
				bestD = d
				best = idx
			}
		})
		if best >= 0 {
			// Minimum possible distance to anything in ring+1.
			ringInnerM := float64(ring) * gridCellM
			if ringInnerM > bestD {
				break
			}
		}
		// Guard against an unbounded loop if the point is wildly off-graph:
		// once a ring covered the whole index extent and we still have a best,
		// stop. `found` is false when a ring touched no populated cells AND we
		// already have a candidate.
		if !found && best >= 0 && ring > 0 {
			break
		}
		if ring > 1<<20 { // pathological safety valve
			break
		}
	}
	return best, best >= 0
}

// scanRing visits every populated cell on the square ring at Chebyshev distance
// `ring` from (cc, cr), calling visit for each node. Returns whether any cell
// on the ring existed in the index (used to terminate over empty regions).
func scanRing(gr *grid, cc, cr, ring int32, visit func(int32)) bool {
	any := false
	visitCell := func(col, row int32) {
		if nodes, ok := gr.cells[gr.cellKey(col, row)]; ok {
			any = true
			for _, idx := range nodes {
				visit(idx)
			}
		}
	}
	if ring == 0 {
		visitCell(cc, cr)
		return any
	}
	for col := cc - ring; col <= cc+ring; col++ {
		visitCell(col, cr-ring)
		visitCell(col, cr+ring)
	}
	for row := cr - ring + 1; row <= cr+ring-1; row++ {
		visitCell(cc-ring, row)
		visitCell(cc+ring, row)
	}
	return any
}
