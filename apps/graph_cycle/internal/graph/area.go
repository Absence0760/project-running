package graph

import "math"

// Coord is a single geographic point in GeoJSON [lng, lat] order, matching the
// route builder's wire format so the web client renders a returned cycle
// without conversion.
type Coord struct {
	Lng float64
	Lat float64
}

const mPerDegLat = 111320.0

// haversineM is the great-circle distance between two points in metres. Used
// for edge lengths at graph-build time and to re-measure a cycle's true length
// from its geometry (Dijkstra distances may be penalised, so they can't be
// trusted as real metres — see cycle.go).
func haversineM(aLat, aLng, bLat, bLng float64) float64 {
	const r = 6371000.0
	dLat := (bLat - aLat) * math.Pi / 180
	dLng := (bLng - aLng) * math.Pi / 180
	lat1 := aLat * math.Pi / 180
	lat2 := bLat * math.Pi / 180
	h := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1)*math.Cos(lat2)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * r * math.Asin(math.Min(1, math.Sqrt(h)))
}

// enclosedAreaM2 is the signed-area magnitude of a closed polyline in m², via
// the shoelace formula on a local equirectangular projection (metres around
// the first vertex's latitude). Open polylines are treated as implicitly
// closed. Direct port of select.ts#enclosedAreaM2 so the sidecar's shape score
// matches the web selector's exactly.
func enclosedAreaM2(coords []Coord) float64 {
	if len(coords) < 4 {
		return 0
	}
	lat0 := coords[0].Lat
	mPerDegLng := mPerDegLat * math.Cos(lat0*math.Pi/180)
	area := 0.0
	n := len(coords)
	for i := 0; i < n; i++ {
		a := coords[i]
		b := coords[(i+1)%n]
		x1 := a.Lng * mPerDegLng
		y1 := a.Lat * mPerDegLat
		x2 := b.Lng * mPerDegLng
		y2 := b.Lat * mPerDegLat
		area += x1*y2 - x2*y1
	}
	return math.Abs(area) / 2
}

// areaEfficiency is enclosed area / area-of-equal-perimeter-circle. A circle of
// circumference C encloses C²/(4π). Returns ~1 for a round loop, →0 for a thin
// out-and-back spur. Port of select.ts#areaEfficiency.
func areaEfficiency(coords []Coord, distanceM float64) float64 {
	if distanceM <= 0 {
		return 0
	}
	circleArea := (distanceM * distanceM) / (4 * math.Pi)
	if circleArea <= 0 {
		return 0
	}
	return enclosedAreaM2(coords) / circleArea
}

// initialBearingDeg is the compass bearing (0=N, 90=E, clockwise) from a→b,
// used to bin candidate far-points into directional sectors so the cycle
// search radiates loops across the whole compass, not just one heading.
func initialBearingDeg(aLat, aLng, bLat, bLng float64) float64 {
	φ1 := aLat * math.Pi / 180
	φ2 := bLat * math.Pi / 180
	Δλ := (bLng - aLng) * math.Pi / 180
	y := math.Sin(Δλ) * math.Cos(φ2)
	x := math.Cos(φ1)*math.Sin(φ2) - math.Sin(φ1)*math.Cos(φ2)*math.Cos(Δλ)
	θ := math.Atan2(y, x) * 180 / math.Pi
	return math.Mod(θ+360, 360)
}
