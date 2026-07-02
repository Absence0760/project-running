package internal

import (
	"testing"
	"time"
)

func ms(iso string) int64 {
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		panic(err)
	}
	return t.UnixMilli()
}

func TestIsCrossProviderDuplicate(t *testing.T) {
	existing := []RunIdentity{
		{StartedAtMs: ms("2026-01-01T09:00:00Z"), DistanceM: 10000},
	}

	cases := []struct {
		name      string
		candidate RunIdentity
		existing  []RunIdentity
		want      bool
	}{
		{
			name:      "exact same start + distance matches",
			candidate: RunIdentity{StartedAtMs: ms("2026-01-01T09:00:00Z"), DistanceM: 10000},
			existing:  existing,
			want:      true,
		},
		{
			// A Garmin watch auto-uploaded to Strava, re-imported from a
			// Garmin ZIP: same effort, small start + distance drift.
			name:      "same effort across providers (start + distance drift) matches",
			candidate: RunIdentity{StartedAtMs: ms("2026-01-01T09:02:00Z"), DistanceM: 10300},
			existing:  existing,
			want:      true,
		},
		{
			name:      "start beyond the 180s tolerance is a distinct run",
			candidate: RunIdentity{StartedAtMs: ms("2026-01-01T09:04:00Z"), DistanceM: 10000},
			existing:  existing,
			want:      false,
		},
		{
			name:      "distance beyond the 5% fraction is a distinct run",
			candidate: RunIdentity{StartedAtMs: ms("2026-01-01T09:00:20Z"), DistanceM: 12000},
			existing:  existing,
			want:      false,
		},
		{
			name:      "empty history never matches",
			candidate: RunIdentity{StartedAtMs: ms("2026-01-01T09:00:00Z"), DistanceM: 10000},
			existing:  nil,
			want:      false,
		},
		{
			// Both axes must match: a warm-up + race of similar distance but
			// well-separated starts is two runs, not one.
			name:      "matching distance but far start is not a duplicate",
			candidate: RunIdentity{StartedAtMs: ms("2026-01-01T10:00:00Z"), DistanceM: 10000},
			existing:  existing,
			want:      false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsCrossProviderDuplicate(tc.candidate, tc.existing); got != tc.want {
				t.Fatalf("IsCrossProviderDuplicate = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestCrossProviderConstants(t *testing.T) {
	if CrossProviderStartToleranceS != 180 {
		t.Fatalf("CrossProviderStartToleranceS = %v, want 180", CrossProviderStartToleranceS)
	}
	if CrossProviderDistanceFraction != 0.05 {
		t.Fatalf("CrossProviderDistanceFraction = %v, want 0.05", CrossProviderDistanceFraction)
	}
}
