package graph

import "testing"

func TestRoadClassFor(t *testing.T) {
	cases := []struct {
		highway string
		want    uint8
	}{
		{"primary", classArterial},
		{"secondary_link", classArterial},
		{"tertiary", classArterial},
		{"motorway", classArterial},
		{"residential", classResidential},
		{"living_street", classResidential},
		{"service", classResidential},
		{"unclassified", classResidential},
		{"footway", classFootFirst},
		{"path", classFootFirst},
		{"steps", classFootFirst},
		{"cycleway", classFootFirst},
		{"", classResidential},
	}
	for _, c := range cases {
		if got := roadClassFor(c.highway); got != c.want {
			t.Errorf("roadClassFor(%q) = %d, want %d", c.highway, got, c.want)
		}
	}
}

func TestAttrBetweenIsSymmetric(t *testing.T) {
	b := newBuilder()
	b.addNode(1, Coord{Lat: 0, Lng: 0})
	b.addNode(2, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b.addNode(3, Coord{Lat: metresToDegLat(100), Lng: 0})
	b.addSegment(1, 2, classArterial)
	b.addSegment(1, 3, classFootFirst|attrGreen)
	g := b.finalize()

	for _, c := range []struct {
		from, to int32
		want     uint8
	}{
		{0, 1, classArterial},
		{1, 0, classArterial},
		{0, 2, classFootFirst | attrGreen},
		{2, 0, classFootFirst | attrGreen},
	} {
		got, ok := g.attrBetween(c.from, c.to)
		if !ok {
			t.Fatalf("no edge %d→%d", c.from, c.to)
		}
		if got != c.want {
			t.Errorf("attr %d→%d = %#b, want %#b", c.from, c.to, got, c.want)
		}
	}
	if _, ok := g.attrBetween(1, 2); ok {
		t.Error("nodes 1 and 2 are not adjacent, attrBetween claimed they are")
	}
}

func TestStubGridDeadEnds(t *testing.T) {
	g, _ := BuildTestStubGrid(3, 3, 100, 40.0, -77.0, 0.4)
	deadEnds := 0
	for n := int32(0); n < int32(g.NumNodes()); n++ {
		if g.degree(n) == 1 {
			deadEnds++
		}
	}
	if deadEnds != 9 {
		t.Fatalf("dead ends = %d, want one per lattice node (9)", deadEnds)
	}
}

func TestSplitGridAttributesEastAndWest(t *testing.T) {
	g, _ := BuildTestSplitGrid(5, 6, 100, 40.0, -77.0, true)
	// Node index is r*cols + c for this fixture. Column 0→1 is western, 4→5 eastern.
	west, ok := g.attrBetween(0, 1)
	if !ok || west&classMask != classArterial {
		t.Fatalf("west edge attr = %#b (ok=%v), want arterial", west, ok)
	}
	east, ok := g.attrBetween(4, 5)
	if !ok || east&classMask != classFootFirst || east&attrGreen == 0 {
		t.Fatalf("east edge attr = %#b (ok=%v), want foot-first + green", east, ok)
	}
}
