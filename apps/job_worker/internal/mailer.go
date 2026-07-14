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
// ListUnsubscribeOneClick is true only when ListUnsubscribe points at a
// genuine RFC 8058 one-click POST endpoint (one that accepts the
// `List-Unsubscribe=One-Click` body); it gates emission of the companion
// List-Unsubscribe-Post header. It stays false for a List-Unsubscribe that is
// merely a GET preferences page — that page can't honour a one-click POST, and
// advertising List-Unsubscribe-Post for it would make Gmail/Yahoo fire a POST
// the page rejects.
type Email struct {
	Subject                 string
	Preheader               string
	Body                    string // plain-text alternative
	HTML                    string // text/html part ("" → text-only message)
	ListUnsubscribe         string
	ListUnsubscribeOneClick bool
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
		if msg.ListUnsubscribeOneClick {
			// RFC 8058. Lets Gmail/Yahoo unsubscribe with a single
			// background POST (List-Unsubscribe=One-Click) instead of
			// opening the URL — only advertised when the target endpoint
			// actually honours that POST.
			b.WriteString("List-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n")
		}
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
	lang              string // <html lang> (BCP-47); "" → "en"
	subject           string
	preheader         string   // inbox preview snippet
	heading           string   // H1
	body              []string // paragraphs
	ctaLabel          string   // button text ("" → no button)
	ctaURL            string
	footer            string // "why you're receiving this" line (localized by caller)
	prefsURL          string // manage-preferences link in the footer ("" → omit)
	prefsLabel        string // localized "Manage email preferences" link text
	prefsTextPrefix   string // localized plain-text footer prefix
	listUnsub         string // List-Unsubscribe header value ("" → none)
	listUnsubOneClick bool   // listUnsub is an RFC 8058 one-click POST endpoint
}

