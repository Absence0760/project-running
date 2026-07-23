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
	msg := renderNotificationEmail(n, "https://threkir.test/", "en")

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
	msg := renderNotificationEmail(n, "https://threkir.test", "en")
	if !strings.Contains(msg.Body, "https://threkir.test/runs/run-9") {
		t.Errorf("kudos should link to the run, got:\n%s", msg.Body)
	}

	// Missing FK → safe fallback path, never an empty/garbled link.
	n2 := NotificationRow{ID: "n2", UserID: "u1", Kind: "kudos"}
	msg2 := renderNotificationEmail(n2, "https://threkir.test", "en")
	if !strings.Contains(msg2.Body, "https://threkir.test/notifications") {
		t.Errorf("kudos with no run_id should fall back to /notifications, got:\n%s", msg2.Body)
	}
}

// TestRenderNotificationEmail_AllKinds asserts every kind that can reach
// the email channel renders a complete message — non-empty subject + body,
// the action link, and the unsubscribe footer — and lands on the right
// deep link for the FK the kind carries. A new notification kind that
// forgets a notificationCopy case would surface here (it'd hit the generic
// fallback and fail the per-kind link assertion) rather than shipping a
// blank/garbled email.
func TestRenderNotificationEmail_AllKinds(t *testing.T) {
	const base = "https://threkir.test"
	ev, run, club := "evt-1", "run-1", "club-1"

	cases := []struct {
		kind     string
		row      NotificationRow
		wantPath string // the deep link the body must contain
	}{
		{"event_reminder", NotificationRow{Kind: "event_reminder", EventID: &ev}, base + "/events/evt-1"},
		{"event_cancel", NotificationRow{Kind: "event_cancel", EventID: &ev}, base + "/events/evt-1"},
		{"event_rsvp", NotificationRow{Kind: "event_rsvp", EventID: &ev}, base + "/events/evt-1"},
		{"plan_update", NotificationRow{Kind: "plan_update"}, base + "/plans"},
		{"plan_assigned", NotificationRow{Kind: "plan_assigned"}, base + "/plans"},
		{"message", NotificationRow{Kind: "message"}, base + "/messages"},
		{"club_post", NotificationRow{Kind: "club_post", ClubID: &club}, base + "/clubs/club-1"},
		{"run_completed", NotificationRow{Kind: "run_completed", RunID: &run}, base + "/runs/run-1"},
		{"kudos", NotificationRow{Kind: "kudos", RunID: &run}, base + "/runs/run-1"},
		{"comment", NotificationRow{Kind: "comment", RunID: &run}, base + "/runs/run-1"},
		{"comment_reply", NotificationRow{Kind: "comment_reply", RunID: &run}, base + "/runs/run-1"},
		{"follow", NotificationRow{Kind: "follow", UserID: "usr-1"}, base + "/u/usr-1"},
		{"challenge_complete", NotificationRow{Kind: "challenge_complete"}, base + "/challenges"},
		{"achievement", NotificationRow{Kind: "achievement"}, base + "/notifications"},
		{"unknown_future_kind", NotificationRow{Kind: "unknown_future_kind"}, base + "/notifications"},
	}

	for _, c := range cases {
		msg := renderNotificationEmail(c.row, base, "en")
		if strings.TrimSpace(msg.Subject) == "" {
			t.Errorf("%s: empty subject", c.kind)
		}
		if strings.TrimSpace(msg.Body) == "" {
			t.Errorf("%s: empty text body", c.kind)
		}
		if strings.TrimSpace(msg.HTML) == "" {
			t.Errorf("%s: empty HTML body", c.kind)
		}
		if strings.TrimSpace(msg.Preheader) == "" {
			t.Errorf("%s: empty preheader (inbox preview text)", c.kind)
		}
		// The deep link appears in both the text CTA line and the HTML CTA href.
		if !strings.Contains(msg.Body, c.wantPath) {
			t.Errorf("%s: text body should deep-link to %q, got:\n%s", c.kind, c.wantPath, msg.Body)
		}
		if !strings.Contains(msg.HTML, `href="`+c.wantPath+`"`) {
			t.Errorf("%s: HTML CTA should link to %q, got:\n%s", c.kind, c.wantPath, msg.HTML)
		}
		// Branded shell + footer present.
		if !strings.Contains(msg.HTML, brandName) {
			t.Errorf("%s: HTML missing the %s brand header", c.kind, brandName)
		}
		if msg.ListUnsubscribe != base+"/settings/preferences" {
			t.Errorf("%s: unexpected unsubscribe URL %q", c.kind, msg.ListUnsubscribe)
		}
		if !strings.Contains(msg.Body, base+"/settings/preferences") ||
			!strings.Contains(msg.HTML, base+"/settings/preferences") {
			t.Errorf("%s: missing manage-preferences footer", c.kind)
		}
	}

	// Every kind the preference matrix knows about must have a non-fallback
	// render. Cross-check the importantKinds set is fully covered above so
	// adding an important kind without a render case can't slip through.
	covered := map[string]bool{}
	for _, c := range cases {
		covered[c.kind] = true
	}
	for k := range importantKinds {
		if !covered[k] {
			t.Errorf("importantKinds member %q has no render test case", k)
		}
	}
}

