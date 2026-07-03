package internal

import (
	"fmt"
	"strings"
	"testing"
)

// samplePIIBody stands in for a real PostgREST/GoTrue/Storage error
// response: they echo back the offending row, which can carry emails,
// run titles, and health/injury free text. The regression this guards
// is a leak of that payload into the error string, which propagates via
// %w all the way into Fly.io logs. /audit/pii-in-logs.
const samplePIIBody = `{"code":"23505","message":"duplicate key",` +
	`"details":"user=ultra.runner@example.com note='left knee ITB flare, DNF at mile 62'"}`

func TestHTTPError_ErrorOmitsBody(t *testing.T) {
	e := &HTTPError{
		StatusCode: 409,
		Method:     "POST",
		Endpoint:   "/rest/v1/webhook_events",
		Body:       samplePIIBody,
	}
	got := e.Error()

	// The raw body — and every PII fragment inside it — must never
	// appear in the formatted message.
	for _, leak := range []string{
		samplePIIBody,
		"ultra.runner@example.com",
		"left knee ITB flare",
		"duplicate key",
		`"details"`,
	} {
		if strings.Contains(got, leak) {
			t.Fatalf("Error() leaked %q into the log-bound string: %q", leak, got)
		}
	}

	// It must still be actionable: status + reason + method + path.
	for _, want := range []string{"409", "Conflict", "POST", "/rest/v1/webhook_events"} {
		if !strings.Contains(got, want) {
			t.Fatalf("Error() missing %q; got %q", want, got)
		}
	}
}

func TestHTTPError_ErrorEndpointIsPathOnly(t *testing.T) {
	// A PostgREST query string carries filter VALUES (emails, ids,
	// timestamps). Only req.URL.Path is ever assigned to Endpoint, so
	// the query can't ride the error — pin that a query-bearing value
	// isn't what we format even if one were assigned by mistake.
	e := &HTTPError{
		StatusCode: 400,
		Method:     "GET",
		Endpoint:   "/rest/v1/integrations",
		Body:       `{"message":"bad filter"}`,
	}
	got := e.Error()
	if strings.Contains(got, "?") || strings.Contains(got, "eq.") {
		t.Fatalf("Error() must not contain a query string: %q", got)
	}
	if !strings.Contains(got, "/rest/v1/integrations") {
		t.Fatalf("Error() missing endpoint path; got %q", got)
	}
}

func TestHTTPError_ErrorBareStatusDegrades(t *testing.T) {
	// Constructed off a bare status (the push transports do this):
	// no Method/Endpoint, but still no Body, and still a usable line.
	e := &HTTPError{StatusCode: 503, Body: samplePIIBody}
	got := e.Error()
	if strings.Contains(got, "ultra.runner@example.com") || strings.Contains(got, samplePIIBody) {
		t.Fatalf("bare-status Error() leaked the body: %q", got)
	}
	if !strings.Contains(got, "503") {
		t.Fatalf("bare-status Error() missing status; got %q", got)
	}
}

func TestHTTPError_WrappedStaysScrubbed(t *testing.T) {
	// The finding is specifically about %w propagation — verify the
	// scrub survives being wrapped the way every caller wraps it.
	e := &HTTPError{StatusCode: 500, Method: "PATCH", Endpoint: "/rest/v1/runs", Body: samplePIIBody}
	wrapped := fmt.Errorf("update matched track row: %w", e)
	if strings.Contains(wrapped.Error(), "ultra.runner@example.com") {
		t.Fatalf("wrapped error leaked PII: %q", wrapped.Error())
	}
}
