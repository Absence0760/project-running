package livehub

import (
	"bytes"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"testing"
)

// A 403 body must say nothing about WHY. The authorizer separates "unknown
// run", "not the run owner" and "blocked by run owner", and echoing those told
// an unauthenticated prober which run ids exist and — the one that matters —
// told a blocked person that a specific runner had blocked them. Nothing in
// the web client parses this body; the reason belongs in the operator's log.
func TestServer_ForbiddenBodyDisclosesNoReason(t *testing.T) {
	reasons := []string{
		"auth: unknown run",
		"auth: not the run owner",
		"auth: blocked by run owner",
	}
	for _, reason := range reasons {
		var logBuf bytes.Buffer
		srv := &Server{
			Log: slog.New(slog.NewTextHandler(&logBuf, &slog.HandlerOptions{Level: slog.LevelInfo})),
			Authorizer: func(_ *http.Request, _ string, _ AuthAction) error {
				return errors.New(reason)
			},
		}
		base, teardown := newTestServer(t, srv)

		resp, err := http.Post(base+"/v1/live/run-1/push", "application/json",
			strings.NewReader(`{"lat":1,"lng":1,"distance_m":1,"elapsed_s":1}`))
		if err != nil {
			teardown()
			t.Fatal(err)
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		teardown()

		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("%s: status = %d, want 403", reason, resp.StatusCode)
		}
		if strings.Contains(string(body), "owner") ||
			strings.Contains(string(body), "blocked") ||
			strings.Contains(string(body), "unknown") {
			t.Errorf("%s: 403 body leaked the reason: %q", reason, string(body))
		}
		// The operator still gets it.
		if !strings.Contains(logBuf.String(), reason) {
			t.Errorf("%s: the reason never reached the log:\n%s", reason, logBuf.String())
		}
	}
}

// Every denied action answers the same way, so the body cannot be used to tell
// a subscribe refusal from a push refusal either.
func TestServer_ForbiddenBodyIsIdenticalAcrossActions(t *testing.T) {
	srv := &Server{
		Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
		Authorizer: func(_ *http.Request, _ string, action AuthAction) error {
			return errors.New("auth: denied " + string(action))
		},
	}
	base, teardown := newTestServer(t, srv)
	defer teardown()

	push, err := http.Post(base+"/v1/live/run-1/push", "application/json",
		strings.NewReader(`{"lat":1,"lng":1,"distance_m":1,"elapsed_s":1}`))
	if err != nil {
		t.Fatal(err)
	}
	pushBody, _ := io.ReadAll(push.Body)
	push.Body.Close()

	snap, err := http.Get(base + "/v1/live/run-1/snapshot")
	if err != nil {
		t.Fatal(err)
	}
	snapBody, _ := io.ReadAll(snap.Body)
	snap.Body.Close()

	if push.StatusCode != http.StatusForbidden || snap.StatusCode != http.StatusForbidden {
		t.Fatalf("statuses = %d / %d, want 403 / 403", push.StatusCode, snap.StatusCode)
	}
	if string(pushBody) != string(snapBody) {
		t.Fatalf("push body %q differs from snapshot body %q", pushBody, snapBody)
	}
}
