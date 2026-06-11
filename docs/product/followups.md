---
name: Gap-closure follow-ups
description: Open follow-ups only. Shipped items are pruned as they land — their cutover recipes live in apps/*/deployment.md and the code is in git history. Mirrors roadmap.md in spirit.
---

# Open follow-ups

What's left after the gap-closure + persona-hunt sessions. Shipped work has been pruned: the operator cutover recipes for the Go-service migrations (live hub, Strava webhook, token refresh, data export, premium endpoints) live in [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) and [`apps/web/deployment.md`](../../apps/web/deployment.md); everything else is in git history. Pair this file with [`docs/testing/testing.md`](../testing/testing.md) "What's *not* covered" for the test view.

Every item below is one of: (a) blocked on an external credential / account, (b) an operator deploy step on code that's already merged, or (c) a sized-but-unstarted feature awaiting a product green-light.

## Data-architecture remediation — Rounds 1–5 (CLOSED 2026-06-04)

The full data-architecture remediation (the five concurrent rounds in `reviews/remediation-rounds.md`) is **done**. Round 4 — the last open chunk — landed 2026-06-04:

- **R4·G1 backend** (`20261210_001`–`20261215_001`): F16 (missing `event_attendees.status` / `clubs.join_policy` / `club_members.status` / `events.recurrence_freq` CHECKs + consolidated `notifications.kind` / `jobs.kind` allowlists), F15 (polymorphic `notifications.(activity_kind, activity_id)`), F5 (`race_pings` retention cron), F7 (trigger-maintained `gym_workouts.set_count`/`volume_kg` retiring the `activities`-view subqueries), F9 (`user_coach_usage` retention cron + `docs/backend/derived_state.md` cache contract), F2f (EXPLAIN'd — `runs_user_started_at` is **not** redundant, kept). Each with pgtap.
- **R4·G2 web + R4·G3 mobile** (Tier-2 client switch): every web and mobile (+ iOS twin) read/write site moved off `metadata['activity_type']` / `['is_dnf']` onto the real columns; `coach/context.ts` + `local_food_store.dart` moved off the renamed `food_log.started_at` (the live PostgREST 400 is fixed); `ActivityType` TS union added to the CHECK-union guard; the `api_client.saveRun` bag→column shim dropped. Authoritative migrated-site list: [`docs/backend/metadata.md` → "Promoted to real columns"](../backend/metadata.md).

**F2 + F10 closed 2026-06-04 (decide-and-document, split out of the gated 4b phase):** the Storage-bucket-naming policy (F2) and the `external_id` `provider:native_id` namespacing rule (F10) are now written into [`conventions.md` § SQL](../architecture/conventions.md#sql). Neither needed the Phase-4 product gate they were bundled under: F1 Option A already settled the bucket question (per-modality buckets named for their tables — `runs`, `run-photos`, future `gym-photos`/`meal-photos`; **no rename**, since a generic `activities` bucket would re-create the table↔bucket-name mismatch), and the `provider:native_id` prefix is already 4-for-4 across importers (`strava:`/`garmin:`/`parkrun:`/`csv:`). The structural `(source, external_id)` column split stays documented as the escalation if a cross-provider id collision ever becomes possible — not done speculatively.

**One sliver left by design:** the web F11 registry covers the activity-core tables + the base tables whose `.from()` sites live only in `core/data.ts`; **12 tables** (`user_profiles, clubs, events, routes, saved_routes, training_plans, plan_weeks, plan_workouts, coach_messages, user_follows, user_settings, user_device_settings`) stay bare because their call sites spill across route pages owned by other concurrent sessions (227 sites — pure churn). Documented in `apps/web/src/lib/core/schema.ts` + `apps/web/CLAUDE.md`; a later pass extends `TABLES` outward as call sites move.

**Still genuinely deferred (product-gated, NOT remediation):** F14 *structural* half + F20 — the `FeedEntry` union / feed-over-`activities` / mobile Run-tab→Log-action reshape / sibling Gym\*/Meal\* views — are the Phase 4 multi-modal **product** build below, gated on the gym-engagement validation gate per decision D3. The F14 *cosmetic* half (route/i18n/glyph rename) already shipped.

## Phase 4 (multi-modal) — session handoff groups

The remaining [`docs/features/multi_modal.md`](../features/multi_modal.md) work, sliced into chunks that can be handed to **separate Claude sessions**. The slicing rule is **clean file ownership**, because concurrent sessions share one working tree + git index (CLAUDE.md § "Working alongside other Claude sessions") — two sessions editing the same file clobber each other. **Each session should run in its own git worktree** (`git worktree add ../run-<slug> -b <branch>`).

**Already shipped (do not re-do):** data model (migration `20261204_001` — `gym_workouts`/`gym_sets`/`food_log`, `activities` view; the `runs.kind` discriminator was dropped per F1/D1 in `20261206_001`) + `api_client` gym/food methods; `gym_prs.ts`↔`.dart` parity pair; web gym module (`/gym`, `/gym/[id]`, `GymEditor`, `core/data.ts` gym queries, gym e2e); `multi_modal_nav` flag read on web + Gym sidebar item; the `training_load` lift-load mechanic (`computeLiftStress`/`aggregateDailyLiftStress`/`lifts` arg — **built, not wired to a consumer**); `LocalGymStore`/`LocalFoodStore` (**built, not wired into nav/sync**).

**The one hotspot:** `apps/mobile_android/lib/home_screen.dart` (bottom nav + Home) is wanted by the nav reshape, Home redesign, and every new mobile screen's nav entry. **G5 owns it.** Other mobile sessions deliver self-contained screens and let G5 wire them in.

**Sequencing:** the doc gates the whole phase behind finishing the Phase 3 training moat, and gates **nutrition** behind a gym-engagement validation gate. The nutrition *code* (G6–G8) can be pre-built but must not ship ahead of that gate. Wave 1 (G1–G4) has no cross-deps and can run fully concurrently. G5 owns the mobile shell and should land before/with G4's nav wiring.

### Wave 1 — run concurrently (disjoint paths)

