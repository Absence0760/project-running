// Package graph is an in-memory, foot-routable street graph built from an OSM
// PBF, plus the disjoint-path cycle search that powers the "Generate a route by
// distance" loop generator (docs/features/graph_cycle_loop_generation.md, v3).
//
// Nodes are OSM nodes referenced by at least one foot-permitted way; directed
// edges connect consecutive nodes along those ways in BOTH directions (foot
// routing ignores oneway). Indices are dense int32 and adjacency is stored CSR
// (compressed sparse row) so Dijkstra stays cache-friendly on a country-scale
// graph. The original OSM node id is not retained — nothing downstream needs
// it, and dropping it halves the per-node footprint.
package graph

import "math"

// Graph is immutable after Build. All routing reads it concurrently without
// locking.
type Graph struct {
	lat []float64 // per node index
	lng []float64

	// CSR adjacency: the out-edges of node i are the half-open range
	// [edgeHead[i], edgeHead[i+1]) into edgeTo / edgeLen. edgeHead has
	// len(nodes)+1 entries.
	edgeHead []int32
	edgeTo   []int32
	edgeLen  []float32 // metres

	grid *grid // spatial index for NearestNode
}

// NumNodes returns the node count.
func (g *Graph) NumNodes() int { return len(g.lat) }

// NumEdges returns the directed-edge count (each undirected segment is stored
// twice, once per direction).
func (g *Graph) NumEdges() int { return len(g.edgeTo) }

// coordOf returns the [lng, lat] of a node index.
func (g *Graph) coordOf(i int32) Coord { return Coord{Lng: g.lng[i], Lat: g.lat[i]} }

// edgeKey is the canonical undirected key for the segment between two node
// indices: the unordered pair packed into a uint64 (smaller index in the high
// 32 bits). The disjoint-path search penalises segments by this key so both
// travel directions of a reused road are discouraged on the return leg.
func edgeKey(a, b int32) uint64 {
	if a > b {
		a, b = b, a
	}
	return uint64(uint32(a))<<32 | uint64(uint32(b))
}

// degrees-per-metre helpers for the spatial grid cell sizing.
func metresToDegLat(m float64) float64 { return m / mPerDegLat }
func metresToDegLng(m, atLat float64) float64 {
	c := math.Cos(atLat * math.Pi / 180)
	if c < 1e-6 {
		c = 1e-6
	}
	return m / (mPerDegLat * c)
}
