---
description: Verify signup + Pro purchase + AI coach are reachable in every country the app is offered
---

Audit regional availability: which countries can sign up, which can buy Pro, which can use the AI Coach, and where the answers diverge.

## Goal

The classic launch bug: a user signs up from a country where Stripe isn't supported, becomes engaged, taps "Upgrade to Pro", and hits a wall. Or signs up in a country where Anthropic's API is geo-blocked and the Coach 500s forever. The audit job is to make the available-feature surface match the target country list, and the target country list match reality (Apple/Google country availability + Stripe + AI APIs + sanctions).

## What to check

1. **Country list per channel.**
   - **Web app**: Anyone with internet today. No country gate on signup. AWS CloudFront serves globally.
   - **iOS App Store**: Country availability is set in App Store Connect. Confirm the list — common pattern is "ship globally except sanctioned + low-priority".
   - **Play Store**: Same exercise.
   - **Wear OS**: Inherits Android country list.
   - **Apple Watch**: Inherits iOS.
2. **Payment paths.**
   - **Stripe direct** (web `/settings/upgrade`): supported countries list at <https://stripe.com/global>. Roughly 46 today. Buyer can be anywhere; the *merchant* (us) must be in a supported country.
   - **RevenueCat → Apple / Google IAP**: country list inherited from the store. Wider than Stripe (~175 countries each).
   - Confirm the web Upgrade page works for an EU buyer; confirm mobile IAP works for non-Stripe countries.
3. **AI Coach API regions.**
   - **Anthropic**: now globally available. Verify current region availability for any tighter constraints.
   - **OpenAI** (fallback): country exclusion list at <https://platform.openai.com/docs/supported-countries>. Notably excludes China, Iran, Russia, North Korea, others.
4. **OAuth providers.**
   - **Google Sign-In**: globally supported.
   - **Apple Sign-In**: required on iOS for any app with third-party sign-in; supports the same countries as Apple ID.
5. **Sanctions / export-control screens.**
   - US OFAC SDN list (any user, any country).
   - EU consolidated financial sanctions list.
   - UK OFSI.
   - Apple + Google enforce these at the store-availability layer; we don't have to screen signups directly, but if we ship via web outside the stores, signup-time check is required.
6. **In-app integrations with regional bias.**
   - **parkrun**: UK-founded, present in ~25 countries. Don't show the integration prompt to users in countries with no parkrun events; or surface it with "no events near you" instead.
   - **Strava / Garmin / Health Connect / HealthKit**: global.
   - **MapTiler tiles**: global; some countries (Crimea) may render incomplete.
7. **Locale-dependent feature defaults.**
   - Distance unit (km vs mi) defaults — already handled by `preferred_unit`, but check the *default* on first signup: should follow `navigator.language` / `Accept-Language` / OS locale (US/UK/Liberia/Myanmar → mi, rest → km).
   - Weekday-first (Mon vs Sun) — affects week-grid + plan rendering. ISO 8601 says Mon; en-US says Sun.
   - Date / time / number formatting — should use `Intl.*` everywhere; audit hard-coded `dd/mm/yyyy` etc.
8. **Currency.** Display prices in user's local currency where Stripe + RevenueCat support it. The current `/compare`, `/settings/upgrade`, `/coach` paywall surfaces — what currency do they show? Hard-coded USD?

## Report

- **Critical** — a user can sign up + use the app fully in a country where they can never pay (Stripe-unsupported + IAP-unavailable on their store).
- **High** — a feature 500s instead of degrading gracefully in a country where the upstream is geo-blocked.
- **Medium** — locale defaults mismatch (UK user defaulted to mi, JP user defaulted to Sunday week-start).
- **Low** — currency shown only in USD, no `Intl.NumberFormat`.

For each: the file/flow + the country / region + the proposed gate (block signup / block feature / show alternate UI).

End with a **clean** section: features confirmed to work globally without geo-restriction.

## Delegate to

Use the `compliance-auditor` agent: `"Audit regional availability and feature reachability per country."`

Read-only. Findings only.

## Output → `reviews/`

Persist the findings to `reviews/audit-regional-availability.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
