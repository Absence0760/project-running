package internal

import (
	"context"
	"fmt"
	"net/smtp"
	"strings"
	"time"
)

// EmailSender is the transport the notification-email handler sends
// through. Production wires *SMTPSender (Mailpit in local dev on
// 127.0.0.1:54325; Resend / SES SMTP in prod). Tests substitute a fake
// recorder so the handler logic is exercised without a live SMTP server.
type EmailSender interface {
	Send(ctx context.Context, to string, msg Email) error
}

// Email is a rendered, transport-agnostic message. Body is plain text;
// the channel deliberately stays text-only for the first slice (no HTML
// template surface to maintain, no tracking pixels — a privacy-app-
// appropriate default). ListUnsubscribe is the URL placed in the
// List-Unsubscribe header so mail clients surface a one-tap opt-out that
// lands on the in-app notification preferences.
type Email struct {
	Subject         string
	Body            string
	ListUnsubscribe string
}

// SMTPSender sends via a plain SMTP server. Auth is nil for an
// unauthenticated server (the local Mailpit catcher accepts mail without
// AUTH); production sets smtp.PlainAuth. net/smtp.SendMail negotiates
// STARTTLS automatically when the server advertises it, so the same code
// path serves Mailpit (no TLS) and a TLS-requiring provider.
type SMTPSender struct {
	Addr string    // host:port
	From string    // RFC 5322 From, e.g. "Threkir <noreply@threkir.com>"
	Auth smtp.Auth // nil → no AUTH command (local Mailpit)
}

func (s *SMTPSender) Send(ctx context.Context, to string, msg Email) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	raw := buildMIME(s.From, to, msg)
	if err := smtp.SendMail(s.Addr, s.Auth, extractAddr(s.From), []string{to}, []byte(raw)); err != nil {
		// Surface as a transient-classifiable error: a refused
		// connection / 4xx greylist should defer + retry rather than
		// burn the notification. The worker's isTransient sniffs the
		// message for network markers; SMTP 4xx text contains them.
		return fmt.Errorf("smtp send: %w", err)
	}
	return nil
}

// buildMIME assembles a minimal RFC 5322 / MIME text message. CRLF line
// endings per the SMTP wire format. A fixed Date is not used — the send
// time is now; callers don't depend on a deterministic header here, and
// the rendering tests assert on the body, not the envelope.
func buildMIME(from, to string, msg Email) string {
	var b strings.Builder
	fmt.Fprintf(&b, "From: %s\r\n", from)
	fmt.Fprintf(&b, "To: %s\r\n", to)
	fmt.Fprintf(&b, "Subject: %s\r\n", msg.Subject)
	fmt.Fprintf(&b, "Date: %s\r\n", time.Now().UTC().Format(time.RFC1123Z))
	if msg.ListUnsubscribe != "" {
		// RFC 2369. Mail clients render a one-tap "Unsubscribe" that
		// opens the preferences page.
		fmt.Fprintf(&b, "List-Unsubscribe: <%s>\r\n", msg.ListUnsubscribe)
	}
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	b.WriteString("\r\n")
	b.WriteString(strings.ReplaceAll(msg.Body, "\n", "\r\n"))
	return b.String()
}

// extractAddr pulls the bare address out of an RFC 5322 "Name <addr>"
// string for the SMTP MAIL FROM. A plain address passes through
// unchanged.
func extractAddr(from string) string {
	if i := strings.LastIndex(from, "<"); i >= 0 {
		if j := strings.Index(from[i:], ">"); j >= 0 {
			return from[i+1 : i+j]
		}
	}
	return strings.TrimSpace(from)
}

// ─────────────────── preference + rendering (pure) ───────────────────

// Email-channel modes stored in user_settings.prefs.email_notifications.
// See docs/backend/settings.md. Default is "important" when the key is
// absent or unrecognised — fail toward the smaller, expected set rather
// than emailing everything to a user who never configured it.
const (
	emailModeAll       = "all"
	emailModeImportant = "important"
	emailModeOff       = "off"
)

// importantKinds is the set emailed under the default "important" mode:
// things the user is waiting on or that change their plans. Social-loop
// noise (kudos, comment, comment_reply, follow, club_post, run_completed,
// event_rsvp) is emailed only under "all". event_reminder / event_cancel
// are the Phase 4b event-day items; message is a DM; plan_update is a
// coach changing the user's training.
var importantKinds = map[string]bool{
	"event_reminder": true,
	"event_cancel":   true,
	"plan_update":    true,
	"message":        true,
}

