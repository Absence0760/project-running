package graph

import (
	"context"
	"math"
	"sort"
)

// Tuning constants. spurFloor + distanceBand are ported verbatim from the web
// selector (select.ts) so the sidecar and the client agree on what counts as a
// "clean loop" and as "close enough on distance". reusePenalty and the sampling
// spread are the P0 spike's validated values.
const (
	spurFloor    = 0.12 // min areaEfficiency for a candidate to be a real loop, not a spur
	distanceBand = 0.15 // ±fraction of target within which we decide on shape, not distance
	reusePenalty = 8.0  // ×cost applied to an outbound edge reused on the return leg
	numBearings  = 12   // directional sectors far-points are bucketed into (30° each)
)

// farFractions are the outbound (S→F) graph distances to sample, as fractions
// of the target loop length. A clean out-and-back would put F at exactly D/2;
// the penalised return leg runs longer than the outbound, so the actual loop
// overshoots a 0.5 sample — hence we sample BELOW 0.5 and keep whichever
// concatenated loop lands closest to target (the doc's "don't trust a single
// divisor"). The 0.58 sample covers sparse/circuitous networks whose only loop
// needs an outbound leg past D/2.
var farFractions = []float64{0.34, 0.40, 0.46, 0.52, 0.58}

// Loop is one candidate (or chosen) cycle: its geometry in [lng,lat] order, its
// true length in metres (measured from geometry, not Dijkstra's penalised cost),
// and its isoperimetric shape score. `path` is the node-index sequence the
// geometry came from, kept so the preference layer can read the edge
// attribution the coordinates no longer carry.
type Loop struct {
	Coords         []Coord
	DistanceM      float64
	AreaEfficiency float64

	path  []int32
	share float64 // fraction of DistanceM on the active preference's edges
	stubM float64 // credited cul-de-sac stub length, 0 outside that mode
}

// CycleResult is what SearchCycle returns. Best is the chosen loop under the
// selection contract (in-band → roundest, else closest-to-target), or nil when
// no candidate cleared the spur floor (a genuinely loop-poor start). LargestClean
// is the longest clean loop the search found regardless of target — the honest
// "largest loop achievable here" signal that feeds the loop-poor UX.
type CycleResult struct {
	Best         *Loop
	LargestClean *Loop

	// Applied is the preference the served loop actually honours. It is
	// PrefNone when none was asked for, when one was asked for but the
	// unweighted retry produced the loop, and when a cul-de-sac ask spliced no
	// spur — an unhonoured ask must never read as honoured. PreferredShare is
	// meaningful only alongside a set Applied.
	Applied        Preference
	PreferredShare float64
}

// ShortestPath returns the foot-routing geometry and length between two
// coordinates, snapping each to the nearest graph node. ok is false when either
// endpoint can't be snapped or no path connects them. Exposed mainly to validate
// the graph against OSRM; the loop generator uses the internal search directly.
func (g *Graph) ShortestPath(ctx context.Context, fromLat, fromLng, toLat, toLng float64) (coords []Coord, distanceM float64, ok bool) {
	src, ok1 := g.NearestNode(fromLat, fromLng)
	dst, ok2 := g.NearestNode(toLat, toLng)
	if !ok1 || !ok2 {
		return nil, 0, false
	}
	_, _, prev := g.dijkstra(ctx, src, dst, math.Inf(1), nil, PrefNone)
	path := reconstruct(prev, src, dst)
	if path == nil {
		return nil, 0, false
	}
	coords = g.pathCoords(path)
	return coords, g.pathLengthM(path), true
}

