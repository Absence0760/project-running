package graph

import (
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
// overshoots a 0.5 sample — hence we sample BELOW 0.5 too and keep whichever
// concatenated loop lands closest to target (the doc's "don't trust a single
// divisor"). Centred on ~0.44·D.
var farFractions = []float64{0.34, 0.40, 0.46, 0.52}

// Loop is one candidate (or chosen) cycle: its geometry in [lng,lat] order, its
// true length in metres (measured from geometry, not Dijkstra's penalised cost),
// and its isoperimetric shape score.
type Loop struct {
	Coords         []Coord
	DistanceM      float64
	AreaEfficiency float64
}

// CycleResult is what SearchCycle returns. Best is the chosen loop under the
// selection contract (in-band → roundest, else closest-to-target), or nil when
// no candidate cleared the spur floor (a genuinely loop-poor start). LargestClean
// is the longest clean loop the search found regardless of target — the honest
// "largest loop achievable here" signal that feeds the loop-poor UX.
type CycleResult struct {
	Best         *Loop
	LargestClean *Loop
}

// ShortestPath returns the foot-routing geometry and length between two
// coordinates, snapping each to the nearest graph node. ok is false when either
// endpoint can't be snapped or no path connects them. Exposed mainly to validate
// the graph against OSRM; the loop generator uses the internal search directly.
func (g *Graph) ShortestPath(fromLat, fromLng, toLat, toLng float64) (coords []Coord, distanceM float64, ok bool) {
	src, ok1 := g.NearestNode(fromLat, fromLng)
	dst, ok2 := g.NearestNode(toLat, toLng)
	if !ok1 || !ok2 {
		return nil, 0, false
	}
	_, prev := g.dijkstra(src, dst, math.Inf(1), nil)
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
func (g *Graph) SearchCycle(startLat, startLng, targetM float64) CycleResult {
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
	outDist, outPrev := g.dijkstra(src, -1, outRadius, nil)

	fars := g.pickFarPoints(src, targetM, outDist)

	var candidates []*Loop
	// The return leg may legitimately detour well past the outbound length;
	// cap generously so a real but circuitous loop isn't pruned.
	returnRadius := targetM * 2.0
	for _, f := range fars {
		out := reconstruct(outPrev, src, f)
		if len(out) < 2 {
			continue
		}
		penalised := pathEdgeKeys(out)
		_, retPrev := g.dijkstra(f, src, returnRadius, penalised)
		back := reconstruct(retPrev, f, src)
		if len(back) < 2 {
			continue // no second way home from F — the loop-poor signal at this F
		}
		loop := g.assembleLoop(out, back)
		if loop != nil {
			candidates = append(candidates, loop)
		}
	}

	return selectLoops(candidates, targetM)
}

// pickFarPoints buckets reached nodes into compass sectors and, for each
// (sector, farFraction) pair, keeps the node whose outbound distance is closest
// to the desired fraction of target. Deduped by node index.
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
			if err < best[sector][fi].err {
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
	}
}

// selectLoops applies the web selection contract and finds the largest clean
// loop. Clean = areaEfficiency ≥ spurFloor.
//
//   - In-band candidates (|len−target| ≤ distanceBand·target) exist → pick the
//     roundest; distance closeness breaks ties.
//   - Otherwise → the closest-to-target clean loop; roundness breaks ties.
//   - No clean loop at all → Best is nil (loop-poor).
func selectLoops(cands []*Loop, targetM float64) CycleResult {
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

	band := distanceBand * targetM
	var within []*Loop
	for _, c := range clean {
		if math.Abs(c.DistanceM-targetM) <= band {
			within = append(within, c)
		}
	}

	var best *Loop
	if len(within) > 0 {
		best = within[0]
		for _, c := range within[1:] {
			if c.AreaEfficiency > best.AreaEfficiency+1e-9 ||
				(math.Abs(c.AreaEfficiency-best.AreaEfficiency) <= 1e-9 &&
					math.Abs(c.DistanceM-targetM) < math.Abs(best.DistanceM-targetM)) {
				best = c
			}
		}
	} else {
		best = clean[0]
		bestDelta := math.Abs(best.DistanceM - targetM)
		for _, c := range clean[1:] {
			delta := math.Abs(c.DistanceM - targetM)
			if delta < bestDelta-1e-9 ||
				(math.Abs(delta-bestDelta) <= 1e-9 && c.AreaEfficiency > best.AreaEfficiency) {
				best = c
				bestDelta = delta
			}
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
