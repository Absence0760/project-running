package internal

import (
	"context"
	"fmt"
	"html"
	"net/smtp"
	"strings"
	"time"
)

// EmailSender is the transport the email handlers send through. Production
// wires *SMTPSender (Mailpit in local dev on 127.0.0.1:54325; Resend / SES
// SMTP in prod). Tests substitute a fake recorder so the handler logic is
// exercised without a live SMTP server.
type EmailSender interface {
	Send(ctx context.Context, to string, msg Email) error
}

// Email is a rendered, transport-agnostic message. It carries both a
// branded HTML part and a plain-text alternative — buildMIME sends them as
// multipart/alternative so every client (and spam scorer) gets a clean
// text fallback while modern clients render the HTML. Preheader is the
// inbox preview snippet (hidden at the top of the HTML). ListUnsubscribe is
// the URL placed in the List-Unsubscribe header for a one-tap opt-out
// ("" for transactional mail that isn't a subscription).
type Email struct {
	Subject         string
	Preheader       string
	Body            string // plain-text alternative
	HTML            string // text/html part ("" → text-only message)
	ListUnsubscribe string
}

// Brand tokens — kept in lockstep with apps/web/src/app.css (--color-primary
// deep teal). Email clients can't read CSS variables, so the values are
// inlined here.
const (
	brandName  = "Threkir"
	brandColor = "#2C5F6E"
)

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

// buildMIME assembles the RFC 5322 / MIME message. When HTML is present it
// emits multipart/alternative (text first, then HTML — clients render the
// last part they understand); otherwise a bare text/plain. CRLF line
// endings per the SMTP wire format. The boundary is a fixed token — one
// message is built at a time, so it needn't be random (and randomness
// isn't available deterministically for the tests).
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

	if msg.HTML == "" {
		b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n\r\n")
		b.WriteString(toCRLF(msg.Body))
		return b.String()
	}

	const boundary = "threkir_alt_boundary_x7k2"
	fmt.Fprintf(&b, "Content-Type: multipart/alternative; boundary=\"%s\"\r\n\r\n", boundary)
	fmt.Fprintf(&b, "--%s\r\n", boundary)
	b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n\r\n")
	b.WriteString(toCRLF(msg.Body) + "\r\n")
	fmt.Fprintf(&b, "--%s\r\n", boundary)
	b.WriteString("Content-Type: text/html; charset=UTF-8\r\n\r\n")
	b.WriteString(toCRLF(msg.HTML) + "\r\n")
	fmt.Fprintf(&b, "--%s--\r\n", boundary)
	return b.String()
}

func toCRLF(s string) string { return strings.ReplaceAll(s, "\n", "\r\n") }

// extractAddr pulls the bare address out of an RFC 5322 "Name <addr>"
// string for the SMTP MAIL FROM. A plain address passes through unchanged.
func extractAddr(from string) string {
	if i := strings.LastIndex(from, "<"); i >= 0 {
		if j := strings.Index(from[i:], ">"); j >= 0 {
			return from[i+1 : i+j]
		}
	}
	return strings.TrimSpace(from)
}

// ─────────────────── shared layout (pure) ───────────────────

// emailContent is the structured copy a template produces; composeEmail
// turns it into the text + HTML parts so every email shares one layout and
// adding a template is just filling these fields.
type emailContent struct {
	lang      string   // <html lang> (BCP-47); "" → "en"
	subject   string
	preheader string   // inbox preview snippet
	heading   string   // H1
	body      []string // paragraphs
	ctaLabel  string   // button text ("" → no button)
	ctaURL    string
	footer    string // "why you're receiving this" line (localized by caller)
	prefsURL  string // manage-preferences link in the footer ("" → omit)
	prefsLabel string // localized "Manage email preferences" link text
	prefsTextPrefix string // localized plain-text footer prefix
	listUnsub string // List-Unsubscribe header value ("" → none)
}

func composeEmail(c emailContent) Email {
	return Email{
		Subject:         c.subject,
		Preheader:       c.preheader,
		Body:            renderTextBody(c),
		HTML:            renderHTMLBody(c),
		ListUnsubscribe: c.listUnsub,
	}
}

func renderTextBody(c emailContent) string {
	var b strings.Builder
	b.WriteString(c.heading + "\n\n")
	for _, p := range c.body {
		b.WriteString(p + "\n\n")
	}
	if c.ctaURL != "" {
		b.WriteString(c.ctaLabel + ": " + c.ctaURL + "\n\n")
	}
	b.WriteString("—\n")
	b.WriteString(c.footer)
	if c.prefsURL != "" {
		b.WriteString(" " + c.prefsTextPrefix + " " + c.prefsURL)
	}
	b.WriteString("\n")
	return b.String()
}