// pathForKind is the shared deep-link source for the email, web-push and
// native-push channels; a wrong target sends every channel to the wrong screen
// at once. This pins the mapping and each nil/empty-id fallback with exact
// equality (the AllKinds test only asserts the body *contains* the path).
func TestPathForKind(t *testing.T) {
	const base = "https://threkir.test"
	ev, run, club := "e1", "r1", "c1"
	cases := []struct {
		name string
		kind string
		row  NotificationRow
		want string
	}{
		// Event family → /events/{id}, else the clubs hub.
		{"event_reminder", "event_reminder", NotificationRow{EventID: &ev}, base + "/events/e1"},
		{"event_cancel", "event_cancel", NotificationRow{EventID: &ev}, base + "/events/e1"},
		{"event_rsvp", "event_rsvp", NotificationRow{EventID: &ev}, base + "/events/e1"},
		{"event nil id → /clubs", "event_reminder", NotificationRow{}, base + "/clubs"},
		// Plan family → /plans (there is NO /training route — the old target
		// was a dead deep link).
		{"plan_update → /plans", "plan_update", NotificationRow{}, base + "/plans"},
		{"plan_assigned → /plans", "plan_assigned", NotificationRow{}, base + "/plans"},
		// Club → /clubs/{id}, else the hub.
		{"club_post", "club_post", NotificationRow{ClubID: &club}, base + "/clubs/c1"},
		{"club nil id → /clubs", "club_post", NotificationRow{}, base + "/clubs"},
		// Run family → /runs/{id}, else the inbox. comment_reply folds to run.
		{"run_completed", "run_completed", NotificationRow{RunID: &run}, base + "/runs/r1"},
		{"kudos", "kudos", NotificationRow{RunID: &run}, base + "/runs/r1"},
		{"comment", "comment", NotificationRow{RunID: &run}, base + "/runs/r1"},
		{"comment_reply", "comment_reply", NotificationRow{RunID: &run}, base + "/runs/r1"},
		{"run nil id → inbox", "kudos", NotificationRow{}, base + "/notifications"},
		// Follow → recipient's own profile (there is NO /profile route).
		{"follow → /u/{id}", "follow", NotificationRow{UserID: "u1"}, base + "/u/u1"},
		{"follow empty user → inbox", "follow", NotificationRow{}, base + "/notifications"},
		// Static targets.
		{"message", "message", NotificationRow{}, base + "/messages"},
		{"challenge_complete", "challenge_complete", NotificationRow{}, base + "/challenges"},
		// Inbox fallback: achievement has no dedicated surface yet, and any
		// unknown/future kind lands on the inbox.
		{"achievement → inbox", "achievement", NotificationRow{}, base + "/notifications"},
		{"unknown → inbox", "totally_new_kind", NotificationRow{}, base + "/notifications"},
	}
	for _, c := range cases {
		c.row.Kind = c.kind
		if got := pathForKind(c.kind, base, c.row); got != c.want {
			t.Errorf("%s: pathForKind(%q) = %q, want %q", c.name, c.kind, got, c.want)
		}
	}
}

