package graph

import (
	"math"
	"testing"
)

func TestHaversineM(t *testing.T) {
	// One degree of latitude is ~111.2 km.
	d := haversineM(0, 0, 1, 0)
	if math.Abs(d-111195) > 500 {
		t.Fatalf("1° lat = %.0f m, want ~111195", d)
	}
	if got := haversineM(40, -77, 40, -77); got != 0 {
		t.Fatalf("zero-distance = %v, want 0", got)
	}
}

func TestEnclosedAreaSquare(t *testing.T) {
	// A ~100 m square near the equator encloses ~10,000 m².
	d := metresToDegLat(100)
	sq := []Coord{{0, 0}, {d, 0}, {d, d}, {0, d}}
	area := enclosedAreaM2(sq)
	if math.Abs(area-10000) > 200 {
		t.Fatalf("100m square area = %.0f m², want ~10000", area)
	}
}

func TestEnclosedAreaDegenerate(t *testing.T) {
	if a := enclosedAreaM2([]Coord{{0, 0}, {1, 1}}); a != 0 {
		t.Fatalf("2-point area = %v, want 0", a)
	}
}

func TestAreaEfficiency(t *testing.T) {
	// A square is a reasonably round loop: efficiency well above the spur floor.
	d := metresToDegLat(100)
	sq := []Coord{{0, 0}, {d, 0}, {d, d}, {0, d}}
	per := 0.0
	for i := 0; i < len(sq); i++ {
		a, b := sq[i], sq[(i+1)%len(sq)]
		per += haversineM(a.Lat, a.Lng, b.Lat, b.Lng)
	}
	eff := areaEfficiency(sq, per)
	if eff < 0.6 || eff > 0.85 {
		t.Fatalf("square efficiency = %.3f, want ~0.785 (π/4)", eff)
	}

	// An out-and-back spur encloses ~no area → efficiency ≈ 0.
	spur := []Coord{{0, 0}, {d, 0}, {2 * d, 0}, {d, 0}}
	if e := areaEfficiency(spur, 400); e > 0.01 {
		t.Fatalf("spur efficiency = %.4f, want ~0", e)
	}

	if e := areaEfficiency(sq, 0); e != 0 {
		t.Fatalf("zero-distance efficiency = %v, want 0", e)
	}
}

func TestInitialBearing(t *testing.T) {
	cases := []struct {
		name                  string
		toLat, toLng, wantDeg float64
	}{
		{"north", 1, 0, 0},
		{"east", 0, 1, 90},
		{"south", -1, 0, 180},
		{"west", 0, -1, 270},
	}
	for _, c := range cases {
		got := initialBearingDeg(0, 0, c.toLat, c.toLng)
		diff := math.Abs(got - c.wantDeg)
		if diff > 1 && math.Abs(diff-360) > 1 {
			t.Errorf("%s: bearing = %.1f°, want %.1f°", c.name, got, c.wantDeg)
		}
	}
}
