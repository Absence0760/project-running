// Package api exposes the foot graph over a tiny stdlib HTTP server: a health
// probe, a nearest-node lookup, a shortest-path route (for validating the graph
// against OSRM), and the cycle search that powers "Generate a route by distance".
//
// The server binds the public Fly port directly and enforces the X-Engine-Key
// shared-secret guard in-process (Guard, guard.go) — no Caddy sidecar, unlike
// the Java GraphHopper app. /health is the one route the guard leaves open.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/Absence0760/project-running/apps/graph_cycle/internal/graph"
)

// maxTargetDistanceM bounds the cycle search's per-request cost. The web
// validator allows up to 1000 km (route_loop.ts), but the search radius — and
// thus the Dijkstra exploration on a country-scale graph — scales with the
// target, so the sidecar caps far lower: 100 km is already an unrealistically
// large neighbourhood loop, and a larger ask harmlessly falls back to round_trip.
const maxTargetDistanceM = 100_000.0

// maxBodyBytes caps request bodies; these payloads are a handful of numbers.
const maxBodyBytes = 4 << 10

// defaultSearchTimeout bounds one search on the SERVER's clock.
//
// Until it existed the only bound was the caller's: r.Context() is cancelled
// when the client goes away, and nothing else stopped a Dijkstra. That leaves
// two holes. main.go's WriteTimeout is 30 s and does NOT cancel the handler
// context — Go only fails the connection write — so a search running past it
// burns a core producing a response no one can receive. And a caller that holds
// the connection open (a wedged Lambda behind a proxy, or anyone who has the
// shared key: the endpoint is public, decisions §575) pins that core for as
// long as it likes.
//
// 20 s leaves headroom under the 30 s WriteTimeout so the refusal below can
// actually be written, and sits well past the web client's own 8 s
// AbortController budget, so in normal operation the caller still gives up
// first and this never fires.
const defaultSearchTimeout = 20 * time.Second

// Server wires the immutable graph + its stats behind the HTTP handlers.
type Server struct {
	g     *graph.Graph
	stats graph.Stats
	log   *slog.Logger

	// SearchTimeout bounds one /cycle or /route search. Zero uses
	// defaultSearchTimeout; tests set it small to prove the bound exists.
	SearchTimeout time.Duration
}

func (s *Server) searchTimeout() time.Duration {
	if s.SearchTimeout > 0 {
		return s.SearchTimeout
	}
	return defaultSearchTimeout
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
	ctx, cancel := context.WithTimeout(r.Context(), s.searchTimeout())
	defer cancel()
	coords, dist, ok := s.g.ShortestPath(ctx, req.From.Lat, req.From.Lng, req.To.Lat, req.To.Lng)
	if ctx.Err() != nil {
		s.abandoned(ctx, w, "route")
		return
	}
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
	// Optional route-design preference. An unrecognised value is dropped
	// silently rather than rejected — a stale knob on an older client must not
	// be able to deny route generation.
	Preference string `json:"preference"`
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

	ctx, cancel := context.WithTimeout(r.Context(), s.searchTimeout())
	defer cancel()
	res := s.g.SearchCycle(ctx, req.Start.Lat, req.Start.Lng, req.TargetDistanceM, graph.ParsePreference(req.Preference))
	// An abandoned search must NOT come back as found=false. That flag is a
	// product claim — "this neighbourhood has no loop", which the client turns
	// into "the best loop near you is ~X km" — and a search that simply ran out
	// of clock has established nothing about the neighbourhood. A refusal is
	// what the client's own GraphCycleError path is for: it falls back to
	// round_trip either way, but with the reason intact.
	if ctx.Err() != nil {
		s.abandoned(ctx, w, "cycle")
		return
	}
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
		// Reported only when a preference was actually honoured — a request
		// served by the unweighted retry says nothing, so the client can show
		// the runner what they got rather than what they asked for.
		if res.Applied != graph.PrefNone {
			resp["preferenceApplied"] = res.Applied.String()
			resp["preferenceShare"] = res.PreferredShare
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

// abandoned answers a search that did not finish. A server-side deadline is a
// 503 (come back later, the graph is fine); a caller who went away gets a 499
// nobody reads, logged so a wedged client is visible in the machine's logs
// rather than looking like a loop-poor region.
func (s *Server) abandoned(ctx context.Context, w http.ResponseWriter, route string) {
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		s.log.Warn("search exceeded its deadline", "route", route, "timeout", s.searchTimeout().String())
		http.Error(w, "search timed out", http.StatusServiceUnavailable)
		return
	}
	s.log.Info("search abandoned by the caller", "route", route)
	w.WriteHeader(499)
}

// decodeBody reads a size-capped JSON body that rejects unknown fields, writing
// a 400 and returning false on any malformation. An EMPTY body is rejected too:
// decoding it into the zero-value struct would otherwise sail through as
// {start:{0,0}, target:0} and only fail later (or, on /route, silently route
// null-island→null-island). Requiring a real object keeps the failure honest.
func decodeBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		// io.EOF == empty body; any other error is malformed JSON / oversize /
		// unknown field. All are a 400.
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return false
	}
	// A stream carrying a SECOND value is not the one object this endpoint
	// takes. Decode stops at the first, so `{...}{...}` used to be accepted with
	// the tail silently discarded — which is exactly the laxness
	// DisallowUnknownFields above exists to refuse.
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
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