- [x] **G1 · DSAR export completeness** — **DONE 2026-06-10.** On audit, `gym_workouts` / `gym_sets` (nested) / `food_log` / `body_metrics` were **already** in both export paths; `safety_contacts` was the only genuinely-missing table (the Go export-completeness guard couldn't auto-flag it because it keys on `owner_id`/`contact_user_id`, not a literal `user_id`). Now exported in both directions — `safety_contacts_owned.json` (filtered `owner_id`) + `safety_contacts_as_contact.json` (filtered `contact_user_id`) — with the `confirm_token` capability credential redacted via a narrow select, in both the Go `dataexport` worker (`exportPersonalDataSpecs`) and the `export-data` EF (`buildBackupSpecs`). Go guard + Deno (39-spec) tests green. Closes the `safety_contacts` Art 20 sub-item below.
- [ ] **G2 · Web Home + History redesign** (web-only) — self-hiding prioritised card stack on web Home; single reverse-chron timeline + client-side filter chips over the `activities` view; lift cards in the social feed (`is_public`, meals not shareable). Owns: web home + history routes + their components under `apps/web/src/routes/` + `apps/web/src/lib/components/`. No mobile, no backend schema.
  - **F14 rename + the structural timeline have since shipped (2026-06-04 → 2026-06-08):** `/history` is the unified single timeline over the `activities` view with All/Runs/Lifts/Meals chips (every chip incl. Runs is the timeline; per-tab `View all`). The F14 `/runs → /history` rename happened, but `/runs` was then **un-redirected into the dedicated run-list / management page** (filters / pagination / bulk-delete / Add run / Heatmap, a `Runs` sidebar item) — it is NOT a redirect any more (§63 amendment, 2026-06-08). Mobile mirrors all of this (`runs_screen.dart`, local-store-backed timeline). The `history.*` i18n keys + the `timeline` nav glyph are in place. **Remaining G2 piece:** lift cards in the social feed (`is_public`, meals not shareable) — the only part not yet built. Run detail/new/heatmap stay at `/runs/[id]` etc. by design.
  - **Deferred conditional (R5 Group WEB carry-over):** when a backend group adds a generic `weekly_activity_load` RPC (sum of all-modality load per week), wire the dashboard's weekly chart to it and **keep `weekly_mileage()` as the running-distance number**. The RPC did not exist as of 2026-06-04, so the dashboard still reads `weekly_mileage()` only.
  ```
  Read docs/features/multi_modal.md (§ Home, § History, § Cross-modality) and apps/web/CLAUDE.md. On web only: (1) rebuild Home as the prioritised self-hiding card stack (today's actionable card → today's logged modalities → trend cards; omit modalities with no data); (2) rebuild History as one timeline over the `activities` view with client-side filter chips (hidden for empty kinds), each row tapping to its existing detail route; (3) add lift summary cards to the social feed gated on is_public (meals are NOT feed-shareable). Add Playwright e2e in apps/web/tests-e2e/ in the same commits. Own ONLY apps/web/src/routes/ home+history+feed pages and their components. Work in a worktree; path-scoped commits per piece; no AI attribution; flip parity.md + roadmap.md cells when done.
  ```
- [x] **G3 · Cross-modality backend (lift-load wiring + Coach context)** — **DONE.** Both halves were already shipped on `main` (commits `229563ac`/`fec0d67e` feed real `gym_workouts` into `computeTrainingLoadSeries` via `readinessLifts`/`liftsFromSetHistory` with a run-only-recoverable split + the `exclude_gym_from_readiness` opt-out; `25295f8b`/`5cf45841` gave `coach/context.ts` the bounded recent-lifts cap (`COACH_LIFTS_CAP=8`, per-session summaries) + a consent-gated 7-day nutrition summary). 2026-06-10 added the missing source-level guard (`dashboard_fitness_source_guard.test.ts`, 3→6 tests) pinning the lift feed + the exclude opt-out so a refactor can't silently sever cross-modality. `training_load` math untouched (parity-locked).
- [ ] **G4 · Mobile gym screens** (mostly new files) — `gym_screen.dart` (list), `gym_compose_sheet.dart` (composer), `gym_detail_screen.dart` (detail); wire `LocalGymStore`; byte-identical iOS twin. Owns: new `screens/gym_*.dart` + `widgets/gym_compose_sheet.dart`. **Dep:** needs a nav entry from G5 — build standalone, wire after.
  ```
  Read docs/features/multi_modal.md (§ Gym), apps/mobile_android/CLAUDE.md, and the shipped web gym surface (apps/web/src/routes/gym/, GymEditor.svelte) to mirror behaviour. Build the mobile gym screens: gym_screen.dart (list), widgets/gym_compose_sheet.dart (free-text exercise name with history autocomplete, inline sets reps+weight+optional RPE, weight stored kg), gym_detail_screen.dart (read-only review + per-exercise PR chips via the shipped gym_prs.dart). Wire the already-shipped LocalGymStore for offline. Mirror byte-identically to apps/mobile_ios/ (run the mobile-twin-mirror agent). Add tests in the same commit. Do NOT edit home_screen.dart's nav — G5 owns the shell; expose the screens so they can be wired in. Worktree; path-scoped commits; no AI attribution; update parity.md.
  ```

### Wave 2 — owns the mobile shell (gates G4's nav wiring)

- [ ] **G5 · Mobile app shell: bottom nav + Log sheet + Home + History** — `Home / History / Log / Social / Settings`; Log centre action button → sheet (start run/lift/meal/snack, long-press = repeat last); runner-protection Settings toggle (keep Run as one-tap primary); mobile Home self-hiding card stack; mobile History timeline + chips. **Owns `home_screen.dart`** + `widgets/log_sheet.dart`, `screens/runs_screen.dart` (the History tab — there is no separate `history_screen.dart`; History reused `runs_screen.dart`), `widgets/nutrition_rings_card.dart`, `widgets/gym_summary_card.dart`; iOS twin.
  - **Cosmetic F14 half already landed (2026-06-04):** the History-screen i18n key family was renamed `runs* → history*` (63 keys) across all 7 ARB catalogues + the regenerated `gen/app_localizations*` + iOS twin, and the three consumers (`runs_screen.dart`, `routes_screen.dart`, `period_summary_screen.dart`) were updated. The mobile nav label/icon were **already** generic (`navHistory` = "History", `Icons.history`), so no swap was needed (mobile never carried the web's `directions_run` running-centric glyph). The current History screen file is still `runs_screen.dart` — G5 builds the **structural** half: the Run-tab → Log-action reshape and the new `screens/history_screen.dart` timeline over `activities`. Keep the Run tab one-tap until the Log sheet exists; do NOT redo the i18n key rename (the new `history_screen.dart` inherits the already-renamed `history*` keys).
  ```
  Read docs/features/multi_modal.md (§ Bottom nav, § Home, § History, § "Protect the core runner") and apps/mobile_android/CLAUDE.md. Reshape the mobile shell: bottom nav Home/History/Log/Social/Settings with the centre Log as an action button presenting a sheet (start run/lift/meal/snack, last-used floats to top, long-press repeats last activity, ≥48dp target + Semantics label); a Settings toggle that lets a pure runner keep Run as the one-tap primary; the Home self-hiding prioritised card stack; the History timeline over the activities view with hidden-for-empty filter chips. You OWN home_screen.dart and the bottom nav — coordinate nav entries for the gym (G4) / nutrition (G8) screens. Mirror byte-identically to iOS (mobile-twin-mirror agent). Tests in the same commit. Worktree; path-scoped commits; no AI attribution; flip parity.md/roadmap.md.
  ```

### Wave 3 — Nutrition (gated on the gym-engagement validation gate; pre-buildable, don't ship ahead)

> **G6 + G7 (web) landed 2026-06-04, behind `multi_modal_nav`.** Done:
> `nutrition_targets` TS↔Dart parity pair (13 tests each); `body_metrics`
> migration `20261216_001` (+ `user_profiles.height_cm`, owner-only,
> pgtap) wired into both DSAR export paths; web nutrition data layer
> (`core/data.ts`, `body_metrics` in the `TABLES` registry); `food_search`
> Open Food Facts client (injectable fetcher, 7 tests); `nutrition_totals`
> (4 tests); Settings body-metrics + activity/goal entry under a broadened
> Art 9 consent gate (6 web locales); `/nutrition` (rings/meal-slots/water/
> trend) + `/nutrition/log` (search→confirm-portion + manual fallback) +
> flag-gated sidebar item + Playwright e2e; Open Food Facts added to
> `sub-processors.md`. A real `<input type="number">` binding bug
> (`.trim` on a number) was caught by the e2e and fixed.
>
> **G8 (mobile) landed 2026-06-04.** `screens/nutrition_screen.dart`
> (rings/meal-slots/water/7-day trend, offline-first via `LocalFoodStore`)
> + `widgets/nutrition_log_sheet.dart` (Open Food Facts search →
> confirm-portion dialog + manual fallback) + `food_search.dart` +
> `nutrition_totals.dart` (mirror web; unit-tested) + `api_client
> .fetchLatestBodyWeightKg` + `body_metrics` in the gen_dart_models
> allowlist (`BodyMetricRow`). 7-ARB i18n + widget tests + byte-identical
> iOS twin. Built standalone like the gym screens.
>
> **Remaining for the nutrition vertical:**
> - **Mobile nav entry** — the gym + nutrition screens are reachable only
>   once the G5 `multi_modal_nav` Run→Log bottom-nav reshape lands.
> - **Mobile Settings body-metrics entry** — height/weight/activity/goal
>   input under the Art 9 consent gate (the web half shipped). Until then
>   mobile targets use default activity/goal + web-set profile metrics, so
>   the rings show consumed-only for a mobile-only user.
> - **Operator carry-overs:** iOS Privacy Nutrition Label + Play Data
>   Safety form for the new body-metrics (height/weight, Art 9) + Open
>   Food Facts hop, before a store submission that ships nutrition.
> - **Translation review:** the de/es/fr/ja/pt-BR nutrition + consent
>   strings (web + mobile ARB) are best-effort and want native review.
> - **Mobile calories-remaining + over-budget mirror — DONE 2026-06-10.**
>   `nutrition_budget.ts` → `nutrition_budget.dart` (new parity pair); the
>   mobile ceiling rings (calories/fat) recolour on an over day and the
>   "X kcal left / over / on target" headline chip is on `nutrition_screen.dart`
>   + the Home `nutrition_rings_card.dart`.
> - **Mobile hydration-goal mirror — DONE 2026-06-10.** `hydration.ts` →
>   `hydration.dart` (new parity pair); the mobile water card now shows the
>   `consumed / target L` readout, an "X ml left" / "Goal reached" chip, and
>   goal-relative pips.
> - **Mobile weekly-goal-trend mirror — DONE 2026-06-10.** `nutrition_week.ts`
>   → `nutrition_week.dart` (new parity pair); the mobile 7-day trend now has
>   the daily-goal reference line + the "X under/over goal/day" summary chip.

- [ ] **G6 · Nutrition foundation (pure + schema)** — `nutrition_targets` parity pair (Mifflin-St Jeor BMR × activity-level); `body_metrics` migration (height on `user_profiles` + `body_metrics` weight time-series, owner RLS, cascade-delete); Settings height/weight entry; privacy-disclosure updates (iOS label / Play Data Safety / Open Food Facts sub-processor). **Feeds G1** (add `body_metrics` to export). Owns: `nutrition_targets.ts`/`.dart`, the new migration, Settings body-metrics entry.
  ```
  Read docs/features/multi_modal.md (§ Nutrition targets, § "Body metrics & sensitive data"), docs/architecture/schema_codegen.md, and docs/backend/settings.md. (1) Build the nutrition_targets TS↔Dart parity pair (Mifflin-St Jeor BMR × activity-level, unit-tested both sides, equal test counts). (2) Add an additive migration: height on user_profiles + a body_metrics weight time-series (user_id, recorded_at, weight_kg), owner-scoped RLS, cascade-delete from auth.users; regenerate both type files (npm run gen:types + dart gen_dart_models) and update the CHECK↔union guard if needed. (3) Settings height/weight entry (web + mobile twin). (4) Update the iOS Privacy Label / Play Data Safety / sub-processor list (Open Food Facts is a new outbound hop). Flag to G1 that body_metrics must join the export path. Worktree; path-scoped commits; no AI attribution.
  ```
- [ ] **G7 · Nutrition web** — `/nutrition` (rings + meal-slot daily view + weekly trends), `/nutrition/log` (Open Food Facts search → tap → confirm portion; manual entry fallback only); `food_search` client + web `core/data.ts` food queries; water tracker; Nutrition sidebar item (flag-gated). **Dep:** G6. Owns: `apps/web/src/routes/nutrition/`, web food data-access, nutrition sidebar in `+layout.svelte`.
  ```
  Read docs/features/multi_modal.md (§ Nutrition) and apps/web/CLAUDE.md. Depends on G6 (nutrition_targets + body_metrics). On web: build /nutrition (concentric macro rings vs targets, meal-slot grouped daily log, water tracker, weekly-trends section reusing the mileage-trend pattern) and /nutrition/log (a food_search client over Open Food Facts — world.openfoodfacts.org, no API key, pluggable-fetcher seam like routing.ts — search → tap → confirm portion, with manual macro entry ONLY as the no-match fallback), the food queries in core/data.ts, and the flag-gated Nutrition sidebar item in +layout.svelte. Playwright e2e in the same commits. Own ONLY apps/web nutrition routes/components + food data-access. Worktree; path-scoped commits; no AI attribution; flip parity.md.
  ```
- [ ] **G8 · Nutrition mobile** — `nutrition_screen.dart`, `nutrition_log_sheet.dart`, `food_search.dart` (Open Food Facts, pluggable-fetcher seam); wire `LocalFoodStore`; iOS twin. Barcode scan is a v1.1 fast-path on the same lookup. **Deps:** G6 + plugs into G5's shell. Owns: new `screens/nutrition_screen.dart` + `widgets/nutrition_log_sheet.dart` + `food_search.dart`.
  ```
  Read docs/features/multi_modal.md (§ Nutrition) and apps/mobile_android/CLAUDE.md; mirror the web nutrition surface (G7) for behaviour. Build nutrition_screen.dart (rings + meal-slot daily view + water tracker + weekly trends), widgets/nutrition_log_sheet.dart (search → tap → confirm portion; manual fallback), and food_search.dart (Open Food Facts client with a pluggable-fetcher seam like routing.dart). Wire the shipped LocalFoodStore for offline. Barcode scan (camera) is a later v1.1 fast-path on the same lookup — leave a seam, don't build it now. Mirror byte-identically to iOS (mobile-twin-mirror agent). Tests in the same commit. Do NOT edit the bottom nav — G5 wires the entry. Worktree; path-scoped commits; no AI attribution; flip parity.md.
  ```

- [x] **`weight_unit` (kg/lbs) display/entry converter + toggle** (F19) — **done 2026-06-04**, web + mobile twin. Storage stays canonical kg; a unit-aware formatter/parser (`format/weight.ts` + the reactive `weightUnit` signal in `units.svelte.ts` on web; `WeightFormat` + `Preferences.weightUnit` on mobile), a Settings → Preferences toggle on both, and the gym surfaces (`/gym`, `GymEditor`, mobile gym compose/detail + volume rendering) wired through it. Round-trip kg↔lbs tests both sides. (When `body_metrics` lands with nutrition G6, body weight picks up the same converter.)

**Deferred (Tier 2, do not hand off yet):** recommendation engine, plan re-planning from fuelling/lift load, Coach-authored meal/lift plans, unified Whoop-style recovery score — gated on reliable logging per multi_modal.md.

### Web↔mobile multi-modal-nav gating drift — RESOLVED (2026-06-04)

- [x] **Resolved: web ungated to match mobile.** The two platforms had drifted — mobile shipped gym/nutrition **ungated** (always reachable via the Log action + data-gated Home cards, `keep_run_primary` protecting the pure runner) while web hid them behind `multi_modal_nav` (default off, no UI, undiscoverable). The durable fix landed per the plan below: the three web surfaces now rely **purely on data presence**, matching mobile's self-hiding behaviour — the Gym + Nutrition sidebar items are always present (`+layout.svelte`), the `/dashboard` lift cards + lift→load contribution self-hide on no gym data, and the `/history` kind chips + unified timeline appear once a second modality has data. The `multi_modal_nav` flag is **no longer read by any surface** (kept registered in `settings.md` as dormant/deprecated, so a kill-switch could be reintroduced without a migration). [decisions.md § 63](../architecture/decisions.md) carries the amendment; `parity.md` / `roadmap.md` cells flipped; the `multi_modal_nav`-setting Playwright spec (`tests-e2e/gym/multimodal_home_history.spec.ts`) reworked to assert always-on (seeds gym data, no flag flip). A Settings toggle was considered and rejected (mobile has none, so it wouldn't make the platforms consistent). (Surfaced + resolved 2026-06-04.)

## Testing gaps

- [ ] **Device-instrumented `integration_test` harness** — none today; would cover tile-cache / foreground-service / background-sync on real Android primitives. New infrastructure.
- [ ] **OSRM smoke test in CI** — blocked on free-runner capacity (OSM PBF extract + osrm-extract memory). Options: a self-hosted runner, or a pre-built OSRM cache in S3 the workflow downloads.
- [ ] **Positive-path Edge Function tests** — the envelope suite covers auth-rejection only; 200-on-valid-HMAC / replay-dedupe / freshness-window tests need real secret values in the CI config.
- [x] **`apps/job_worker` Go tests now gate CI** (2026-06-04) — added a `test-worker` job to `ci.yml` running `go vet ./...` + `go test ./...` (working-directory `apps/job_worker`). The whole worker Go suite — including the GDPR Art 20 export-completeness guard (`internal/personal_data_export_guard_test.go`, which fails when a new `user_id`-bearing table isn't wired into `exportPersonalDataSpecs` or the reasoned exclusion list) — now fails a PR instead of only failing locally.
- [ ] **Two flaky `/history` run-list specs** (surfaced 2026-06-04 during the History polish) — `tests-e2e/runs/list.spec.ts:38` ("Walk activity filter narrows to the single seeded walk") and `:109` ("filter state survives a reload"). Both fail intermittently against the **224-run seed** in the all-time full-fetch path, and they fail identically with the History page **stashed to its pre-polish state** — i.e. pre-existing, not caused by the polish. Likely a timing race: the assertion (`toHaveCount(1)` / the restored filter) runs before the all-time full-fetch + client-side filter settles. Fix is probably to await a stable count / the loaded list rather than asserting immediately after flipping the activity filter — not a markup change. Low priority (the feature works; it's the test that's racy).

## Mobile

- [x] **Apple-Watch WCSession ingest forwards `last_modified_at`** — **done 2026-06-04** (R4 mobile, PIECE C). `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` and `WatchIngest._runFromArgs` in `apps/mobile_android/lib/main.dart` (byte-identical iOS twin) now carry `last_modified_at` through, so a WCSession (paired-phone) watch run resurfaces in the phone's delta-fetch (`metadata->>'last_modified_at' > since`) after the first full pull. (`steps`/`laps` forwarding stays a smaller future follow-up; the correctness gap — delta-fetch invisibility — is closed.)
- [x] **`OfflineSyncStore<S>` base over gear / gym / food** — **done 2026-06-04** (R4 mobile, PIECE F). Extracted `apps/mobile_android/lib/offline_sync_store.dart` (+ byte-identical iOS twin) as the generic per-row sync-state machine that `local_gear_store.dart` / `local_gym_store.dart` / `local_food_store.dart` extend, with a single shared `SyncState` enum + per-store typedef aliases so the store tests + gym screens didn't churn. Pure refactor — every divergence finding it was meant to close (gym/food `replaceFromServer` newer-wins, gear clock fixes, `_v` schema stamp, the `GymWorkout`/`FoodEntry` DTOs) was already fixed earlier; the ~57 store tests were the behaviour guard. Run/route stay separate by design (sidecar sync-state model — decisions.md § 122).
- [ ] **Pro native RevenueCat purchase sheet + native donate** — scaffolding shipped (`revenuecat.dart`); the live sheet needs a RevenueCat project + a `pro_monthly` package + `REVENUECAT_API_KEY_ANDROID` / `_IOS` provisioned. Until then the Subscribe tile falls through to the web URL. (The store-localised Pro price is now WIRED: `settings_pro_screen.dart` fetches `proMonthlyPriceString` from `getOfferings()` and shows it in the Subscribe tile, falling back to the `$9.99` USD list price + the "billed in USD" regional note only when RevenueCat is unconfigured or the offering hasn't loaded. So the Apple 3.1.1 / Play store-localised-price requirement is satisfied in code — it just needs the RC project provisioned for the localised amount to actually appear.)
- [x] **Cross-modality mirror: dynamic TDEE + gym-aware readiness** — **DONE 2026-06-10** (mobile + iOS twin). All three surfaces wired: (1) `nutrition_screen.dart` feeds today's runs + gym sessions through `exerciseCaloriesForDay` into `loadNutritionTargets` and shows the `base + exercise` breakdown; (2) the mobile dashboard shows the gym-in-fatigue note; (3) a mobile Settings → Preferences `exclude_gym_from_readiness` toggle drops lifts from the readiness curve. The ARB activity labels were relabelled to non-exercise-baseline wording **in the same change** as the exercise-kcal feed (honouring the ordering constraint). `dashboard_gym_readiness_test.dart` pins the factored-in/excluded paths.
  - **Ordering constraint (read before touching mobile nutrition labels):** mobile currently passes **no** `exerciseKcal`, so `computeNutritionTargets` returns base-only — i.e. the activity multiplier still does the *total-activity* job, and mobile's `app*.arb` activity labels ("Light (1–3 days/week)" … "Very active (twice a day)") are correct **for mobile as-is**. Web's `prefs.activity_*` strings were reworded to *non-exercise baseline* because web adds exercise on top; **do NOT copy that wording to the mobile ARBs until mobile wires step (1)** — relabeling mobile to "baseline" while it still computes base-only would make it under-target. Relabel + rewire mobile in the **same** change. (The dead `activityLevels[].label` field in `nutrition_targets.dart` carries the baseline text for TS↔Dart parity only; the *live* mobile strings are the ARB keys via `_activityLabel`.)
- [x] **Gear wear status on the mobile gear screen** — **done 2026-06-08.** `gear_wear.dart` is the byte-identical Dart twin of web `gear_wear.ts` (untracked/ok/due/worn at the 0.85 due-fraction, 8-test mirror suite; parity pair registered in `CLAUDE.md` + `shared-library-syncer.md`). `gear_screen.dart` now recolours the `LinearProgressIndicator` (amber for due, `colorScheme.error` for worn) and shows a Replace-soon / Past-replacement badge next to the gear name via two new ARB keys (`gearWearDue` / `gearWearWorn`, all 7 catalogues). Retired gear shows no wear badge (mirrors web, which only classifies the active list). iOS twin mirrored; widget tests pin the worn/due/retired paths. Pure derivation, no shared setting → no cross-device drift.
- [x] **Mobile mirror: per-exercise records + progression surfaces** — **DONE 2026-06-10** (mobile + iOS twin). `exercise_records.ts` → `exercise_records.dart` and `exercise_history.ts` → `exercise_history.dart` ported as TS↔Dart parity pairs (registered in `CLAUDE.md` + `shared-library-syncer.md`; `exercise_history.dart` carries `previousExerciseSession`), both driven from `LocalGymStore` and reusing `gym_prs.dart` primitives so numbers can't drift. A Records screen (reachable from `gym_screen.dart`) drills into a per-exercise progression screen (headline est.-1RM delta vs first session + a new-e1RM PR badge per session), and `gym_detail_screen.dart` shows the "vs last time" hint. Widget tests pin the screens.
- [ ] **Typed-events (slice E): mobile `EventEditor` create-wiring** — web shipped the type-first editor + category-gated detail (2026-06-11): `EventEditor.svelte` picks `category` (run/cycle/class/social) as its first control, shows a free-text `discipline` for a `class`, self-hides + clears the athletic fields off-category, and `createEvent` persists `category` + `discipline`; the detail page gates all athletic affordances on `isAthleticCategory`. The **mobile** read-only `event_detail_screen.dart` gate already landed, but the Flutter **event-create** path (+ Dart `createEvent`) does **not** yet write `category`/`discipline` — mobile still creates run-shaped events only. Mirror the web editor: category picker + discipline field + athletic-field gating, add the `eventEditor.cat*`/`discipline*` keys to all mobile ARBs (+ iOS twin), and a Flutter widget test. `isAthleticEventCategory` already exists in `event_category.dart`. Web-first; this is the remaining cross-platform gap before `parity.md` can claim typed-events complete. See [club_events.md § Slice E](../features/club_events.md).
- [ ] **Wear OS recording-service foreground type may need `health`** — `apps/watch_wear/.../RunRecordingService.kt` runs as `foregroundServiceType="location"` but instantiates `HeartRateMonitor` (BODY_SENSORS) while in the foreground. On `targetSdk=35` (Android 14+ FGS-type enforcement) a service that accesses body sensors should declare `foregroundServiceType="location|health"` and hold `FOREGROUND_SERVICE_HEALTH`. Needs a Wear build + device test to confirm the current code doesn't already throw (Health Services passive monitoring may not trip the requirement) before changing the manifest — an unvalidated FGS-type edit can crash the service on `startForeground()`. Surfaced by the 2026-05-30 app-store-privacy audit while verifying the BODY_SENSORS disclosure.

## Deploys (code merged, operator steps remain)

- [ ] **share-run Lambda og:image PNG — verify the arm64 @resvg binary ships in the zip** — code merged (persona round-5 very-social): the share-run Lambda now serves `/og/run/<id>.png` at request time, CloudFront routes `/og/run/*` to it, and `build.mjs` copies the `@resvg/resvg-js` loader + the `@resvg/resvg-js-linux-arm64-gnu` native package into the zip's `node_modules`. The Lambda runs on arm64, so that native package must be resolvable on the build host. On `ubuntu-latest` (CI) `npm ci` normally pulls all-platform optional deps, but if `build.mjs` fails fast with the missing-binary error, run `npm install --workspace=apps/web --cpu=arm64 --os=linux @resvg/resvg-js-linux-arm64-gnu` before the zip step. Operator action: confirm the first prod/preview deploy after this lands actually renders `/og/run/<known-id>.png` (200, valid PNG) and that a private/deleted id returns the generic branded card at 200, not a 404. The new `/og/run/*` CloudFront behaviour is a `terraform apply` on `infra/envs/{prod,preview}`. See `apps/web/lambda/share-run/README.md § og:image PNG`.
- [ ] **Live spectator hub → Fly.io** — `fly.toml` exposes the hub on `:443` with `LIVEHUB_ALLOWED_ORIGINS`; remaining: provision the Fly app + `flyctl deploy`, add the `live.threkir.com` DNS record (`flyctl certs add` + Route 53), set `PUBLIC_LIVE_HUB_URL` (web sops blob) + `LIVE_HUB_URL` (mobile release builds). Client wiring (mobile + web) already switches transport on the env flip; no further code change. Recipe: `apps/job_worker/deployment.md § Live spectator hub`.
- [ ] **Map matching deploy** — OSRM alongside Supabase, OSM-extract refresh pipeline, auth endpoint, matched-geom return + raw-vs-matched toggle, offline fallback. Engine choice + trigger wiring shipped; the deploy is what remains.
- [ ] **Protomaps self-hosted tiles** — all 4 items from `roadmap.md` "Future — Protomaps self-hosted tiles".

## Web SEO

- [x] **Request-time `share-route` Lambda (parity with `share-run`)** — **landed 2026-06-04.** `/share/route/[id]` + `/og/route/[id].png` were prerendered at build time (`entries()` from `public_routes`, capped at 5k); a route made public *after* a build — or beyond the cap — served the SPA-shell fallback `<head>` (generic "Threkir" title, no per-route OG) and a 404 for the og:image until the next deploy, and a public→private flip stayed served from S3 until overwritten. Now mirrored on the `share-run` design: a dedicated `share-route` Lambda (`apps/web/lambda/share-route/`) renders both surfaces at request time, reusing `buildRouteShareCanonical` / `buildRouteJsonLd` / `buildRouteOgSvg` (+ `buildRouteShareTitle` / `…Description`) via the new `share_route_lookup` / `share_route_meta` / `share_route_spa_shell` / `og_route_png` helpers. The page `+page.ts` + og `+server.ts` flipped to `prerender = false` (dev server owns the path locally), CloudFront gained `/share/route/*` + `/og/route/*` behaviours + a dedicated cache/origin policy, `infra/github-oidc` grants `…-share-route*` deploy perms, and `release-web.yml` bundles + redeploys the zip on every `web@*` tag (arm64 @resvg packaging matches share-run). The og PNG path returns a generic branded card at **HTTP 200** for private / deleted ids (never a 404), and the track is privacy-clipped via `clip_track_for_user` server-side. Unit coverage: `share_route_spa_shell.test.ts` (injection, canonical/JSON-LD strip, XSS escape, per-env URLs) + `og_route_png.test.ts` (missing-route → valid PNG). **Operator action:** confirm the first prod/preview deploy after this lands renders `/og/route/<known-id>.png` (200, valid PNG) and that a private/deleted id returns the generic card at 200; the new CloudFront behaviours + share-route Lambda are a `terraform apply` on `infra/envs/{prod,preview}`. See `apps/web/lambda/share-route/README.md`.

## Web bundle weight

- [ ] **Externalise the RevenueCat web SDK behind hosted checkout** — `@revenuecat/purchases-js` is a top-level static import in `apps/web/src/lib/billing/revenuecat.ts`, so the full SDK (~178 KB gzipped) ships in the `/settings/upgrade` route bundle and is the second-largest single lib after maplibre-gl. The `web-bundle-budget.yml` total ceiling was raised 1500 → 1900 on 2026-06-10 to acknowledge legitimate cumulative growth (the app measured 1689 KB), but that metric sums *all* chunks incl. lazy ones, so code-splitting won't recover the weight — only removing the SDK does. Durable fix: drive Pro checkout + the management-URL link through RevenueCat's hosted-checkout redirect instead of the embedded JS SDK, dropping ~178 KB and buying back headroom under the *old* 1500 ceiling. Rewrites the billing flow (`startProCheckout` / `managementUrl` / the configured-vs-unconfigured fallback) + needs its own e2e + a mobile-parity check, so it was out of scope for the CI fix that surfaced it.

## Performance — deferred hot spots (perf-hunt 2026-06-10)

The 2026-06-10 perf-hunt over the web read/query layer fixed the migration-free
hot spots inline (coach request path: dropped a duplicate `get_my_profile` RPC +
fanned out `buildContext`'s five serial reads with `Promise.all`; `CalendarHeatmap`:
windowed the run bucketing to the rendered weeks). The three migration / `/safe-edit`-grade
survivors were then completed (2026-06-10 follow-up):

- [x] **`fetchEffortsForRun` N+1 rank loop → one RPC** — `segment_effort_ranks(p_run_id)`
  (migration `20261223_001`, SECURITY INVOKER so RLS gates the comparison set identically)
  ranks every effort on a run in one round-trip; `fetchEffortsForRun` calls it instead of a
  count-per-effort loop. pgTAP `segment_effort_ranks_test.sql`.
- [x] **`/runs` unbounded full-filter render → windowed + Show-more** — the render is capped
  at `PAGE_SIZE` in full-fetch mode with a Show-more reveal (paginated browse mode unchanged,
  DB Load-More already bounds it); cap resets on filter/sort change. e2e plants 55 hikes and
  asserts the cap + reveal. i18n `runs.showMore` in all six locales.
- [x] **`fetchGymSetHistory` whole-history reads → bounded/aggregated per surface.** Each
  hot surface now reads only what it needs instead of the user's entire `gym_sets` log:
  - **/gym/records** → `gym_exercise_records()` RPC (migration `20261224_001`): per-exercise
    all-time bests aggregated server-side (all-time maxima can't be windowed). Mirrors how
    run PRs live in SQL, so the client-side `exercise_records.ts` stopgap was retired; pgTAP
    pins the metrics to the `gym_prs.test.ts` fixture shape.
  - **/dashboard** → `fetchGymSetHistory({ sinceDays: 180 })`: it only reasons about recent
    training (90-day load curve + 5 most-recent-lift cards). Source guard in
    `dashboard_fitness_source_guard.test.ts`.
  - **/gym/exercise** → `gym_exercise_set_history(p_name)` RPC (migration `20261225_001`):
    one exercise's sets, matched on the normalised name so a differently-cased session still
    matches. pgTAP covers the case/whitespace-insensitive match.
  - **/gym/[id]** → the same per-exercise RPC, fetched per distinct exercise in the workout
    (deduped by normalised key) — the PR badges + vs-last-time only judge the workout's own
    exercises.
  - **/history** autocomplete → `gym_exercise_names()` RPC (migration `20261226_001`):
    distinct names + use counts, most-used first.
  - **Residual — /gym list temporal PR badges (`prWorkoutIds`)** still reads the full set
    history: judging "did each of the ~100 displayed workouts set an all-time PR up to that
    point" inherently needs every prior set across all exercises, so it can't be windowed.
    Fully eliminating it needs a **write-time PR flag** — a trigger-maintained
    `gym_workouts.pr_kinds` computed when a workout's sets change (against the then-current
    records), with a cascading recompute of later workouts of the same exercises (changing a
    record-holder flips later badges). That cascade-correctness + the SQL PR math is a
    multi-day feature in its own right; tracked here as the one remaining gym read.

The lower-ranked data findings (`fetchEngagementSummaries` / `hydratePeopleSuggestions` /
`enrichPosts` fetch-rows-to-count, `fetchClubMembers` unbounded roster) only bite at
engagement/club scales the prod tables haven't reached; each wants a grouped-count RPC or
`.range()` pagination when those tables grow — not worth a migration today.

## Route loop generation — loop-poor UX (designed, P3 half unbuilt)

- [ ] **Largest-achievable-loop probe + 3-way choice** — the v2 sampled via-point loop generator ([decisions §137 amendment](../architecture/decisions.md), [route_loop_generation.md](../features/route_loop_generation.md)) ships polygon-first with a `round_trip` fall-through, but the doc's *first-class loop-poor UX* is **not built**. Today a loop-poor start (polygon generator returns `null`) falls through to `round_trip` and reuses the pre-existing "shorter than X — use Y instead" shortfall banner. Remaining: have `generatePolygonLoop` / `handleGenerate` surface the **largest in-band-free real loop** it actually found so the client can offer "best loop near you is ~X km", plus the explicit three-way choice — (a) generate that shorter real loop, (b) accept the out-and-back to the requested distance, (c) try a different start — across `RouteBuilder.svelte`, the SvelteKit `+server.ts`, and the generate-route Lambda. ~1 day. Durable fix for the reported sparse start.

- [ ] **Graph-cycle generator (v3) — use the real neighbourhood loop** — both v2 (polygon) and `round_trip` reason about *geometry*, not the street *graph*, so on irregular grids they can't trace the clean loop a human would pick (proven: 432 polygon placements found zero loops at a start where one demonstrably exists). The durable fix is to search the actual local street graph for cycles (direction-sampled disjoint-path loops on a foot-graph sidecar extracted from the same PBF). Full design, data-source comparison, phasing, and effort (~8–10 d, new prod sidecar is the real cost) in [graph_cycle_loop_generation.md](../features/graph_cycle_loop_generation.md). **P0 spike run 2026-06-10 → green-lit** (real clean loops at dense/medium areaEff 0.42–0.60 vs geometry's zero; the report start confirmed genuinely loop-poor). It also **subsumes the largest-achievable-loop probe above** (the graph search surfaces the largest clean loop for free). Remaining: P1–P3 (Go graph sidecar + integration + prod deploy).

- [ ] **Tighten the polygon path toward target + multi-distance for the polygon radius** — the `round_trip` path now races a spread of request distances and lands in-band ([fix](../architecture/decisions.md)), but the polygon path's in-band selection still prefers the *roundest* loop, which can return ~+8–11% in dense areas when a closer loop exists. Apply the same closest-to-target weighting + race the polygon radius fraction, not just a fixed [0.12–0.16] band. Small, web-only.

- [ ] **Route-design preferences** — once the graph-cycle generator exists, expose preference knobs (avoid highways, stick to neighbourhoods, scenic/quiet, elevation-aware, opt-in cul-de-sacs) as edge weights/filters + a multi-objective scoring layer on the graph search. The avoid-highways/prefer-residential half is cheaply doable today via a GraphHopper custom profile. Design in [graph_cycle_loop_generation.md § Extension](../features/graph_cycle_loop_generation.md). ~2–3 d on top of v3.

- [ ] **AI route assistant** — an LLM *bookend* around the generator: plain-English request → validated generation constraints (tool-use extraction), and generated route → plain-English description. The LLM never routes (graph search owns correctness); it translates intent + writes prose, reusing the existing Anthropic/AI-Coach transport + paywall. Build the description half first (cheap, has a templated fallback). Design in [ai_route_assistant.md](../features/ai_route_assistant.md). ~4–7 d, generator-agnostic.

## Blocked on external credentials / accounts

- [ ] **Push notifications (FCM + APNs + web Push)** — operator: create a Firebase project, drop `google-services.json` (Android) / `GoogleService-Info.plist` (iOS), enable an APNs auth key in the Apple Developer portal + upload to Firebase, generate `VAPID_PRIVATE_KEY` for web. Then add `firebase_messaging`, register tokens to `user_devices.push_token`, write the workout-reminder + kudos receive handlers, and wire `apps/web/src/lib/util/push.ts`.
- [ ] **Garmin Connect** — blocked on the multi-day Garmin Developer Program application + OAuth client provisioning. Then follow the Strava pattern: a `garmin.dart` helper + a `garmin-import` Edge Function + a Settings tile wired to OAuth. (Distinct from the on-watch Connect IQ data field at `apps/watch_garmin/` — that runs *on* the watch in Monkey C and needs no Garmin approval; this is server-side cloud sync. See [decisions.md § 107](../architecture/decisions.md#107-vector-1-starts-as-a-connect-iq-data-field-grade-adjusted-pace-not-a-full-watch-app).)
- [x] **Grade-adjusted pace on web/mobile** — done 2026-06-02. The Minetti 2002 model is now a shared TS↔Dart parity pair (`apps/web/src/lib/runs/grade_adjusted_pace.ts` ↔ `apps/mobile_android/lib/grade_adjusted_pace.dart`), surfaced as a run-detail key-stat on web and a secondary stat on mobile (byte-identical iOS twin), 10-test mirror suite each side. See [decisions.md § 114](../architecture/decisions.md#114-grade-adjusted-pace-lands-on-webmobile-first-as-a-shared-minetti-parity-helper-computed-over-5-m-segments-and-shown-only-when-it-diverges-from-raw-pace). **This satisfies the web-first prerequisite** [§107](../architecture/decisions.md#107-vector-1-starts-as-a-connect-iq-data-field-grade-adjusted-pace-not-a-full-watch-app) placed on the `apps/watch_garmin/` Connect IQ GAP field; remaining work is operator/product (publishing that field via the Connect IQ Store), not code — the math now matches across web, both mobile twins, and the watch field.
- [ ] **RunSignUp race-results** — needs a runsignup.com API key (free for non-commercial use). Then follow the parkrun pattern: a `runsignup-import` Edge Function + a Settings tile that ingests into `runs.metadata.event` / `position`.
- [ ] **iOS verification** — Mac-only. The byte-identical Dart codebase already supports every Android feature (decisions §39); `parity.md` cells stay ✗/Partial *by design* until simulator/device-verified. Gates: `Runner.entitlements` (HealthKit + Sign-in-with-Apple), `pod install`, the Apple Developer Sign-in-with-Apple Services ID + APNs setup. Info.plist is already complete.
- [ ] **Apple Watch** — Xcode / watchOS device required: route-nav visuals, ultra-length stress test, live race participant, complication target (Widget Extension), activity types, lap markers, hold-to-stop, TTS cues, pedometer, GPS self-heal, indoor mode, route picker, BLE pairing UI — each wired in Xcode + verified on a simulator or paired device.

## Internationalisation framework (sized project, not started)

Surfaced by the 2026-05-30 i18n-readiness audit. RTL *layout* is already complete web-wide (logical CSS properties + dir switch), and two standalone items shipped — the non-Latin font fallback (`app.css`) and the coach "reply in the runner's language" instruction. The remaining work is one coherent project, not piecemeal fixes:

- [~] **Web string framework runtime** (W-1/W-2/W-3 foundation) — **landed 2026-06-01.** The i18n runtime lives at `apps/web/src/lib/i18n/`: a client-side locale signal (`store.svelte.ts`, `m(key, params)`), pure negotiation (`locale.ts`), a per-locale message catalogue (`locales/{en,de,fr,es,ja,pt-BR}.ts`, lazy-imported via `catalogues.ts`), and detection wired in `+layout.svelte` (`initLocale` → `<html lang/dir>`). W-2/W-3 are resolved **client-side**, not via an `Accept-Language` server hook — the web app is statically prerendered with no per-request SSR ([decisions.md § 108](../architecture/decisions.md#108-web-i18n-is-detected-client-side-with-a-lazy-loaded-message-catalogue--not-an-accept-language-ssr-framework)). Starter translations ship for de/fr/es/ja/pt-BR. The **settings language picker** shipped (Settings → Preferences, endonym options). The **locale-aware formatter pass** shipped: number formatting (`format/number.ts` → `units.svelte.ts`, **W-15**), relative time (`Intl.RelativeTimeFormat`, **W-7**), the weekly-mileage axis label (**W-10 label**); **W-11** (recap-image numbers) was already locale-aware. The **calendar pass** shipped: PlanCalendar month/weekday names + `week_start_day` reorder via `format/calendar.ts` (**W-5**), and the weekly-mileage chart now anchors on `week_start_day` (**W-14**); **W-6** (`CalendarHeatmap`) already supports `weekStartDay` + locale-aware labels and the component is not currently mounted anywhere; the run-list week filter already honours `week_start_day` (the rest of W-14). **W-12** is done: `time.ts` carries a runtime-synced active format locale (`setActiveFormatLocale`/`activeFormatLocale`), so `formatDate`/`formatDateShort`/`formatRelativeTime` follow the picker, and all 19 inline `toLocaleDateString(undefined,…)` surfaces were swept to `activeFormatLocale()`. **W-8/W-9** done: the Free-tier price routes through `formatPrice(0)` and the Strava competitor price is labelled a US reference that varies by region. **Remaining (the only open web i18n item): incremental extraction of the ~400 user-facing string literals** across the route/component tree into the catalogue — a large mechanical + per-locale-translation effort, best done cluster-by-cluster. **Done:** app-shell nav/profile/offline + `prefs.language` + the full `/login` page; **workflow batch 1** (+1067 keys): dashboard, runs + runs/[id], routes + routes/[id] + routes/new, onboarding, coach + CoachChat, plans + plans/[id], u/[id], settings/{account,devices,integrations}. **Workflow batch 2** (+1231 keys): clubs (home + event detail + new-event + join + ClubEditor + EventEditor), landing, the plan/workout/run/event/plan-meta editors, settings/{upgrade,gear}, recap, compare, coaching (+ accept + athletes), share (run + route), live (+ event), messages, social (feed/people/clubs/hub + RunSocial), RunPhotos, SegmentsPanel, ImportRoute, RouteExplorer, RouteHeatmap, DateRangePicker, PeriodSummary, plans/new, guided detail, auth/reset. **Workflow batch 3** (+239 keys): the final tail — NotificationBell/NotificationsList, CookieConsentBanner, LicenseList, ReportDialog, RaceDayPanel, RunMap, ElevationProfile, PersonalHeatmap, RouteBuilder, TrainingLoadChart, RunGearChips, runs/heatmap, settings/+layout, and the auth/{confirm-age,callback} + guided + clubs/new + runs/new page-chrome wrappers. **Post-batch fixes (2026-06-01):** (1) the **Settings → Preferences** page itself was still ~95% English — the batches skipped it because it already used `m('prefs.language')`, so a `+87`-key extraction pass finished it. (2) A **reactivity bug** class was found + fixed: labels built in top-level `const` arrays/objects (the /runs filter chips, run-detail activity/zone labels, settings/devices spec, settings nav sections, landing app cards, integrations descriptions) called `m()` once at init and never updated on a locale switch — each was moved to `$derived(...)` (or rendered reactively in-template). **Watch for this anti-pattern in future extraction: never `const x = [{ label: m(...) }]` at script scope — use `$derived` or call `m()` inline in the template.** **Web string extraction is now COMPLETE** — ~75 files / ~2682 keys × 6 locales across the three workflow batches plus the hand-done shell/login/preferences. The only English-by-design surface left is the **legal pages** (privacy/terms/cookie-notice) — counsel-pending draft copy, translating them is a legal decision. **Caveat:** the ~2540 machine-extracted translations want a **native review** before advertising full localisation (agents flagged the fitness-domain tooltips — CTL/ATL/TSB/VO₂max — and a few register/article-agreement/fragment-split spots, all noted in their per-file outputs). Next platforms: **mobile (Flutter)**, **Wear OS**, **watchOS**, and Supabase **email templates** (per the M-*/W-OS-*/iOS-W-1/SRV-1 audit items). Each cluster: pull the literals into `locales/{en,…}.ts`, swap to `m('key')`, translate ×5 (running-domain copy wants a native review). Then the mobile / watch / watchOS / email surfaces.
- [x] **Web i18n has no plural support** — **DONE 2026-06-10.** `interpolate()` now resolves inline `{var, plural, one {…} other {…}}` blocks by selecting the CLDR category via `Intl.PluralRules` for the active locale (`#` → count, `=N` exact matches win, named placeholders still filled); `m()` threads the live locale through. Converted the single-form countable-noun templates across all six locales (`history.setCount`, `gym.exercisesShort`, `coachPage.cueCount`, `coachChat.daysAgo`/`errorDailyLimit`/`limitReached`, `planDetail.replanApplied`, `settingsAccount.restoreWarnings`/`contactsSaved`/`parkrunImported`/`exportReady`, `recap.shareStreak`, `routeHeatmap.clusterHead`) and folded the hand-rolled `settingsAccount.parkrunImportedOne` twin into the ICU string (no one-off `*One` keys added; `ja` uses a lone `other` branch). Invariant/parenthetical/unit/ordinal counts deliberately left alone (no noun to inflect). 34 unit + 1 e2e (singular "1 exercise") green; the placeholder-parity guard holds (ICU branches emit no stray `{token}`). The many pre-existing manual `*One`/`*Other` pairs can migrate to the ICU runtime incrementally in a later pass. See [decisions.md § 108](../architecture/decisions.md#108-web-i18n-is-detected-client-side-with-a-lazy-loaded-message-catalogue--not-an-accept-language-ssr-framework).
- [~] **Mobile (Flutter) localisation** (M-1/M-2/M-3) — **mostly done** (verified 2026-06-02; the old "unstarted, ~473 literals" estimate is stale). `flutter_localizations` + `intl` + gen-l10n are wired with six-locale ARB catalogues, committed gen output, a per-device locale picker, locale-aware `DateFormat`, and locale-driven TTS — see [decisions.md § 113](../architecture/decisions.md#113-mobile-i18n-uses-flutter-gen-l10n--arb-with-committed-non-synthetic-output-and-a-per-device-locale). 79 of ~158 `lib/` files already route through `AppLocalizations`. **Remaining (2026-06-03 pass):** the residual screen cleanup is essentially done — `people`, `trusted_contacts`, `club_invite`, `route_picker`, `recap`, `import`, `readiness_card`, and `missing_map_tiles_hint` were extracted (~107 keys ×6 locales + iOS twin mirror; the `import` pass also dropped a dual English/l10n shim in `buildImportStatus` plus two dead helpers). The last two files — `run_screen.dart` + `widgets/run_share_card.dart` — were localized on 2026-06-03 (run-start background-location + battery-optimisation dialog title/body, and the run-share caption; +5 keys ×6 locales, their now-orphaned English `k*` constants in `background_location_nudge.dart` / `battery_optimisation_hint.dart` deleted). A **wider follow-up sweep the same day** (a stricter grep than the `Text('[A-Z]` heuristic that had under-counted) caught the genuine remainder the earlier passes missed: the whole `settings_screen` landing (tile labels reuse existing `settingsAccountTitle`/`prefsTitle`/… keys, +7 new subtitle keys), `period_summary_screen` (`Week of`, `All time`, the share-text run-count plural + `Avg pace:` — pure helpers localized via context-free `lookupAppLocalizations`, +3 keys reusing `historyRangeAll`), the `verified_badge` tooltip (+1 key), and the dashboard + run-detail **best-effort distance names** (`Half Marathon`/`Marathon`/`5 km`/`10 km` — +4 keys via a `bestEffortDistanceLabel` resolver in `run_stats.dart`). Confirmed **not** gaps and left as-is: the `devices_screen` `overrideKeyRegistry` English `label`/`hint` (fallbacks behind a working `labelFor`/`hintFor` l10n switch, pinned non-empty by a test), `workout_review_section`'s `fromMap` labels (display uses `localizedLabel(l10n)` + the existing `workoutReviewLabel*` keys), `$e`-interpolated exception text in already-localized banners, the `"DELETE"` account-deletion challenge token (referenced literally in every locale's instruction string), and proper nouns (`Strava`/`GPX`/`Threkir`/parkrun `A123456` format hint). The mobile string-extraction pass is now **complete**; the only remaining mobile i18n work is RTL (`EdgeInsetsDirectional` sweep), still deferred until an RTL catalogue ships.
- [ ] **Watch localisation** (WR-1, WOS-1) — Wear Compose string resources + watchOS `Localizable.strings`.
- [x] **Guided-run scripts** (S-1) — **landed 2026-06-04.** Web `guided_runs.ts` no longer exports a hard-coded English `const`: `GUIDED_RUN_LIBRARY` became `guidedRunLibrary(t)` (+ `findGuidedRun(t, id)`), the web twin of the mobile `guidedRunLibrary(AppLocalizations)`. The three runs' titles/subtitles/descriptions/cues are now 37 `guidedRuns.*` catalogue keys across all six locales (translations reused verbatim from the mobile ARB twin, so no fresh native review is needed — the copy already ships on mobile). The cue *timing* stays inline (locale-independent). Consumers (`/guided`, `/guided/[id]`, `/coach`) build the library inside a `$derived` so it re-localizes on a locale switch; `/coach`'s `intensityFor` was moved off localized-title substring matching onto the stable run `id` (would have silently failed in every non-English locale).
- [~] **2026-06-03 i18n residual closures** — re-verified the 2026-05-30 audit against current code; the bulk was already done. Closed this pass: **W-4** (workout-kind + plan-phase labels were still bare English in `training.ts`/`training.dart` — moved to presentation helpers `workout_labels.ts` / `training_labels.dart` that read the catalogues, +14 keys across all web locales and all 7 ARBs, both mobile twins); **W-12** (`PeriodSummary` week-range *end* date passed `undefined` instead of the active locale); **W-OS-3** (Android run-notification channel name + Resume/Pause/Stop action labels were hard-coded in `RunNotificationBridge.kt` — now string resources with 5 locale folders + a guard test). Note: the **watch** framing on the line above is stale — Wear already uses `stringResource` + `values-{de,fr,es,ja,b+pt+BR}` and watchOS ships `Localizable.xcstrings` with 5 locales (W-OS-1/W-OS-2/iOS-W-1 are closed). **Closed 2026-06-04:** the **`routes/heatmap` web page** + its `RouteHeatmap` component now route entirely through `m()` (the earlier "0 `m()` calls" note was stale — the page chrome was localized in a prior pass and the user-facing copy lives in `RouteHeatmap` (53 keys) + `PersonalHeatmap` (18 keys), both fully extracted; verified no bare user-facing literals remain on either `routes/heatmap` or `runs/heatmap`); and **guided-run scripts** (S-1, line above). **Still genuinely open:** Supabase auth email templates (SRV-1 — GoTrue serves one template set per project with no per-recipient locale, so this is platform-limited, not a quick edit); and RTL (`EdgeInsetsDirectional`/`AlignmentDirectional`, deferred until an RTL locale ships).

## Watch (Wear OS) — sized features awaiting hardware + a product green-light

Surfaced by the persona round-5 samsung-watch hunt (plus the mi-preference item
from the 2026-06-10 run-detail UX pass). Most need the Wear build toolchain plus
on-watch verification (Galaxy Watch / Pixel Watch) — the recording stack isn't
runtime-testable without a device — though the mi-preference item below is mostly
pure parse/format logic that *is* host-JVM testable, with only the end-to-end
readout needing a device. The audio-focus ducking fix from the same hunt shipped
already (`TtsAnnouncer.kt` now requests `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`);
these four are genuine features, not bug fixes.

- [ ] **Honour the mi distance preference on the watch** (~2-4 d, partly host-testable) —
  surfaced by the 2026-06-10 run-detail UX pass. `PostRunScreen` and the running
  screen always render distance in **km** (`R.string.distance_km` via `formatKm`)
  and pace as raw sec/km (`formatPace` in `ui/RunWatchApp.kt`), regardless of the
  user's `preferred_unit` — so a miles-preference runner who sees `/mi` everywhere
  on web + mobile gets km on the wrist. The data source is **lighter than it first
  looks**: `preferred_unit` is a universal-settings-bag key (`docs/backend/settings.md`
  — dual-read with the legacy `user_profiles.preferred_unit` column), and the watch
  *already* fetches that bag (`SupabaseClient.fetchUniversalSettings` →
  `user_settings?select=prefs`, parsed by `parseUniversalSettings`, threaded through
  `RunViewModel` exactly like `bodyWeightKg`). Scope:
  - **Read** — add `preferredUnit: String?` to `UniversalSettings` (`SupabaseClient.kt`)
    + parse `prefs["preferred_unit"]`; thread it through `RunViewModel.UiState` to the
    screens (same path as `bodyWeightKg`). No new permission, no Samsung SDK / Health
    Connect — unlike the body-weight item below.
  - **Format** — `recording/UnitFormat.kt` is km-only today; add a unit-aware
    `formatDistance(distanceM, unit, locale)` (÷1609.344 for mi) and a unit-aware pace
    (the existing `formatPace` assumes per-km). Keep the locale decimal-separator
    behaviour `UnitFormatTest` already pins.
  - **Strings** — add `distance_mi` + `pace_per_mi` to `values/strings.xml` and **all
    five** `values-*` (`L10nResourceParityTest` fails otherwise); apply at the PostRun
    distance, running-screen distance + pace, the route "X.XX km to go" badge, and the
    active-run tile (`tiles/ActiveRunTileService.kt` `formatStatRow`).
  - **TTS (optional, for full parity)** — the split cue speaks "N kilometre(s)"
    (`tts_*` resources / `TtsPhrases.kt`); a mile variant keeps the spoken cue consistent
    with the displayed unit. Can ship as a follow-on if scoped out.
  - **Testable on host JVM:** the parse + the new `UnitFormat` mile path + `formatStatRow`
    are pure — extend `UnitFormatTest` / add a `preferred_unit` `parseUniversalSettings`
    case. Only "the watch face actually flips to mi" needs a device.

- [ ] **BLE chest-strap HR paired directly to the watch** (~1-1.5 wk + device) —
  today BLE chest-strap HR is **phone-only** (`apps/mobile_android/lib/ble_heart_rate.dart`);
  the watch records **optical** HR via Health Services `MeasureClient` only, and
  only when standalone. Supporting a strap paired to the *watch* means an
  on-watch Wear OS BLE GATT client: a scan/pair UI, the standard Heart Rate
  Service (`0x180D`) / Heart Rate Measurement (`0x2A37`) characteristic
  subscription, `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` runtime perms, and a
  source-preference so a connected strap overrides the optical stream into
  `metadata.avg_bpm`. Reconnect/dropout handling on the wrist is the fiddly part.
  A minority feature (watch-standalone runners who own a strap) — already noted
  as deferred in [`apps/watch_wear/CLAUDE.md` § "What's still deferred"](../../apps/watch_wear/CLAUDE.md).
  **Needs hardware**: a real strap + watch to validate GATT connect, sample
  cadence, and battery cost; not unit-testable.
- [ ] **Real body weight → calorie estimate** (~2-4 d + device) —
  `apps/watch_wear/.../recording/RunCalories.kt` reads `body_weight_kg` from the
  prefs bag but defaults to **70 kg** when unset, so a runner who never set a
  weight in the web/mobile settings gets a generic kcal figure on `PostRunScreen`.
  Pipe the user's *actual* weight into the estimate. Data-source options, in
  rough order of fidelity: (a) Samsung Health BIA body-composition (most accurate
  on a Galaxy Watch, but requires the Samsung Health SDK / Health Connect read
  permission + Samsung partner approval — heaviest integration); (b) Health
  Services / Health Connect `WeightRecord` (vendor-neutral, lighter, but the user
  must have logged a weight somewhere that syncs); (c) surface a weight field in
  the watch settings or rely on the existing universal-setting sync from
  web/mobile (cheapest, no new permission, but manual). The watch still won't
  apply the female calibration the phone/web cell uses (it reads
  `user_settings.prefs` only, not `user_profiles.gender` — decisions §77), so the
  watch summary stays an estimate that the synced run-detail page recomputes.
  **Needs a device** to confirm the chosen read path actually returns a value on
  a real Galaxy Watch.
- [ ] **Watch-face complication** (~1-1.5 wk + device) — only an **active-run
  tile** ships today (`tiles/ActiveRunTileService.kt`); a true watch-face
  *complication* (a glanceable slot the user adds directly to their watch face,
  vs. the swipe-to tile carousel) is unbuilt — `parity.md` was corrected to say
  tile-only. Building it means a `ComplicationDataSourceService` (androidx
  `wear-watchface-complications-data-source`), supported complication types
  (`SHORT_TEXT` for elapsed/distance, `RANGED_VALUE` for goal progress,
  `MONOCHROMATIC_IMAGE` for an idle glyph), a tap `PendingIntent` into
  `MainActivity`, the same `requestUpdate`-on-stage-transition wiring the tile
  uses, plus a preview + picker label. Pure formatters can be unit-tested
  (mirror `ActiveRunTileFormattersTest`); the data-source binding + render need a
  watch face that hosts the complication slot, so **on-device verification is
  required**.

## Competitor-parity backlog (needs product green-light)

From `roadmap.md § Competitor-parity backlog`; sizes are rough estimates carried from the roadmap table:

- [ ] **Heatmap / popular-route discovery** (#4, ~2 wk) — materialised tile table or a Go tile service; anonymised aggregation. Open decision: opt-in vs opt-out privacy default.
- [ ] **Trail / offline navigation** (#5, ~3-4 wk) — turn-by-turn on a loaded route + offline tile packs + condition reports. Needs a routing-engine choice (Valhalla vs GraphHopper).
- [x] **Gear tracking** (#7) — shipped end-to-end (migrations `20260827_001` + `20260901_001`; `/settings/gear` + `RunGearChips` on web, `GearScreen` + twin on mobile, auto-tag-default trigger, `gear_with_distance` mileage view). 2026-06-02 follow-up closed a latent RLS bug: the gear chip never rendered on the **public** run-share page for non-owners — the `run_gear` SELECT policy wrapped `is_run_visible_to` in a base-`runs` subquery that the public-read-policy drop (`20260701_001`) had silently defanged, and the `gear` join is owner-only so a non-owner read NULL anyway. Fixed by `20261126_001` (direct definer call + a `public_run_gear` SECURITY DEFINER RPC that projects only public columns), `RunGearChips` mounted on `RunShareView`, pgtap + anon e2e. Mobile parity closed 2026-06-04: the `RunGearChips` Flutter widget (already on `run_detail_screen`) now also mounts on `public_run_screen.dart` (+ iOS twin), unconditionally so anon viewers see the read-only chips, reading via the same `public_run_gear` RPC through `ApiClient.fetchRunGear`; the owner-only edit affordance stays gated on viewer == owner. `run_gear_chips_test.dart` widget test pins the non-owner/anon read-only path + the owner edit affordance.
- [ ] **Audio-coached runs** (#9, ~3-4 wk) — pre-recorded workout library + TTS-narrated pace cues. Audio CDN strategy + voice-talent budget needed.
- [ ] **Race calendar + results import** (#10, ~2 wk) — event discovery + entry links + auto-match results on record. Gated on the RunSignUp key above.
- [ ] **Advanced analytics polish** (#11, ~2 wk) — no new tables; richer dashboard breakdowns + race-time predictor over what VDOT / training-load already ship.
- [ ] **Premium billing extensions** (#12, ~1-2 wk) — Stripe Checkout + customer portal + paywall enforcement across web + mobile.
- [ ] **Treadmill BLE FTMS** (#13, ~3-5 d, mobile-only) — real-time speed / distance / incline from a paired treadmill. Spec in `integrations.md § Treadmills (BLE FTMS)`. Needs hardware-in-the-loop testing.

## Safety-contact finish alerts (persona round-5 family-club)

The `run_completed` notification (migration `20261101_001`) correctly fans a
**public** run out to the runner's **followers**. The family-club persona wanted
a partner to be alerted that the runner finished *even on a private run* (a
safety use case). This is NOT a fix to the `is_public` gate — removing that gate
would broadcast every private run to all followers, a privacy regression. The
real need is a distinct, opt-in feature:

- [x] **Safety contacts** — **core shipped 2026-06-04** (migration
  `20261218_001`, `decisions.md § 131`). A `safety_contacts` table (owner →
  email-identified contact, account-linked on confirm; double opt-in via
  `confirmed_at`), a `runs` AFTER INSERT trigger that enqueues a new
  `safety_email` `finish` job per **confirmed** contact regardless of
  `is_public` (24h recency guard, **not** gated on the runner's
  `email_notifications` pref), and a `safety_contacts` AFTER INSERT trigger that
  emails the opt-in `confirm` request. Confirm paths: in-app
  (`my_pending_safety_requests` + `confirm_safety_contact`) and an
  unauthenticated email-link (`confirm_safety_contact_by_token`). Web Settings →
  Safety (`/settings/safety`) add/confirm/remove + the logged-out
  `/safety/confirm` page. pgtap + Playwright + Go handler tests; owner-scoped
  RLS with no owner-UPDATE (can't self-confirm). **Mobile UI shipped 2026-06-04
  (R2-B)** — Settings → Safety contacts (`settings_safety_screen.dart`,
  byte-identical iOS twin) mirrors the web surface: add by email, see
  pending/confirmed status, remove, and confirm/decline incoming requests.
  `ApiClient` safety methods (`fetchMySafetyContacts` / `addSafetyContact` /
  `removeSafetyContact` / `fetchPendingSafetyRequests` / `confirmSafetyRequest` /
  `declineSafetyRequest`) + `SafetyContact`/`PendingSafetyRequest` DTOs; widget
  + DTO tests. The email-link `/safety/confirm` page stays web-only (no mobile
  deep-link route). **Remaining:**
  - **Art 20 DSAR export of `safety_contacts`** — **DONE 2026-06-10** (with G1
    above). Now exported in both directions (`safety_contacts_owned.json` filtered
    `owner_id` + `safety_contacts_as_contact.json` filtered `contact_user_id`,
    `confirm_token` redacted) in both the Go `exportPersonalDataSpecs` and the
    `export-data` EF `buildBackupSpecs`; Go guard + Deno tests cover it.
  - Native push to a locked phone still waits on the FCM/APNs leg.

## Auto-follow on club join (persona round-5 social-group) — product decision

`join_club_by_token` adds an active `club_members` row; it deliberately does
NOT create `user_follows` edges. The social-group persona wanted joining a club
to wire up the social graph. But club invite tokens are **generic** (one
`clubs.invite_token`, not per-inviter), so there is no specific person to
follow-back, and auto-following every active member on join is presumptuous +
spammy + a consent concern (you didn't choose to follow 50 strangers). The club
feed (`club_posts`, already fanned out via notifications) is the intended
in-club social surface. If we want member-to-member connection, the right shape
is a **"Follow members" suggestion list** on the club page (opt-in, one tap),
not an automatic fan-out — tracked here rather than shipped as a silent
follow-everyone trigger.

## Persona round-5 — feature-scale items (not bug fixes)

Surfaced by the round-5 persona hunt; each is a real feature or needs external
keys/product sign-off, so none were half-built. Sized for the roadmap:

- [x] **Email notification delivery + event-day reminders (theme B, email leg)** —
  SHIPPED 2026-06-03 (migration `20261130_001`, `decisions.md § 117`). A
  `notification_email` job kind on the Go worker reads new notification rows and
  sends over SMTP, gated on `user_settings.prefs.email_notifications`
  (`all | important | off`, default `important`); `enqueue_event_reminders()`
  (hourly pg_cron) creates `event_reminder` rows for `going` RSVPs in the next
  24 h. Credential-free, end-to-end tested against local Mailpit. So the
  Saturday-morning race cancellation now reaches an inbox. Addresses the
  parkrun-owner / event-organizer / family-club / social-group findings for the
  email channel; admin-update fan-out rides the same path once that kind exists.
- [x] **Welcome / "thanks for signing up" email (lifecycle leg)** — SHIPPED
  2026-06-03 (migration `20261202_001`, `decisions.md § 119`). A `lifecycle_email`
  job kind (template-keyed, separate from the notification channel) sends a welcome
  on signup, enqueued by an AFTER-INSERT trigger on `user_profiles`; `lifecycle_email_log`
  is the send-once guard. End-to-end tested against local Mailpit. Transactional —
  no preference gate, no `List-Unsubscribe`.
- [x] **Transactional subscription emails — Pro receipt + payment-failed dunning** —
  SHIPPED 2026-06-03 (migration `20261203_001`, `decisions.md § 121`). An AFTER-UPDATE
  trigger on `user_profiles` enqueues `pro_welcome` on free→pro/lifetime and
  `payment_failed` on `billing_issue_at` null→non-null (the columns the RevenueCat
  webhook writes). Localized across all six locales; recurring (not deduped by the
  once-per-user log). End-to-end tested against local Mailpit.
- [ ] **Account-deletion receipt** — feasible but needs a different mechanism than the
  other lifecycle emails: the worker can't look up the address post-deletion (GoTrue
  404s), `delete-account` drains the user's pending jobs before the cascade, and
  `lifecycle_email_log` cascades away with the user. Build = send the email inline from
  the `delete-account` EF where `user.email` is still live (or enqueue a job carrying the
  address in the payload, exempt from the job-drain, with a non-cascading send-once
  record) — plus consider that the deleted user's email then lingers in `jobs.payload`
  until drained. `decisions.md § 121`.
- [ ] **Data-export-ready email** — NOT planned: the export endpoint is synchronous and
  returns a 10-minute signed URL inline, so an async "your export is ready" email would
  arrive stale and add no value. Revisit only if export moves to an async/job model.
- [ ] **Security emails (password-changed, new-device sign-in)** — blocked on absent
  infrastructure: no GoTrue auth hooks are configured (`config.toml`) and there's no
  sign-in/device tracking (the `device_tokens` table has no write path). Needs a
  password-change auth hook + a device/session table with new-device detection — a
  separate feature, not an email. `decisions.md § 121`.
- [ ] **Weekly digest + lifecycle drip (engagement email, ~1-2 wk + ops)** — reuses
  the shipped `lifecycle_email` kind with new templates: a weekly digest
  (mileage/PBs/kudos/upcoming events, weekly pg_cron → one job per opted-in user)
  and re-engagement / onboarding-drip / streak-nudge templates. **Prerequisites that
  the one-off welcome did NOT need** (these are bulk/engagement, so they're required
  before any of these go out): (1) a per-category **preference center** — separate
  keys (`email_weekly_digest`, …) on web + mobile, not folded into
  `email_notifications`; (2) **RFC 8058 one-click unsubscribe** (a tiny unauthenticated
  endpoint that flips the relevant pref); (3) **bounce/complaint suppression** so a
  dead address isn't retried. Per `decisions.md § 119`.
- [x] **Web-push server-side delivery (theme B, web-push leg)** — SHIPPED
  2026-06-04 (migration `20261219_001`). A `web_push` job kind on the Go worker
  (`handler_web_push.go` + the dependency-light `internal/webpush/` RFC 8291/8292
  sender) is the sibling consumer of the `notifications` row the email handler
  proved: the AFTER INSERT trigger enqueues one `web_push` job per recipient who
  has a browser subscription, the handler checks the recipient's
  `push_notifications` preference (separate key from `email_notifications`, same
  `all|important|off` shape, default `important`), reads their
  `user_device_settings.prefs.push_subscription` registrations, and POSTs an
  encrypted Web Push message to each — pruning a dead one on 404/410, deferring on
  429/5xx. Gated on the operator-generated `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY`
  (self-generated, not credential-blocked); unset → jobs finish done but leave the
  rows pending. `web_push_sent_at` is the per-channel idempotency guard. The client
  subscribe path (`apps/web/src/lib/util/push.ts`) + `/sw.js` already shipped, so
  this closes the loop. Go handler + webpush-crypto round-trip tests, pgtap, schema
  codegen.
  - **Remaining (`push_notifications` UI toggle)** — gating works with the default
    `important` without UI; a Settings → Preferences category toggle (web + mobile,
    mirroring the `email_notifications` one) is a small follow-up so users can pick
    `all`/`off` for push independently.
- [ ] **Native push delivery (theme B, FCM/APNs leg, ~1 wk + ops)** — the remaining
  leg: native push to a locked phone. Same `notifications` source of truth + sibling
  consumer pattern the web-push leg above now demonstrates end-to-end; an FCM/APNs
  sender is another sibling. Still genuinely blocked on operator-supplied
  Firebase/APNs credentials + mobile client-side token registration (no
  `firebase_messaging` wiring exists).
- [x] **Paid event registration** — superseded by [club_events.md](../features/club_events.md)
  (Slice E typed events + Slice P Stripe Connect marketplace). Slice P1 (in-person,
  host payouts, web checkout, manual refunds) has shipped on web: migration
  `20261229_001` + the three Edge Functions + `/settings/payouts` + the EventEditor
  Charge toggle + the event-detail Register flow. Refunds (automated), buyer
  self-cancel, waitlist notify-to-pay, and mobile register are P2–P3. The original
  sizing here undercounted: E is a prerequisite and the Connect foundation is larger
  than a registration form.
- [ ] **Strava community segment import (~2-3 wk)** — strava-migration wants their
  Strava KOM/QOM segments imported. Strava's segment API requires per-segment
  OAuth scopes we don't request, and segment-leaderboard data has Strava ToS
  redistribution limits — needs a legal + API-scope decision before building.
- [ ] **Family / household Pro tier (~1 wk + pricing decision)** — family-club pays
  4× $9.99 for 4 accounts. A household plan (shared subscription across linked
  accounts) is a pricing/product decision (RevenueCat entitlement model + a
  household link table), not a code-only change.

## Persona round-5 — remaining dispositions

- [ ] **Consent-flow consistency for health-data fields (privacy, legal-adjacent)** —
  onboarding still writes the bare `date_of_birth` column unconditionally (minor-
  exclusion) while gating the prefs-bag mirror + gender + consent timestamp on the
  Art 9 checkbox. `/settings/account` is now consent-gated (DOB writeback +
  `grant_health_data_consent` RPC, matching `/settings/preferences`), so the two
  settings surfaces are aligned; the remaining inconsistency is the onboarding
  unconditional-DOB-column write. Decide whether onboarding's minor-exclusion DOB
  capture counts as implicit consent or needs the explicit toggle too — a legal-flow
  decision, deliberately not bolted on without counsel input.
- [x] **Age-grade calculator for non-parkrun races (older, MEDIUM)** — **done 2026-06-04.**
  The authoritative **USATF-MLDR 2025** road age-grade tables (Alan Jones + Tom
  Bernhard, approved 2025-01-10; CC0 1.0; open standards match current world records)
  are embedded verbatim — **not** approximated from memory — via the raw RunScore
  files + generator under `scripts/age_grade/` → committed data modules
  `age_grade_tables.ts` ↔ `.dart` (identical by construction; 22 distances 1 mile…200 km
  incl. ultras, single-year factors 5–99, M/F). Logic is the shared TS↔Dart parity pair
  `age_grade.ts` ↔ `age_grade.dart` (12 mirrored tests each): nearest-standard match
  within ±2 %, age on race day, binary-sex gate, `agePct = openStandard / (duration ×
  ageFactor) × 100`. Surfaced on run-detail (web key-stat tile + mobile twin) when DOB +
  sex + a standard distance + duration are known and `metadata.age_grade` is absent;
  the parkrun scraped value still takes precedence. See [decisions.md § 132](../architecture/decisions.md)
  + [features/age_grade.md](../features/age_grade.md).
- [~] **Treadmill / indoor per-point HR → HR-zone chart (garmin)** — **core shipped 2026-06-02.**
  Chose data model (b): a sibling `{user_id}/{run_id}.hr.json.gz` Storage object in the
  `runs` bucket + a `runs.hr_series_url` column (migration `20261127_001`, [decisions.md
  § 116](../architecture/decisions.md)). `garmin-fit.ts` collects HR from records with no
  GPS fix into `ParsedFitRun.hr_series`; `saveRun` uploads the sidecar when the track has
  no bpm; web run-detail + the mobile twin (`ApiClient.fetchHrSeries`) fall back to the
  sidecar so the HR-zone chart renders for trackless indoor runs. The coordinate pipeline
  (GPX export, clip RPC, map-match) is untouched — the sidecar carries no location and is
  owner-only (never in `public_runs` / clip). Tests: FIT-parser unit tests + an anon-safe
  HR-zone e2e (`hr-zones.spec.ts` indoor case) + the path-forgery pgtap; twins byte-identical.
  **Backup/restore done (2026-06-02):** both backup builders (Dart `writeBackupZipStreaming`
  + Go `BuildBackupZip`) archive the sidecar under `hr/{id}.hr.json.gz` and count it in the
  manifest; the Dart restore re-homes it and always re-stamps `hr_series_url` (the archived
  value is the old owner/run path, which the path-shape CHECK would reject). Per-point HR now
  survives a device-swap backup→restore. **Fully shipped** — no remaining sub-items. (Offline
  restore still doesn't reconstruct per-point HR, the same documented caveat the GPS track has
  on that path; the cloud copy + online restore are complete.)
- [ ] **Health Connect import brings tracks (garmin/android, mobile + device)** —
  `health_connect_importer.dart` hard-codes `track: []`, so every HC-imported run is
  trackless/lapless/cadenceless. Reading the HC ExerciseRoute + sample series into a
  track needs the HC route API + on-device testing. Mobile feature.
- [ ] **Segment-KOM "crowns" in the recap (deferred)** — the Year-in-Running recap now
  shows a derived **Trophies** badge grid + **Photos** and **Personal records** counts
  (`recap.ts#computeRecapBadges` + `fetchRecapExtras`). Strava-style segment KOM/QOM
  "crowns" specifically are still omitted: `segment_efforts` has no stored rank, so a
  per-segment global-min aggregation across all users would be needed — heavier than a
  recap card warrants, and segment leaderboards are a secondary surface here. Personal
  records stand in as the achievement metric.

## iOS runtime bring-up (deferred app; first simulator launch 2026-06-06)

- [ ] **Background sync doesn't execute on an iOS device (BGAppRefreshTask vs `fetch`)** —
  `background_sync.dart`'s `Workmanager().registerPeriodicTask` maps to a
  `BGAppRefreshTaskRequest` on iOS, which requires the `fetch` `UIBackgroundMode`. The
  Info.plist only declares `processing` (a deliberate 2026-05-30 choice aimed at a
  `BGProcessingTask` the Dart side never actually schedules). `AppDelegate.swift` now
  registers the identifier with `BGTaskScheduler` so launch no longer crashes (was a
  `SIGABRT`), but on a real device the app-refresh submit is rejected (`BGTaskSchedulerError`,
  caught + logged) so background sync never runs in the background. Fix: either add `fetch`
  to `UIBackgroundModes` and keep app-refresh, or switch the Dart side to a `BGProcessingTask`
  (`Workmanager().registerProcessingTask`) registered via `WorkmanagerPlugin.registerBGProcessingTask`.
  Needs on-device testing. iOS-only — Android uses `WorkManager` and is unaffected. See
  `apps/mobile_ios/CLAUDE.md § Catch-up status`.
