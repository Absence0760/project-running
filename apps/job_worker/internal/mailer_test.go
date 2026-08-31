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

// emailPrefs / pushPrefs build the one-key bag the gate reads, so the matrix
// below still reads as "kind x mode" now that shouldEmail/shouldPush take the
// whole prefs bag rather than a pre-resolved mode.
func emailPrefs(mode string) map[string]interface{} {
	return map[string]interface{}{"email_notifications": mode}
}

func pushPrefs(mode string) map[string]interface{} {
	return map[string]interface{}{"push_notifications": mode}
}

func TestShouldEmail_Matrix(t *testing.T) {
	important := []string{"event_reminder", "event_cancel", "plan_update", "message", "data_export_ready", "refund_failed"}
	social := []string{"kudos", "comment", "comment_reply", "follow", "club_post", "run_completed", "event_rsvp"}

	for _, k := range important {
		if !shouldEmail(k, emailPrefs(emailModeImportant)) {
			t.Errorf("%s should email under 'important'", k)
		}
		if !shouldEmail(k, emailPrefs(emailModeAll)) {
			t.Errorf("%s should email under 'all'", k)
		}
		if shouldEmail(k, emailPrefs(emailModeOff)) {
			t.Errorf("%s must NOT email under 'off'", k)
		}
	}
	for _, k := range social {
		if shouldEmail(k, emailPrefs(emailModeImportant)) {
			t.Errorf("%s must NOT email under 'important'", k)
		}
		if !shouldEmail(k, emailPrefs(emailModeAll)) {
			t.Errorf("%s should email under 'all'", k)
		}
		if shouldEmail(k, emailPrefs(emailModeOff)) {
			t.Errorf("%s must NOT email under 'off'", k)
		}
	}
}

// The per-kind mute (decisions.md § 729) can only ever SUBTRACT. It is the
// proportionate control the three-mode channel setting cannot express — muting
// email to stop one notice would also stop direct messages — and its direction
// is deliberately the opposite of the engagement streams' opt-IN: the subject
// asked for the export minutes earlier, so an absent key means "never chose",
// not "declined".
func TestKindMute_OnlyEverSubtracts(t *testing.T) {
	const kind = "data_export_ready"
	muted := map[string]interface{}{"notify_data_export_ready": "off"}

	for _, mode := range []string{emailModeAll, emailModeImportant} {
		prefs := emailPrefs(mode)
		if !shouldEmail(kind, prefs) {
			t.Fatalf("precondition: %s should email under %q", kind, mode)
		}
		prefs["notify_data_export_ready"] = "off"
		if shouldEmail(kind, prefs) {
			t.Errorf("a muted kind must not email under %q", mode)
		}
	}
	for _, mode := range []string{pushModeAll, pushModeImportant} {
		prefs := pushPrefs(mode)
		if !shouldPush(kind, prefs) {
			t.Fatalf("precondition: %s should push under %q", kind, mode)
		}
		prefs["notify_data_export_ready"] = "off"
		if shouldPush(kind, prefs) {
			t.Errorf("a muted kind must not push under %q", mode)
		}
	}

	// It never widens: the mute key is not a way past a muted channel, and it
	// says nothing about any other kind.
	off := map[string]interface{}{"email_notifications": emailModeOff, "notify_data_export_ready": "on"}
	if shouldEmail(kind, off) {
		t.Error("a per-kind 'on' must not promote a kind past email_notifications=off")
	}
	if !shouldEmail("message", muted) {
		t.Error("muting one kind must not touch another")
	}

	// Absent, unrecognised and non-string all read as unmuted: a corrupt bag is
	// not a decision to stop being told about your own data-rights request.
	for name, v := range map[string]interface{}{
		"unknown string": "silence",
		"bool":           true,
		"number":         0,
	} {
		if kindMuted(kind, map[string]interface{}{"notify_data_export_ready": v}) {
			t.Errorf("%s value must not mute", name)
		}
	}
	if kindMuted(kind, map[string]interface{}{}) {
		t.Error("an absent key must not mute")
	}
	if kindMuted("message", muted) {
		t.Error("a kind with no registered mute key is never muted")
	}
}

