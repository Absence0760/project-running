package internal

// Matcher decouples the worker loop from the engine choice. The
// roadmap calls for evaluating Valhalla Meili / OSRM / GraphHopper
// before committing — none of those are wired in yet, so this package
// ships a passthrough implementation that proves the pipeline
// end-to-end (claim → download → match → upload → finish) without
// pretending to align points to roads. Replace with a real engine
// when the choice is made; the interface should be stable.
type Matcher interface {
	// Algorithm returns the engine identifier persisted on the
	// run_matched_tracks row. Pick something stable: callers will
	// re-match when the algorithm changes, so renaming an existing
	// implementation forces a re-match across the whole table.
	Algorithm() string

	// Version is bumped when the same engine produces different
	// output (engine upgrade, parameter retune, etc.). Pairs with
	// Algorithm to form the re-match key.
	Version() string

	// Match consumes a raw GPS track and returns the matched track.
	// Implementations must not mutate the input slice. Returning a
	// nil / empty slice with a nil error is interpreted as "no
	// matchable points" and writes status='skipped' on the row.
	Match(points []TrackPoint) ([]TrackPoint, error)
}

// PassthroughMatcher copies the input track without transformation.
// First-cut shim until a real engine is selected. Useful as a smoke
// test that the rest of the pipeline (claim, storage I/O, row write,
// finish_job) is wired correctly — pointing the worker at a real
// engine after this is the swap-in.
type PassthroughMatcher struct{}

func (PassthroughMatcher) Algorithm() string { return "passthrough" }
func (PassthroughMatcher) Version() string   { return "v1" }

func (PassthroughMatcher) Match(points []TrackPoint) ([]TrackPoint, error) {
	if len(points) == 0 {
		return nil, nil
	}
	out := make([]TrackPoint, len(points))
	copy(out, points)
	return out, nil
}
