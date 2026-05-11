package livehub

import (
	"math"
	"testing"
)

// 1 m east at 47.37 °N latitude ≈ 1.3261 × 10^-5 degrees lng. Lets
// the test scenarios use easy round-number metres.
const (
	testLat       = 47.37
	metrePerDegLng = 111320 * 0.6773
)

func eastOf(metresEast float64) (float64, float64) {
	return testLat, 8.54 + metresEast/metrePerDegLng
}

func TestIsInAnyZone_EmptyZones(t *testing.T) {
	if IsInAnyZone(0, 0, nil) {
		t.Fatal("nil zones → false expected")
	}
	if IsInAnyZone(0, 0, []PrivacyZone{}) {
		t.Fatal("empty zones → false expected")
	}
}

func TestIsInAnyZone_CentreIsIn(t *testing.T) {
	zone := PrivacyZone{Lat: testLat, Lng: 8.54, RadiusM: 200}
	if !IsInAnyZone(testLat, 8.54, []PrivacyZone{zone}) {
		t.Fatal("dead-centre point must be in-zone")
	}
}

func TestIsInAnyZone_InsideRadius(t *testing.T) {
	zone := PrivacyZone{Lat: testLat, Lng: 8.54, RadiusM: 200}
	lat, lng := eastOf(150) // 150 m east — inside 200 m
	if !IsInAnyZone(lat, lng, []PrivacyZone{zone}) {
		t.Fatal("150 m east of centre with 200 m radius must be in-zone")
	}
}

func TestIsInAnyZone_OutsideRadius(t *testing.T) {
	zone := PrivacyZone{Lat: testLat, Lng: 8.54, RadiusM: 200}
	lat, lng := eastOf(350) // 350 m east — outside 200 m
	if IsInAnyZone(lat, lng, []PrivacyZone{zone}) {
		t.Fatal("350 m east with 200 m radius must NOT be in-zone")
	}
}

func TestIsInAnyZone_MultipleZones(t *testing.T) {
	// Two distinct zones; a point inside the SECOND must still trigger.
	zones := []PrivacyZone{
		{Lat: 0, Lng: 0, RadiusM: 100},
		{Lat: testLat, Lng: 8.54, RadiusM: 200},
	}
	lat, lng := eastOf(50)
	if !IsInAnyZone(lat, lng, zones) {
		t.Fatal("point inside the second zone must read as in-zone")
	}
}

func TestIsInAnyZone_RadiusBoundary(t *testing.T) {
	// On the boundary (≤ radius_m, per the <= comparison in the impl)
	// the point is considered in-zone — defensive default so a point
	// exactly on the edge doesn't accidentally leak.
	zone := PrivacyZone{Lat: testLat, Lng: 8.54, RadiusM: 200}
	lat, lng := eastOf(200)
	if !IsInAnyZone(lat, lng, []PrivacyZone{zone}) {
		t.Fatal("point at exactly the radius must be in-zone (<=)")
	}
}

// haversineMetres is the engine behind IsInAnyZone — keep one direct
// test so a future refactor that swaps the formula stays honest.
func TestHaversineMetres_ZeroDistance(t *testing.T) {
	d := haversineMetres(testLat, 8.54, testLat, 8.54)
	if math.Abs(d) > 1e-9 {
		t.Fatalf("haversine(same point, same point) = %f, want 0", d)
	}
}

func TestHaversineMetres_OneMetreEast(t *testing.T) {
	lat, lng := eastOf(1)
	d := haversineMetres(testLat, 8.54, lat, lng)
	// ~1 m, allow 1 cm tolerance for float drift.
	if math.Abs(d-1) > 0.01 {
		t.Fatalf("haversine(1 m east) = %f, want ~1", d)
	}
}
