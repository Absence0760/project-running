package internal

import (
	"sort"
	"strings"
	"testing"
)

// TestEmailCatalogueParity is the worker's mirror of the web/mobile
// l10n-parity tests: every supported locale must carry every key the
// English template has, with no empty strings. A missing translation would
// otherwise silently fall back to English mid-email.
func TestEmailCatalogueParity(t *testing.T) {
	en := emailCatalogue["en"]
	for _, loc := range emailLocales {
		cat, ok := emailCatalogue[loc]
		if !ok {
			t.Fatalf("locale %q missing from emailCatalogue", loc)
		}
		if len(cat) != len(en) {
			t.Errorf("locale %q has %d keys, en has %d", loc, len(cat), len(en))
		}
		for key, enStr := range en {
			s, ok := cat[key]
			if !ok {
				t.Errorf("locale %q missing key %q", loc, key)
				continue
			}
			if strings.TrimSpace(s.subject) == "" || strings.TrimSpace(s.preheader) == "" ||
				strings.TrimSpace(s.heading) == "" || strings.TrimSpace(s.cta) == "" {
				t.Errorf("locale %q key %q has an empty field", loc, key)
			}
			if len(s.body) != len(enStr.body) {
				t.Errorf("locale %q key %q has %d body paragraphs, en has %d", loc, key, len(s.body), len(enStr.body))
			}
			for i, p := range s.body {
				if strings.TrimSpace(p) == "" {
					t.Errorf("locale %q key %q body[%d] is empty", loc, key, i)
				}
			}
		}
		// Shared strings present + non-empty.
		sh, ok := emailSharedByLocale[loc]
		if !ok {
			t.Errorf("locale %q missing from emailSharedByLocale", loc)
			continue
		}
		if sh.footerNotification == "" || sh.footerWelcome == "" || sh.managePrefsLabel == "" || sh.managePrefsTextPrefix == "" {
			t.Errorf("locale %q has an empty shared string", loc)
		}
		if sh.footerDigest == "" || sh.footerDrip == "" {
			t.Errorf("locale %q has an empty engagement-mail footer", loc)
		}
	}
}

// TestNormalizeEmailLocale pins the tag→catalogue table against the web
// negotiator's (apps/web/src/lib/i18n/locale.ts). The Portuguese rows used to
// pin the OPPOSITE rule — `pt` and `pt-PT` both asserted to be "pt-BR" — so
// the one test covering this function was the thing keeping a Lisbon reader's
// inbox Brazilian while the browser and the wrist had already moved
// (decisions § 761).
func TestNormalizeEmailLocale(t *testing.T) {
	cases := map[string]string{
		"en": "en", "de": "de", "fr": "fr", "es": "es", "ja": "ja",
		"pt-BR": "pt-BR", "pt-PT": "pt-PT",
		"de-DE": "de", "en-US": "en", "ja-JP": "ja", "de_AT": "de",
		// Brazilian is reached by its own tag, which every browser, Android
		// and iOS report. The bare tag and the other European-orthography
		// regions have nowhere else to land, so they resolve to European —
		// the same call BASE_TO_LOCALE.pt makes on web.
		"pt": "pt-PT", "PT-br": "pt-BR", "pt_PT": "pt-PT",
		"pt-AO": "pt-PT", "pt-MZ": "pt-PT", "pt-CV": "pt-PT",
		"":   "en",
		"xx": "en", "zh-CN": "en",
	}
	for in, want := range cases {
		if got := normalizeEmailLocale(in); got != want {
			t.Errorf("normalizeEmailLocale(%q) = %q, want %q", in, got, want)
		}
	}
}

