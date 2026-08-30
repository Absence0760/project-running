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

// footWay is one kept way: its node-id sequence and the road-class bucket every
// segment along it inherits.
type footWay struct {
	nodes []int64
	class uint8
}

// wayScan is what one pass over the PBF's ways yields: the foot-routable ways
// with their road class, the green-space ways the scenic attribution needs, and
// the node ids each set references. The two sets stay separate so the green
// coordinates can be released before the graph itself is allocated.
type wayScan struct {
	refs      map[int64]struct{}
	greenRefs map[int64]struct{}
	kept      []footWay
	green     [][]int64
}

// Build parses an OSM PBF at `path` into a foot-routable Graph. Two passes over
// the file: the first reads ways (foot-filtered, plus the green-space areas) to
// learn which node ids are needed; the second reads only those nodes'
// coordinates. This keeps the coordinate map to the foot network rather than
// every node in the extract.
func Build(path string) (*Graph, Stats, error) {
	ws, err := scanWays(path)
	if err != nil {
		return nil, Stats{}, err
	}
	coords, greenCoords, err := scanNodes(path, ws.refs, ws.greenRefs)
	if err != nil {
		return nil, Stats{}, err
	}

	gg := newGreenGrid(greenCoords)
	for _, w := range ws.green {
		pts := make([]Coord, 0, len(w))
		for _, id := range w {
			if c, ok := greenCoords[id]; ok {
				pts = append(pts, c)
			}
		}
		gg.markWay(pts, len(w) > 2 && w[0] == w[len(w)-1])
	}
	// The occupancy raster is all that is wanted from the green geometry, and
	// the builder below is the run's peak allocation. greenCoords needs no
	// help — liveness analysis stops treating an unread local as a GC root —
	// but ws stays live for ws.kept, and liveness is per variable, not per
	// field, so the polygons would be held across the whole build.
	ws.green = nil

	b := newBuilder()
	for _, w := range ws.kept {
		var prev int64 = -1
		var prevOK bool
		for _, id := range w.nodes {
			c, ok := coords[id]
			if ok {
				b.addNode(id, c)
			}
			if prevOK && ok {
				p := coords[prev]
				attr := w.class
				if gg.contains((p.Lat+c.Lat)/2, (p.Lng+c.Lng)/2) {
					attr |= attrGreen
				}
				b.addSegment(prev, id, attr)
			}
			prev, prevOK = id, ok
		}
	}
	g := b.finalize()
	return g, Stats{Nodes: g.NumNodes(), Edges: g.NumEdges(), Ways: len(ws.kept)}, nil
}

// scanWays reads only ways, collecting the foot-routable ones with their road
// class and the green-space areas, plus the node ids each references. Both are
// taken in the SAME pass — the file is already streaming every way, so a
// separate pass for green space would double the parse for nothing.
func scanWays(path string) (wayScan, error) {
	f, err := os.Open(path)
	if err != nil {
		return wayScan{}, fmt.Errorf("open pbf: %w", err)
	}
	defer f.Close()

	scanner := osmpbf.New(context.Background(), f, runtime.NumCPU())
	scanner.SkipNodes = true
	scanner.SkipRelations = true
	defer scanner.Close()

	out := wayScan{refs: make(map[int64]struct{}), greenRefs: make(map[int64]struct{})}
	for scanner.Scan() {
		w, ok := scanner.Object().(*osm.Way)
		if !ok {
			continue
		}
		if greenWay(w.Tags) {
			ids := make([]int64, 0, len(w.Nodes))
			for _, wn := range w.Nodes {
				id := int64(wn.ID)
				ids = append(ids, id)
				out.greenRefs[id] = struct{}{}
			}
			if len(ids) >= 2 {
				out.green = append(out.green, ids)
			}
			continue
		}
		if !footAllowed(w.Tags) {
			continue
		}
		ids := make([]int64, 0, len(w.Nodes))
		for _, wn := range w.Nodes {
			id := int64(wn.ID)
			ids = append(ids, id)
			out.refs[id] = struct{}{}
		}
		if len(ids) >= 2 {
			out.kept = append(out.kept, footWay{nodes: ids, class: roadClassFor(w.Tags.Find("highway"))})
		}
	}
	if err := scanner.Err(); err != nil {
		return wayScan{}, fmt.Errorf("scan ways: %w", err)
	}
	return out, nil
}

// scanNodes reads only nodes, keeping coordinates for the two referenced sets.
func scanNodes(path string, refs, greenRefs map[int64]struct{}) (coords, greenCoords map[int64]Coord, err error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, fmt.Errorf("open pbf: %w", err)
	}
	defer f.Close()

	scanner := osmpbf.New(context.Background(), f, runtime.NumCPU())
	scanner.SkipWays = true
	scanner.SkipRelations = true
	defer scanner.Close()

	coords = make(map[int64]Coord, len(refs))
	greenCoords = make(map[int64]Coord, len(greenRefs))
	for scanner.Scan() {
		n, ok := scanner.Object().(*osm.Node)
		if !ok {
			continue
		}
		id := int64(n.ID)
		c := Coord{Lng: n.Lon, Lat: n.Lat}
		if _, want := refs[id]; want {
			coords[id] = c
		}
		if _, want := greenRefs[id]; want {
			greenCoords[id] = c
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, nil, fmt.Errorf("scan nodes: %w", err)
	}
	return coords, greenCoords, nil
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
	segAttr  []uint8
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

func (b *builder) addSegment(idA, idB int64, attr uint8) {
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
	b.segAttr = append(b.segAttr, attr)
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
	edgeAttr := make([]uint8, total)
	cursor := make([]int32, n)
	copy(cursor, edgeHead[:n])
	put := func(from, to int32, length float32, attr uint8) {
		pos := cursor[from]
		edgeTo[pos] = to
		edgeLen[pos] = length
		edgeAttr[pos] = attr
		cursor[from]++
	}
	for i := range b.segFrom {
		from, to, length, attr := b.segFrom[i], b.segTo[i], b.segLen[i], b.segAttr[i]
		put(from, to, length, attr)
		put(to, from, length, attr)
	}
	g := &Graph{
		lat:      b.lat,
		lng:      b.lng,
		edgeHead: edgeHead,
		edgeTo:   edgeTo,
		edgeLen:  edgeLen,
		edgeAttr: edgeAttr,
	}
	g.grid = buildGrid(b.lat, b.lng)
	return g
}
