package internal

// Coverage for privacyDefaultIsPublic, the helper that makes Strava-synced
// runs honour the user's privacy_default (persona #27). Only an explicit
// 'public' default publishes; everything else — and any read error — falls
// closed to private. Uses the same httptest harness as the data-export tests.

import (
	"context"
	"net/http"
	"testing"
)

func TestPrivacyDefaultIsPublic(t *testing.T) {
	cases := []struct {
		name     string
		body     string
		status   int
		expected bool
	}{
		{"explicit public publishes", `[{"prefs":{"privacy_default":"public"}}]`, 200, true},
		{"followers stays private", `[{"prefs":{"privacy_default":"followers"}}]`, 200, false},
		{"private stays private", `[{"prefs":{"privacy_default":"private"}}]`, 200, false},
		{"unset pref stays private", `[{"prefs":{"preferred_unit":"km"}}]`, 200, false},
		{"no settings row stays private", `[]`, 200, false},
		{"null prefs stays private", `[{"prefs":null}]`, 200, false},
		{"read error falls closed to private", `boom`, 500, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
				if tc.status != 200 {
					w.WriteHeader(tc.status)
				}
				_, _ = w.Write([]byte(tc.body))
			})
			got := client.privacyDefaultIsPublic(context.Background(), "user-A")
			if got != tc.expected {
				t.Errorf("privacyDefaultIsPublic = %v; want %v", got, tc.expected)
			}
		})
	}
}
