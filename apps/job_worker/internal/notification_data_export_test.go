package internal

// The data-export-ready notification's one load-bearing property
// (decisions.md § 729).
//
// The follow-up that asked for this message stood unbuilt for months
// with a specific reason: an asynchronous mail announcing a 10-minute
// signed URL would arrive stale. What answered that objection was not
// the message getting faster — it was § 717 refusing to store the URL
// at all. The row holds an object PATH, the status endpoint signs at
// read time, and the message therefore carries a link to the page and
// nothing else.
//
// The moment this notification carries a URL of its own, the original
// objection is back and every recipient gets a link that may already be
// spent. So the absence is asserted rather than left to the copy.

import (
	"strings"
	"testing"
)

const exportReadyKind = "data_export_ready"

func TestDataExportNotification_PointsAtThePageAndNowhereElse(t *testing.T) {
	base := "https://threkir.com"
	row := NotificationRow{Kind: exportReadyKind, UserID: "usr-1"}
	got := pathForKind(exportReadyKind, base, row)
	if got != base+"/settings/account" {
		t.Fatalf("target=%q, want the account page", got)
	}
	// No id of any kind. The export lives in `data_export_jobs`, which
	// the notifications projection has no column for and does not need —
	// the endpoint answers for the subject's LATEST export.
	if strings.Contains(got, "?") || strings.Contains(got, "usr-1") {
		t.Fatalf("target=%q carries state it should not", got)
	}
}

func TestDataExportNotification_CarriesNoDownloadUrlInAnyLocale(t *testing.T) {
	base := "https://threkir.com"
	row := NotificationRow{Kind: exportReadyKind, UserID: "usr-1"}
	// Every catalogue, plus an unknown tag so the English fallback is
	// exercised on the same terms.
	locales := make([]string, 0, len(emailCatalogue)+1)
	for loc := range emailCatalogue {
		locales = append(locales, loc)
	}
	locales = append(locales, "zz")

	for _, loc := range locales {
		mail := renderNotificationEmail(row, base, loc)
		for _, part := range []struct {
			name string
			text string
		}{
			{"subject", mail.Subject},
			{"preheader", mail.Preheader},
			{"body", mail.Body},
			{"html", mail.HTML},
		} {
			lower := strings.ToLower(part.text)
			for _, banned := range []string{"token=", "/object/sign/", "signedurl", "expiresin", "/storage/v1/"} {
				if strings.Contains(lower, banned) {
					t.Errorf("%s %s carries %q — a signed URL in this message "+
						"restores the staleness objection § 729 answered", loc, part.name, banned)
				}
			}
		}
		if mail.Subject == "" || mail.Body == "" {
			t.Errorf("%s: the notification rendered empty", loc)
		}
		// The only link the message needs is the page, and the
		// preferences link every notification mail carries.
		if !strings.Contains(mail.Body, base+"/settings/account") {
			t.Errorf("%s: the body does not link to the account page", loc)
		}
	}
}

func TestDataExportNotification_ThePerKindKeyCannotPromoteItPastAMutedPush(t *testing.T) {
	// mailer_test's TestKindMute_OnlyEverSubtracts pins this direction on
	// email. Push is the channel that matters most here: § 724 refused a
	// background poller on the grounds that iOS background refresh is
	// opportunistic, so a locked-phone push is how a mobile subject
	// learns the archive landed — and a per-kind key that could switch it
	// back on past a channel mute would be a way to reach a runner who
	// turned pushes off.
	if !shouldPush(exportReadyKind, map[string]interface{}{"push_notifications": pushModeImportant}) {
		t.Error("the export notice must push under the default mode")
	}
	if shouldPush(exportReadyKind, map[string]interface{}{
		"push_notifications": pushModeOff, "notify_data_export_ready": "on",
	}) {
		t.Error("a per-kind 'on' promoted the kind past push_notifications=off")
	}
}

func TestDataExportNotification_TheInboxRowIsNeverWithheld(t *testing.T) {
	// The mute has exactly the scope the channel settings have, which is
	// the OUTBOUND channels. A subject who silenced the mail still finds
	// the archive announced in their own inbox.
	muted := map[string]interface{}{
		"email_notifications":      emailModeOff,
		"push_notifications":       pushModeOff,
		"notify_data_export_ready": "off",
	}
	if shouldEmail(exportReadyKind, muted) || shouldPush(exportReadyKind, muted) {
		t.Fatal("the outbound channels must be silent")
	}
	// The inbox row is written by notify_data_export_ready() in SQL,
	// which consults no preference at all — the worker only reports
	// whether the RPC was the call that announced.
	src := readWorkerSource(t, "handler_data_export.go")
	for _, banned := range []string{"kindMuted", "shouldEmail", "shouldPush", "prefs"} {
		if strings.Contains(src, banned) {
			t.Errorf("the export handler consults %q; the inbox row is not the mute's scope", banned)
		}
	}
}