// SearchCycle is the v3 generator: from a start coordinate it searches the real
// street graph for a clean loop of ≈ targetM metres and returns the best one
// plus the largest clean loop found. Returns an all-nil result if the start
// can't be snapped to the graph.
//
// Algorithm (the validated P0 spike, verbatim):
//  1. Snap start S; run ONE Dijkstra from S out to a radius generously past the
//     largest far-point sample, recording distance + predecessor for every node
//     in range.
//  2. Pick candidate far-points F: for each of numBearings compass sectors and
//     each farFraction, the reached node in that sector whose graph distance is
//     closest to farFraction·targetM.
//  3. For each F: the outbound path S→F is already known from step 1. Penalise
//     its edges ×reusePenalty and run a return Dijkstra F→S; concatenate into a
//     cycle.
//  4. Score every cycle by areaEfficiency, drop spurs (< spurFloor), and select
//     under the web contract.
//
// A preference biases steps 1-3 through soft per-edge multipliers and step 4
// through a ranking term. It can never deny a route: if the weighted search
// clears no candidate over the spur floor, the whole search is repeated
// unweighted and that loop is served with Applied left at PrefNone.
func (g *Graph) SearchCycle(ctx context.Context, startLat, startLng, targetM float64, pref Preference) CycleResult {
	res := g.searchCycle(ctx, startLat, startLng, targetM, pref)
	if res.Best != nil || pref == PrefNone || ctx.Err() != nil {
		return res
	}
	return g.searchCycle(ctx, startLat, startLng, targetM, PrefNone)
}

func (g *Graph) searchCycle(ctx context.Context, startLat, startLng, targetM float64, pref Preference) CycleResult {
	src, ok := g.NearestNode(startLat, startLng)
	if !ok {
		return CycleResult{}
	}

	maxFar := farFractions[0]
	for _, f := range farFractions {
		if f > maxFar {
			maxFar = f
		}
	}
	// Outbound tree: reach far-points up to maxFar·target, with slack.
	outRadius := maxFar*targetM*1.25 + 200
	_, outReal, outPrev := g.dijkstra(ctx, src, -1, outRadius, nil, pref)

	if ctx.Err() != nil {
		return CycleResult{}
	}
	fars := g.pickFarPoints(src, targetM, outReal)

	var candidates []*Loop
	// The return leg may legitimately detour well past the outbound length; cap
	// generously (in TRUE metres — dijkstra bounds by real distance, not penalised
	// cost) so a real but circuitous loop isn't pruned.
	returnRadius := targetM * 2.0
	for _, f := range fars {
		// The 61 return searches are where the wall-clock actually goes, and the
		// per-pop check inside dijkstra is scoped to ONE search — at realistic
		// targets each is short enough that it never reaches its 4096-pop
		// interval, so the cancellation was evaluated zero times across the whole
		// request. Checking between legs is what makes a disconnect stop work.
		if ctx.Err() != nil {
			break
		}
		out := reconstruct(outPrev, src, f)
		if len(out) < 2 {
			continue
		}
		penalised := pathEdgeKeys(out)
		_, _, retPrev := g.dijkstra(ctx, f, src, returnRadius, penalised, pref)
		back := reconstruct(retPrev, f, src)
		if len(back) < 2 {
			continue // no second way home from F — the loop-poor signal at this F
		}
		loop := g.assembleLoop(out, back)
		if loop != nil {
			candidates = append(candidates, loop)
		}
	}

	for _, c := range candidates {
		if pref == PrefCulDeSac {
			g.augmentCulDeSac(c, targetM)
		}
		c.share = g.preferredShare(c, pref)
	}

	res := selectLoops(candidates, targetM, pref)
	// A cul-de-sac ask is binary and observable, so a loop carrying no spur did
	// not honour it however the search was weighted. quiet and scenic are
	// gradients — the search genuinely was biased and the share reports what it
	// achieved — so any loop they returned honours the ask.
	if res.Best != nil && (pref != PrefCulDeSac || res.Best.stubM > 0) {
		res.Applied = pref
		res.PreferredShare = res.Best.share
	}
	return res
}

