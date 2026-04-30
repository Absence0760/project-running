package internal

import (
	"testing"
)

func TestPassthroughMatcher_PreservesTrack(t *testing.T) {
	m := PassthroughMatcher{}
	in := []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	out, err := m.Match(in)
	if err != nil {
		t.Fatal(err)
	}
	if len(out) != len(in) {
		t.Fatalf("len out=%d, want %d", len(out), len(in))
	}
	for i := range in {
		if out[i] != in[i] {
			t.Errorf("point %d: got %+v, want %+v", i, out[i], in[i])
		}
	}
	// Mutating the output must not mutate the input — interface
	// contract.
	out[0].Lat = 99
	if in[0].Lat == 99 {
		t.Errorf("matcher returned aliased slice; input was mutated")
	}
}

func TestPassthroughMatcher_EmptyTrack(t *testing.T) {
	out, err := PassthroughMatcher{}.Match(nil)
	if err != nil {
		t.Fatal(err)
	}
	if out != nil {
		t.Errorf("empty input should return nil, got %v", out)
	}
}

func TestPassthroughMatcher_AlgorithmAndVersion(t *testing.T) {
	m := PassthroughMatcher{}
	if m.Algorithm() != "passthrough" {
		t.Errorf("algorithm=%q", m.Algorithm())
	}
	if m.Version() != "v1" {
		t.Errorf("version=%q", m.Version())
	}
}
