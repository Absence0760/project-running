package graph

import "testing"

func TestGreenWay(t *testing.T) {
	for _, c := range []struct {
		name string
		want bool
		t    []string
	}{
		{"park", true, []string{"leisure", "park"}},
		{"garden", true, []string{"leisure", "garden"}},
		{"nature reserve", true, []string{"leisure", "nature_reserve"}},
		{"water", true, []string{"natural", "water"}},
		{"forest", true, []string{"landuse", "forest"}},
		{"grass", true, []string{"landuse", "grass"}},
		{"recreation ground", true, []string{"landuse", "recreation_ground"}},
		{"residential landuse", false, []string{"landuse", "residential"}},
		{"untagged", false, nil},
		// A footpath THROUGH a park is a graph edge, not a green polygon — it
		// earns its green flag from the occupancy grid like any other edge.
		{"path tagged park", false, []string{"highway", "footway", "leisure", "park"}},
	} {
		if got := greenWay(tags(c.t...)); got != c.want {
			t.Errorf("%s: greenWay = %v, want %v", c.name, got, c.want)
		}
	}
}

// squareWay returns a closed way of `sideM` metres around (lat, lng).
func squareWay(lat, lng, sideM float64) []Coord {
	dLat := metresToDegLat(sideM)
	dLng := metresToDegLng(sideM, lat)
	return []Coord{
		{Lat: lat, Lng: lng},
		{Lat: lat, Lng: lng + dLng},
		{Lat: lat + dLat, Lng: lng + dLng},
		{Lat: lat + dLat, Lng: lng},
		{Lat: lat, Lng: lng},
	}
}

func TestGreenGridFillsClosedInterior(t *testing.T) {
	pts := squareWay(40.0, -77.0, 1000)
	coords := map[int64]Coord{}
	for i, c := range pts {
		coords[int64(i)] = c
	}
	gg := newGreenGrid(coords)
	gg.markWay(pts, true)

	midLat := 40.0 + metresToDegLat(500)
	midLng := -77.0 + metresToDegLng(500, 40.0)
	if !gg.contains(midLat, midLng) {
		t.Fatal("the middle of a 1 km park must be green; boundary rasterising alone would miss it")
	}
	if !gg.contains(40.0, -77.0) {
		t.Fatal("a park corner must be green")
	}
	if gg.contains(40.0+metresToDegLat(5000), -77.0) {
		t.Fatal("a point 5 km away must not be green")
	}
}

func TestGreenGridSkipsFillOnAnOversizeWay(t *testing.T) {
	// 20 km on a side — past greenFillMaxCells (50 × 200 m). The boundary is
	// still marked, but the interior must not be, or one forest polygon would
	// make an entire region scenic.
	pts := squareWay(40.0, -77.0, 20000)
	coords := map[int64]Coord{}
	for i, c := range pts {
		coords[int64(i)] = c
	}
	gg := newGreenGrid(coords)
	gg.markWay(pts, true)

	if !gg.contains(40.0, -77.0) {
		t.Fatal("the boundary of an oversize way is still green")
	}
	midLat := 40.0 + metresToDegLat(10000)
	midLng := -77.0 + metresToDegLng(10000, 40.0)
	if gg.contains(midLat, midLng) {
		t.Fatal("the interior of an oversize way must be left unfilled")
	}
}

func TestGreenGridOpenWayIsNotFilled(t *testing.T) {
	// An open way (a river centreline, a hedge) has no interior to fill: only
	// the cells it runs through are green.
	dLng := metresToDegLng(1000, 40.0)
	pts := []Coord{{Lat: 40.0, Lng: -77.0}, {Lat: 40.0, Lng: -77.0 + dLng}}
	coords := map[int64]Coord{0: pts[0], 1: pts[1]}
	gg := newGreenGrid(coords)
	gg.markWay(pts, false)

	if !gg.contains(40.0, -77.0+dLng/2) {
		t.Fatal("a point on the line must be green")
	}
	if gg.contains(40.0+metresToDegLat(1000), -77.0+dLng/2) {
		t.Fatal("a point 1 km off an open way must not be green")
	}
}

func TestGreenGridEmptyIsNeverGreen(t *testing.T) {
	gg := newGreenGrid(nil)
	gg.markWay(squareWay(40.0, -77.0, 1000), true)
	if gg.contains(40.0, -77.0) {
		t.Fatal("a grid built from no green geometry must report nothing green")
	}
}