func TestRenderLifecycleEmail_Welcome(t *testing.T) {
	msg, ok := renderLifecycleEmail("welcome", "https://threkir.test/", "en")
	if !ok {
		t.Fatal("welcome template should render")
	}
	if msg.Subject != "Welcome to Threkir" {
		t.Errorf("unexpected subject %q", msg.Subject)
	}
	if !strings.Contains(msg.Body, "Thanks for signing up") {
		t.Errorf("body should thank the user:\n%s", msg.Body)
	}
	if !strings.Contains(msg.Body, "https://threkir.test/settings/preferences") {
		t.Errorf("body should link to preferences:\n%s", msg.Body)
	}
	// No trailing-slash double-up from the base URL.
	if strings.Contains(msg.Body, "threkir.test//") {
		t.Errorf("base URL trailing slash leaked:\n%s", msg.Body)
	}
	// Transactional welcome carries no List-Unsubscribe (not a subscription).
	if msg.ListUnsubscribe != "" {
		t.Errorf("welcome should not set List-Unsubscribe, got %q", msg.ListUnsubscribe)
	}
	// Branded HTML part: preheader, brand header, heading, CTA to the app root.
	if strings.TrimSpace(msg.Preheader) == "" {
		t.Error("welcome should set an inbox preheader")
	}
	for _, want := range []string{
		"<!DOCTYPE html>", brandName,
		"Welcome to Threkir",
		`href="https://threkir.test"`, // CTA → app root (no trailing slash)
		"https://threkir.test/settings/preferences",
	} {
		if !strings.Contains(msg.HTML, want) {
			t.Errorf("welcome HTML missing %q in:\n%s", want, msg.HTML)
		}
	}
}

func TestRenderLifecycleEmail_UnknownTemplate(t *testing.T) {
	_, ok := renderLifecycleEmail("no_such_template", "https://threkir.test", "en")
	if ok {
		t.Error("unknown template must report ok=false so the handler skips")
	}
}

