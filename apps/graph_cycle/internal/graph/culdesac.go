package graph

// Cul-de-sac mode caps. A loop with a few short spurs is still a loop; past
// these it is an out-and-back nobody asked for.
const (
	culDeSacMaxStubs = 4
	// One-way length of a single stub. A dead-end street a runner would
	// deliberately turn down is short — past this it is a leg, not a spur.
	culDeSacMaxStubM = 250.0
	// Total credited (out-and-back) stub length, as a fraction of target.
	culDeSacShareOfTarget = 0.20
	// Nodes one probe may visit before giving up. A dense lattice has no dead
	// ends at all, so without a budget every probe would walk the whole 250 m
	// neighbourhood of every node on every candidate before returning nothing.
	culDeSacProbeNodes = 64
)

type culDeSacStub struct {
	at   int // index into the loop path the stub hangs off
	path []int32
	outM float64
}

// augmentCulDeSac splices short quiet dead-end spurs into a loop that is
// running short of target, in place. This is the design's deliberate exception:
// a spur is what areaEfficiency exists to punish, so the mode credits the stub
// length in the ranking instead (scoreStubCredit) rather than inverting the
// shape score itself — a cul-de-sac loop still has to look like a loop, which
// is why an augmentation that would drop the loop below the spur floor is
// walked back one stub at a time.
func (g *Graph) augmentCulDeSac(l *Loop, targetM float64) {
	// Stubs are added to loops, not to spurs, and only ever to close a
	// shortfall: they can lengthen a loop, never shorten one.
	if l.AreaEfficiency < spurFloor || l.DistanceM >= targetM {
		return
	}
	onLoop := make(map[int32]struct{}, len(l.path))
	for _, n := range l.path {
		onLoop[n] = struct{}{}
	}
	claimed := make(map[int32]struct{})
	budget := culDeSacShareOfTarget * targetM

	var stubs []culDeSacStub
	total := 0.0
	for i, u := range l.path {
		if len(stubs) >= culDeSacMaxStubs || total >= budget {
			break
		}
		stub := g.findQuietStub(u, onLoop, claimed)
		if stub == nil {
			continue
		}
		outM := g.pathLengthM(stub)
		if total+2*outM > budget || l.DistanceM+total+2*outM > targetM {
			continue
		}
		for _, n := range stub[1:] {
			claimed[n] = struct{}{}
		}
		stubs = append(stubs, culDeSacStub{at: i, path: stub, outM: outM})
		total += 2 * outM
	}

	for len(stubs) > 0 {
		path := spliceStubs(l.path, stubs)
		coords := g.pathCoords(path)
		distanceM := g.pathLengthM(path)
		if eff := areaEfficiency(coords, distanceM); eff >= spurFloor {
			l.path, l.Coords, l.DistanceM, l.AreaEfficiency = path, coords, distanceM, eff
			l.stubM = 0
			for _, s := range stubs {
				l.stubM += 2 * s.outM
			}
			return
		}
		stubs = stubs[:len(stubs)-1]
	}
}

// findQuietStub returns the shortest path in hops from u to a dead end reachable
// without touching the loop, another stub, or an arterial road — the dead ends
// worth running down hang off neighbourhood streets. nil when there is none
// within the length and probe budgets.
func (g *Graph) findQuietStub(u int32, onLoop, claimed map[int32]struct{}) []int32 {
	prev := map[int32]int32{u: -1}
	dist := map[int32]float64{u: 0}
	queue := []int32{u}
	visited := 0
	for len(queue) > 0 && visited < culDeSacProbeNodes {
		cur := queue[0]
		queue = queue[1:]
		visited++
		for e := g.edgeHead[cur]; e < g.edgeHead[cur+1]; e++ {
			v := g.edgeTo[e]
			if _, on := onLoop[v]; on {
				continue
			}
			if _, taken := claimed[v]; taken {
				continue
			}
			if _, seen := prev[v]; seen {
				continue
			}
			if g.edgeAttr[e]&classMask == classArterial {
				continue
			}
			d := dist[cur] + float64(g.edgeLen[e])
			if d > culDeSacMaxStubM {
				continue
			}
			prev[v] = cur
			dist[v] = d
			if g.degree(v) == 1 {
				return reconstruct(prev, u, v)
			}
			queue = append(queue, v)
		}
	}
	return nil
}

// spliceStubs inserts each stub as an out-and-back at its anchor, so the loop
// leaves the anchor, reaches the dead end, and comes back to it before carrying
// on. `stubs` must be in ascending anchor order, which is how they are chosen.
func spliceStubs(path []int32, stubs []culDeSacStub) []int32 {
	extra := 0
	for _, s := range stubs {
		extra += 2 * (len(s.path) - 1)
	}
	out := make([]int32, 0, len(path)+extra)
	next := 0
	for i, n := range path {
		out = append(out, n)
		if next < len(stubs) && stubs[next].at == i {
			st := stubs[next].path
			out = append(out, st[1:]...)
			for k := len(st) - 2; k >= 0; k-- {
				out = append(out, st[k])
			}
			next++
		}
	}
	return out
}
