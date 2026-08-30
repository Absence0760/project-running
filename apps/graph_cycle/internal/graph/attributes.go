package graph

// Per-directed-edge attribution, packed into a single byte: bits 0-1 hold the
// road-class bucket, bit 2 the green flag. A byte per edge rather than a struct
// per edge — a country extract carries tens of millions of directed edges, and
// an annotation the search consults must not cost more than the geometry it
// annotates (the same reasoning that drops the OSM node id, see the package
// doc). classResidential is deliberately the zero value, so a graph built
// without attribution reads as ordinary streets rather than as arterials.
const (
	classResidential uint8 = 0 // residential / living_street / service / unclassified / road
	classArterial    uint8 = 1 // tertiary and up, plus a foot=yes motorway or trunk
	classFootFirst   uint8 = 2 // footway / path / pedestrian / steps / track / cycleway
	classMask        uint8 = 0b11

	attrGreen uint8 = 1 << 2 // the edge's midpoint falls in a green occupancy cell
)

// roadClassFor buckets an OSM highway= value into the three classes a
// preference can act on: the roads a runner asks to be kept off, the
// neighbourhood streets they are indifferent to, and the car-free ways they
// would rather be on.
func roadClassFor(highway string) uint8 {
	switch highway {
	case "motorway", "motorway_link", "trunk", "trunk_link",
		"primary", "primary_link", "secondary", "secondary_link",
		"tertiary", "tertiary_link":
		return classArterial
	case "footway", "path", "pedestrian", "steps", "track", "cycleway", "bridleway", "corridor":
		return classFootFirst
	}
	return classResidential
}

// attrBetween returns the attribution of the directed edge u→v, and whether the
// two nodes are adjacent at all. Both directions of a segment carry the same
// byte, so the lookup direction does not matter.
func (g *Graph) attrBetween(u, v int32) (uint8, bool) {
	for e := g.edgeHead[u]; e < g.edgeHead[u+1]; e++ {
		if g.edgeTo[e] == v {
			return g.edgeAttr[e], true
		}
	}
	return 0, false
}

// degree is the out-degree of a node. A degree of 1 is a dead end: the only way
// out is the way in.
func (g *Graph) degree(n int32) int32 { return g.edgeHead[n+1] - g.edgeHead[n] }