// emailMode reads the channel preference out of the user_settings.prefs
// bag, defaulting to "important". A non-string or unknown value also
// falls back to "important" (fail-toward-smaller-set).
func emailMode(prefs map[string]interface{}) string {
	v, ok := prefs["email_notifications"].(string)
	if !ok {
		return emailModeImportant
	}
	switch v {
	case emailModeAll, emailModeImportant, emailModeOff:
		return v
	default:
		return emailModeImportant
	}
}

// shouldEmail decides whether a notification of the given kind is emailed
// under the resolved mode.
func shouldEmail(kind, mode string) bool {
	switch mode {
	case emailModeOff:
		return false
	case emailModeAll:
		return true
	default: // emailModeImportant
		return importantKinds[kind]
	}
}

// renderNotificationEmail turns a notification row into a subject + body
// + unsubscribe link. Text is intentionally generic-but-actionable: it
// names the category and links to the relevant surface, without extra
// joins to fetch actor handles / event titles (a later enrichment pass
// can add those). baseURL is the web app origin (APP_BASE_URL).
func renderNotificationEmail(n NotificationRow, baseURL string) Email {
	base := strings.TrimRight(baseURL, "/")
	unsub := base + "/settings/preferences"

	subject, line, path := notificationCopy(n, base)
	body := line + "\n\n" +
		"Open Threkir: " + path + "\n\n" +
		"—\n" +
		"You're receiving this because of your notification settings. " +
		"Change what gets emailed (or turn emails off) at " + unsub + "\n"

	return Email{Subject: subject, Body: body, ListUnsubscribe: unsub}
}

// notificationCopy maps a kind to (subject, body line, deep link). Kept
// in one place so adding a kind is a single edit. Unknown kinds get a
// safe generic fallback rather than an empty mail.
func notificationCopy(n NotificationRow, base string) (subject, line, path string) {
	switch n.Kind {
	case "event_reminder":
		return "Reminder: your event is coming up",
			"You have an event starting soon that you said you're going to.",
			eventPath(base, n)
	case "event_cancel":
		return "An event you were going to was cancelled",
			"One of the events you'd RSVP'd to has been cancelled.",
			eventPath(base, n)
	case "plan_update":
		return "Your training plan was updated",
			"Your coach made a change to your training plan.",
			base + "/training"
	case "message":
		return "You have a new message",
			"Someone sent you a direct message.",
			base + "/messages"
	case "event_rsvp":
		return "New RSVP to your event",
			"Someone RSVP'd to an event you organise.",
			eventPath(base, n)
	case "club_post":
		return "New post in your club",
			"There's a new post in one of your clubs.",
			clubPath(base, n)
	case "run_completed":
		return "A runner you follow finished a run",
			"Someone you follow just completed a run.",
			runPath(base, n)
	case "kudos":
		return "You got kudos",
			"Someone gave kudos to your run.",
			runPath(base, n)
	case "comment", "comment_reply":
		return "New comment on a run",
			"There's a new comment on a run.",
			runPath(base, n)
	case "follow":
		return "You have a new follower",
			"Someone started following you.",
			base + "/profile"
	default:
		return "You have a new notification",
			"You have a new notification on Threkir.",
			base + "/notifications"
	}
}

// ─────────────────── lifecycle templates (pure) ───────────────────

// renderLifecycleEmail renders a named lifecycle template. Returns ok=false
// for an unknown template so the handler skips rather than sends a blank
// email. Lifecycle mail is transactional/relationship — no List-Unsubscribe
// header (it's not a subscription); the footer still points at preferences
// for managing future email.
func renderLifecycleEmail(template, baseURL string) (Email, bool) {
	base := strings.TrimRight(baseURL, "/")
	switch template {
	case "welcome":
		body := "Thanks for signing up — welcome to Threkir!\n\n" +
			"You're all set to record your first run, build routes, and follow friends.\n\n" +
			"Get started: " + base + "\n\n" +
			"— The Threkir team\n\n" +
			"—\n" +
			"You're receiving this because you just created a Threkir account. " +
			"Manage your email at " + base + "/settings/preferences\n"
		return Email{Subject: "Welcome to Threkir", Body: body}, true
	default:
		return Email{}, false
	}
}

func eventPath(base string, n NotificationRow) string {
	if n.EventID != nil {
		return base + "/events/" + *n.EventID
	}
	return base + "/clubs"
}

func clubPath(base string, n NotificationRow) string {
	if n.ClubID != nil {
		return base + "/clubs/" + *n.ClubID
	}
	return base + "/clubs"
}

func runPath(base string, n NotificationRow) string {
	if n.RunID != nil {
		return base + "/runs/" + *n.RunID
	}
	return base + "/notifications"
}
