package internal

import (
	"encoding/json"
	"time"
)

// Job is the row shape returned by claim_next_job. The function returns
// (id, kind, payload, attempts) — we don't need the rest of the row for
// the handler path.
type Job struct {
	ID       int64           `json:"id"`
	Kind     string          `json:"kind"`
	Payload  json.RawMessage `json:"payload"`
	Attempts int16           `json:"attempts"`
}

// MapMatchPayload is the payload shape the runs trigger writes for
// kind='map_match'. Defined in
// apps/backend/supabase/migrations/20260609_001_run_match_pipeline.sql.
type MapMatchPayload struct {
	RunID  string `json:"run_id"`
	UserID string `json:"user_id"`
}

// TrackPoint mirrors the Dart / TypeScript TrackPoint shape uploaded by
// every recorder. The watch_wear and mobile recorders write
// {lat, lng, ele, ts}; older imports may omit ele or ts.
type TrackPoint struct {
	Lat       float64    `json:"lat"`
	Lng       float64    `json:"lng"`
	Elevation *float64   `json:"ele,omitempty"`
	Timestamp *time.Time `json:"ts,omitempty"`
}

// MatchOutput is what a Matcher hands back to the worker. The matched
// track is uploaded under matched_track_url; the algorithm name + version
// land on the run_matched_tracks row so re-matching can be triggered
// when the engine improves.
type MatchOutput struct {
	Points           []TrackPoint
	Algorithm        string
	AlgorithmVersion string
}

// MatchedTrackRow is the subset of run_matched_tracks the worker writes
// after a successful match. PATCH'd via PostgREST.
type MatchedTrackRow struct {
	Status            string     `json:"status"`
	MatchedTrackURL   string     `json:"matched_track_url"`
	MatchedAt         *time.Time `json:"matched_at,omitempty"`
	Algorithm         string     `json:"algorithm"`
	AlgorithmVersion  string     `json:"algorithm_version"`
	ErrorMessage      *string    `json:"error_message"`
}

// RouteMatchCandidate is a row returned by the
// routes_intersecting_track RPC (migration 20260610_001). Same shape
// as the Dart core_models class — keeping the names in sync helps
// when the worker logs hint at a client-side discrepancy.
type RouteMatchCandidate struct {
	ID            string  `json:"id"`
	Name          string  `json:"name"`
	DistanceM     float64 `json:"distance_m"`
	StartOffsetM  float64 `json:"start_offset_m"`
	EndOffsetM    float64 `json:"end_offset_m"`
}
