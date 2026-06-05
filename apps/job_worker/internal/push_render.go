package internal

import (
	"encoding/json"
	"strings"
)

// Web-push channel preference, stored in user_settings.prefs.push_notifications.
// Same three-mode shape + default as the email channel (email_notifications)
// so the two channels read identically; they are SEPARATE keys so a user can
// keep browser push while muting email (or vice-versa). See
// docs/backend/settings.md. Absent / non-string / unknown → "important"
// (fail toward the smaller set).
const (
	pushModeAll       = "all"
	pushModeImportant = "important"
	pushModeOff       = "off"
)

// pushMode reads the push-channel preference out of the user_settings.prefs
// bag, defaulting to "important". Mirrors emailMode.
func pushMode(prefs map[string]interface{}) string {
	v, ok := prefs["push_notifications"].(string)
	if !ok {
		return pushModeImportant
	}
	switch v {
	case pushModeAll, pushModeImportant, pushModeOff:
		return v
	default:
		return pushModeImportant
	}
}

// shouldPush decides whether a notification of the given kind is pushed under
// the resolved mode. Shares importantKinds with the email channel — the
// "what's important" classification is channel-independent.
func shouldPush(kind, mode string) bool {
	switch mode {
	case pushModeOff:
		return false
	case pushModeAll:
		return true
	default: // pushModeImportant
		return importantKinds[kind]
	}
}

// webPushPayload is the JSON the service worker's `push` handler consumes —
// the contract documented in apps/web/static/sw.js. Title surfaces as the
// system-notification title; Body is the snippet; URL is the deep link the
// `notificationclick` handler opens; Tag coalesces repeat sends of the same
// notification so a retry replaces rather than stacks.
type webPushPayload struct {
	Title string `json:"title"`
	Body  string `json:"body,omitempty"`
	URL   string `json:"url"`
	Tag   string `json:"tag"`
}

// renderWebPushPayload turns a notification row into the marshalled push
// payload, localized from the shared email catalogue (one copy source for both
// channels). The heading is the title; the inbox-preview preheader is the
// body; pathForKind is the deep link. locale is the recipient's
// user_settings.prefs.locale.
func renderWebPushPayload(n NotificationRow, baseURL, locale string) ([]byte, error) {
	base := strings.TrimRight(baseURL, "/")
	loc := normalizeEmailLocale(locale)
	s := lookupEmailStrings(loc, keyForKind(n.Kind))

	body := s.preheader
	if body == "" && len(s.body) > 0 {
		body = s.body[0]
	}
	// The deep link is a path under the web origin; the service worker opens
	// it relative to the app, so strip the origin to a path the SW matchAll
	// can compare. pathForKind already yields base+path; keep it absolute —
	// the SW opens absolute URLs fine and matchAll compares by substring.
	return json.Marshal(webPushPayload{
		Title: s.heading,
		Body:  body,
		URL:   pathForKind(n.Kind, base, n),
		Tag:   "notif-" + n.ID,
	})
}
