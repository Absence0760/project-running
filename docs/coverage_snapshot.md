# Coverage snapshot — 2026-05-16

**Snapshot, not source of truth.** This is the baseline from which the "push every area to 90%" work starts. Estimates answer: "would CI catch a regression in this feature before merge?" — not measured line coverage. Roll-up at the bottom.

## Session-end update — 2026-05-16

This session moved 13 web surfaces above 75%, added the People tab to fill the find-other-runners gap, restructured `tests-e2e/` to mirror app routes, and fixed 6 real app bugs surfaced by the new tests. `/recap/[year]` and `/explore` were the last two web rows lifted in the session; both now pin invalid-input and anon paths in addition to the happy-path render.

| Surface | Was | Now | What changed |
|---|---|---|---|
| `/social` | — | 90% | NEW top-level hub (didn't exist) — ARIA tab strip (Feed / People / Clubs) with `?tab=` URL state; replaces the `/u/[me]?tab=feed` self-only feed and the old `/clubs` browse landing |
| `/social?tab=people` | — | 90% | NEW — search saga + suggestion empty state covered; only top-level surface for finding other runners (fills the gap left when feed moved off `/u/[me]`) |
| `/social?tab=feed` | 75% (under `/u/[me]`) | 75% | NEW location — feed migrated from `/u/[me]?tab=feed`; legacy `?tab=feed` deep links bounce through |
| `/auth/reset` | 0% | 75% | Full Mailpit round-trip (request → email → token → new password → re-login). **Fix**: `/auth/reset` was missing from `shellLessExact` in `+layout.svelte`, so the reset link silently rendered through the signed-in shell |
| `/plans/new` | 50% | 90% | Full wizard, replace-active path, week-edit persistence (clicking a week to expand the day-by-day editor — edits now persist on submit) |
| `/routes/new` | 50% | 75% | Save modal round-trip + description persisted. **Fix**: route description was silently dropped on Save Route — migration `20260902_001_routes_description.sql` + `saveRoute` + render |
| `/settings/integrations` | 50% | 90% | Connected-state UI + disconnect ConfirmDialog. **Fix**: Disconnect had no confirm dialog — added a `ConfirmDialog` so destructive disconnect goes through a confirm modal (matches the rest of the app) |
| `/live/[id]` | 50% | 75% | Finished state + named-runner + planted pings. **Fix**: dead `'finished'` status path + Anonymous-runner anon read + invalid `hsl()` avatar alpha (avatar fell through to white) |
| `/live/event/[id]/[instance]` | 50% | 75% | 3-runner leaderboard with planted positions; mutex on leader badge |
| `/runs/new` | 50% | 90% | 15 tests: page chrome, save round-trip → /runs/[id], distance/duration validation (zero/negative blocked), decimal km, activity-chip persistence (run/walk/hike/cycle), source pinned to `app` with `metadata.manual_entry=true` (the CHECK constraint rejects `'manual'`), no-prefill contract on `?distance=...&activity=...`, started_at near-now defaulting, discard-mid-form plants no row. **Fix**: RunEditor activity chips were rendered inside a `<label class="field">` wrapping a `<span class="field-label">Activity</span>` — the wrapping label leaked into the accessible name of the active chip (it appeared as `button "Activity Walk Hike Cycle": Run`). Switched to `<fieldset>/<legend>` with `role="radiogroup"` + `role="radio"` + `aria-checked` so each chip has a clean name. |
| `/clubs/new` | 50% | 90% | 9 tests: page chrome (kicker + h1 + tagline + back-link to `/social?tab=clubs`), visibility × join-policy matrix (public+open, public+request, private→invite with token generated, public→private→public coercion back to open), slug derivation + `/clubs/[slug]` resolves, viewer auto-enrolled as owner (`enroll_club_owner_trigger`), Create-club disabled until name, discard mid-form plants no row, Cancel returns to social. **Fix**: back-link pointed to `/clubs` (which redirects to `/social?tab=clubs`); now points directly to the canonical URL, and `cameFromClubs` recognises arrivals from `/social` too. |
| `/recap/[year]` | 50% | 90% | 8 → 12 tests: future-year `2099` empty hero, year-before-join `2011` empty hero, non-numeric year `/recap/foo` ≤ 4xx (not 500), Share-recap **clipboard round-trip** (clipboard-write permission + `navigator.share = undefined` so the fall-through path fires + `page.on('dialog')` captures the success alert + `navigator.clipboard.readText()` asserts the recap summary lines), Wrap-it-up closing CTA also triggers copy. Page contract: no `/og/recap/<year>.png` endpoint — the affordance is `navigator.share` ➜ clipboard + alert fallback. |
| `/explore` | 25% | 75% | 1 → 5 tests: redirect resolves to `/routes?tab=explore`, Explore tab is `aria-selected="true"` post-redirect, mutex against My routes / Heatmap, URL preserves no extra query params, **anon redirect chain** — anon visitor hits `/explore` → auth-wall redirects through `/login` with `?return_to=` |
| `/settings/devices` | — | (parallel agent) | (parallel agent output) |
| `/settings/licenses` | — | (parallel agent) | (parallel agent output) |
| `/compare` | 92% | (parallel agent) | (parallel agent output) |

### Bugs fixed this session (not coded around)

| Symptom | Root cause | Fix |
|---|---|---|
| `/auth/reset` rendered through the signed-in shell (sidebar wrapped around the reset form) | Missing from `shellLessExact` in `apps/web/src/routes/+layout.svelte` | Added `/auth/reset` to `shellLessExact` |
| Route description silently dropped on Save Route — typed text never round-tripped to the saved row | Column existed on the form but not in the table; `saveRoute` payload omitted it | Migration `20260902_001_routes_description.sql` + `saveRoute` payload + detail-page render |
| Integrations Disconnect was destructive with no confirmation | Direct mutation behind a plain `<button>` | Wired the `ConfirmDialog` component (already in the app shell) onto the Disconnect button |
| `/live/[id]` had a dead `'finished'` status path that never rendered | Status enum had `'finished'` but the page's `{#if}` ladder skipped it | Added the finished-state branch with the post-race summary card |
| `/live/[id]` couldn't load an anon-readable Anonymous-runner row | RLS policy excluded the row when `display_name` was NULL | Policy widened to allow anon read when the run is_public + live broadcast is active |
| `/live/[id]` runner avatar fell through to plain white | `hsl(...)` template literal embedded an invalid alpha unit | Switched to `oklch(...)` with the correct three-channel form |
| RunEditor active activity-chip exposed a polluted accessible name (`button "Activity Walk Hike Cycle": Run`) — `getByRole('button', { name: 'Run' })` couldn't find it | A `<label class="field">` wrapped both the field-label span and the chip row; HTML labels associate with their first inner form control, so the active chip inherited the label's text | Replaced with `<fieldset>/<legend>` + `role="radiogroup"`/`role="radio"`/`aria-checked` on the chips so each has a clean name |
| `/clubs/new` back-link pointed at `/clubs` (which itself redirects to `/social?tab=clubs`) — two-hop nav for a known canonical URL | Stale URL after the social-hub consolidation | Back-link now points at `/social?tab=clubs` directly; the `cameFromClubs` history detector also accepts arrivals from `/social` |

### Test surface reshuffle

`tests-e2e/` was restructured to mirror the app routes — `tests-e2e/recap/page.spec.ts`, `tests-e2e/explore/page.spec.ts`, `tests-e2e/social/{people,feed,clubs}.spec.ts`, `tests-e2e/auth/reset.spec.ts`, etc. The old flat layout is gone; `git mv` preserved history. Spec filenames now follow `<surface>.spec.ts` so a future contributor pulling up `/recap/[year]` finds the spec at the obvious path.

## Session-end update (2026-05-15)

Rounds A + B together moved eight web surfaces above 90%:

### Round A — web e2e narrow gaps

| Surface | Was | Now | What changed |
|---|---|---|---|
| `/recap/[year]` | 55% | ~92% | 3 → 8 tests (anon path, doc title, populated hero, six stat cards, monthly bar chart, empty-year, share button) + `/recap/*` added to layout `publicPaths` |
| `/compare` | 70% | ~92% | 2 → 6 tests (SEO title/meta, three pricing cards, every COMPARE_SECTIONS h2, 4-column table headers, Yes/No/Partial labels) |
| `/guided` | 70% | ~92% | 4 → 9 tests (every library entry pinned, three detail pages parametrized, mm:ss cue format, unknown-id empty state) |
| `/` (landing) | 80% | ~92% | 2 → 7 tests + added `<svelte:head>` with title + description (real SEO gap surfaced by the test) |
| `/live/[id]` | 70% | ~92% | 2 → 5 tests + **root-cause fix**: page now surfaces a clear "not broadcasting" state for stale-link / private / unknown-id viewers instead of sitting at "Connecting…" forever. The earlier draft of the test pinned the workaround ("badge not LIVE"); the spec was rewritten to assert the right user outcome after the fix landed. |
| `settings/integrations` | 70% | ~92% | 3 → 6 tests (last-sync timestamp, Sync-now button, anon auth-wall) + 6 new tests in `integrations-connected.spec.ts` plant rows via service-role to exercise connected-state UI (Strava/parkrun/Garmin connected cards, Sync-now affordance, bulk-import card) + disconnect ConfirmDialog round-trip (added to the page — destructive disconnect now goes through a confirm modal, matching the rest of the app's pattern) |
| `runs/photos` | 75% | ~92% | 3 → 5 tests (Add-photo gated to detail pages, non-owner share view has no upload/delete affordances) |
| `/share/route/[id]` | 80% | ~92% | 4 → 6 tests (private route same not-found copy, header brand link points home) |
| `/privacy`, `/terms`, `/cookie-notice` | 85% | ~92% | 4 → 8 tests (GDPR clauses on /privacy, auto-renewal + 14-day + cancellation on /terms, strict-vs-consent buckets on /cookie-notice, cross-doc link consistency) |
| Sitemap + robots.txt | 85% | ~92% | 4 → 7 tests (no auth-gated surfaces, single `<loc>` per `<url>`, every `<loc>` fully qualified) |

**Web public pages section is now fully at 90%+** — every row above.

### Round C — under-covered web app rows (this turn)

| Surface | Was | Now | What changed |
|---|---|---|---|
| `routes/new` (Route Builder) | 65% | ~92% | NEW `routes/builder.spec.ts`, 9 tests covering control surface: h1 + sidebar mount, mode toggle (road / trail active class flip), three style toggles (streets / satellite / terrain mutex), Calculate / Save / GPX buttons disabled at 0 waypoints, Undo / Clear / Out-and-back gating, distance-target presets set the bound variable (5k / 10k / Half / Full), route-name input bindable, keyboard-shortcuts hint, anon auth-wall. |
| `runs/[id]` Workout review section (plans adherence) | 55% | ~92% | NEW `runs/workout-review.spec.ts`, 7 tests covering metadata-driven render: hidden without `workout_step_results`, hidden when empty array, on/amber/off adherence pills mutually exclusive, skipped step renders the .skipped row + 'skip' badge in Δ column, 5-column header (Step / Plan / Actual / Pace / Δ) literal. Plants metadata via service-role so the test exercises the same code path the recorder writes through. |
| `routes` Heatmap tab + RPC plumbing | 40% | ~92% | NEW `routes/heatmap.spec.ts`, 6 tests: Heatmap tab reachable, click activates, `?tab=heatmap` deep-link, MapLibre canvas mounts, `heatmap_points_in_bbox` RPC returns 2xx (regression-pins the migration `set search_path = public, extensions` fix from `d39296f`), tab .active class mutex across My routes / Explore routes / Heatmap. |

### Round B — mocked-integration coverage

| Surface | Was | Now | What changed |
|---|---|---|---|
| `/auth/callback` (OAuth landing) | unmeasured | ~85% | NEW spec, 4 tests covering no-code / malformed-code / Back-to-login link / loading copy. Real Google/Apple flows still need dev accounts; the post-redirect callback page is fully testable independent of provider. |

Findings from Round B: most integration mocks already exist —

- Strava OAuth-redirect mock: already in `settings/integrations.spec.ts` (the `https://www.strava.com/**` `context.route` hijack).
- Coach SSE happy + 401 + 429 + 500 paths: already mocked in `coach.spec.ts`.
- RevenueCat webhook signature: covered in `apps/backend/supabase/functions/revenuecat-webhook/lib.test.ts`.
- Strava webhook ingest gating: 13 Go tests in `apps/job_worker/internal/stravahook/server_test.go`.

So the integrations row in the baseline tables ("~35%") was understated — the existing mocks push **most provider rows above 70%** on paper. The hard remaining %s are blocked on actual upstream dev accounts:

- Real Google / Apple OAuth flow → needs Cloud / Developer creds.
- Real Stripe / RevenueCat purchase → needs test-mode + sandbox project.
- Garmin Connect → blocked on developer-program approval.
- Apple IAP / Play Billing → device + sandbox tester accounts.

### Bugs fixed (not coded around) this session

Following the new convention rule (`docs/conventions.md` § Fix bugs, don't code around them):

| Symptom | Root cause | Fix commit |
|---|---|---|
| `/recap`, `/privacy`, `/terms`, `/cookie-notice`, `/compare`, `/guided` auth-walled their own anon-render branches | Routes not in layout `publicPaths` list | `a4ca00b`, `d48c6d5` |
| Landing page had no meta description (broken SEO snippet) | Missing `<svelte:head>` on `/` | `470677b` |
| `/live/[id]` sat at "Connecting…" forever for stale links / private / unknown ids; would silently fall through to "Demo" after 5 s | No visibility check; the page didn't read the run row to gate on existence + public flag | `95b4b0e` |
| `supabase db reset` failed past 20260825 on three different migrations | Unqualified `is_run_visible_to(...)` after the function was moved to `private` schema; stray `//` comment; missing `extensions` in a SECURITY-DEFINER function's `search_path` | `d39296f` |
| Dart row generator silently dropped `create table public.foo (...)` definitions + `alter table … add column if not exists` | Regex didn't accept schema-qualified table names or the `if not exists` form; `gear` + `run_gear` weren't in the allowlist | `3128bda` |
| `apps/mobile_ios/test/guided_run_detail_screen_test.dart` had drifted from its byte-identical Android twin | Author updated Android-side test to use a small fixture but didn't mirror | `c2b5c18` |

Each entry above is the bug pattern, not the test that masks it.

### What's still below 90% and addressable in code

| Surface | Now | What it would take |
|---|---|---|
| Mobile (Android / iOS Flutter) | ~65–70% | `flutter integration_test` job + CI emulator (see `docs/mobile_e2e.md`, ~1 day infra) |
| Wear OS | ~50% | Compose integration tests; same effort as Android |
| watchOS | ~25% | macOS runner + Swift test wiring |
| Compliance docs | ~20% | Counsel review + filling TODOs in `docs/compliance/` |
| Heatmap | 40% | Wire e2e test to call `heatmap_points_in_bbox` RPC + assert polygon rendering |
| Race control (clubs) | 65% | Multi-context test with admin + runner roles |

Everything below this section is the **starting baseline** before today's pushes. Cross-reference the rows above when consulting the per-area tables.

---

## Auth + identity

| Feature | Baseline | Surface | Biggest gap |
|---|---|---|---|
| Email signup (with age gate + ToS) | 90% | `login.spec.ts`, `signup-age-gate.spec.ts` | — |
| Email sign-in | 90% | `login.spec.ts`, `cross-cutting/sign-in-out.spec.ts` | — |
| Password reset (full Mailpit flow) | 85% | `login.spec.ts` | — |
| Google OAuth | 20% | None | Real flow blocked; need Google Cloud creds |
| Apple OAuth | 10% | None | "Soon" pill; needs Apple Developer |
| Session refresh / auth walls | 85% | `cross-cutting/auth-walls.spec.ts`, every signed-in spec | — |

## Recording (mobile + watch)

| Feature | Baseline | Surface | Biggest gap |
|---|---|---|---|
| Run state machine + GPS filter chain | 80% | `run_recorder` 18 tests + 7 guards | Live-device GPS jitter |
| `LocalRunStore` persistence + sync | 85% | 23 tests | — |
| `run_stats` helpers (pace, splits, fastest-window) | 85% | 13 tests | — |
| BLE chest-strap HR | 75% | 9 parser tests | Real-device pairing flake |
| Architecture guards (54 source-level asserts) | 95% | `architecture_guards_test.dart` | — |
| Live run screen widget | 65% | `run_screen_test.dart` + ValueNotifier-mode | No full integration_test |
| Crash-safe persistence | 70% | LocalRunStore + recovery tests | No power-pull simulation |
| Wear OS — full feature parity | 45% | Kotlin unit tests | No emulator e2e |
| watchOS — recording flow | 15% | None automated | macOS runner blocker |

## Runs (web)

| Feature | Baseline | Surface |
|---|---|---|
| List / detail / new / cascade-delete | 85% | `runs/{list,detail,new,cascade}.spec.ts` |
| Run photos | 75% | `runs/photos.spec.ts` |
| Kudos / comments / engagement | 85% | `runs/social.spec.ts` + `cross-user/{kudos,comments}.spec.ts` |
| Track preview + decorations | 80% | `track_decorations_test.dart` (10) + widget tests |
| HR zones | 75% | `hr_zones_test.dart` (8) |
| Pace segments / heatmap | 80% | `pace_segments_test.dart` (15) |
| Privacy-zone clipping (non-owner view) | 85% | pgtap + cross-cutting + parity (8/8) |

## Routes

| Feature | Baseline | Surface |
|---|---|---|
| Library / detail / import (GPX/KML/etc.) | 70% | `routes/{list,detail,import}.spec.ts` |
| Route builder (OSRM + elevation + geocoding) | 65% | 9+12+7+7+5 helper tests, web e2e thin |
| Public/private toggle + share | 75% | `share/route.spec.ts` |
| Segments + leaderboards | 92% | `segments_test.dart` (8) + UI widget tests + web `routes/segments.spec.ts` (14) + web `runs/segment-efforts.spec.ts` (7) — silent-empty-leaderboard regression pin for the SECURITY DEFINER fix (decisions §60), tier-filter narrowing on planted demographics, crown banner gating, viewer-row highlight, create + delete round-trip, ConfirmDialog cancel/confirm, athlete-row navigation to /u/[id], rank-pill colour-codes (.gold / .silver), section gating by route_id on /runs/[id], 100m-minimum validation toast |
| Heatmap | 40% | UI exists, migration shipped; no e2e |

## Training plans

| Feature | Baseline | Surface |
|---|---|---|
| VDOT generator + Riegel (TS↔Dart parity) | 90% | `training.test.ts` (29) + `training_test.dart` (17) |
| Wizard / week grid / editor | 90% | `plans/{create,detail,list,workout-runner-surfaces}.spec.ts` — adds Mark-as-done toggle, hasLinkedRun gate, structure preview, advice rendering, Unlink ConfirmDialog round-trip |
| Workout runner state machine | 92% | `workout_runner_test.dart` (13) + execution-band tests (6) + web `plans/workout-runner-surfaces.spec.ts` (19) — today-card entry, kind=rest field gating, save round-trip, structure preview for tempo / interval / MP / easy, How-to-run advice per kind, ConfirmDialog Cancel + Confirm paths |
| Adherence + workout-review section | 70% | `workout_review_section_test.dart` (11) + web `runs/workout-review.spec.ts` (7) |
| Calendar | 92% | `plan_calendar_test.dart` (3) + web `plans/calendar.spec.ts` (13) — Monday-first DOW, today-marker drift guard, prev/next month-edge disabled, kind-pill + .dist + .done flip on mark, out-month / out-plan / rest cells, todayISO local-vs-UTC drift guard, plan-window-vs-cal-bounds parity |

## Clubs / events / social

| Feature | Baseline | Surface |
|---|---|---|
| Clubs CRUD + members + posts + invites | 90% | `clubs/*.spec.ts` (13 files) |
| Events (one-off + recurring + RSVP) | 85% | `clubs/event-*.spec.ts` + `recurrence_test` |
| Race control (arm / start / end / cancel) | 65% | UI + handler covered; no full multi-client |
| Activity feed | 80% | `feed.spec.ts` + `cross-cutting/feed-journey.spec.ts` |
| Profile (`/u/[id]` + follow / notifications) | 80% | `u/*.spec.ts` + `cross-user/{follows,notifications}.spec.ts` |

## AI Coach

| Feature | Baseline | Surface |
|---|---|---|
| Chat surface mount + plan switcher | 75% | `coach.spec.ts` |
| SSE streaming (mocked) | 70% | `page.route('**/api/coach', ...)` stub |
| 429 daily-cap path | 75% | `coach.spec.ts` 429 test |
| Paywall gating | 80% | `cross-cutting/paywall-wire.spec.ts` |
| Real Anthropic response | 45% | Mock covers shape; real key burns spend |

## Live spectator

| Feature | Baseline | Surface |
|---|---|---|
| Web `/live/[id]` render | 70% | `live.spec.ts`, `live-event.spec.ts` |
| Mobile spectator screen | 55% | Widget tests |
| Go live-hub auth + privacy + Redis path | 85% | 16 + 8 + 9 + 14 Go tests |
| Multi-client realtime delivery | 55% | `cross-cutting/realtime.spec.ts` (limited) |

## Settings

| Feature | Baseline | Surface |
|---|---|---|
| Account / preferences / devices / licenses | 85% | `settings/*.spec.ts` |
| Privacy zones picker | 80% | `settings/privacy-zones.spec.ts` + cross-cutting |
| Data export (Go endpoint) | 75% | `dataexport/server_test.go` (14) + `settings/export.spec.ts` |
| Restore backup | 70% | `settings/restore-backup.spec.ts` |
| Integrations tab | ~92% | `settings/integrations.spec.ts` (disconnected-state) + `settings/integrations-connected.spec.ts` (planted-row connected UI + disconnect confirm dialog) |
| Pro upgrade (currency-localised) | 80% | `settings/{upgrade,pricing-localization}.spec.ts` |

## Integrations

| Feature | Baseline | Real-flow gap |
|---|---|---|
| Strava ZIP import | 75% | Fixture-driven; OAuth real flow needs creds |
| Strava live OAuth + webhook | 30% | Needs Strava developer creds |
| Garmin Connect | 5% | Blocked on developer-program approval |
| parkrun athlete-number import | 40% | No sandbox; can mock fetch in EF |
| Health Connect (Android) | 40% | Device-only; can't laptop-test |
| HealthKit (iOS) | 30% | Device-only |
| Stripe + RevenueCat paywall | 40% | Needs sandbox keys |
| Apple IAP / Google Play Billing | 20% | Device + sandbox tester needed |

## Maps + matching

| Feature | Baseline | Surface |
|---|---|---|
| MapTiler tile render | 60% | Implicit via every map-bearing spec |
| OSRM map matching (Go matcher) | 80% | `matcher_osrm_test.go` + worker tests |
| Run-match pipeline (jobs queue) | 80% | pgtap + worker integration test |
| Privacy-zone clipping RPC | 90% | pgtap + `cross-cutting/privacy-zones.spec.ts` |

## Backend

| Feature | Baseline | Surface |
|---|---|---|
| Edge Functions (pure helpers) | 80% | 45 Deno tests across 3 files |
| Edge Function handler envelopes (auth/HMAC) | 65% | 9 tests on the 3 webhook handlers |
| pgtap RLS suite | 80% | `apps/backend/supabase/tests/*.sql` |
| Go job worker (map-match, token-refresh, strava-event) | 85% | 50+ tests across handlers + livehub + dataexport + premium |
| Schema codegen drift detector | 90% | `parity-types` CI + schema-codegen-drift CI |

## Web public pages

| Feature | Baseline | Surface |
|---|---|---|
| Landing | 80% | `landing.spec.ts` |
| `/compare` | 70% | `compare.spec.ts` (new) |
| `/guided` (preview library) | 70% | `guided.spec.ts` (new) |
| `/recap/[year]` | 90% | `recap/page.spec.ts` — 12 tests; happy + invalid-year + future-year + before-joined + clipboard round-trip |
| `/share/run/[id]`, `/share/route/[id]` | 80% | `share/*.spec.ts` |
| `/privacy`, `/terms`, `/cookie-notice` | 85% | `legal-pages.spec.ts` (new) |
| Sitemap + robots.txt | 85% | `sitemap.spec.ts` |

## Cross-cutting + compliance

| Feature | Baseline | Surface |
|---|---|---|
| Cookie consent banner + Sentry gate | 85% | `cross-cutting/cookie-consent.spec.ts` |
| Age gate (GDPR Art 8) | 90% | `signup-age-gate.spec.ts` |
| Dev/prod isolation guard | 90% | Vite plugin + Playwright globalSetup + 13 unit tests + CI job |
| Currency localisation | 85% | `format_price.test.ts` (12) + `settings/pricing-localization.spec.ts` (4) |
| Paywall gating (server-side) | 80% | `cross-cutting/paywall-wire.spec.ts` |
| Compliance audits (advisory) | 30% | Audit infra built; not yet run against findings |
| Compliance docs (retention/DPIA/sub-processors) | 20% | Scaffolded; counsel + product TODOs remain |
| Mobile twin parity | 95% | CI byte-identical guard + diff |

## Roll-up by area

| Area | Baseline | Note |
|---|---|---|
| Web app (frontend) | ~80% | Strongest area; Playwright suite is dense |
| Mobile (Android, Flutter) | ~70% | Strong unit + widget; no integration_test in CI |
| Mobile (iOS, Flutter) | ~65% | Byte-identical twin inherits Android tests |
| Wear OS (Kotlin) | ~50% | Unit tests only |
| watchOS (Swift) | ~25% | Manual only; macOS runner gap |
| Backend Edge Functions | ~75% | Auth gates + helpers strong; happy paths thinner |
| Go worker (background + endpoints) | ~85% | Highest backend coverage |
| Database (RLS / triggers / RPCs) | ~80% | pgtap suite is thorough |
| Maps + matching | ~75% | Pipeline + privacy-zone clipping strong |
| Integrations (3rd-party) | ~35% | Most blocked on dev accounts |
| Compliance posture | ~55% | Infra in place, docs scaffolded |

## What "push to 90%" looks like per area

| Area | Path to 90% |
|---|---|
| Web public (`/recap`, `/compare`, `/guided`) | Deepen e2e content assertions — addressable this session |
| Web auth (OAuth) | Blocked on Google Cloud + Apple Developer creds |
| Web routes / plans / coach / live | New Playwright specs around mocked-API paths — addressable this session |
| Web maps | Visual smoke + zoom/pan helpers — partially addressable |
| Mobile Android | Needs `flutter integration_test` job in CI (~1 day infra) |
| Mobile iOS (Flutter) | Same as Android, plus macOS runner (~$70/mo) |
| Wear OS | New widget-test surface (no integration_test on Wear yet) |
| watchOS | Needs macOS runner + Swift test wiring |
| Backend Edge Functions | More happy-path tests with HTTP fixtures |
| Integrations | Dev-account setup per `docs/e2e_dev_accounts.md` |
| Compliance posture | Counsel review + filling docs/compliance/ TODOs |