// TestEmailLocaleSetIsDerivedAndReachable is the guard a seventh locale needs
// and the six shipped ones never had: that the locale set is one set, not four
// hand-kept ones, and that every catalogue in it can actually be reached.
//
// A catalogue nothing normalizes to is dead weight nobody can see — the shape
// § 740 named on the client side — and a locale in the normalizer's tables
// with no catalogue behind it renders English while claiming otherwise. Both
// directions are checked here because emailLocales itself is now derived from
// emailCatalogue, so the parity test above can no longer catch either.
func TestEmailLocaleSetIsDerivedAndReachable(t *testing.T) {
	if len(emailLocales) == 0 {
		t.Fatal("emailLocales is empty — catalogueLocales() derived nothing")
	}
	for i := 1; i < len(emailLocales); i++ {
		if emailLocales[i-1] >= emailLocales[i] {
			t.Fatalf("emailLocales is not sorted/unique: %v", emailLocales)
		}
	}

	// The three catalogues carry exactly the same locales. Ranging
	// emailLocales only proves one direction; a locale present in
	// emailSharedByLocale or smsCatalogue but not in emailCatalogue would
	// otherwise be invisible to every test in the package.
	for name, got := range map[string][]string{
		"emailSharedByLocale": sortedLocaleKeys(emailSharedByLocale),
		"smsCatalogue":        sortedLocaleKeys(smsCatalogue),
	} {
		if strings.Join(got, ",") != strings.Join(emailLocales, ",") {
			t.Errorf("%s carries %v, emailCatalogue carries %v", name, got, emailLocales)
		}
	}

	shipped := map[string]bool{}
	for _, loc := range emailLocales {
		shipped[loc] = true
	}
	// Nothing in the normalizer may point at a catalogue that does not exist.
	for tag, loc := range emailExact {
		if !shipped[loc] {
			t.Errorf("emailExact[%q] = %q, which has no catalogue", tag, loc)
		}
	}
	for base, loc := range emailBase {
		if !shipped[loc] {
			t.Errorf("emailBase[%q] = %q, which has no catalogue", base, loc)
		}
	}
	// And every catalogue is reachable by its own tag — the exact-match row
	// is what a client writing the canonical value into prefs.locale hits.
	for _, loc := range emailLocales {
		if got := normalizeEmailLocale(loc); got != loc {
			t.Errorf("catalogue %q is unreachable: normalizeEmailLocale(%q) = %q", loc, loc, got)
		}
	}
}

func sortedLocaleKeys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func TestLocaleFromPrefs(t *testing.T) {
	if got := localeFromPrefs(map[string]interface{}{"locale": "de"}); got != "de" {
		t.Errorf("got %q, want de", got)
	}
	if got := localeFromPrefs(map[string]interface{}{}); got != "en" {
		t.Errorf("missing key should default en, got %q", got)
	}
	if got := localeFromPrefs(map[string]interface{}{"locale": 5}); got != "en" {
		t.Errorf("non-string should default en, got %q", got)
	}
	if got := localeFromPrefs(nil); got != "en" {
		t.Errorf("nil prefs should default en, got %q", got)
	}
}

func TestRenderNotificationEmail_Localized(t *testing.T) {
	ev := "evt-1"
	n := NotificationRow{Kind: "event_reminder", EventID: &ev}

	de := renderNotificationEmail(n, "https://threkir.test", "de")
	if de.Subject != emailCatalogue["de"]["event_reminder"].subject {
		t.Errorf("de subject = %q, want the German catalogue subject", de.Subject)
	}
	if !strings.Contains(de.HTML, `lang="de"`) {
		t.Error("de email HTML should carry lang=\"de\"")
	}
	// The deep link is locale-independent.
	if !strings.Contains(de.Body, "https://threkir.test/events/evt-1") {
		t.Error("de email should still deep-link the event")
	}

	// Unknown locale → English.
	xx := renderNotificationEmail(n, "https://threkir.test", "xx")
	if xx.Subject != emailCatalogue["en"]["event_reminder"].subject {
		t.Errorf("unknown locale should fall back to English subject, got %q", xx.Subject)
	}
}

func TestRenderLifecycleEmail_Localized(t *testing.T) {
	ja, ok := renderLifecycleEmail("welcome", "https://threkir.test", "ja")
	if !ok {
		t.Fatal("welcome should render")
	}
	if ja.Subject != emailCatalogue["ja"]["welcome"].subject {
		t.Errorf("ja subject = %q, want the Japanese catalogue subject", ja.Subject)
	}
	if !strings.Contains(ja.HTML, `lang="ja"`) {
		t.Error("ja welcome HTML should carry lang=\"ja\"")
	}
}
