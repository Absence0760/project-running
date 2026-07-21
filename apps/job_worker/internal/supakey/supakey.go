// Package supakey shapes the auth headers for server-side Supabase
// REST calls across both API-key generations. Leaf package (no
// internal import) so the worker client and the livehub fetchers can
// share it without a cycle.
package supakey

import (
	"net/http"
	"strings"
)

// SetAuthHeaders sets the headers for a REST call authenticated with a
// server API key. A legacy service_role key is a JWT and must travel
// as both `apikey` and the `Authorization` bearer. New-format keys
// (`sb_secret_…` / `sb_publishable_…`) are not JWTs and the docs
// require them on `apikey` alone: a bearer that differs from the
// apikey is forwarded to the database and rejected (PGRST301), and
// only a bearer exactly equal to the apikey rides the gateway's
// compat carve-out (decisions §280) — apikey-only sidesteps the
// distinction entirely.
func SetAuthHeaders(h http.Header, key string) {
	h.Set("apikey", key)
	if !strings.HasPrefix(key, "sb_") {
		h.Set("Authorization", "Bearer "+key)
	}
}
