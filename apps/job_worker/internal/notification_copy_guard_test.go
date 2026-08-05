package internal

import (
	"testing"
)

// Cross-language lockstep between the TS NotificationKind union in
// apps/web/src/lib/types.ts and this package's email catalogue.
//
// The catalogue's "default" entry is a fallback for a kind a running binary
// predates — an older worker draining a queue a newer deploy is filling. It was
// silently doing double duty as the resting place for kinds we already knew
// about: achievement, challenge_complete, content_hidden and plan_assigned all
// resolved to "You have a new notification on Threkir." with an "Open Threkir"
// CTA, on the email, web-push and native-push channels at once. Nothing failed;
// production just sent content-free mail.
//
// The parity test in email_i18n_test.go checks the catalogue against ITSELF
// (every locale carries every en key), which cannot catch a key that is missing
// from en too. These guards check it against the union — the same source
// notification_link_guard_test.go reads for the deep-link guard, and the same
// one apps/web's notification_kind_coverage.test.ts reads for the inbox.

// TestEmailCatalogue_CoversEveryNotificationKind fails when a kind the database
// can store has neither its own copy nor an explicit inAppOnlyKinds exemption.
func TestEmailCatalogue_CoversEveryNotificationKind(t *testing.T) {
	en := emailCatalogue["en"]
	for _, kind := range notificationKindsFromWeb(t) {
		if inAppOnlyKinds[kind] {
			continue
		}
		key := keyForKind(kind)
		if _, ok := en[key]; !ok {
			t.Errorf("notification kind %q has no email copy (catalogue key %q) and is not in "+
				"inAppOnlyKinds — it would send the generic \"you have a new notification\" "+
				"default on email, web push and native push. Either write real copy for it in "+
				"every locale in emailLocales, or record it as in-app only with the reason",
				kind, key)
		}
	}
}

// TestRenderNotificationEmail_NoKindRendersTheDefault asserts the property the
// map-key check above cannot: that the rendered email for every emailable kind
// actually differs from the generic default. A key present but copied from
// "default" would satisfy the lockstep and still ship content-free mail.
func TestRenderNotificationEmail_NoKindRendersTheDefault(t *testing.T) {
	const base = "https://threkir.test"
	id := "9f1c3a52-0000-4000-8000-000000000001"
	for _, kind := range notificationKindsFromWeb(t) {
		if inAppOnlyKinds[kind] {
			continue
		}
		for _, loc := range emailLocales {
			def := emailCatalogue[loc]["default"]
			n := NotificationRow{ID: id, UserID: id, Kind: kind}
			msg := renderNotificationEmail(n, base, loc)
			if msg.Subject == def.subject {
				t.Errorf("%s/%s renders the generic default subject %q", loc, kind, msg.Subject)
			}
		}
	}
}

// TestInAppOnlyKinds_AreRealKinds keeps the exemption list from going stale: an
// entry for a kind the union no longer carries would silently exempt nothing
// while reading as a considered decision.
func TestInAppOnlyKinds_AreRealKinds(t *testing.T) {
	known := map[string]bool{}
	for _, k := range notificationKindsFromWeb(t) {
		known[k] = true
	}
	for kind := range inAppOnlyKinds {
		if !known[kind] {
			t.Errorf("inAppOnlyKinds exempts %q, which is not in the NotificationKind union — "+
				"drop the entry or fix the name", kind)
		}
	}
}
