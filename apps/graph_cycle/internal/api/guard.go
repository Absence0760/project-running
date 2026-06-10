package api

import (
	"crypto/subtle"
	"net/http"
)

// Guard is the shared-secret gate in front of the sidecar. It plays the same
// role Caddy plays for the GraphHopper app — but in-process, because we own this
// Go server and don't need a reverse-proxy to add a header check.
//
// The endpoint is PUBLIC (the generate-route Lambda runs on AWS and has no 6PN
// path into Fly), so without a guard anyone who learns the hostname could hammer
// the CPU-heavy /cycle search and bypass the CloudFront WAF rate-limit. /health
// stays open for Fly's machine check; every other route requires the
// X-Engine-Key header to equal the configured key (constant-time compare).
//
// FAIL CLOSED: an empty key (operator forgot the secret) rejects every guarded
// request rather than leaving the endpoint open — the safe direction on a
// misconfig, matching the GraphHopper Caddyfile. The web client only sends the
// header when its own key is configured (graph_cycle.ts), so a keyed sidecar +
// keyless client correctly 403s rather than silently serving.
func Guard(key string, next http.Handler) http.Handler {
	keyB := []byte(key)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			next.ServeHTTP(w, r)
			return
		}
		if len(keyB) == 0 {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		got := []byte(r.Header.Get("X-Engine-Key"))
		if len(got) != len(keyB) || subtle.ConstantTimeCompare(got, keyB) != 1 {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}