// pickFarPoints buckets reached nodes into compass sectors and, for each
// (sector, farFraction) pair, keeps the node whose outbound distance is closest
// to the desired fraction of target. Deduped by node index. The distances are
// TRUE metres (dijkstra's realTo), so a preference-weighted outbound tree still
// sizes its far-points against the loop the runner asked for.
func (g *Graph) pickFarPoints(src int32, targetM float64, outDist map[int32]float64) []int32 {
	sLat, sLng := g.lat[src], g.lng[src]

	type pick struct {
		node int32
		err  float64
	}
	// best[sector][fractionIndex]
	best := make([][]pick, numBearings)
	for s := range best {
		best[s] = make([]pick, len(farFractions))
		for f := range best[s] {
			best[s][f] = pick{node: -1, err: math.Inf(1)}
		}
	}

	for node, d := range outDist {
		if node == src {
			continue
		}
		bearing := initialBearingDeg(sLat, sLng, g.lat[node], g.lng[node])
		sector := int(bearing/(360.0/numBearings)) % numBearings
		for fi, frac := range farFractions {
			err := math.Abs(d - frac*targetM)
			cur := best[sector][fi]
			// Strict-less on error, with the LOWER node index winning ties — the
			// map iteration order over outDist is random, so without this tiebreak
			// two equal-error nodes would make the chosen far-point (and the whole
			// result) non-deterministic across runs / JSON round-trips.
			if err < cur.err || (err == cur.err && (cur.node < 0 || node < cur.node)) {
				best[sector][fi] = pick{node: node, err: err}
			}
		}
	}

	seen := map[int32]struct{}{}
	var out []int32
	for s := range best {
		for fi := range best[s] {
			n := best[s][fi].node
			if n < 0 {
				continue
			}
			if _, dup := seen[n]; dup {
				continue
			}
			seen[n] = struct{}{}
			out = append(out, n)
		}
	}
	return out
}

// assembleLoop concatenates an outbound path S→F and a return path F→S into a
// closed cycle, drops the duplicated F vertex, measures the true length and
// shape, and rejects a degenerate (sub-4-vertex) result.
func (g *Graph) assembleLoop(out, back []int32) *Loop {
	full := make([]int32, 0, len(out)+len(back)-1)
	full = append(full, out...)
	full = append(full, back[1:]...) // back[0] == F, already the last of out
	if len(full) < 4 {
		return nil
	}
	coords := g.pathCoords(full)
	distanceM := g.pathLengthM(full)
	if distanceM <= 0 {
		return nil
	}
	return &Loop{
		Coords:         coords,
		DistanceM:      distanceM,
		AreaEfficiency: areaEfficiency(coords, distanceM),
		path:           full,
	}
}

// Multi-objective ranking weights. One weighted score replaces the two-branch
// selection the sidecar shipped with, so a preference can trade a little
// roundness or distance error for a loop that is actually on the roads the
// runner asked for.
//
// With no preference the ordering is the shipped contract: an in-band candidate
// scores on the roundness scale and an out-of-band one in a strictly lower band,
// so the two never cross and whichever objective led the old branch still leads
// it. The other rides at scoreTieWeight. That is why BOTH branches score on an
// O(1) scale rather than in metres — a tie-break this small added to a 25 km
// delta is a fraction of one ULP of it and rounds away entirely, silently
// reversing the objective it exists to decide. The 1e-9 tolerance the old
// comparison treated as a tie also made it non-transitive, so no scalar score
// can reproduce it exactly; selection_pin_test.go measures what is left.
const (
	// The grid the leading objective is snapped to before the tie-break is
	// added — the same 1e-9 the old comparison called a tie. Without it two
	// loops equidistant from target to the last bit would be separated by float
	// noise instead of by their shape, which is the one place a scalar score
	// could diverge from the contract.
	scoreQuantum = 1e-9
	// The tie-break's WHOLE range: both branches normalise their secondary
	// objective to [0,1] before scaling by it, so a hundredth of a quantum is
	// what keeps the tie-break under the grid of the objective it breaks ties
	// within while still spanning thousands of ULP of the sum it joins.
	scoreTieWeight = scoreQuantum / 100
	// What a fully preferred loop may buy itself, in each branch's own currency:
	// half of the roundness scale while the field is judged on shape, and one
	// band's width of (target-normalised) distance error while it is judged on
	// distance. Every candidate has already cleared the spur floor, so trading
	// some roundness for the roads the runner explicitly asked for is the right
	// trade —
	// roundness is our aesthetic proxy, the preference is their instruction.
	// Trading a whole band of distance, though, would let a preference serve a
	// loop the runner did not ask for the length of.
	scoreShareRoundness = 0.5
	scoreShareDistance  = distanceBand
	// The cul-de-sac inversion. A loop that grows by a fraction f of its length
	// with no new area keeps only 1/(1+f)² of its shape score, so at the stub
	// cap it loses roughly 0.15 of an ordinary score against a credited share
	// of about 0.17. A credit of 1 therefore leaves a fully-stubbed loop
	// ranked a shade above the same loop without them — which is the ask —
	// rather than penalised for taking the spurs the runner requested.
	scoreStubCredit = 1.0
)

