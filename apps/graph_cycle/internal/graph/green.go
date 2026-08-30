package graph

import (
	"math"

	"github.com/paulmach/osm"
)

// greenWay decides whether a way delineates the green space the scenic
// preference is about. Only the tags with dependable OSM coverage are listed —
// a longer list marks more cells without making a route meaningfully greener.
func greenWay(tags osm.Tags) bool {
	if tags.Find("highway") != "" {
		return false
	}
	switch tags.Find("leisure") {
	case "park", "garden", "nature_reserve":
		return true
	}
	if tags.Find("natural") == "water" {
		return true
	}
	switch tags.Find("landuse") {
	case "forest", "grass", "recreation_ground":
		return true
	}
	return false
}

// greenFillMaxCells caps the scanline fill in fillRows. Rasterising a closed
// way's boundary alone leaves the MIDDLE of any park wider than a cell
// unmarked, so each closed way's rows are filled between its own extremes. That
// fill is convex per row, which over-marks a concave park's bays — the right
// direction to be wrong in, since the resulting weight is soft and merely makes
// a few extra edges cheap — but an unbounded fill would let one national-forest
// polygon blanket the whole extract. A way spanning more than this many cells
// (≈10 km) keeps its boundary raster only.
const greenFillMaxCells = 50

// greenGrid is a coarse occupancy raster of green space on the same gridCellM
// cell scheme the spatial index uses. It exists to answer one build-time
// question — is this edge's midpoint in or beside green space — and is dropped
// once the per-edge attribution is written, so it costs nothing at query time.
type greenGrid struct {
	cellLat, cellLng float64
	minLat, minLng   float64
	cells            map[int64]struct{}
}

func newGreenGrid(coords map[int64]Coord) *greenGrid {
	gg := &greenGrid{cells: make(map[int64]struct{})}
	if len(coords) == 0 {
		return gg
	}
	minLat, minLng := math.Inf(1), math.Inf(1)
	sumLat := 0.0
	for _, c := range coords {
		minLat = math.Min(minLat, c.Lat)
		minLng = math.Min(minLng, c.Lng)
		sumLat += c.Lat
	}
	meanLat := sumLat / float64(len(coords))
	gg.cellLat = metresToDegLat(gridCellM)
	gg.cellLng = metresToDegLng(gridCellM, meanLat)
	gg.minLat, gg.minLng = minLat, minLng
	return gg
}

func (gg *greenGrid) row(lat float64) int32 { return int32(math.Floor((lat - gg.minLat) / gg.cellLat)) }
func (gg *greenGrid) col(lng float64) int32 { return int32(math.Floor((lng - gg.minLng) / gg.cellLng)) }
func (gg *greenGrid) key(col, row int32) int64 {
	return int64(row)<<32 | int64(uint32(col))
}

// markWay rasterises one green way's geometry into the occupancy grid. `closed`
// comes from the way's node ids rather than its coordinates, so a polygon whose
// last node fell outside the extract is still recognised as an area.
func (gg *greenGrid) markWay(pts []Coord, closed bool) {
	// A grid built from no green geometry has a zero cell size; dividing by it
	// would put every point in the same NaN cell.
	if gg.cellLat == 0 || len(pts) < 2 {
		return
	}
	local := make(map[int64]struct{})
	for i := 1; i < len(pts); i++ {
		gg.rasterise(pts[i-1], pts[i], local)
	}
	if closed {
		gg.fillRows(local)
	}
	for k := range local {
		gg.cells[k] = struct{}{}
	}
}

// rasterise marks every cell a segment passes through, stepping at half a cell
// so a diagonal segment cannot hop a cell corner and leave a gap in the raster.
func (gg *greenGrid) rasterise(a, b Coord, into map[int64]struct{}) {
	dCol := absI32(gg.col(b.Lng) - gg.col(a.Lng))
	dRow := absI32(gg.row(b.Lat) - gg.row(a.Lat))
	steps := int(max(dCol, dRow)) * 2
	if steps < 1 {
		steps = 1
	}
	for s := 0; s <= steps; s++ {
		t := float64(s) / float64(steps)
		lat := a.Lat + (b.Lat-a.Lat)*t
		lng := a.Lng + (b.Lng-a.Lng)*t
		into[gg.key(gg.col(lng), gg.row(lat))] = struct{}{}
	}
}

// fillRows fills each raster row between that row's own extreme columns, so the
// interior of an area way counts as green and not just its boundary.
func (gg *greenGrid) fillRows(cells map[int64]struct{}) {
	type span struct{ lo, hi int32 }
	rows := make(map[int32]span)
	minRow, maxRow := int32(math.MaxInt32), int32(math.MinInt32)
	minCol, maxCol := int32(math.MaxInt32), int32(math.MinInt32)
	for k := range cells {
		row := int32(k >> 32)
		col := int32(uint32(k))
		if s, ok := rows[row]; ok {
			rows[row] = span{lo: min(s.lo, col), hi: max(s.hi, col)}
		} else {
			rows[row] = span{lo: col, hi: col}
		}
		minRow, maxRow = min(minRow, row), max(maxRow, row)
		minCol, maxCol = min(minCol, col), max(maxCol, col)
	}
	if maxRow-minRow > greenFillMaxCells || maxCol-minCol > greenFillMaxCells {
		return
	}
	for row, s := range rows {
		for col := s.lo; col <= s.hi; col++ {
			cells[gg.key(col, row)] = struct{}{}
		}
	}
}

func (gg *greenGrid) contains(lat, lng float64) bool {
	if len(gg.cells) == 0 {
		return false
	}
	_, ok := gg.cells[gg.key(gg.col(lng), gg.row(lat))]
	return ok
}
