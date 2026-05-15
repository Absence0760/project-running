---
description: Find hard-coded English strings, en-US formatting, missing RTL support across web + mobile + watch
---

Audit internationalisation readiness.

## Goal

The app is going international. `preferred_unit` (km/mi) is wired through every formatter already — that's the *one* piece of localisation we get right. Everything else (UI strings, date / time / number formatting, currency, week start, RTL, font coverage, TTS language, email templates) is in en-US-only state today.

The audit's job is to enumerate every surface that needs work, grouped by platform owner so the user can scope the i18n investment.

## What to check

The `i18n-readiness-auditor` agent has the full per-platform checklist. Headline buckets:

- **Web (SvelteKit)**: hard-coded strings in components + routes; `Intl.DateTimeFormat` vs hand-rolled dates; currency on `/compare` + `/settings/upgrade`; week-start in `PlanCalendar` + `CalendarHeatmap`; `Accept-Language` handling in `hooks.server.ts`; CSS logical properties for RTL.
- **Flutter (mobile_android = mobile_ios)**: every `Text('...')` literal in `lib/`; `MaterialApp` localisation delegates; `intl/intl.dart` DateFormat usage; `flutter_tts.setLanguage`; `EdgeInsetsDirectional` vs `EdgeInsets`.
- **Wear OS (Compose-for-Wear)**: `stringResource(R.string.x)` vs `Text("literal")`; `res/values-XX/strings.xml` per target locale.
- **watchOS (SwiftUI)**: `LocalizedStringKey` / `NSLocalizedString` vs hard-coded literals; `Localizable.strings` per locale.
- **Server / DB**: guided-run library + coach system prompt + default route names + Supabase Auth email templates.

## Report

Group by *platform* (web / mobile / wear / watchOS / server) so the right owner gets the right list. Severity within each:

- **Critical** — UI breaks (RTL layout, missing glyph, blocked flow).
- **High** — visible wrong content (English to Japanese user, USD to EU user).
- **Medium** — formatting drift (`12/05/2026` ambiguous, decimal separator wrong).
- **Low** — convention drift (Sun-first week for en-GB).

End with **clean** — what's already localised correctly (units; surfaces that have no user-facing text).

## Delegate to

Use the `i18n-readiness-auditor` agent: `"Audit i18n readiness across web (SvelteKit) + mobile (Flutter) + wear (Compose-for-Wear) + watchOS (SwiftUI) + server."`

Read-only. Don't propose an i18n library (`paraglide` vs `sveltekit-i18n` etc.) — that's a separate decision.