func TestRenderLifecycleEmail_SubscriptionTemplates(t *testing.T) {
	pro, ok := renderLifecycleEmail("pro_welcome", "https://threkir.test", "en")
	if !ok {
		t.Fatal("pro_welcome should render")
	}
	if pro.Subject != "You're now on Threkir Pro" {
		t.Errorf("unexpected pro_welcome subject %q", pro.Subject)
	}

	pf, ok := renderLifecycleEmail("payment_failed", "https://threkir.test", "en")
	if !ok {
		t.Fatal("payment_failed should render")
	}
	// Dunning CTA points at billing management.
	if !strings.Contains(pf.HTML, `href="https://threkir.test/settings/upgrade"`) {
		t.Errorf("payment_failed CTA should target /settings/upgrade:\n%s", pf.HTML)
	}
	// Transactional (service-message) footer, not the welcome footer.
	if !strings.Contains(pf.Body, "service message") {
		t.Errorf("transactional footer expected:\n%s", pf.Body)
	}
	if strings.Contains(pf.Body, "just created a Threkir account") {
		t.Errorf("payment_failed must not use the welcome footer:\n%s", pf.Body)
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
	// A List-Unsubscribe pointing at a GET preferences page (one-click false)
	// must NOT advertise List-Unsubscribe-Post — the page can't honour the POST.
	if strings.Contains(raw, "List-Unsubscribe-Post") {
		t.Errorf("GET-only unsubscribe must not advertise one-click POST:\n%s", raw)
	}
}

func TestBuildMIME_OneClickPostHeader(t *testing.T) {
	raw := buildMIME("Threkir <noreply@threkir.com>", "runner@test.com", Email{
		Subject:                 "Digest",
		Body:                    "weekly summary",
		ListUnsubscribe:         "https://threkir.test/unsubscribe/weekly-digest?token=abc",
		ListUnsubscribeOneClick: true,
	})
	if !strings.Contains(raw, "List-Unsubscribe: <https://threkir.test/unsubscribe/weekly-digest?token=abc>\r\n") {
		t.Errorf("MIME missing List-Unsubscribe:\n%s", raw)
	}
	if !strings.Contains(raw, "List-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n") {
		t.Errorf("MIME missing RFC 8058 List-Unsubscribe-Post:\n%s", raw)
	}
}

func TestBuildMIME_NoOneClickPostWithoutListUnsubscribe(t *testing.T) {
	// One-click flag without a List-Unsubscribe URL emits neither header —
	// the -Post header is meaningless on its own.
	raw := buildMIME("Threkir <noreply@threkir.com>", "runner@test.com", Email{
		Subject:                 "Hi",
		Body:                    "body",
		ListUnsubscribeOneClick: true,
	})
	if strings.Contains(raw, "List-Unsubscribe") {
		t.Errorf("no List-Unsubscribe URL → no unsubscribe headers at all:\n%s", raw)
	}
}

func TestBuildMIME_MultipartWhenHTMLPresent(t *testing.T) {
	raw := buildMIME("Threkir <noreply@threkir.com>", "runner@test.com", Email{
		Subject: "Hi",
		Body:    "plain version",
		HTML:    "<p>html version</p>",
	})
	for _, want := range []string{
		"Content-Type: multipart/alternative; boundary=",
		"Content-Type: text/plain; charset=UTF-8",
		"plain version",
		"Content-Type: text/html; charset=UTF-8",
		"<p>html version</p>",
	} {
		if !strings.Contains(raw, want) {
			t.Errorf("multipart MIME missing %q in:\n%s", want, raw)
		}
	}
	// The text part must precede the HTML part (clients render the last
	// understood part; text-first is the convention).
	if strings.Index(raw, "plain version") > strings.Index(raw, "html version") {
		t.Error("text/plain part must come before text/html")
	}
}

// headerLines returns the header block (everything before the first blank
// CRLF line) split into individual header lines. A header value that carried a
// smuggled CRLF would show up here as an extra line.
func headerLines(raw string) []string {
	headers := strings.SplitN(raw, "\r\n\r\n", 2)[0]
	return strings.Split(headers, "\r\n")
}

func countHeaderLines(raw, prefix string) int {
	n := 0
	for _, line := range headerLines(raw) {
		if strings.HasPrefix(line, prefix) {
			n++
		}
	}
	return n
}

func TestBuildMIME_SanitizesHeaderInjection(t *testing.T) {
	// Every interpolated header carries a CRLF-injection payload. The
	// sanitizer must collapse each onto its single header line — no forged
	// Bcc:/Subject: line may appear in the header block.
	raw := buildMIME(
		"Threkir <noreply@threkir.com>\r\nBcc: sneaky@from.com",
		"contact@example.com\r\nBcc: sneaky@to.com",
		Email{
			Subject:         "Ada\r\nBcc: evil@example.com\r\nSubject: forged",
			Body:            "body",
			ListUnsubscribe: "https://threkir.test/u\r\nBcc: sneaky@unsub.com",
		})

	for _, prefix := range []string{"From:", "To:", "Subject:", "List-Unsubscribe:"} {
		if n := countHeaderLines(raw, prefix); n != 1 {
			t.Errorf("want exactly one %q header line, got %d in:\n%s", prefix, n, raw)
		}
	}
	for _, line := range headerLines(raw) {
		if strings.HasPrefix(line, "Bcc:") {
			t.Errorf("injected Bcc reached the header block:\n%s", raw)
		}
	}
	// The literal payload text survives (control chars removed) folded onto
	// the single Subject line — proof it was stripped, not truncated.
	if !strings.Contains(raw, "Subject: AdaBcc: evil@example.comSubject: forged\r\n") {
		t.Errorf("subject not sanitized as expected:\n%s", raw)
	}
}

func TestRenderSafetyEmail_OwnerNameHeaderInjection(t *testing.T) {
	// The runner's own display_name flows into the Subject of every
	// safety-contact email. A CR/LF in that name must never split the header.
	p := SafetyEmailPayload{
		Template:     "confirm",
		OwnerName:    "Ada\r\nBcc: evil@example.com",
		ConfirmToken: "tok-123",
	}
	msg, ok := renderSafetyEmail(p, "https://threkir.test", "en")
	if !ok {
		t.Fatal("confirm template should render")
	}
	if strings.ContainsAny(msg.Subject, "\r\n") {
		t.Errorf("owner name left a raw CR/LF in the Subject: %q", msg.Subject)
	}

	raw := buildMIME("Threkir <noreply@threkir.com>", "contact@example.com", msg)
	if n := countHeaderLines(raw, "Subject:"); n != 1 {
		t.Errorf("want exactly one Subject header line, got %d in:\n%s", n, raw)
	}
	for _, line := range headerLines(raw) {
		if strings.HasPrefix(line, "Bcc:") {
			t.Errorf("owner-name injection produced a Bcc header line:\n%s", raw)
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
