package internal

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// truncatedBodyServer returns a 200 promising a long body via
// Content-Length, sends only a few bytes, then slams the connection —
// the client's body read fails with an unexpected EOF, simulating a
// mid-transfer network drop on an otherwise-successful request.
func truncatedBodyServer(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hj, ok := w.(http.Hijacker)
		if !ok {
			t.Fatal("ResponseWriter is not a Hijacker")
		}
		conn, _, err := hj.Hijack()
		if err != nil {
			t.Errorf("hijack: %v", err)
			return
		}
		defer func(c net.Conn) { _ = c.Close() }(conn)
		_, _ = conn.Write([]byte("HTTP/1.1 200 OK\r\nContent-Length: 4096\r\nContent-Type: application/json\r\n\r\n"))
		_, _ = conn.Write([]byte(`{"id":123,`)) // truncated JSON, far short of 4096
	}))
}

func TestStravaRefresh_ReturnsParsedResponse(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/oauth/token" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		if got := r.Header.Get("Content-Type"); got != "application/x-www-form-urlencoded" {
			t.Errorf("Content-Type=%q", got)
		}
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		if r.PostForm.Get("grant_type") != "refresh_token" {
			t.Errorf("grant_type=%q", r.PostForm.Get("grant_type"))
		}
		if r.PostForm.Get("client_id") != "id-123" {
			t.Errorf("client_id=%q", r.PostForm.Get("client_id"))
		}
		if r.PostForm.Get("refresh_token") != "rt-abc" {
			t.Errorf("refresh_token=%q", r.PostForm.Get("refresh_token"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"new-at","refresh_token":"new-rt","expires_at":1800000000,"token_type":"Bearer","athlete":{"id":1}}`))
	}))
	defer srv.Close()

	c := &StravaClient{
		ClientID:     "id-123",
		ClientSecret: "secret-456",
		BaseURL:      srv.URL,
	}
	out, err := c.Refresh(context.Background(), "rt-abc")
	if err != nil {
		t.Fatal(err)
	}
	if out.AccessToken != "new-at" || out.RefreshToken != "new-rt" || out.ExpiresAt != 1800000000 {
		t.Errorf("response decode wrong: %+v", out)
	}
}

func TestStravaRefresh_NonOkSurfacesHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(401)
		_, _ = w.Write([]byte(`{"message":"invalid_grant"}`))
	}))
	defer srv.Close()

	c := &StravaClient{ClientID: "id", ClientSecret: "sec", BaseURL: srv.URL}
	_, err := c.Refresh(context.Background(), "any")
	if err == nil {
		t.Fatal("want error")
	}
	var herr *HTTPError
	if !errors.As(err, &herr) {
		t.Fatalf("want HTTPError; got %T (%v)", err, err)
	}
	if herr.StatusCode != 401 {
		t.Errorf("status=%d, want 401", herr.StatusCode)
	}
}

func TestStravaRefresh_RejectsIncompleteResponse(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		// Missing refresh_token and expires_at — the writer would
		// otherwise persist an empty refresh, breaking the next sweep.
		_, _ = w.Write([]byte(`{"access_token":"new-at"}`))
	}))
	defer srv.Close()

	c := &StravaClient{ClientID: "id", ClientSecret: "sec", BaseURL: srv.URL}
	_, err := c.Refresh(context.Background(), "rt")
	if err == nil {
		t.Fatal("incomplete response must be rejected")
	}
}

func TestStravaFetchActivity_TruncatedBodyIsTransient(t *testing.T) {
	// A connection that drops mid-body after a 200 must surface as
	// transient (defer + retry), not fall through to a permanent
	// decode error that drops the activity.
	srv := truncatedBodyServer(t)
	defer srv.Close()

	c := &StravaClient{BaseURL: srv.URL}
	res, err := c.FetchActivity(context.Background(), "at", 123)
	if err != nil {
		t.Fatalf("body-read failure should not surface as a Go error here; got %v", err)
	}
	if res.Status != StravaFetchTransient {
		t.Fatalf("status=%v, want StravaFetchTransient", res.Status)
	}
}

func TestStravaFetchStreams_TruncatedBodyIsTransient(t *testing.T) {
	srv := truncatedBodyServer(t)
	defer srv.Close()

	c := &StravaClient{BaseURL: srv.URL}
	_, err := c.FetchStreams(context.Background(), "at", 123)
	if err == nil {
		t.Fatal("want an error from a truncated streams body")
	}
	if !isTransient(err) {
		t.Fatalf("a body-read failure must be classified transient; got %v", err)
	}
}

func TestIsTransient_UnexpectedEOF(t *testing.T) {
	if !isTransient(io.ErrUnexpectedEOF) {
		t.Fatal("io.ErrUnexpectedEOF (truncated body) must be transient")
	}
}

func TestStravaRefresh_DefaultsToProductionURL(t *testing.T) {
	// We don't actually hit Strava; just confirm that an empty
	// BaseURL doesn't crash. The DNS lookup or connection refusal
	// produces a network error, which is fine — we just want to know
	// the URL was constructed against the production host.
	c := &StravaClient{
		ClientID:     "id",
		ClientSecret: "sec",
		HTTP:         &http.Client{Timeout: 50 * time.Millisecond},
	}
	_, err := c.Refresh(context.Background(), "rt")
	if err == nil {
		t.Fatal("expected a transport error for the real Strava host under 50 ms")
	}
	// The error message should mention strava.com to confirm we built the right URL.
	if !strings.Contains(err.Error(), "strava.com") {
		t.Errorf("error doesn't mention strava.com host: %v", err)
	}
}
