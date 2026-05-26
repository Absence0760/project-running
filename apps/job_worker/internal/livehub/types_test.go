package livehub

import (
	"math"
	"testing"
)

func TestPing_Validate(t *testing.T) {
	bpm := func(v int) *int { return &v }
	ele := func(v float64) *float64 { return &v }
	cases := []struct {
		name    string
		p       Ping
		wantErr bool
	}{
		{"valid minimum", Ping{Lat: 0, Lng: 0}, false},
		{"valid full", Ping{Lat: 47.37, Lng: 8.54, DistanceM: 5000, ElapsedS: 1200, BPM: bpm(140), Elevation: ele(420)}, false},
		{"lat too high", Ping{Lat: 91, Lng: 0}, true},
		{"lat too low", Ping{Lat: -91, Lng: 0}, true},
		{"lat NaN", Ping{Lat: math.NaN(), Lng: 0}, true},
		{"lat Inf", Ping{Lat: math.Inf(1), Lng: 0}, true},
		{"lng too high", Ping{Lat: 0, Lng: 181}, true},
		{"lng too low", Ping{Lat: 0, Lng: -181}, true},
		{"distance negative", Ping{Lat: 0, Lng: 0, DistanceM: -1}, true},
		{"distance absurd", Ping{Lat: 0, Lng: 0, DistanceM: 2_000_000}, true},
		{"elapsed negative", Ping{Lat: 0, Lng: 0, ElapsedS: -1}, true},
		{"elapsed absurd", Ping{Lat: 0, Lng: 0, ElapsedS: 2_000_000}, true},
		{"bpm too low", Ping{Lat: 0, Lng: 0, BPM: bpm(10)}, true},
		{"bpm too high", Ping{Lat: 0, Lng: 0, BPM: bpm(400)}, true},
		{"bpm zero rejected", Ping{Lat: 0, Lng: 0, BPM: bpm(0)}, true},
		{"ele NaN", Ping{Lat: 0, Lng: 0, Elevation: ele(math.NaN())}, true},
		{"ele too high (above Everest)", Ping{Lat: 0, Lng: 0, Elevation: ele(10_000)}, true},
		{"ele Dead Sea ok", Ping{Lat: 31.5, Lng: 35.5, Elevation: ele(-430)}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := c.p.Validate()
			if (err != nil) != c.wantErr {
				t.Errorf("Validate() error = %v, wantErr = %v", err, c.wantErr)
			}
		})
	}
}

func TestHub_MetricsSnapshot(t *testing.T) {
	h := NewHub()
	// Publish increments PublishCount.
	for i := 0; i < 3; i++ {
		h.Publish("run-m", Ping{Lat: 1, Lng: 1})
	}
	if got := h.Metrics().PublishCount; got != 3 {
		t.Fatalf("PublishCount = %d, want 3", got)
	}
	// Subscribe-cap rejection increments SubscribeRejectCap.
	cleanups := make([]func(), 0, MaxSubsPerRoom)
	t.Cleanup(func() {
		for _, u := range cleanups {
			u()
		}
	})
	for i := 0; i < MaxSubsPerRoom; i++ {
		_, u, err := h.Subscribe(nil, "run-cap")
		if err != nil {
			t.Fatalf("Subscribe[%d] = %v", i, err)
		}
		cleanups = append(cleanups, u)
	}
	_, _, _ = h.Subscribe(nil, "run-cap")
	_, _, _ = h.Subscribe(nil, "run-cap")
	if got := h.Metrics().SubscribeRejectCap; got != 2 {
		t.Fatalf("SubscribeRejectCap = %d, want 2", got)
	}
}
