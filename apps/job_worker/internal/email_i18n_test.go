package internal

import (
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

func TestNormalizeEmailLocale(t *testing.T) {
	cases := map[string]string{
		"en": "en", "de": "de", "fr": "fr", "es": "es", "ja": "ja", "pt-BR": "pt-BR",
		"de-DE": "de", "en-US": "en", "ja-JP": "ja",
		"pt": "pt-BR", "pt-PT": "pt-BR", "PT-br": "pt-BR",
		"":   "en",
		"xx": "en", "zh-CN": "en",
	}
	for in, want := range cases {
		if got := normalizeEmailLocale(in); got != want {
			t.Errorf("normalizeEmailLocale(%q) = %q, want %q", in, got, want)
		}
	}
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
