package graph

import (
	"context"
	"math"
	"testing"
)

func TestPrefCostIsAlwaysSoft(t *testing.T) {
	b := newBuilder()
	b.addNode(0, Coord{Lat: 0, Lng: 0})
	b.addNode(1, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b.addNode(2, Coord{Lat: metresToDegLat(100), Lng: 0})
	b.addNode(3, Coord{Lat: -metresToDegLat(100), Lng: 0})
	b.addSegment(0, 1, classArterial)
	b.addSegment(0, 2, classResidential)
	b.addSegment(0, 3, classFootFirst|attrGreen)
	g := b.finalize()

	for _, pref := range []Preference{PrefNone, PrefQuiet, PrefScenic, PrefCulDeSac} {
		for e := int32(0); e < int32(g.NumEdges()); e++ {
			c := g.prefCost(e, pref)
			// Soft only: a zero or infinite multiplier would let a preference
			// remove an edge and disconnect an otherwise buildable network.
			if !(c > 0) || math.IsInf(c, 0) || math.IsNaN(c) {
				t.Fatalf("pref %d edge %d cost = %v, want finite and positive", pref, e, c)
			}
		}
	}
	if g.prefCost(0, PrefNone) != 1 {
		t.Fatal("PrefNone must leave every edge at its true length")
	}
}

// splitGridCentre is the middle node of a BuildTestSplitGrid lattice: the
// boundary between the arterial west and the quiet, green east.
func splitGridCentre(rows, cols int, spacingM, originLat, originLng float64) (lat, lng float64) {
	return originLat + float64(rows/2)*metresToDegLat(spacingM),
		originLng + float64(cols/2)*metresToDegLng(spacingM, originLat)
}

// sweepTargets is a spread of loop lengths a 13x13 lattice at 100 m spacing can
// actually serve, so a preference is judged over a field of choices rather than
// on one lucky target.
var sweepTargets = []float64{400, 600, 800, 1000, 1200, 1600, 2000, 2400}

func TestPreferenceSteersOntoPreferredEdges(t *testing.T) {
	// The same lattice with the preferred half mirrored, so nothing about the
	// geometry can favour one answer. The unweighted search is blind to the
	// attribution and must pick the same loops on both; the weighted one must
	// end up on more preferred road than it does.
	for _, preferEast := range []bool{true, false} {
		g, _ := BuildTestSplitGrid(13, 13, 100, 40.0, -77.0, preferEast)
		lat := 40.0 + 6*metresToDegLat(100)
		lng := -77.0 + 6*metresToDegLng(100, 40.0)

		for _, pref := range []Preference{PrefQuiet, PrefScenic} {
			plainShare, prefShare := 0.0, 0.0
			for _, target := range sweepTargets {
				plain := g.SearchCycle(context.Background(), lat, lng, target, PrefNone)
				res := g.SearchCycle(context.Background(), lat, lng, target, pref)
				if plain.Best == nil || res.Best == nil {
					t.Fatalf("east=%v pref=%d target=%.0f: expected a loop on a dense grid", preferEast, pref, target)
				}
				if plain.Applied != PrefNone || plain.PreferredShare != 0 {
					t.Fatalf("unpreferenced result claimed applied=%d share=%v", plain.Applied, plain.PreferredShare)
				}
				if res.Applied != pref {
					t.Fatalf("east=%v pref=%d: applied = %d", preferEast, pref, res.Applied)
				}
				if math.Abs(res.PreferredShare-res.Best.share) > 1e-12 {
					t.Fatalf("reported share %.6f != the winner %.6f", res.PreferredShare, res.Best.share)
				}
				plainShare += g.preferredShare(plain.Best, pref)
				prefShare += res.PreferredShare
			}
			if prefShare <= plainShare {
				t.Fatalf("east=%v pref=%d: preferred share over the sweep %.3f did not beat the unpreferenced %.3f",
					preferEast, pref, prefShare, plainShare)
			}
		}
	}
}

func TestPreferenceNeverDeniesALoop(t *testing.T) {
	// The contract: a preference is an enhancement. Wherever the unweighted
	// search finds a loop, the weighted search must serve one too — either its
	// own, or the unweighted retry's.
	grid, _ := BuildTestGrid(9, 9, 100, 40.0, -77.0)
	split, _ := BuildTestSplitGrid(9, 9, 100, 40.0, -77.0, true)
	stub, _ := BuildTestStubGrid(9, 9, 100, 40.0, -77.0, 0.4)
	lat, lng := splitGridCentre(9, 9, 100, 40.0, -77.0)

	for gi, g := range []*Graph{grid, split, stub} {
		for _, target := range []float64{400, 800, 1200, 2000, 3000} {
			plain := g.SearchCycle(context.Background(), lat, lng, target, PrefNone)
			if plain.Best == nil {
				continue
			}
			for _, pref := range []Preference{PrefQuiet, PrefScenic, PrefCulDeSac} {
				res := g.SearchCycle(context.Background(), lat, lng, target, pref)
				if res.Best == nil {
					t.Fatalf("graph %d target %.0f pref %d: preference denied a loop the plain search found", gi, target, pref)
				}
			}
		}
	}
}

func TestLoopPoorStartReportsNoPreference(t *testing.T) {
	g, _ := BuildTestLine(30, 100, 40.0, -77.0)
	res := g.SearchCycle(context.Background(), 40.0, -77.0, 1000, PrefQuiet)
	if res.Best != nil {
		t.Fatal("a line graph is loop-poor under any preference")
	}
	if res.Applied != PrefNone || res.PreferredShare != 0 {
		t.Fatalf("loop-poor result claimed applied=%d share=%v", res.Applied, res.PreferredShare)
	}
}

func TestPreferredLoopLengthComesFromGeometry(t *testing.T) {
	// The weighted cost is not metres. A served loop's distance must still be
	// re-measured from its geometry, exactly as the reuse penalty already
	// required.
	g, _ := BuildTestSplitGrid(9, 9, 100, 40.0, -77.0, true)
	lat, lng := splitGridCentre(9, 9, 100, 40.0, -77.0)
	res := g.SearchCycle(context.Background(), lat, lng, 800, PrefQuiet)
	if res.Best == nil {
		t.Fatal("expected a loop")
	}
	if math.Abs(res.Best.DistanceM-g.pathLengthM(res.Best.path)) > 1e-6 {
		t.Fatalf("reported %.3f m, geometry measures %.3f m", res.Best.DistanceM, g.pathLengthM(res.Best.path))
	}
}

// The wire vocabulary is a round trip, and nothing measured it.
//
// `ParsePreference` reads the token a client sends; `String` writes the token
// the response reports back as `preferenceApplied`. They are two switches over
// one vocabulary, edited separately, and a token in one and not the other fails
// silently in both directions: a preference the parser does not know is
// accepted as PrefNone and quietly dropped — the runner asked for quiet streets
// and got the plain search with nothing saying so — while a token only the
// writer knows makes the response name a preference no client can ask for
// again. Neither shows up as an error anywhere.
func TestPreferenceVocabularyRoundTrips(t *testing.T) {
	named := []Preference{PrefQuiet, PrefScenic, PrefCulDeSac}

	// Every preference that has a token parses back to itself.
	for _, p := range named {
		token := p.String()
		if token == "" {
			t.Fatalf("preference %d has no wire token, so a response can never name it", p)
		}
		if got := ParsePreference(token); got != p {
			t.Fatalf("ParsePreference(%q) = %d, want %d — the token this preference reports "+
				"is not one a client can send back", token, got, p)
		}
	}

	// PrefNone deliberately has none: the response omits the field rather than
	// reporting a preference that was not applied.
	if PrefNone.String() != "" {
		t.Fatalf("PrefNone.String() = %q, want empty — a response would name a preference "+
			"the search never applied", PrefNone.String())
	}

	// And the enum has no unnamed member. A fourth preference added to the
	// const block without a String case would report as "" and read to every
	// client as "no preference was honoured".
	for p := PrefNone; p <= PrefCulDeSac; p++ {
		if p != PrefNone && p.String() == "" {
			t.Fatalf("preference %d is in the enum but has no wire token", p)
		}
	}
	if PrefCulDeSac.String() == "" || ParsePreference("cul_de_sac") != PrefCulDeSac {
		t.Fatal("the enum's last member is not wired to the vocabulary, so the sweep above " +
			"stops short of it")
	}

	// The parser is the enhancement's fail-open half: a stale, empty or garbled
	// token must degrade to the plain search, never block route generation.
	for _, token := range []string{"", "Quiet", "QUIET", "quiet ", "cul-de-sac", "culdesac",
		"scenic;drop table", "hilly", "0", "none"} {
		if got := ParsePreference(token); got != PrefNone {
			t.Fatalf("ParsePreference(%q) = %d, want PrefNone — an unrecognised token must "+
				"degrade, and must not alias onto a real preference", token, got)
		}
	}
}

// prefCost over the WHOLE attribute byte, not the three a fixture happens to
// build. The soft-cost promise is what stops a preference disconnecting a
// buildable neighbourhood, and it is a claim about every attribution the packed
// byte can hold — including a road class no `roadClassFor` returns today, which
// is exactly what a fourth class would introduce.
func TestPrefCostIsSoftForEveryAttributionTheByteCanHold(t *testing.T) {
	for attr := 0; attr < 256; attr++ {
		b := newBuilder()
		b.addNode(0, Coord{Lat: 0, Lng: 0})
		b.addNode(1, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
		b.addSegment(0, 1, uint8(attr))
		g := b.finalize()
		for _, pref := range []Preference{PrefNone, PrefQuiet, PrefScenic, PrefCulDeSac} {
			c := g.prefCost(0, pref)
			if !(c > 0) || math.IsInf(c, 0) || math.IsNaN(c) {
				t.Fatalf("attr %#02x under pref %d costs %v — a non-positive or infinite "+
					"multiplier lets a preference remove the edge", attr, pref, c)
			}
			if pref == PrefNone && c != 1 {
				t.Fatalf("attr %#02x under PrefNone costs %v, want 1", attr, c)
			}
		}
	}
}

// preferredShare is what the response reports, so it is a claim to the runner
// about what the search achieved. It must stay a fraction under every input the
// caller can produce, including the degenerate ones the search itself can hand
// it: a nil loop (loop-poor), a zero-length one, and a path whose consecutive
// nodes are not adjacent in the graph at all.
func TestPreferredShareStaysAFraction(t *testing.T) {
	b := newBuilder()
	b.addNode(0, Coord{Lat: 0, Lng: 0})
	b.addNode(1, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b.addNode(2, Coord{Lat: metresToDegLat(100), Lng: metresToDegLng(100, 0)})
	b.addNode(3, Coord{Lat: metresToDegLat(100), Lng: 0})
	b.addSegment(0, 1, classFootFirst|attrGreen)
	b.addSegment(1, 2, classFootFirst|attrGreen)
	b.addSegment(2, 3, classFootFirst|attrGreen)
	b.addSegment(3, 0, classFootFirst|attrGreen)
	g := b.finalize()

	all := &Loop{path: []int32{0, 1, 2, 3, 0}, DistanceM: 400, stubM: 40}

	for _, pref := range []Preference{PrefNone, PrefQuiet, PrefScenic, PrefCulDeSac} {
		if s := g.preferredShare(all, pref); s < 0 || s > 1 {
			t.Fatalf("pref %d share = %v, want 0..1", pref, s)
		}
		// A loop-poor result carries no loop; a zero-length one is what a
		// degenerate candidate looks like. Neither may divide.
		if s := g.preferredShare(nil, pref); s != 0 {
			t.Fatalf("pref %d over a nil loop = %v, want 0", pref, s)
		}
		if s := g.preferredShare(&Loop{path: all.path, DistanceM: 0}, pref); s != 0 {
			t.Fatalf("pref %d over a zero-length loop = %v, want 0", pref, s)
		}
	}

	// PrefNone reports nothing: the field is omitted, not zeroed by accident.
	if s := g.preferredShare(all, PrefNone); s != 0 {
		t.Fatalf("PrefNone share = %v, want 0", s)
	}
	// Every edge here is green and car-free, so scenic and quiet both see the
	// whole loop. The tolerance is the degree-conversion round trip in the
	// fixture's own coordinates (four ~100 m sides against a declared 400),
	// not slack in the claim: the point is that the share reaches the ceiling
	// rather than exceeding it.
	for _, pref := range []Preference{PrefQuiet, PrefScenic} {
		if s := g.preferredShare(all, pref); s <= 0.99 || s > 1 {
			t.Fatalf("pref %d over a wholly preferred loop = %v, want ~1", pref, s)
		}
	}

	// The discriminating half: a loop with none of the preferred edges must
	// report nothing. Without this the assertion above is satisfied by a
	// function that returns 1 unconditionally.
	b2 := newBuilder()
	b2.addNode(0, Coord{Lat: 0, Lng: 0})
	b2.addNode(1, Coord{Lat: 0, Lng: metresToDegLng(100, 0)})
	b2.addNode(2, Coord{Lat: metresToDegLat(100), Lng: metresToDegLng(100, 0)})
	b2.addNode(3, Coord{Lat: metresToDegLat(100), Lng: 0})
	for _, e := range [][2]int64{{0, 1}, {1, 2}, {2, 3}, {3, 0}} {
		b2.addSegment(e[0], e[1], classArterial)
	}
	arterial := b2.finalize()
	unpreferred := &Loop{path: []int32{0, 1, 2, 3, 0}, DistanceM: 400}
	for _, pref := range []Preference{PrefQuiet, PrefScenic} {
		if s := arterial.preferredShare(unpreferred, pref); s != 0 {
			t.Fatalf("pref %d over an all-arterial loop = %v, want 0", pref, s)
		}
	}
	// A DistanceM smaller than the geometry it describes is the one way the
	// ratio can exceed 1, and the clamp is what stops the response claiming a
	// runner spent 240% of their loop on footpaths.
	if s := g.preferredShare(&Loop{path: all.path, DistanceM: 1}, PrefScenic); s != 1 {
		t.Fatalf("an under-reported distance gave share %v, want the clamp at 1", s)
	}
	// A path the graph does not connect contributes nothing rather than
	// panicking or counting a segment that is not there.
	if s := g.preferredShare(&Loop{path: []int32{0, 2}, DistanceM: 100}, PrefScenic); s != 0 {
		t.Fatalf("a non-adjacent pair contributed %v", s)
	}
	// Cul-de-sac credit is the stub fraction, and it is clamped too.
	if s := g.preferredShare(&Loop{path: all.path, DistanceM: 400, stubM: 40}, PrefCulDeSac); math.Abs(s-0.1) > 1e-9 {
		t.Fatalf("cul-de-sac share = %v, want 0.1", s)
	}
	if s := g.preferredShare(&Loop{path: all.path, DistanceM: 100, stubM: 4000}, PrefCulDeSac); s != 1 {
		t.Fatalf("an over-credited stub gave share %v, want the clamp at 1", s)
	}
}