// renderHTMLBody builds an email-client-safe HTML message: table layout,
// inline styles, ≤600px centred card, a branded header bar, an H1, body
// paragraphs, a bulletproof CTA button, and a muted footer. The preheader
// is a hidden span so the inbox preview reads well without showing in the
// body. All interpolated copy is HTML-escaped (defensive — today's copy is
// static, but future enrichment may inject names / titles).
func renderHTMLBody(c emailContent) string {
	var paras strings.Builder
	for _, p := range c.body {
		fmt.Fprintf(&paras,
			`<p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#374151;">%s</p>`,
			html.EscapeString(p))
	}

	cta := ""
	if c.ctaURL != "" {
		cta = fmt.Sprintf(
			`<table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 4px;"><tr>`+
				`<td bgcolor="%s" style="border-radius:8px;">`+
				`<a href="%s" style="display:inline-block;padding:12px 26px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;">%s</a>`+
				`</td></tr></table>`,
			brandColor, html.EscapeString(c.ctaURL), html.EscapeString(c.ctaLabel))
	}

	footer := html.EscapeString(c.footer)
	if c.prefsURL != "" {
		footer += fmt.Sprintf(
			` <a href="%s" style="color:#6b7280;">%s</a>.`,
			html.EscapeString(c.prefsURL), html.EscapeString(c.prefsLabel))
	}

	lang := c.lang
	if lang == "" {
		lang = "en"
	}

	return fmt.Sprintf(`<!DOCTYPE html>
<html lang="%s"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="x-apple-disable-message-reformatting"></head>
<body style="margin:0;padding:0;background:#f4f5f7;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">%s</div>
<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;"><tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%%;background:#ffffff;border-radius:12px;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<tr><td style="background:%s;padding:20px 32px;"><span style="color:#ffffff;font-size:20px;font-weight:700;letter-spacing:0.5px;">%s</span></td></tr>
<tr><td style="padding:32px;"><h1 style="margin:0 0 16px;font-size:22px;line-height:1.3;color:#111827;">%s</h1>%s%s</td></tr>
<tr><td style="padding:20px 32px;border-top:1px solid #e5e7eb;"><p style="margin:0;font-size:12px;line-height:1.5;color:#9ca3af;">%s</p></td></tr>
</table></td></tr></table>
</body></html>`,
		lang, html.EscapeString(c.preheader), brandColor, brandName,
		html.EscapeString(c.heading), paras.String(), cta, footer)
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

// renderNotificationEmail turns a notification row into a branded, localized
// email. Copy comes from emailCatalogue[locale]; the deep-linked CTA from
// pathForKind. Generic-but-actionable: names the category and links to the
// relevant surface, without extra joins for actor handles / event titles (a
// later enrichment pass can add those). baseURL is the web app origin
// (APP_BASE_URL); locale is the recipient's user_settings.prefs.locale.
func renderNotificationEmail(n NotificationRow, baseURL, locale string) Email {
	base := strings.TrimRight(baseURL, "/")
	loc := normalizeEmailLocale(locale)
	s := lookupEmailStrings(loc, keyForKind(n.Kind))
	shared := lookupEmailShared(loc)
	return composeEmail(emailContent{
		lang:            loc,
		subject:         s.subject,
		preheader:       s.preheader,
		heading:         s.heading,
		body:            s.body,
		ctaLabel:        s.cta,
		ctaURL:          pathForKind(n.Kind, base, n),
		footer:          shared.footerNotification,
		prefsURL:        base + "/settings/preferences",
		prefsLabel:      shared.managePrefsLabel,
		prefsTextPrefix: shared.managePrefsTextPrefix,
		listUnsub:       base + "/settings/preferences",
	})
}

// pathForKind maps a notification kind to its deep link. One place so a new
// kind is a single edit alongside its catalogue entry.
func pathForKind(kind, base string, n NotificationRow) string {
	switch kind {
	case "event_reminder", "event_cancel", "event_rsvp":
		return eventPath(base, n)
	case "plan_update":
		return base + "/training"
	case "message":
		return base + "/messages"
	case "club_post":
		return clubPath(base, n)
	case "run_completed", "kudos", "comment", "comment_reply":
		return runPath(base, n)
	case "follow":
		return base + "/profile"
	default:
		return base + "/notifications"
	}
}

// ─────────────────── lifecycle templates (pure) ───────────────────

// renderLifecycleEmail renders a named lifecycle template. Returns ok=false
// for an unknown template so the handler skips rather than sends a blank
// email. Lifecycle mail is transactional/relationship — no List-Unsubscribe
// header (it's not a subscription); the footer still points at preferences
// for managing future email.
func renderLifecycleEmail(template, baseURL, locale string) (Email, bool) {
	base := strings.TrimRight(baseURL, "/")
	loc := normalizeEmailLocale(locale)
	switch template {
	case "welcome":
		s := lookupEmailStrings(loc, "welcome")
		shared := lookupEmailShared(loc)
		return composeEmail(emailContent{
			lang:            loc,
			subject:         s.subject,
			preheader:       s.preheader,
			heading:         s.heading,
			body:            s.body,
			ctaLabel:        s.cta,
			ctaURL:          base,
			footer:          shared.footerWelcome,
			prefsURL:        base + "/settings/preferences",
			prefsLabel:      shared.managePrefsLabel,
			prefsTextPrefix: shared.managePrefsTextPrefix,
			// transactional — no List-Unsubscribe.
		}), true
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
