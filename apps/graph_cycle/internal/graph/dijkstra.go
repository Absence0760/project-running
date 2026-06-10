package graph

import "container/heap"

// dijkstra runs a single-source shortest-path search over the foot graph.
//
// It is SPARSE: distances and predecessors live in maps keyed only by the nodes
// the search actually touches, not by the whole graph. The cycle search caps
// every search to a radius around the start (≈ the target loop length), so a
// search over a country-scale graph still only allocates for the few thousand
// nodes inside that radius — running ~36 of them per request stays cheap.
//
// penalised edges (canonical undirected keys) have their traversal cost
// multiplied by reusePenalty. This is the P0 finding made concrete: the return
// leg of a loop must be DISCOURAGED from reusing the outbound roads (otherwise
// the loop degenerates to an out-and-back), but in a bottlenecked sparse network
// strict removal can disconnect the return entirely — so we penalise rather than
// forbid, letting the search reuse a lone connector only when it has no choice.
//
//   - src:        start node index.
//   - target:     stop early once this node is settled; -1 builds the full tree
//     out to maxRadiusM.
//   - maxRadiusM: never relax an edge that would put a node beyond this many
//     TRUE metres from src. The cap is on real distance, NOT penalised cost — a
//     penalised return leg accrues ×reusePenalty cost, and capping on that would
//     silently FORBID reuse (prune a real loop) instead of merely discouraging
//     it, defeating the whole point of penalised reuse.
//   - penalised:  undirected keys whose cost is scaled; nil for an unpenalised
//     search.
//
// Returns the (penalised) distance map and predecessor map. A node absent from
// distTo was not reached within the cap. For an unpenalised search the penalised
// distance equals the real distance, so distTo is exact real metres (the forward
// far-point search relies on this).
func (g *Graph) dijkstra(src, target int32, maxRadiusM float64, penalised map[uint64]struct{}) (distTo map[int32]float64, prev map[int32]int32) {
	distTo = map[int32]float64{src: 0}
	prev = map[int32]int32{src: -1}
	settled := map[int32]struct{}{}

	pq := &nodeHeap{{node: src, dist: 0, real: 0}}
	for pq.Len() > 0 {
		top := heap.Pop(pq).(heapItem)
		u := top.node
		if _, done := settled[u]; done {
			continue
		}
		settled[u] = struct{}{}
		if u == target {
			return distTo, prev
		}
		du := top.dist
		duReal := top.real

		start := g.edgeHead[u]
		end := g.edgeHead[u+1]
		for e := start; e < end; e++ {
			v := g.edgeTo[e]
			realW := float64(g.edgeLen[e])
			w := realW
			if penalised != nil {
				if _, p := penalised[edgeKey(u, v)]; p {
					w *= reusePenalty
				}
			}
			ndReal := duReal + realW
			if ndReal > maxRadiusM {
				continue // bound exploration by real geographic extent
			}
			nd := du + w
			if old, ok := distTo[v]; !ok || nd < old {
				distTo[v] = nd
				prev[v] = u
				heap.Push(pq, heapItem{node: v, dist: nd, real: ndReal})
			}
		}
	}
	return distTo, prev
}

// reconstruct walks prev from dst back to src, returning the node-index path in
// forward order (src first, dst last). Returns nil if dst has no path.
func reconstruct(prev map[int32]int32, src, dst int32) []int32 {
	if _, ok := prev[dst]; !ok {
		return nil
	}
	var rev []int32
	for at := dst; at != -1; {
		rev = append(rev, at)
		if at == src {
			break
		}
		p, ok := prev[at]
		if !ok {
			return nil
		}
		at = p
	}
	if len(rev) == 0 || rev[len(rev)-1] != src {
		return nil
	}
	for i, j := 0, len(rev)-1; i < j; i, j = i+1, j-1 {
		rev[i], rev[j] = rev[j], rev[i]
	}
	return rev
}

// heapItem / nodeHeap is a tiny binary min-heap on tentative distance. A plain
// container/heap keeps the dependency surface at stdlib.
type heapItem struct {
	node int32
	dist float64 // penalised tentative cost — the priority key
	real float64 // true metres along this path — used only for the radius cap
}

type nodeHeap []heapItem

func (h nodeHeap) Len() int           { return len(h) }
func (h nodeHeap) Less(i, j int) bool { return h[i].dist < h[j].dist }
func (h nodeHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *nodeHeap) Push(x any)        { *h = append(*h, x.(heapItem)) }
func (h *nodeHeap) Pop() any {
	old := *h
	n := len(old)
	it := old[n-1]
	*h = old[:n-1]
	return it
}
