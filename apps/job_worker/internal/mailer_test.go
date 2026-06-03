package internal

import (
	"strings"
	"testing"
)

func TestEmailMode_DefaultsToImportant(t *testing.T) {
	cases := []struct {
		name  string
		prefs map[string]interface{}
		want  string
	}{
		{"absent key", map[string]interface{}{}, emailModeImportant},
		{"nil bag", nil, emailModeImportant},
		{"explicit all", map[string]interface{}{"email_notifications": "all"}, emailModeAll},
		{"explicit off", map[string]interface{}{"email_notifications": "off"}, emailModeOff},
		{"unknown value", map[string]interface{}{"email_notifications": "weekly"}, emailModeImportant},
		{"non-string value", map[string]interface{}{"email_notifications": 3}, emailModeImportant},
	}
	for _, c := range cases {
		if got := emailMode(c.prefs); got != c.want {
			t.Errorf("%s: emailMode = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestShouldEmail_Matrix(t *testing.T) {
	important := []string{"event_reminder", "event_cancel", "plan_update", "message"}
	social := []string{"kudos", "comment", "comment_reply", "follow", "club_post", "run_completed", "event_rsvp"}

	for _, k := range important {
		if !shouldEmail(k, emailModeImportant) {
			t.Errorf("%s should email under 'important'", k)
		}
		if !shouldEmail(k, emailModeAll) {
			t.Errorf("%s should email under 'all'", k)
		}
		if shouldEmail(k, emailModeOff) {
			t.Errorf("%s must NOT email under 'off'", k)
		}
	}
	for _, k := range social {
		if shouldEmail(k, emailModeImportant) {
			t.Errorf("%s must NOT email under 'important'", k)
		}
		if !shouldEmail(k, emailModeAll) {
			t.Errorf("%s should email under 'all'", k)
		}
		if shouldEmail(k, emailModeOff) {
			t.Errorf("%s must NOT email under 'off'", k)
		}
	}
}

func TestRenderNotificationEmail_EventReminderDeepLink(t *testing.T) {
	ev := "evt-42"
	n := NotificationRow{ID: "n1", UserID: "u1", Kind: "event_reminder", EventID: &ev}
	msg := renderNotificationEmail(n, "https://threkir.test/")

	if !strings.Contains(msg.Subject, "event") && !strings.Contains(msg.Subject, "Reminder") {
		t.Errorf("subject should mention the event reminder, got %q", msg.Subject)
	}
	if !strings.Contains(msg.Body, "https://threkir.test/events/evt-42") {
		t.Errorf("body should deep-link to the event, got:\n%s", msg.Body)
	}
	if msg.ListUnsubscribe != "https://threkir.test/settings/preferences" {
		t.Errorf("unexpected unsubscribe URL: %q", msg.ListUnsubscribe)
	}
	// Trailing slash on baseURL must not double up.
	if strings.Contains(msg.Body, "threkir.test//") {
		t.Errorf("base URL trailing slash leaked into a double slash:\n%s", msg.Body)
	}
}

func TestRenderNotificationEmail_RunDeepLinkAndFallback(t *testing.T) {
	run := "run-9"
	n := NotificationRow{ID: "n1", UserID: "u1", Kind: "kudos", RunID: &run}
	msg := renderNotificationEmail(n, "https://threkir.test")
	if !strings.Contains(msg.Body, "https://threkir.test/runs/run-9") {
		t.Errorf("kudos should link to the run, got:\n%s", msg.Body)
	}

	// Missing FK → safe fallback path, never an empty/garbled link.
	n2 := NotificationRow{ID: "n2", UserID: "u1", Kind: "kudos"}
	msg2 := renderNotificationEmail(n2, "https://threkir.test")
	if !strings.Contains(msg2.Body, "https://threkir.test/notifications") {
		t.Errorf("kudos with no run_id should fall back to /notifications, got:\n%s", msg2.Body)
	}
}

func TestBuildMIME_HeadersAndCRLF(t *testing.T) {
	raw := buildMIME("Threkir <noreply@threkir.com>", "runner@test.com", Email{
		Subject:         "Hi",
		Body:            "line one\nline two",
		ListUnsubscribe: "https://threkir.test/settings/preferences",
	})
	for _, want := range []string{
		"From: Threkir <noreply@threkir.com>\r\n",
		"To: runner@test.com\r\n",
		"Subject: Hi\r\n",
		"List-Unsubscribe: <https://threkir.test/settings/preferences>\r\n",
		"Content-Type: text/plain; charset=UTF-8\r\n",
		"\r\n\r\n", // header/body separator
		"line one\r\nline two", // body LF rewritten to CRLF
	} {
		if !strings.Contains(raw, want) {
			t.Errorf("MIME missing %q in:\n%s", want, raw)
		}
	}
}

func TestExtractAddr(t *testing.T) {
	cases := map[string]string{
		"Threkir <noreply@threkir.com>": "noreply@threkir.com",
		"noreply@threkir.com":           "noreply@threkir.com",
		"  spaced@x.com  ":              "spaced@x.com",
	}
	for in, want := range cases {
		if got := extractAddr(in); got != want {
			t.Errorf("extractAddr(%q) = %q, want %q", in, got, want)
		}
	}
}
