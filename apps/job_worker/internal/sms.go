package internal

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

// SmsSender is the transport the safety_sms handler sends through. It is a
// NEW escalation channel behind a provider abstraction: no SMS provider ships
// in the stack, so production wires *TwilioSender only when SMS_PROVIDER +
// the Twilio credentials are all set. When nothing is configured the worker
// leaves w.Sms nil and handleSafetySms fails closed — the parallel email
// escalation (enqueued by the same scan) is the guaranteed floor, so a
// missing SMS provider never suppresses the alert.
//
// Tests substitute a fake recorder; TwilioSender itself is exercised against
// an httptest server, never a live Twilio endpoint.
type SmsSender interface {
	Send(ctx context.Context, to, body string) error
}

// TwilioSender posts to the Twilio Messages API. Auth is HTTP Basic
// (AccountSID:AuthToken). BaseURL defaults to the live Twilio host; tests
// point it at a local httptest server so no real message is ever sent.
type TwilioSender struct {
	AccountSID string
	AuthToken  string
	From       string // an SMS-capable Twilio number or messaging-service SID
	HTTP       *http.Client
	BaseURL    string // "" → https://api.twilio.com
}

func (s *TwilioSender) Send(ctx context.Context, to, body string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	base := s.BaseURL
	if base == "" {
		base = "https://api.twilio.com"
	}
	endpoint := strings.TrimRight(base, "/") +
		"/2010-04-01/Accounts/" + url.PathEscape(s.AccountSID) + "/Messages.json"

	form := url.Values{}
	form.Set("To", to)
	form.Set("From", s.From)
	form.Set("Body", body)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return fmt.Errorf("twilio request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.SetBasicAuth(s.AccountSID, s.AuthToken)

	resp, err := s.HTTP.Do(req)
	if err != nil {
		// Surface as transient-classifiable (network markers) so the queue
		// defers + retries rather than burning the alert.
		return fmt.Errorf("twilio send: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
	return fmt.Errorf("twilio send: status %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
}
