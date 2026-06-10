// Package api exposes the foot graph over a tiny stdlib HTTP server: a health
// probe, a nearest-node lookup, a shortest-path route (for validating the graph
// against OSRM), and the cycle search that powers "Generate a route by distance".
//
// The server binds localhost only in production — Caddy fronts it as the
// shared-secret guard on the public port (see the Caddyfile), exactly mirroring
// the GraphHopper sidecar. No auth lives here; /health is the one route Caddy
// leaves open.
package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"math"
	"net/http"
	"strconv"

	"github.com/Absence0760/project-running/apps/graph_cycle/internal/graph"
)

// maxTargetDistanceM mirrors route_loop.ts#MAX_TARGET_DISTANCE_M (1000 km) so
// the sidecar rejects the same absurd asks the web validator does.
const maxTargetDistanceM = 1_000_000.0

// maxBodyBytes caps request bodies; these payloads are a handful of numbers.
const maxBodyBytes = 4 << 10

// Server wires the immutable graph + its stats behind the HTTP handlers.
type Server struct {
	g     *graph.Graph
	stats graph.Stats
	log   *slog.Logger
}

func New(g *graph.Graph, stats graph.Stats, log *slog.Logger) *Server {
	return &Server{g: g, stats: stats, log: log}
}

// RegisterRoutes mounts the handlers on a mux (stdlib, no router dependency).
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/nearest", s.handleNearest)
	mux.HandleFunc("/route", s.handleRoute)
	mux.HandleFunc("/cycle", s.handleCycle)
}

type point struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

func (p point) valid() bool {
	return isFinite(p.Lat) && isFinite(p.Lng) && math.Abs(p.Lat) <= 90 && math.Abs(p.Lng) <= 180
}

func isFinite(f float64) bool { return !math.IsNaN(f) && !math.IsInf(f, 0) }

// coordsJSON converts graph geometry to GeoJSON [lng, lat] pairs, the route
// builder's wire order.
func coordsJSON(cs []graph.Coord) [][2]float64 {
	out := make([][2]float64, len(cs))
	for i, c := range cs {
		out[i] = [2]float64{c.Lng, c.Lat}
	}
	return out
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ok",
		"nodes":  s.stats.Nodes,
		"edges":  s.stats.Edges,
		"ways":   s.stats.Ways,
	})
}

func (s *Server) handleNearest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	lat, err1 := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	lng, err2 := strconv.ParseFloat(r.URL.Query().Get("lng"), 64)
	p := point{Lat: lat, Lng: lng}
	if err1 != nil || err2 != nil || !p.valid() {
		http.Error(w, "invalid lat/lng", http.StatusBadRequest)
		return
	}
	idx, ok := s.g.NearestNode(lat, lng)
	if !ok {
		writeJSON(w, http.StatusOK, map[string]any{"found": false})
		return
	}
	nLat, nLng := s.g.LatLng(idx)
	writeJSON(w, http.StatusOK, map[string]any{"found": true, "lat": nLat, "lng": nLng})
}

type routeRequest struct {
	From point `json:"from"`
	To   point `json:"to"`
}

func (s *Server) handleRoute(w http.ResponseWriter, r *http.Request) {
	var req routeRequest
	if !decodeBody(w, r, &req) {
		return
	}
	if !req.From.valid() || !req.To.valid() {
		http.Error(w, "invalid from/to", http.StatusBadRequest)
		return
	}
	coords, dist, ok := s.g.ShortestPath(req.From.Lat, req.From.Lng, req.To.Lat, req.To.Lng)
	if !ok {
		writeJSON(w, http.StatusOK, map[string]any{"found": false})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"found":       true,
		"coordinates": coordsJSON(coords),
		"distanceM":   dist,
	})
}

type cycleRequest struct {
	Start           point   `json:"start"`
	TargetDistanceM float64 `json:"targetDistanceM"`
}

// loopJSON is the wire shape of one chosen/clean loop.
type loopJSON struct {
	Coordinates    [][2]float64 `json:"coordinates"`
	DistanceM      float64      `json:"distanceM"`
	AreaEfficiency float64      `json:"areaEfficiency"`
}

func loopToJSON(l *graph.Loop) *loopJSON {
	if l == nil {
		return nil
	}
	return &loopJSON{
		Coordinates:    coordsJSON(l.Coords),
		DistanceM:      l.DistanceM,
		AreaEfficiency: l.AreaEfficiency,
	}
}

func (s *Server) handleCycle(w http.ResponseWriter, r *http.Request) {
	var req cycleRequest
	if !decodeBody(w, r, &req) {
		return
	}
	if !req.Start.valid() {
		http.Error(w, "invalid start", http.StatusBadRequest)
		return
	}
	if !isFinite(req.TargetDistanceM) || req.TargetDistanceM <= 0 || req.TargetDistanceM > maxTargetDistanceM {
		http.Error(w, "invalid targetDistanceM", http.StatusBadRequest)
		return
	}

	res := s.g.SearchCycle(req.Start.Lat, req.Start.Lng, req.TargetDistanceM)
	// found=false is a first-class loop-poor signal, NOT an error: the web
	// client turns it into null and falls back to round_trip. largestClean is
	// still surfaced so a caller can show the largest achievable loop.
	resp := map[string]any{
		"found":        res.Best != nil,
		"largestClean": loopToJSON(res.LargestClean),
	}
	if res.Best != nil {
		resp["coordinates"] = coordsJSON(res.Best.Coords)
		resp["distanceM"] = res.Best.DistanceM
		resp["areaEfficiency"] = res.Best.AreaEfficiency
	}
	writeJSON(w, http.StatusOK, resp)
}

// decodeBody reads a size-capped JSON body that rejects unknown fields, writing
// a 400 and returning false on any malformation.
func decodeBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil && err != io.EOF {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