// scoreLoop ranks one candidate; higher is better. An in-band candidate scores
// on the roundness scale, which every candidate that reached scoring occupies
// above zero (they have all cleared spurFloor); an out-of-band one scores an
// order below zero. So the field is judged on shape exactly when something
// reached the band, without a magnitude-dwarfing bonus to say so. The snapped
// delta is divided by targetM rather than snapped after: targetM is a positive
// constant within a call, so the primary ordering is untouched and equal snapped
// deltas still yield an identical quotient.
func scoreLoop(c *Loop, targetM float64, pref Preference) float64 {
	delta := math.Abs(c.DistanceM - targetM)
	band := distanceBand * targetM
	if delta <= band {
		s := snapToQuantum(c.AreaEfficiency) - scoreTieWeight*(delta/band)
		if pref != PrefNone {
			s += shareWeightFor(pref) * c.share
		}
		return s
	}
	s := -1 - snapToQuantum(delta)/targetM + scoreTieWeight*c.AreaEfficiency
	if pref != PrefNone {
		s += scoreShareDistance * c.share
	}
	return s
}

// shareWeightFor is what a fully preferred loop may buy while the field is
// judged on shape.
func shareWeightFor(pref Preference) float64 {
	if pref == PrefCulDeSac {
		return scoreStubCredit
	}
	return scoreShareRoundness
}

func snapToQuantum(v float64) float64 { return math.Round(v/scoreQuantum) * scoreQuantum }

// selectLoops drops spurs (areaEfficiency < spurFloor), ranks what is left by
// scoreLoop, and reports the largest clean loop alongside the winner. No clean
// loop at all → Best is nil (loop-poor).
func selectLoops(cands []*Loop, targetM float64, pref Preference) CycleResult {
	clean := make([]*Loop, 0, len(cands))
	for _, c := range cands {
		if c.AreaEfficiency >= spurFloor {
			clean = append(clean, c)
		}
	}
	if len(clean) == 0 {
		return CycleResult{}
	}

	// Deterministic order before selection so equal-scoring candidates resolve
	// stably (round trips through JSON shouldn't flip the chosen loop).
	sort.SliceStable(clean, func(i, j int) bool {
		if clean[i].DistanceM != clean[j].DistanceM {
			return clean[i].DistanceM < clean[j].DistanceM
		}
		return clean[i].AreaEfficiency > clean[j].AreaEfficiency
	})

	var largest *Loop
	for _, c := range clean {
		if largest == nil || c.DistanceM > largest.DistanceM {
			largest = c
		}
	}

	best := clean[0]
	bestScore := scoreLoop(best, targetM, pref)
	for _, c := range clean[1:] {
		// Strictly better only, so an exact tie keeps the earlier candidate in
		// the deterministic order sorted above.
		if s := scoreLoop(c, targetM, pref); s > bestScore {
			best, bestScore = c, s
		}
	}

	return CycleResult{Best: best, LargestClean: largest}
}

// pathEdgeKeys returns the set of canonical undirected edge keys along a path.
func pathEdgeKeys(path []int32) map[uint64]struct{} {
	keys := make(map[uint64]struct{}, len(path))
	for i := 1; i < len(path); i++ {
		keys[edgeKey(path[i-1], path[i])] = struct{}{}
	}
	return keys
}

// pathCoords maps a node-index path to its [lng,lat] geometry.
func (g *Graph) pathCoords(path []int32) []Coord {
	coords := make([]Coord, len(path))
	for i, n := range path {
		coords[i] = g.coordOf(n)
	}
	return coords
}

// pathLengthM sums the true great-circle length of a node-index path in metres.
// Measured from geometry so a penalised Dijkstra cost never leaks into a
// reported distance.
func (g *Graph) pathLengthM(path []int32) float64 {
	total := 0.0
	for i := 1; i < len(path); i++ {
		a, b := path[i-1], path[i]
		total += haversineM(g.lat[a], g.lng[a], g.lat[b], g.lng[b])
	}
	return total
}
