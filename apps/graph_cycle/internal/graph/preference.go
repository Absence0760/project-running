package graph

import "math"

// Preference is an optional route-design bias supplied by the caller. It scales
// the per-edge search cost and adds a term to the post-hoc ranking of candidate
// loops. It never removes an edge, and a search that finds nothing under a
// preference is retried without one — see SearchCycle and
// docs/features/graph_cycle_loop_generation.md § Extension.
type Preference uint8

const (
	PrefNone Preference = iota
	PrefQuiet
	PrefScenic
	PrefCulDeSac
)

// Soft per-edge cost multipliers. Every value is finite and strictly positive:
// a preference may bias the search but must never be able to disconnect the
// graph, because a hard filter turns a buildable neighbourhood into "no loop"
// and the fallback then serves a worse route than the unbiased search would.
const (
	quietArterialCost  = 1.8
	quietFootFirstCost = 0.85
	scenicGreenCost    = 0.65
	scenicArterialCost = 1.3
)

// prefCost is the multiplier applied to edge e's true length under pref.
func (g *Graph) prefCost(e int32, pref Preference) float64 {
	attr := g.edgeAttr[e]
	switch pref {
	case PrefQuiet, PrefCulDeSac:
		// Cul-de-sac mode inherits the quiet weighting: the dead ends worth
		// running down hang off neighbourhood streets, not off arterials.
		switch attr & classMask {
		case classArterial:
			return quietArterialCost
		case classFootFirst:
			return quietFootFirstCost
		}
	case PrefScenic:
		if attr&attrGreen != 0 {
			return scenicGreenCost
		}
		if attr&classMask == classArterial {
			return scenicArterialCost
		}
	}
	return 1
}

// preferredShare is the fraction of a loop's length that lies on the edges the
// preference is about. It is what the response reports, so the runner is told
// what the search actually achieved rather than what they asked for.
func (g *Graph) preferredShare(l *Loop, pref Preference) float64 {
	if l == nil || l.DistanceM <= 0 || pref == PrefNone {
		return 0
	}
	if pref == PrefCulDeSac {
		return l.stubM / l.DistanceM
	}
	preferred := 0.0
	for i := 1; i < len(l.path); i++ {
		a, b := l.path[i-1], l.path[i]
		attr, ok := g.attrBetween(a, b)
		if !ok {
			continue
		}
		match := false
		switch pref {
		case PrefQuiet:
			match = attr&classMask != classArterial
		case PrefScenic:
			match = attr&attrGreen != 0
		}
		if match {
			preferred += haversineM(g.lat[a], g.lng[a], g.lat[b], g.lng[b])
		}
	}
	return math.Min(1, preferred/l.DistanceM)
}
