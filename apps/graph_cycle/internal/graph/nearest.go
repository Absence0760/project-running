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
	// Bounding box of the POPULATED cells, in cell coordinates. NearestNode
	// bounds its ring expansion to this box at both ends, which is what keeps
	// an off-extract query cheap and the loop terminating.
	minCol, maxCol int32
	minRow, maxRow int32
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
		col, row := g.col(lng[i]), g.row(lat[i])
		if i == 0 {
			g.minCol, g.maxCol, g.minRow, g.maxRow = col, col, row, row
		} else {
			g.minCol = min(g.minCol, col)
			g.maxCol = max(g.maxCol, col)
			g.minRow = min(g.minRow, row)
			g.maxRow = max(g.maxRow, row)
		}
		key := g.cellKey(col, row)
		g.cells[key] = append(g.cells[key], int32(i))
	}
	return g
}

// ringToExtent is the smallest ring radius around (cc, cr) that can hold a
// populated cell: the Chebyshev distance from the query cell to the populated
// bounding box, or 0 when the query sits inside it. Every smaller ring lies
// wholly outside the box and is therefore guaranteed empty.
func (g *grid) ringToExtent(cc, cr int32) int32 {
	dCol := int32(0)
	switch {
	case cc < g.minCol:
		dCol = g.minCol - cc
	case cc > g.maxCol:
		dCol = cc - g.maxCol
	}
	dRow := int32(0)
	switch {
	case cr < g.minRow:
		dRow = g.minRow - cr
	case cr > g.maxRow:
		dRow = cr - g.maxRow
	}
	return max(dCol, dRow)
}

// ringPastExtent is the largest ring radius around (cc, cr) that can still hold
// a populated cell — the Chebyshev distance to the farthest corner of the
// populated bounding box. Every larger ring is guaranteed empty, so the search
// is complete once it has been scanned.
func (g *grid) ringPastExtent(cc, cr int32) int32 {
	col := max(absI32(cc-g.minCol), absI32(cc-g.maxCol))
	row := max(absI32(cr-g.minRow), absI32(cr-g.maxRow))
	return max(col, row)
}

func absI32(v int32) int32 {
	if v < 0 {
		return -v
	}
	return v
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
	//
	// Both ends of the sweep are pinned to the index's populated extent. The
	// first ring skips the empty rings between an off-extract query and the
	// data — walking those is quadratic in the distance, so a start point
	// outside the loaded PBF used to pin a core for minutes. The last ring is
	// what terminates the loop; the previous rule ("this ring was empty, so
	// stop") is unsound on a sparse network, where an empty ring can sit
	// between the current best and a strictly closer node further out.
	for ring, last := gr.ringToExtent(cc, cr), gr.ringPastExtent(cc, cr); ring <= last; ring++ {
		scanRing(gr, cc, cr, ring, func(idx int32) {
			d := haversineM(lat, lng, g.lat[idx], g.lng[idx])
			if d < bestD {
				bestD = d
				best = idx
			}
		})
		if best >= 0 {
			// Minimum possible distance to anything in ring+1, in TRUE metres.
			// The latitude cell is latitude-independent (cellLat·mPerDegLat ==
			// gridCellM), but the longitude cell was sized at the graph's MEAN
			// latitude — so at a query latitude away from the mean a column is a
			// different number of metres wide. Using a flat gridCellM here would
			// over-estimate the lng inner edge above the mean latitude and break
			// early, missing a closer node one column out (a wrong-node bug on a
			// country-scale extract). Take the smaller of the two real edges.
			latEdgeM := float64(ring) * gr.cellLat * mPerDegLat
			lngEdgeM := float64(ring) * gr.cellLng * mPerDegLat * math.Cos(lat*math.Pi/180)
			if math.Min(latEdgeM, lngEdgeM) > bestD {
				break
			}
		}
	}
	return best, best >= 0
}

// scanRing visits every populated cell on the square ring at Chebyshev distance
// `ring` from (cc, cr), calling visit for each node. The walk is clipped to the
// populated bounding box, so a distant ring costs the box's width/height rather
// than the ring's own perimeter — without that clip a far-off query would pay
// O(ring) per ring even though every cell outside the box is empty by
// construction.
func scanRing(gr *grid, cc, cr, ring int32, visit func(int32)) {
	visitCell := func(col, row int32) {
		if row < gr.minRow || row > gr.maxRow || col < gr.minCol || col > gr.maxCol {
			return
		}
		for _, idx := range gr.cells[gr.cellKey(col, row)] {
			visit(idx)
		}
	}
	if ring == 0 {
		visitCell(cc, cr)
		return
	}
	for col := max(cc-ring, gr.minCol); col <= min(cc+ring, gr.maxCol); col++ {
		visitCell(col, cr-ring)
		visitCell(col, cr+ring)
	}
	for row := max(cr-ring+1, gr.minRow); row <= min(cr+ring-1, gr.maxRow); row++ {
		visitCell(cc-ring, row)
		visitCell(cc+ring, row)
	}
}
