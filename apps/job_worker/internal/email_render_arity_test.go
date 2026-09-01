package internal

// Every localized string the worker interpolates into is a format string,
// and nothing measured the arity of one.
//
// The safety templates take the runner's name, the start time and the
// last-seen time; the SMS variants take those plus the live link; the
// digest stat labels take a count or a formatted distance. `fmt.Sprintf`
// does not fail on a mismatch — it writes the mismatch into the output.
// A translator who drops one `%s` from `safety_overdue.body[0]` ships
// `%!(EXTRA string=15:04 UTC on 2 Jan)` into the "is my runner OK" mail
// a safety contact opens; one who adds a `%` ships `%!(NOVERB)`. Both
// pass every parity check the package had, because those only ask
// whether the string is non-empty.
//
// The guard renders through the real render functions rather than
// counting verbs in the catalogue, so the arity is measured against the
// argument list the caller actually supplies, and a new template is
// covered the moment it is added to the loop rather than by a second
// hand-kept count. TestEmailRenderArity_TheDetectorSeesARealDefect
// breaks a catalogue entry and asserts the detector catches it, so the
// silence of the passing cases is evidence rather than assumption.

import (
	"fmt"
	"reflect"
	"strings"
	"testing"
)

// formatDefect returns the first `%!…` run in s, which is how fmt reports
// every arity and verb mismatch (`%!s(MISSING)`, `%!(EXTRA …)`,
// `%!d(string=…)`, `%!(NOVERB)`).
func formatDefect(s string) string {
	i := strings.Index(s, "%!")
	if i < 0 {
		return ""
	}
	end := i + 64
	if end > len(s) {
		end = len(s)
	}
	return s[i:end]
}

func TestEmailRenderArity_TheDetectorSeesFmtsOwnComplaints(t *testing.T) {
	// The whole guard rests on fmt announcing a mismatch in-band. Pinned
	// against fmt itself, because a Go release that stopped doing it would
	// turn every case below into a vacuous pass.
	// The formats are held in a slice so `go vet` reads them as runtime
	// values: it is right that these are wrong, and refusing to compile
	// them would leave the detector unmeasured.
	for _, c := range []struct {
		format string
		args   []any
	}{
		{"%s and %s", []any{"one"}},        // one verb too many
		{"%s", []any{"one", "two"}},        // one argument too many
		{"%d", []any{"not a number"}},      // the wrong kind of argument
		{"100% of the time", []any{"one"}}, // an unescaped percent
	} {
		bad := fmt.Sprintf(c.format, c.args...)
		if formatDefect(bad) == "" {
			t.Fatalf("fmt rendered %q with no in-band complaint; the detector is blind", bad)
		}
	}
	if formatDefect("a plain sentence with no verbs") != "" {
		t.Fatal("the detector fires on clean output")
	}
}

func TestEmailShared_EveryLocaleFillsEveryField(t *testing.T) {
	// Reflective rather than a hand-written field list: the list the
	// package had covered 6 of the 15 fields, so an empty
	// footerAccountDeleted or digestStatRuns shipped a blank footer or a
	// blank stat with nothing to see it. A sixteenth field is covered the
	// moment it exists.
	ty := reflect.TypeOf(emailShared{})
	if ty.NumField() < 15 {
		t.Fatalf("emailShared has %d fields, which cannot be right — reflection is reading "+
			"the wrong type and every locale would pass", ty.NumField())
	}
	for _, loc := range emailLocales {
		sh, ok := emailSharedByLocale[loc]
		if !ok {
			t.Errorf("emailSharedByLocale has no %q", loc)
			continue
		}
		v := reflect.ValueOf(sh)
		for i := 0; i < ty.NumField(); i++ {
			if ty.Field(i).Type.Kind() != reflect.String {
				continue
			}
			if strings.TrimSpace(v.Field(i).String()) == "" {
				t.Errorf("emailSharedByLocale[%q].%s is empty — it renders as a blank "+
					"footer or a blank stat, and no parity check looked at it",
					loc, ty.Field(i).Name)
			}
		}
	}
}

// safetyRenderCases is every (template, has-last-seen) pair the safety
// paths can be called with. Both arms matter: the overdue and off_route
// templates pick a DIFFERENT body paragraph per arm, with a different
// argument count, so a suite that only ever renders one of them measures
// half the catalogue.
var safetyRenderCases = []struct {
	template string
	lastSeen string
}{
	{"finish", ""},
	{"confirm", ""},
	{"overdue", ""},
	{"overdue", "2026-01-02T03:04:05Z"},
	{"off_route", ""},
	{"off_route", "2026-01-02T03:04:05Z"},
}

func renderSafetyForTest(t *testing.T, tc struct {
	template string
	lastSeen string
}, locale string) Email {
	t.Helper()
	runID := "run-1"
	e, ok := renderSafetyEmail(SafetyEmailPayload{
		Template:     tc.template,
		OwnerName:    "Ada Lovelace",
		RunID:        &runID,
		DistanceM:    5000,
		DurationS:    1800,
		ConfirmToken: "tok",
		StartedAt:    "2026-01-02T01:00:00Z",
		LastSeenAt:   tc.lastSeen,
	}, "https://example.test", locale)
	if !ok {
		t.Fatalf("renderSafetyEmail refused template %q", tc.template)
	}
	return e
}

