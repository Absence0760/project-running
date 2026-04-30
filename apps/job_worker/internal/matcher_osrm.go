package internal

// OSRMMatcher: real map matching via the OSRM `/match/v1/foot`
// endpoint. Replaces PassthroughMatcher whenever the worker has an
// OSRM_URL configured. The interface stays the same — the worker
// loop, the run_matched_tracks write path, the auto-link step are
// all engine-agnostic; only the geometry transformation changes.
//
// Why /match and not /route: OSRM's match service runs an HMM over a
// noisy GPS track and snaps each input point to the nearest plausible
// road segment, weighted by movement consistency. /route picks one
// fastest path between A and B and ignores the points in between.
// For a 5 km run with 1500 GPS samples, /match is the only sensible
// choice.
//
// Profile is hard-coded to `foot` because the graph is built with
// foot.lua (see the OSRM Makefile). Bicycle / car profiles would need
// their own graphs and a different default in the URL — different
// engine, different deploy.
//
// Error model:
//   * Network / 5xx → returned as an error so the worker's transient
//     classifier defers the job.
//   * 200 with `code != "Ok"` → matched empty: the engine couldn't
//     align the track. We treat that as a *non-failure* by returning
//     an empty slice; handleMapMatch then writes `status='skipped'`
//     rather than wedging the run as 'failed'.

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// OSRMMatcher calls a self-hosted OSRM `osrm-routed` server. baseURL
// is the root, e.g., "http://127.0.0.1:5000". Algorithm + version
// strings get persisted onto run_matched_tracks so future re-matches
// (engine upgrade, different graph build) can be triggered when one
// changes.
type OSRMMatcher struct {
	BaseURL    string
	HTTPClient *http.Client
	// ChunkSize is the max number of points per /match call. OSRM's
	// default URL length cap chokes on 200+ point tracks, and the
	// engine's HMM gets noisy beyond ~100 points anyway. Chunked
	// matches preserve resolution; the worker stitches them back
	// together. Defaults to 100 if zero.
	ChunkSize int
	// Version: bumped when the engine itself changes (image tag
	// upgrade, profile retune). Pairs with Algorithm to form the
	// re-match key on run_matched_tracks.
	AlgVersion string
}

// NewOSRMMatcher constructs the default-configured matcher. Caller
// supplies the URL; everything else takes a sane default. The HTTP
// client gets a timeout because long matches under load can otherwise
// pin a worker to a single job for minutes.
func NewOSRMMatcher(baseURL string) *OSRMMatcher {
	return &OSRMMatcher{
		BaseURL:    strings.TrimRight(baseURL, "/"),
		HTTPClient: &http.Client{Timeout: 60 * time.Second},
		ChunkSize:  100,
		AlgVersion: "v1",
	}
}

func (m *OSRMMatcher) Algorithm() string { return "osrm" }
func (m *OSRMMatcher) Version() string {
	if m.AlgVersion == "" {
		return "v1"
	}
	return m.AlgVersion
}

// Match runs each chunk through OSRM's /match endpoint and stitches
// the snapped tracepoints back together. Empty input → empty output;
// failed match (engine returned no usable tracepoints) → empty output
// so handleMapMatch writes `skipped`.
func (m *OSRMMatcher) Match(points []TrackPoint) ([]TrackPoint, error) {
	if len(points) < 2 {
		return nil, nil
	}
	chunkSize := m.ChunkSize
	if chunkSize <= 0 {
		chunkSize = 100
	}

	out := make([]TrackPoint, 0, len(points))
	for start := 0; start < len(points); start += chunkSize {
		end := start + chunkSize
		if end > len(points) {
			end = len(points)
		}
		chunk := points[start:end]
		if len(chunk) < 2 {
			// Tail of 1 point left over from the chunking. /match
			// requires 2+. Carry the original through verbatim so
			// the matched track ends where the raw track ends.
			out = append(out, chunk...)
			continue
		}
		matched, err := m.matchChunk(chunk)
		if err != nil {
			return nil, err
		}
		out = append(out, matched...)
	}
	if len(out) < 2 {
		// Engine couldn't match anything actionable. Caller treats
		// this as a skip rather than a failure.
		return nil, nil
	}
	return out, nil
}

func (m *OSRMMatcher) matchChunk(chunk []TrackPoint) ([]TrackPoint, error) {
	// OSRM's URL format: /match/v1/{profile}/{lng,lat;lng,lat;...}
	// Coordinates are lng-first, semicolon-separated. Building the
	// path manually avoids URL-encoding overhead on a hot path.
	var sb strings.Builder
	sb.WriteString(m.BaseURL)
	sb.WriteString("/match/v1/foot/")
	for i, p := range chunk {
		if i > 0 {
			sb.WriteByte(';')
		}
		fmt.Fprintf(&sb, "%.6f,%.6f", p.Lng, p.Lat)
	}
	// `geometries=geojson` so we get GeoJSON LineStrings out
	// (lng/lat arrays we can read with one parse). `overview=full`
	// means every input point gets a snapped output. `tidy=true`
	// asks OSRM to drop redundant adjacent points the engine
	// considers noise — leaves the resulting line cleaner.
	sb.WriteString("?geometries=geojson&overview=full&tidy=true")

	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, sb.String(), nil)
	if err != nil {
		return nil, err
	}
	resp, err := m.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		// Surface the OSRM error verbatim — it's small JSON like
		// `{"code":"InvalidUrl","message":"URL is invalid"}`. The
		// worker's transient classifier picks up 5xx as defer-worthy.
		return nil, &HTTPError{StatusCode: resp.StatusCode, Body: string(body)}
	}

	var resp2 osrmMatchResponse
	if err := json.Unmarshal(body, &resp2); err != nil {
		return nil, fmt.Errorf("decode osrm response: %w", err)
	}
	// `code != "Ok"` → engine didn't find a sufficiently confident
	// alignment. Surface as empty so handleMapMatch writes 'skipped'
	// rather than failing the run.
	if resp2.Code != "Ok" || len(resp2.Matchings) == 0 {
		return nil, nil
	}

	// Concatenate every matching's coordinates. Most tracks return
	// one matching; a route that gets split by a tunnel gap can
	// return two or three. Order is preserved by OSRM.
	out := make([]TrackPoint, 0, len(chunk))
	for _, mtg := range resp2.Matchings {
		for _, c := range mtg.Geometry.Coordinates {
			if len(c) < 2 {
				continue
			}
			out = append(out, TrackPoint{Lng: c[0], Lat: c[1]})
		}
	}
	return out, nil
}

// osrmMatchResponse is the subset of OSRM's /match response we read.
// Schema is documented at https://project-osrm.org/docs/v5.24.0/api/#match-service.
// Tracepoint metadata (alternatives_count, distance, location) is
// available but not used today; if the matcher ever grows confidence
// scoring this is where it'd land.
type osrmMatchResponse struct {
	Code      string `json:"code"`
	Matchings []struct {
		Confidence float64 `json:"confidence"`
		Geometry   struct {
			Coordinates [][]float64 `json:"coordinates"` // [lng, lat]
		} `json:"geometry"`
	} `json:"matchings"`
}
