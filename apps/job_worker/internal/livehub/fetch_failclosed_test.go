package livehub

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
)

// truncatedBodyServer returns a 200 whose declared Content-Length is larger
// than the bytes actually written, then closes the connection — so the HTTP
// client sees io.ErrUnexpectedEOF mid-body. This simulates a connection reset
// truncating a 2xx PostgREST response.
func truncatedBodyServer(t *testing.T, body string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hj, ok := w.(http.Hijacker)
		if !ok {
			t.Fatal("ResponseWriter is not a Hijacker")
		}
		conn, bufrw, err := hj.Hijack()
		if err != nil {
			t.Fatalf("hijack: %v", err)
		}
		defer conn.Close()
		// Declare far more than we write, then drop the connection.
		bufrw.WriteString("HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\n")
		bufrw.WriteString(body)
		bufrw.Flush()
		_ = conn.(*net.TCPConn).CloseWrite()
	}))
}

func TestSupabaseZoneFetcher_TruncatedBodyFailsClosed(t *testing.T) {
	// A short, otherwise-parseable run-owner body that gets truncated. The
	// old hand-rolled reader swallowed the read error and returned the
	// partial bytes as success → fetchZonesForUser then sees no zones and
	// the runner's exact location broadcasts. Fail-closed = return an error.
	srv := truncatedBodyServer(t, `[{"user_id":"u"}]`)
	defer srv.Close()

	f := &SupabaseZoneFetcher{BaseURL: srv.URL, ServiceKey: "k", HTTP: srv.Client()}
	if _, err := f.Zones(context.Background(), "run-1"); err == nil {
		t.Fatal("truncated zone-fetch body must fail closed (error), not return empty zones")
	}
}

func TestSupabaseRunMetaFetcher_TruncatedBodyFailsClosed(t *testing.T) {
	srv := truncatedBodyServer(t, `[{"user_id":"u","is_public":true}]`)
	defer srv.Close()

	f := &SupabaseRunMetaFetcher{BaseURL: srv.URL, ServiceKey: "k", HTTP: srv.Client()}
	if _, err := f.RunMeta(context.Background(), "run-1"); err == nil {
		t.Fatal("truncated run-meta body must fail closed (error), not return a half-parsed row")
	}
}