func composeEmail(c emailContent) Email {
	return Email{
		Subject:                 c.subject,
		Preheader:               c.preheader,
		Body:                    renderTextBody(c),
		HTML:                    renderHTMLBody(c),
		ListUnsubscribe:         c.listUnsub,
		ListUnsubscribeOneClick: c.listUnsubOneClick,
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
		if c.prefsTextPrefix != "" {
			b.WriteString(" " + c.prefsTextPrefix)
		}
		b.WriteString(" " + c.prefsURL)
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
// lifecycleTemplates is the closed set of transactional/relationship
// templates. Membership (not the catalogue's "default" fallback) is what
// gates renderLifecycleEmail — an unknown template returns ok=false so the
// handler skips rather than sending a generic "new notification" email.
var lifecycleTemplates = map[string]bool{
	"welcome":         true,
	"pro_welcome":     true,
	"payment_failed":  true,
	"account_deleted": true,
}

// inlineAddressTemplates carry the recipient's address (and locale) in the job
// payload rather than a user_id the worker resolves via GoTrue. account_deleted
// is the only one: by send time the user is GONE (admin.deleteUser ran), so
// there's no auth.users row to look up and no user_settings.prefs to read for
// the locale (decisions §121). The send-once guard is the non-cascading
// account_deletion_receipts table keyed by the email hash, NOT
// lifecycle_email_log (which cascades away with the user).
var inlineAddressTemplates = map[string]bool{
	"account_deleted": true,
}

// oncePerUserTemplates only fire once per account, so the handler dedups
// them via lifecycle_email_log. Recurring transactional mail (a re-subscribe
// receipt, a repeat billing failure) must NOT be in this set or the
// permanent log would suppress the second legitimate send.
var oncePerUserTemplates = map[string]bool{
	"welcome": true,
}

func renderLifecycleEmail(template, baseURL, locale string) (Email, bool) {
	if !lifecycleTemplates[template] {
		return Email{}, false
	}
	base := strings.TrimRight(baseURL, "/")
	loc := normalizeEmailLocale(locale)
	s := lookupEmailStrings(loc, template)
	shared := lookupEmailShared(loc)

	// account_deleted has no account left to manage — no prefs link, no CTA
	// (the catalogue leaves the CTA empty), and its own footer. Render it
	// before the standard transactional path so it never grows a dead
	// /settings/preferences link a deleted user can't use.
	if template == "account_deleted" {
		return composeEmail(emailContent{
			lang:      loc,
			subject:   s.subject,
			preheader: s.preheader,
			heading:   s.heading,
			body:      s.body,
			ctaLabel:  s.cta,
			ctaURL:    base, // the public homepage — a re-signup invitation, not an account link
			footer:    shared.footerAccountDeleted,
			// no prefsURL / List-Unsubscribe — the account is gone.
		}), true
	}

	// welcome reads as a relationship message; billing/account templates as a
	// service message.
	footer := shared.footerTransactional
	if template == "welcome" {
		footer = shared.footerWelcome
	}

	return composeEmail(emailContent{
		lang:            loc,
		subject:         s.subject,
		preheader:       s.preheader,
		heading:         s.heading,
		body:            s.body,
		ctaLabel:        s.cta,
		ctaURL:          lifecycleCtaURL(template, base),
		footer:          footer,
		prefsURL:        base + "/settings/preferences",
		prefsLabel:      shared.managePrefsLabel,
		prefsTextPrefix: shared.managePrefsTextPrefix,
		// transactional — no List-Unsubscribe.
	}), true
}

// ─────────────────── safety-contact templates (pure) ───────────────────

// renderSafetyEmail renders a safety-contact email. Returns ok=false for an
// unknown template. Safety mail is transactional/opt-in — no
// List-Unsubscribe and no manage-preferences link (the recipient opted in
// to this specific relationship; they manage it via the in-app safety page
// or the confirm-decline path, not the email_notifications preference).
//
// Dynamic copy (owner name, distance, time, confirm token) is interpolated
// here from the catalogue's format strings; composeEmail/renderHTMLBody
// HTML-escape every interpolated value.
func renderSafetyEmail(p SafetyEmailPayload, baseURL, locale string) (Email, bool) {
	base := strings.TrimRight(baseURL, "/")
	loc := normalizeEmailLocale(locale)
	shared := lookupEmailShared(loc)

	owner := strings.TrimSpace(p.OwnerName)
	if owner == "" {
		owner = shared.safetyDefaultOwner
	}

	switch p.Template {
	case "finish":
		s := lookupEmailStrings(loc, "safety_finish")
		return composeEmail(emailContent{
			lang:      loc,
			subject:   fmt.Sprintf(s.subject, owner),
			preheader: s.preheader,
			heading:   fmt.Sprintf(s.heading, owner),
			body: []string{
				fmt.Sprintf(s.body[0], formatDistanceKm(p.DistanceM), formatDurationHM(p.DurationS)),
				s.body[1],
			},
			ctaLabel: s.cta,
			ctaURL:   base,
			footer:   shared.footerSafety,
		}), true
	case "confirm":
		s := lookupEmailStrings(loc, "safety_confirm")
		return composeEmail(emailContent{
			lang:      loc,
			subject:   fmt.Sprintf(s.subject, owner),
			preheader: s.preheader,
			heading:   fmt.Sprintf(s.heading, owner),
			body: []string{
				fmt.Sprintf(s.body[0], owner),
				s.body[1],
			},
			ctaLabel: s.cta,
			ctaURL:   base + "/safety/confirm?token=" + p.ConfirmToken,
			footer:   shared.footerSafety,
		}), true
	case "overdue":
		// body[0] = variant with a last-seen time, body[1] = variant when
		// no ping ever landed (started_at is the only fact), body[2] = the
		// loss-of-signal caveat + what-to-do line. Times only, never
		// coordinates — the live page (the CTA) does the privacy-clipped
		// rendering. docs/features/safety.md.
		s := lookupEmailStrings(loc, "safety_overdue")
		var first string
		if p.LastSeenAt != "" {
			first = fmt.Sprintf(s.body[0], owner, formatTimeUTC(p.StartedAt), formatTimeUTC(p.LastSeenAt))
		} else {
			first = fmt.Sprintf(s.body[1], owner, formatTimeUTC(p.StartedAt))
		}
		ctaURL := base
		if p.RunID != nil && *p.RunID != "" {
			ctaURL = base + "/live/" + *p.RunID
		}
		return composeEmail(emailContent{
			lang:      loc,
			subject:   fmt.Sprintf(s.subject, owner),
			preheader: s.preheader,
			heading:   fmt.Sprintf(s.heading, owner),
			body:      []string{first, s.body[2]},
			ctaLabel:  s.cta,
			ctaURL:    ctaURL,
			footer:    shared.footerSafety,
		}), true
	case "off_route":
		// Sibling of "overdue" but for a runner who LEFT their planned route
		// rather than going silent. Same 3-paragraph shape: body[0] = a
		// last-seen variant, body[1] = a no-ping variant, body[2] = the
		// detour/glitch caveat. Times only, never coordinates — the /live CTA
		// does the privacy-clipped rendering. docs/features/safety.md.
		s := lookupEmailStrings(loc, "safety_off_route")
		var first string
		if p.LastSeenAt != "" {
			first = fmt.Sprintf(s.body[0], owner, formatTimeUTC(p.StartedAt), formatTimeUTC(p.LastSeenAt))
		} else {
			first = fmt.Sprintf(s.body[1], owner, formatTimeUTC(p.StartedAt))
		}
		ctaURL := base
		if p.RunID != nil && *p.RunID != "" {
			ctaURL = base + "/live/" + *p.RunID
		}
		return composeEmail(emailContent{
			lang:      loc,
			subject:   fmt.Sprintf(s.subject, owner),
			preheader: s.preheader,
			heading:   fmt.Sprintf(s.heading, owner),
			body:      []string{first, s.body[2]},
			ctaLabel:  s.cta,
			ctaURL:    ctaURL,
			footer:    shared.footerSafety,
		}), true
	default:
		return Email{}, false
	}
}

// ─────────────────── weekly-digest template (pure) ───────────────────

// renderWeeklyDigest renders the opt-in weekly engagement digest. The copy
// comes from the catalogue's "weekly_digest" key; the middle paragraph is a
// stats line built from the DigestSummary + localized stat labels. A
// List-Unsubscribe header + an unsubscribe footer link both carry the
// RFC 8058 HMAC token (unsubURL) — the recipient opted in, so they can opt
// out one-tap. A week with no runs swaps the stats line for the quiet-week
// nudge so the email never reads as a broken template.
//
// unsubURL is the full, token-bearing unsubscribe URL (built by the handler
// from APP_BASE_URL + the user id + the HMAC token); "" omits the
// List-Unsubscribe header + footer link (a misconfigured secret), which is
// the fail-safe — no header is better than a forgeable one.
func renderWeeklyDigest(s DigestSummary, baseURL, locale, unsubURL string) Email {
	base := strings.TrimRight(baseURL, "/")
	loc := normalizeEmailLocale(locale)
	cat := lookupEmailStrings(loc, "weekly_digest")
	shared := lookupEmailShared(loc)

	// Body: intro, then a stats line (or the quiet-week nudge), then the
	// closing nudge. The catalogue body is [intro, nudge]; we splice the
	// stats line between them.
	body := make([]string, 0, 3)
	body = append(body, cat.body[0])
	if s.RunCount == 0 && s.KudosCount == 0 && s.NewPBs == 0 {
		body = append(body, shared.digestQuietWeek)
	} else {
		body = append(body, digestStatsLine(s, shared))
	}
	if len(cat.body) > 1 {
		body = append(body, cat.body[1])
	}

	return composeEmail(emailContent{
		lang:            loc,
		subject:         cat.subject,
		preheader:       cat.preheader,
		heading:         cat.heading,
		body:            body,
		ctaLabel:        cat.cta,
		ctaURL:          base,
		footer:          shared.footerDigest,
		prefsURL:        unsubURL,
		prefsLabel:      shared.managePrefsLabel,
		prefsTextPrefix: "",
		listUnsub:       unsubURL,
		// The digest's unsubscribe URL is the RFC 8058 one-click endpoint
		// (internal/unsubscribe), which honours the POST body. The
		// notification path's List-Unsubscribe is a GET preferences page, so it
		// stays false there.
		listUnsubOneClick: true,
	})
}

// ─────────────────── lifecycle-drip templates (pure) ───────────────────

// dripTemplates is the closed set of lifecycle-drip template keys. Membership
// gates renderLifecycleDrip — an unknown template returns ok=false so the
// handler skips rather than sending a generic email. These are the SAME keys
// the enqueue_lifecycle_drip() SQL function writes into the job payload
// (migration 20270223_001).
var dripTemplates = map[string]bool{
	"drip_onboarding":   true,
	"drip_first_week":   true,
	"drip_reengagement": true,
	"drip_streak":       true,
}

// renderLifecycleDrip renders an opt-in lifecycle-drip nudge (onboarding /
// re-engagement / streak). Returns ok=false for an unknown template so the
// handler skips rather than sending a blank email. The copy is fixed per
// template from the catalogue (no per-recipient stats — a drip is a single
// nudge, unlike the digest's summary). Like the digest it carries an RFC 8058
// one-click unsubscribe (the recipient opted in); a "" unsubURL omits the
// header + footer link (a misconfigured secret) rather than emit a forgeable
// one. The CTA lands on the app home, which is where recording starts on
// every platform (the same target the welcome / digest use) — no template
// links a record path that doesn't exist on web.
func renderLifecycleDrip(template, baseURL, locale, unsubURL string) (Email, bool) {
	if !dripTemplates[template] {
		return Email{}, false
	}
	base := strings.TrimRight(baseURL, "/")
	loc := normalizeEmailLocale(locale)
	cat := lookupEmailStrings(loc, template)
	shared := lookupEmailShared(loc)

	return composeEmail(emailContent{
		lang:              loc,
		subject:           cat.subject,
		preheader:         cat.preheader,
		heading:           cat.heading,
		body:              cat.body,
		ctaLabel:          cat.cta,
		ctaURL:            base,
		footer:            shared.footerDrip,
		prefsURL:          unsubURL,
		prefsLabel:        shared.managePrefsLabel,
		prefsTextPrefix:   "",
		listUnsub:         unsubURL,
		listUnsubOneClick: true,
	}), true
}

// digestStatsLine joins the non-trivial weekly stats into one human line,
// e.g. "3 runs · 21.40 km total · 5 kudos · 1 new personal bests". Each
// label is a localized format string from emailShared. Zero-valued stats
// are dropped so a runner with runs-but-no-PBs doesn't see "0 new personal
// bests".
func digestStatsLine(s DigestSummary, shared emailShared) string {
	parts := make([]string, 0, 4)
	if s.RunCount > 0 {
		parts = append(parts, fmt.Sprintf(shared.digestStatRuns, s.RunCount))
		parts = append(parts, fmt.Sprintf(shared.digestStatDistance, formatDistanceKm(s.DistanceM)))
	}
	if s.KudosCount > 0 {
		parts = append(parts, fmt.Sprintf(shared.digestStatKudos, s.KudosCount))
	}
	if s.NewPBs > 0 {
		parts = append(parts, fmt.Sprintf(shared.digestStatPBs, s.NewPBs))
	}
	return strings.Join(parts, " · ")
}

// formatDistanceKm renders metres as km with two decimals — locale-neutral
// (the email's words localize, the number doesn't, matching the other
// templates). A safety alert favours an unambiguous metric figure.
func formatDistanceKm(metres float64) string {
	return fmt.Sprintf("%.2f km", metres/1000)
}

// formatTimeUTC renders an ISO timestamp as "15:04 UTC on 2 Jan". The
// recipient's timezone is unknown (they may not be a user at all), so an
// explicitly-labelled UTC wall clock is the honest rendering. Unparseable
// input falls back to the raw string rather than dropping the fact.
func formatTimeUTC(iso string) string {
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		return iso
	}
	return t.UTC().Format("15:04 UTC on 2 Jan")
}

// formatDurationHM renders seconds as "Hh MMm" (or "Mm" under an hour).
func formatDurationHM(seconds int) string {
	if seconds < 0 {
		seconds = 0
	}
	h := seconds / 3600
	m := (seconds % 3600) / 60
	if h > 0 {
		return fmt.Sprintf("%dh %02dm", h, m)
	}
	return fmt.Sprintf("%dm", m)
}

// lifecycleCtaURL maps a lifecycle template to its CTA target.
func lifecycleCtaURL(template, base string) string {
	switch template {
	case "payment_failed":
		return base + "/settings/upgrade"
	default: // welcome, pro_welcome
		return base
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