func TestSafetyEmail_EveryLocaleAndArmRendersWithoutAFormatDefect(t *testing.T) {
	for _, loc := range emailLocales {
		for _, tc := range safetyRenderCases {
			e := renderSafetyForTest(t, tc, loc)
			for part, s := range map[string]string{
				"subject": e.Subject, "body": e.Body, "html": e.HTML,
			} {
				if d := formatDefect(s); d != "" {
					t.Errorf("safety %q/%s (last_seen=%q) %s carries %q — a catalogue "+
						"format string does not match the arguments the renderer supplies",
						tc.template, loc, tc.lastSeen, part, d)
				}
			}
			// The interpolation must actually happen: a translation that
			// dropped its verb altogether produces no fmt complaint at all,
			// only a sentence with the runner's name missing.
			if !strings.Contains(e.Subject, "Ada Lovelace") {
				t.Errorf("safety %q/%s subject %q does not name the runner — the "+
					"catalogue entry lost its verb", tc.template, loc, e.Subject)
			}
		}
	}
}

func TestSafetySms_EveryLocaleAndArmRendersWithoutAFormatDefect(t *testing.T) {
	runID := "run-1"
	for _, loc := range emailLocales {
		for _, template := range []string{"overdue", "off_route"} {
			for _, lastSeen := range []string{"", "2026-01-02T03:04:05Z"} {
				body, ok := renderSafetySms(SafetySmsPayload{
					Template:   template,
					OwnerName:  "Ada Lovelace",
					RunID:      &runID,
					StartedAt:  "2026-01-02T01:00:00Z",
					LastSeenAt: lastSeen,
				}, "https://example.test", loc)
				if !ok {
					t.Fatalf("renderSafetySms refused %q", template)
				}
				if d := formatDefect(body); d != "" {
					t.Errorf("sms %q/%s (last_seen=%q) carries %q", template, loc, lastSeen, d)
				}
				// The live link is the one actionable thing in the message.
				if !strings.Contains(body, "https://example.test/live/run-1") {
					t.Errorf("sms %q/%s (last_seen=%q) carries no live link: %q",
						template, loc, lastSeen, body)
				}
				if !strings.Contains(body, "Ada Lovelace") {
					t.Errorf("sms %q/%s (last_seen=%q) does not name the runner: %q",
						template, loc, lastSeen, body)
				}
			}
		}
	}
}

func TestDigestStatsLine_EveryLocaleRendersEveryStat(t *testing.T) {
	summary := DigestSummary{RunCount: 3, DistanceM: 21400, KudosCount: 5, NewPBs: 1}
	for _, loc := range emailLocales {
		line := digestStatsLine(summary, lookupEmailShared(loc))
		if d := formatDefect(line); d != "" {
			t.Errorf("digest stats/%s carries %q", loc, d)
		}
		// Four labels, four values. The distance label takes an already
		// formatted string and the other three take counts, so a locale
		// that swapped %d for %s would render `%!d(string=21.40 km)`
		// above; this catches the quieter case of a label that dropped
		// its verb and now reports the same figure for every runner.
		for _, want := range []string{"3", "21.40 km", "5", "1"} {
			if !strings.Contains(line, want) {
				t.Errorf("digest stats/%s = %q, missing %q", loc, line, want)
			}
		}
	}
}

// The passing cases above are only evidence if the detector can fail.
// A catalogue entry is broken in each of the three ways a translation
// realistically breaks, through the real render path, and each must be
// caught.
func TestEmailRenderArity_TheDetectorSeesARealDefect(t *testing.T) {
	original := emailCatalogue["de"]["safety_overdue"]
	t.Cleanup(func() { emailCatalogue["de"]["safety_overdue"] = original })

	for _, tc := range []struct {
		name  string
		mutel func(s emailStrings) emailStrings
	}{
		{
			name: "a body paragraph that lost one of its verbs",
			mutel: func(s emailStrings) emailStrings {
				s.body = append([]string(nil), s.body...)
				s.body[0] = strings.Replace(s.body[0], "%s", "", 1)
				return s
			},
		},
		{
			name: "a body paragraph that gained one",
			mutel: func(s emailStrings) emailStrings {
				s.body = append([]string(nil), s.body...)
				s.body[0] += " %s"
				return s
			},
		},
		{
			name: "a subject whose verb turned into a count",
			mutel: func(s emailStrings) emailStrings {
				s.subject = strings.Replace(s.subject, "%s", "%d", 1)
				return s
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			emailCatalogue["de"]["safety_overdue"] = tc.mutel(original)
			defer func() { emailCatalogue["de"]["safety_overdue"] = original }()

			e := renderSafetyForTest(t, struct {
				template string
				lastSeen string
			}{"overdue", "2026-01-02T03:04:05Z"}, "de")
			if formatDefect(e.Subject) == "" && formatDefect(e.Body) == "" {
				t.Fatalf("a broken de catalogue entry rendered clean: subject=%q body=%q",
					e.Subject, e.Body)
			}
		})
	}

	// And the SMS side, whose catalogue is a separate map with its own
	// arity contract (4 verbs with a last-seen time, 3 without).
	originalSms := smsCatalogue["fr"]
	t.Cleanup(func() { smsCatalogue["fr"] = originalSms })
	broken := originalSms
	broken.noPing = strings.Replace(broken.noPing, "%s", "", 1)
	smsCatalogue["fr"] = broken
	runID := "run-1"
	body, _ := renderSafetySms(SafetySmsPayload{
		Template: "overdue", OwnerName: "Ada", RunID: &runID,
		StartedAt: "2026-01-02T01:00:00Z",
	}, "https://example.test", "fr")
	if formatDefect(body) == "" {
		t.Fatalf("a broken fr SMS variant rendered clean: %q", body)
	}
}
