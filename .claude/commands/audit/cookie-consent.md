---
description: Verify every third-party SDK / script / fetch is gated on consent for EU users (ePrivacy + GDPR)
---

Audit the web app's cookie + script consent posture. Every non-essential third-party load on an EU IP must be gated on the user's affirmative consent.

## Goal

ePrivacy Directive Art 5(3) (still in force) + GDPR (consent must be freely given, specific, informed, unambiguous) require:
- A consent banner before any non-essential cookie or third-party script fires.
- Granular toggles (analytics / functional / marketing) rather than one all-or-nothing button.
- Equally prominent "Reject all" alongside "Accept all" (UK ICO + French CNIL guidance — multiple regulator fines in 2024 for dark patterns).
- A "withdraw consent" path that's no harder to reach than the original opt-in.

This project has **no consent banner today**. The audit's job is to enumerate every third-party load that would need to be gated, so the user knows the scope of work before deciding to ship a banner.

## What to check

1. **Page-load chain.** Walk `apps/web/src/app.html`, `apps/web/src/routes/+layout.svelte`, `apps/web/src/routes/+layout.server.ts`, every `+page.server.ts` and `+layout.ts`. Anything that fires on `mount` or in SSR top-level that hits a non-essential third-party.
2. **Sentry.** Web + mobile Sentry SDKs may fire before consent. Confirm `enabled: false` on load, `Sentry.init` is deferred until consent, and that **session replay** is OFF by default everywhere — replay is the highest-risk feature because it captures the DOM.
3. **RevenueCat web SDK.** `@revenuecat/purchases-js` — verify it doesn't fire any analytics on import.
4. **MapTiler tile fetches.** Every render of `<RunMap>`, `<TrackPreview>`, `<RouteBuilder>` fetches map tiles. MapTiler logs the requesting IP per tile fetch. Map fetches need consent under strict ePrivacy reading, **but** they're plausibly justifiable as "strictly necessary" for an essential feature (showing a run on a map). Document the position; it's defensible if disclosed in the cookie notice.
5. **Anthropic streaming endpoint.** `/api/coach` calls Anthropic. The user-initiated nature means consent is implicit when they tap the Coach button — but the *first-load* fetch of the page doesn't need to fire Anthropic. Verify nothing pre-warms it.
6. **OpenAI fallback.** Same as Anthropic.
7. **OAuth redirects (Google / Apple).** Pre-click, the buttons must not fire any provider SDK. The redirect itself is user-initiated → consent implicit.
8. **Open-Meteo, OSRM, Strava API.** Server-side or post-action; check none are called from the unauthenticated landing page.
9. **Local-storage / IndexedDB.** Storing settings keyed by `user_id` is fine; storing a tracking identifier or session pings on first visit is not. Grep `localStorage`, `sessionStorage`, `indexedDB`.
10. **Cookies.** Walk `Set-Cookie` headers. Supabase Auth cookies are *strictly necessary* (the user is logged in). Any other cookie (analytics, session replay, ads) needs the banner gate.

## Report

- **Critical** — a third-party SDK that captures PII (Sentry replay, analytics, ads) fires before consent and is on by default.
- **High** — a non-essential third-party load that fires on the unauthenticated landing page.
- **Medium** — a third-party load that's gated *only* on auth (anon EU user still hits it on /, /login, /privacy).
- **Low** — a third-party that's plausibly essential (map tiles) but not yet disclosed in any cookie notice (there is no notice today).

For each: the file/line that fires the load, what data it carries, and how to gate it (deferred init, conditional load, etc.).

End with a **clean** section listing third-party loads that fire only after user-initiated action (clicking Coach, opening a map screen, signing in) and are therefore implicit-consent-defensible.

## Delegate to

Use the `compliance-auditor` agent: `"Audit the web app's cookie + third-party-SDK consent posture per ePrivacy Art 5(3) + GDPR."`

Read-only. Findings only.

## Output → `reviews/`

Persist the findings to `reviews/audit-cookie-consent.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
