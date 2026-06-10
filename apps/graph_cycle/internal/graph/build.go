package graph

import (
	"context"
	"fmt"
	"os"
	"runtime"

	"github.com/paulmach/osm"
	"github.com/paulmach/osm/osmpbf"
)

// Stats is a small summary of a built graph, surfaced on /health and logged at
// startup so an operator can confirm the right PBF loaded.
type Stats struct {
	Nodes int `json:"nodes"`
	Edges int `json:"edges"`
	Ways  int `json:"ways"`
}

// footWhitelist is the set of OSM highway= values a pedestrian may use. It
// mirrors the intent of OSRM's foot.lua (the same profile the map-matching
// graph is built with): pedestrian-permitted ways in, motorway-class out. Kept
// deliberately generous — parks and trails are exactly what runners want, and
// over-inclusion at worst routes onto a road a runner could legally walk.
var footWhitelist = map[string]bool{
	"footway":        true,
	"path":           true,
	"pedestrian":     true,
	"steps":          true,
	"living_street":  true,
	"residential":    true,
	"service":        true,
	"unclassified":   true,
	"tertiary":       true,
	"tertiary_link":  true,
	"secondary":      true,
	"secondary_link": true,
	"primary":        true,
	"primary_link":   true,
	"track":          true,
	"road":           true,
	"cycleway":       true,
	"bridleway":      true,
	"corridor":       true,
}

// footBlacklist is the set of highway= values a pedestrian may never use,
// regardless of other tags — motorway-class roads and non-routable placeholders.
var footBlacklist = map[string]bool{
	"motorway":      true,
	"motorway_link": true,
	"trunk":         true,
	"trunk_link":    true,
	"construction":  true,
	"proposed":      true,
	"raceway":       true,
	"bus_guideway":  true,
}

// footAllowed decides whether a way is foot-routable from its tags. An explicit
// foot= tag wins over the highway class either way; otherwise the highway must
// be whitelisted and not access-restricted.
func footAllowed(tags osm.Tags) bool {
	highway := tags.Find("highway")
	if highway == "" {
		return false
	}
	// Non-routable placeholders are never walkable, even with foot=yes — OSRM's
	// foot.lua has no speed-table entry for them at all, so a pedestrian-detour
	// foot tag on a construction site must NOT route through it. This precedes
	// the foot= override (which legitimately lets foot=yes onto a motorway/trunk).
	if highway == "construction" || highway == "proposed" {
		return false
	}
	switch tags.Find("foot") {
	case "no", "private":
		return false
	case "yes", "designated", "permissive", "destination":
		return true
	}
	if footBlacklist[highway] {
		return false
	}
	switch tags.Find("access") {
	case "no", "private":
		return false
	}
	return footWhitelist[highway]
}

// Build parses an OSM PBF at `path` into a foot-routable Graph. Two passes over
// the file: the first reads ways (foot-filtered) to learn which node ids the
// graph needs; the second reads only those nodes' coordinates. This keeps the
// coordinate map to the foot network rather than every node in the extract.
func Build(path string) (*Graph, Stats, error) {
	refs, keptWays, err := scanWays(path)
	if err != nil {
		return nil, Stats{}, err
	}
	coords, err := scanNodes(path, refs)
	if err != nil {
		return nil, Stats{}, err
	}

	b := newBuilder()
	for _, w := range keptWays {
		var prev int64 = -1
		var prevOK bool
		for _, id := range w {
			c, ok := coords[id]
			if ok {
				b.addNode(id, c)
			}
			if prevOK && ok {
				b.addSegment(prev, id)
			}
			prev, prevOK = id, ok
		}
	}
	g := b.finalize()
	return g, Stats{Nodes: g.NumNodes(), Edges: g.NumEdges(), Ways: len(keptWays)}, nil
}