// TestInAppOnlyKinds_NeverLeaveTheInbox pins the deliberate skip. "all" is the
// mode that matters: omission from importantKinds would already suppress these
// under the default "important", so only an explicit gate stops a recipient who
// opted into everything from being emailed and pushed a provisional moderation
// notice with no destination.
func TestInAppOnlyKinds_NeverLeaveTheInbox(t *testing.T) {
	if !inAppOnlyKinds["content_hidden"] {
		t.Fatal("content_hidden must be in-app only — see the inAppOnlyKinds rationale")
	}
	for kind := range inAppOnlyKinds {
		for _, mode := range []string{emailModeAll, emailModeImportant, emailModeOff} {
			if shouldEmail(kind, emailPrefs(mode)) {
				t.Errorf("shouldEmail(%q, %q) = true; in-app-only kinds must never email", kind, mode)
			}
		}
		for _, mode := range []string{pushModeAll, pushModeImportant, pushModeOff} {
			if shouldPush(kind, pushPrefs(mode)) {
				t.Errorf("shouldPush(%q, %q) = true; in-app-only kinds must never push", kind, mode)
			}
		}
		if importantKinds[kind] {
			t.Errorf("%q is both in-app-only and important — contradictory", kind)
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

	// Missing FK → safe fallback path, never an empty/garbled link. The inbox
	// is a tab on the recipient's own profile; there is no /notifications route.
	n2 := NotificationRow{ID: "n2", UserID: "u1", Kind: "kudos"}
	msg2 := renderNotificationEmail(n2, "https://threkir.test", "en")
	if !strings.Contains(msg2.Body, "https://threkir.test/u/u1?tab=notifications") {
		t.Errorf("kudos with no run_id should fall back to the inbox tab, got:\n%s", msg2.Body)
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
		{"run_completed", NotificationRow{Kind: "run_completed", UserID: "usr-1", RunID: &run}, base + "/share/run/run-1"},
		{"kudos", NotificationRow{Kind: "kudos", RunID: &run}, base + "/runs/run-1"},
		{"comment", NotificationRow{Kind: "comment", RunID: &run}, base + "/runs/run-1"},
		{"comment_reply", NotificationRow{Kind: "comment_reply", RunID: &run}, base + "/runs/run-1"},
		{"follow", NotificationRow{Kind: "follow", UserID: "usr-1"}, base + "/u/usr-1"},
		{"challenge_complete", NotificationRow{Kind: "challenge_complete"}, base + "/challenges"},
		{"achievement", NotificationRow{Kind: "achievement", UserID: "usr-1"}, base + "/u/usr-1?tab=notifications"},
		{"content_hidden", NotificationRow{Kind: "content_hidden", UserID: "usr-1"}, base + "/u/usr-1?tab=notifications"},
		// The one kind whose link carries no id: the export lives in
		// data_export_jobs, which the notifications row has no column for,
		// and the page mints the signed download URL when the subject
		// arrives (decisions.md § 729).
		{"data_export_ready", NotificationRow{Kind: "data_export_ready", UserID: "usr-1"}, base + "/settings/account"},
		// Both shapes: an event order carries the FK and lands on the event page,
		// a donation carries none and lands on the inbox rather than on
		// eventPath's own /clubs fallback (decisions § 825).
		{"refund_failed", NotificationRow{Kind: "refund_failed", UserID: "usr-1", EventID: &ev}, base + "/events/evt-1"},
		{"refund_failed_donation", NotificationRow{Kind: "refund_failed", UserID: "usr-1"}, base + "/u/usr-1?tab=notifications"},
		{"unknown_future_kind", NotificationRow{Kind: "unknown_future_kind", UserID: "usr-1"}, base + "/u/usr-1?tab=notifications"},
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
//
// Exact strings alone are what let /events/{id} and /notifications survive:
// both were pinned here and neither was a route. notification_link_guard_test.go
// carries the property these cases can't — that each target resolves against
// apps/web/src/routes.
func TestPathForKind(t *testing.T) {
	const base = "https://threkir.test"
	ev, run, club := "e1", "r1", "c1"
	const inbox = base + "/u/u1?tab=notifications"
	cases := []struct {
		name string
		kind string
		row  NotificationRow
		want string
	}{
		// Event family → the stable-id /events/{id} route, which resolves the
		// club slug and forwards to /clubs/{slug}/events/{id}; the projection
		// carries no slug. Nil id → the clubs hub.
		{"event_reminder", "event_reminder", NotificationRow{EventID: &ev}, base + "/events/e1"},
		{"event_cancel", "event_cancel", NotificationRow{EventID: &ev}, base + "/events/e1"},
		{"event_rsvp", "event_rsvp", NotificationRow{EventID: &ev}, base + "/events/e1"},
		{"event nil id → /clubs", "event_reminder", NotificationRow{}, base + "/clubs"},
		// Plan family → /plans (there is NO /training route — the old target
		// was a dead deep link).
		{"plan_update → /plans", "plan_update", NotificationRow{}, base + "/plans"},
		{"plan_assigned → /plans", "plan_assigned", NotificationRow{}, base + "/plans"},
		// Club → the club id in the /clubs/[slug] slot; that page falls back to
		// an id lookup and redirects to the canonical slug URL.
		{"club_post", "club_post", NotificationRow{ClubID: &club}, base + "/clubs/c1"},
		{"club nil id → /clubs", "club_post", NotificationRow{}, base + "/clubs"},
		// Engagement on the recipient's OWN run → the owner-scoped detail page.
		// comment_reply folds to run.
		{"kudos", "kudos", NotificationRow{RunID: &run}, base + "/runs/r1"},
		{"comment", "comment", NotificationRow{RunID: &run}, base + "/runs/r1"},
		{"comment_reply", "comment_reply", NotificationRow{RunID: &run}, base + "/runs/r1"},
		{"run nil id → inbox", "kudos", NotificationRow{UserID: "u1"}, inbox},
		// A followee's run → the public share page. /runs/{id} reads
		// owner-scoped, so it renders "run not found" for the follower this
		// kind is addressed to.
		{"run_completed → share", "run_completed", NotificationRow{RunID: &run}, base + "/share/run/r1"},
		{"run_completed nil id → inbox", "run_completed", NotificationRow{UserID: "u1"}, inbox},
		// Follow → recipient's own profile (there is NO /profile route).
		{"follow → /u/{id}", "follow", NotificationRow{UserID: "u1"}, base + "/u/u1"},
		// A reversed refund on an event order → the event page, whose banner
		// explains the same thing at length. On a DONATION there is no FK to
		// carry, and eventPath's own /clubs fallback would answer "we still
		// have your money" with a club directory — so that half goes to the
		// inbox, where the message is (decisions § 825).
		{"refund_failed order", "refund_failed", NotificationRow{UserID: "u1", EventID: &ev}, base + "/events/e1"},
		{"refund_failed donation → inbox", "refund_failed", NotificationRow{UserID: "u1"}, inbox},
		// Static targets.
		{"message", "message", NotificationRow{}, base + "/messages"},
		{"challenge_complete", "challenge_complete", NotificationRow{}, base + "/challenges"},
		// Inbox fallback: neither achievement nor content_hidden has dedicated
		// copy or a surface yet, and any unknown/future kind lands there too.
		// The inbox is a TAB on the recipient's profile — there is no
		// /notifications route, which is what made the old fallback dead.
		{"achievement → inbox", "achievement", NotificationRow{UserID: "u1"}, inbox},
		{"content_hidden → inbox", "content_hidden", NotificationRow{UserID: "u1"}, inbox},
		{"unknown → inbox", "totally_new_kind", NotificationRow{UserID: "u1"}, inbox},
		// A row with no user_id can't address an inbox; the app root is the
		// honest landing spot rather than a "/u/?tab=…" dead end.
		{"no user_id → app root", "achievement", NotificationRow{}, base},
		{"follow empty user → app root", "follow", NotificationRow{}, base},
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