// scanWays reads only ways, returning the set of node ids referenced by
// foot-routable ways and those ways' node-id sequences.
func scanWays(path string) (map[int64]struct{}, [][]int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, fmt.Errorf("open pbf: %w", err)
	}
	defer f.Close()

	scanner := osmpbf.New(context.Background(), f, runtime.NumCPU())
	scanner.SkipNodes = true
	scanner.SkipRelations = true
	defer scanner.Close()

	refs := make(map[int64]struct{})
	var keptWays [][]int64
	for scanner.Scan() {
		w, ok := scanner.Object().(*osm.Way)
		if !ok || !footAllowed(w.Tags) {
			continue
		}
		ids := make([]int64, 0, len(w.Nodes))
		for _, wn := range w.Nodes {
			id := int64(wn.ID)
			ids = append(ids, id)
			refs[id] = struct{}{}
		}
		if len(ids) >= 2 {
			keptWays = append(keptWays, ids)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, nil, fmt.Errorf("scan ways: %w", err)
	}
	return refs, keptWays, nil
}

// scanNodes reads only nodes, keeping coordinates for the referenced set.
func scanNodes(path string, refs map[int64]struct{}) (map[int64]Coord, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open pbf: %w", err)
	}
	defer f.Close()

	scanner := osmpbf.New(context.Background(), f, runtime.NumCPU())
	scanner.SkipWays = true
	scanner.SkipRelations = true
	defer scanner.Close()

	coords := make(map[int64]Coord, len(refs))
	for scanner.Scan() {
		n, ok := scanner.Object().(*osm.Node)
		if !ok {
			continue
		}
		id := int64(n.ID)
		if _, want := refs[id]; want {
			coords[id] = Coord{Lng: n.Lon, Lat: n.Lat}
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan nodes: %w", err)
	}
	return coords, nil
}

// builder accumulates nodes and undirected segments, deduping each, then emits
// an immutable CSR Graph. Shared by Build (from a PBF) and the unit tests (which
// construct small graphs by hand).
type builder struct {
	idx      map[int64]int32
	lat, lng []float64
	segFrom  []int32
	segTo    []int32
	segLen   []float32
	seenSeg  map[uint64]struct{}
}

func newBuilder() *builder {
	return &builder{idx: make(map[int64]int32), seenSeg: make(map[uint64]struct{})}
}

func (b *builder) addNode(id int64, c Coord) int32 {
	if i, ok := b.idx[id]; ok {
		return i
	}
	i := int32(len(b.lat))
	b.idx[id] = i
	b.lat = append(b.lat, c.Lat)
	b.lng = append(b.lng, c.Lng)
	return i
}

func (b *builder) addSegment(idA, idB int64) {
	a, okA := b.idx[idA]
	c, okC := b.idx[idB]
	if !okA || !okC || a == c {
		return
	}
	key := edgeKey(a, c)
	if _, dup := b.seenSeg[key]; dup {
		return
	}
	b.seenSeg[key] = struct{}{}
	b.segFrom = append(b.segFrom, a)
	b.segTo = append(b.segTo, c)
	length := haversineM(b.lat[a], b.lng[a], b.lat[c], b.lng[c])
	b.segLen = append(b.segLen, float32(length))
}

// finalize converts the accumulated undirected segments into a directed CSR
// adjacency (each segment becomes two directed edges) and builds the spatial
// index.
func (b *builder) finalize() *Graph {
	n := len(b.lat)
	degree := make([]int32, n)
	for i := range b.segFrom {
		degree[b.segFrom[i]]++
		degree[b.segTo[i]]++
	}
	edgeHead := make([]int32, n+1)
	for i := 0; i < n; i++ {
		edgeHead[i+1] = edgeHead[i] + degree[i]
	}
	total := edgeHead[n]
	edgeTo := make([]int32, total)
	edgeLen := make([]float32, total)
	cursor := make([]int32, n)
	copy(cursor, edgeHead[:n])
	put := func(from, to int32, length float32) {
		pos := cursor[from]
		edgeTo[pos] = to
		edgeLen[pos] = length
		cursor[from]++
	}
	for i := range b.segFrom {
		from, to, length := b.segFrom[i], b.segTo[i], b.segLen[i]
		put(from, to, length)
		put(to, from, length)
	}
	g := &Graph{
		lat:      b.lat,
		lng:      b.lng,
		edgeHead: edgeHead,
		edgeTo:   edgeTo,
		edgeLen:  edgeLen,
	}
	g.grid = buildGrid(b.lat, b.lng)
	return g
}
