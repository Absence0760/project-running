# apps/web — AI session notes

**The web app is the canonical feature surface for the whole product.** Every user-facing feature lives here unless it is physically impossible in a browser (live GPS recording, device sensors, haptics, OS share sheets — see the exceptions table in [../../docs/architecture/decisions.md § 24](../../docs/architecture/decisions.md)). Mobile (Flutter Android / iOS) and watch (Wear OS Kotlin / watchOS Swift) clients *mirror* this surface and *add* things only a device in hand or on the wrist can do.

**Working rule:** when you're asked to build a feature, build it here first. When you're asked to fix drift between web and mobile, close it by bringing web up to parity with mobile (not the reverse) unless the feature is a physical exception. See [../../docs/product/parity.md](../../docs/product/parity.md) for the live matrix — rows where this app is `✗` or `Partial` on a non-exception feature are the backlog.

**Multi-modal expansion (Phase 4, in progress):** the product expands from running-only to running + gym + nutrition inside one app per platform ([decisions.md § 63](../../docs/architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db)). On web that's `Gym` + `Nutrition` sidebar sections plus the unified `Home` and `History`. The web **gym** (`/gym`) and **nutrition** (`/nutrition`, `/nutrition/log`) surfaces have shipped; the cross-modality layer (lift→load, Coach context, History timeline) is live. **These are now ungated** (2026-06-04, §63 amendment): the Gym + Nutrition sidebar items are always present, and the `/dashboard` lift cards + `/history` chips/timeline self-hide purely on **data presence** — matching mobile. The `multi_modal_nav` flag is retired (dormant in `settings.md`, read by nothing — don't add new reads). New gym/nutrition UI should follow the same data-presence self-hiding pattern (no empty card / zeroed stat), not a flag. Don't ship nutrition ahead of the gym-engagement validation gate (decision D3). See [roadmap.md § Phase 4](../../docs/product/roadmap.md#phase-4--multi-modal-gym--nutrition) + [multi_modal.md](../../docs/features/multi_modal.md) for sequencing.

Deployed to AWS — S3 (static SvelteKit build) + CloudFront + Route 53 for everything except `/api/coach`, which deploys as a Node 24 Lambda Function URL routed by a separate CloudFront behaviour. Terraform-provisioned (modules + per-env stacks under `infra/`), runtime secrets via sops + AWS KMS, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the rationale and [deployment.md](deployment.md) for the full plan.

## Stack

- **Framework**: SvelteKit 2 with Svelte 5 (runes/next)
- **Language**: TypeScript
- **Package manager**: npm via the root workspace (`npm run <script> --workspace=apps/web`). The repo bootstrapped with pnpm originally and `apps/web/pnpm-lock.yaml` still exists; CI and the canonical build path are npm — see [decisions.md § 7](../../docs/architecture/decisions.md). Either works locally; just don't mix.
- **Adapter**: `@sveltejs/adapter-static` for the bulk; `/api/coach/+server.ts` is reused as the body of a hand-rolled Node 24 Lambda handler (no SvelteKit AWS adapter — see [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages))
- **Styling**: normalize.css + custom CSS in `src/app.css`
- **Icons**: unplugin-icons with `@iconify-json/material-symbols`
- **Markdown**: mdsvex

## Folder Structure

```
src/
  lib/
    components/     # Modal + SplitPane (primitives), Avatar (shared img-or-initial avatar; per-site size/font/bg props), RunMap, ElevationProfile (Android-style interactive chart), ImportRoute, RouteBuilder, CoachChat,
                    # ConfirmDialog, ToastContainer, ProGate, WorkoutEditor, RunTrackPreview, TrackPreview, PlanCalendar, CurrentWeekStrip (focused current-week 7-day planned-vs-completed ribbon on /plans/[id], above the month calendar; window anchored to start_date + currentWeek.week_index*7 so its done/active count matches the week card, re-ordered for display by the week_start pref), RouteExplorer,
                    # CalendarHeatmap, PersonalHeatmap (geographic heatmap of the user's own tracks on /runs/heatmap — distinct from RouteHeatmap's public community map), LicenseList, ClubEditor, EventEditor, PlanEditor (editable preview), PlanMetaEditor, RunEditor
                    # (modal-hosted creation forms), GymEditor (Phase 4 gym composer — modal-hosted, free-text exercise + inline sets, used by /gym + /gym/[id]), FoodLogEditor (Phase 4 nutrition composer — modal-hosted on /nutrition + page-hosted on /nutrition/log; OFF search → inline confirm-portion step + manual-macro fallback), PrivacyZonePicker (MapLibre map picker for owner zones, decisions §33),
                    # TrainingLoadChart (90-day fitness/fatigue/form trio on /dashboard, decisions §34),
                    # PeriodSummary (week/month/all-time stats + run list — used by dashboard modal AND /dashboard/period/...; the dashboard "This Week" + "All time"/Longest-run stat cards open it),
                    # ThisWeekStrip (dashboard current-calendar-week activity ribbon below the stat grid — 7 day cells of the REAL calendar week containing today, honouring week_start_day + the source filter; pure derivation in training/current_week.ts. Distinct from CurrentWeekStrip, which is plan-anchored on /plans/[id]),
                    # RunSocial (kudos + comments on a run — mounted on /share/run/[id], /runs/[id]; feed uses fetchEngagementSummaries chips instead),
                    # RunShareView (the public run share body — extracted so /share/run/[id] (standalone page) and the /feed modal can both render it without duplicating layout),
                    # RunPhotos (gallery for run_photos — mounted on /runs/[id] and /share/run/[id]; owner gates upload + delete; decisions §36),
                    # RoutePhotos (gallery for route_photos — same shape as RunPhotos, mounted on /routes/[id] and /share/route/[id]; owner gates upload/caption/delete; backlog C1),
                    # SegmentsPanel + RunSegmentEfforts (segment leaderboards on /routes/[id] + per-run effort chips on /runs/[id]; decisions §37),
                    # NotificationBell (compact bell icon next to the profile button in the sidebar footer — unread badge + popover for kudos/comments/follows; full inbox lives on /u/[me]?tab=notifications; decisions §38).
                    # NotificationsList (the inbox body — All / Unread tabs, per-row dismiss, bulk Mark-all-read; mounted under the Notifications tab on /u/[id] when isSelf).
                    # SocialFeed, SocialPeople, SocialClubs — the three tab panels of /social. SocialPeople is the only top-level surface for finding other runners (name search + suggested-from-clubs). decisions §54.
    stores/         # auth.svelte.ts (Supabase Auth store), toast.svelte.ts (toast notifications), notifications.svelte.ts (unread badge for the sidebar bell — decisions §38)
    # Loose lib modules are grouped into topical subfolders: core/ (data + supabase client),
    # training/ routes/ segments/ social/ integrations/ backup/ share/ settings/ runs/ format/ util/ billing/ gym/ nutrition/ gear/ (gear_wear.ts wear classification).
    # Only types.ts + database.types.ts stay at the lib root (gen:types writes database.types.ts there; the
    # twin parity-pair paths in docs/architecture/conventions.md + shared-library-syncer.md track the new locations).
    core/data.ts         # All Supabase queries (fetchRuns, searchPublicRoutes, etc.)
    core/schema.ts       # F11 string-literal registry: TABLES / BUCKETS / METADATA_KEYS. Route every `.from('runs')`, `.storage.from('runs')`, and runs.metadata key through these instead of bare strings — core/schema.test.ts derives its guard set from TABLES+BUCKETS and fails the build on any stray bare `.from('<registry name>')` tree-wide. The metadata-key registry of record stays docs/backend/metadata.md. SCOPE: activity-core (runs + gym_workouts/gym_sets/food_log/activities) PLUS the data.ts-only base tables (club_members, club_posts, event_attendees, event_results, route_reviews, run_kudos, run_comments, run_photos, run_gear, notifications, direct_messages, coach_athletes, integrations, segments, segment_efforts, gear, fitness_snapshots, personal_records, user_blocks) and the run-photos bucket are routed. STILL BARE (call sites spill into route pages / components owned by other surfaces — the remaining F11 tail): user_profiles, clubs, events, routes, saved_routes, training_plans, plan_weeks, plan_workouts, coach_messages, user_follows, user_settings, user_device_settings. The public_runs/public_routes/*_redacted/*_with_distance VIEWS stay bare by design (distinct DB objects, unaffected by a base-table rename). The coach metadata allowlist stays inline by design.
    types.ts        # Run, Route, Integration type overlays on generated DB types
    database.types.ts  # Generated Supabase types (regenerate after migrations)
    core/supabase.ts     # Supabase client init
    core/mock-data.ts    # Fallback data when Supabase is empty
    format/units.svelte.ts # Reactive km/mi + kg/lbs preference signals + unit-aware formatters (distance/pace/elevation; weight via the format/weight.ts pure layer)
    format/weight.ts       # Pure kg↔lbs conversion + formatWeightKg / parseWeightToKg for the `weight_unit` pref (storage stays canonical kg). Rune-free sibling of units.svelte.ts so it is tsx-testable (weight.test.ts); mirror the mobile Dart twin.
    format/time.ts         # Pure, locale/unit-independent time formatters (formatRelativeTime, formatDuration, formatDate, formatDateShort) — unit-tested in time.test.ts. NOT in mock-data.ts (which is fallback data only).
    i18n/                  # Web i18n runtime (decisions §108). store.svelte.ts = reactive locale signal + `m(key, params)` + initLocale (call once in +layout). locale.ts = pure negotiation (negotiateLocale / dirForLocale, unit-tested). messages.ts = `Messages = typeof en` type. locales/{en,de,fr,es,ja,pt-BR}.ts = catalogues (en static, rest lazy-imported). Add a user-facing string: add the key to en.ts + every locale (satisfies Messages enforces parity; messages_parity.test.ts guards it), then `{m('key')}` at the call site. Detection is CLIENT-SIDE (no Accept-Language SSR — the site is statically prerendered).
    routes/map-style.svelte.ts  # Reactive map-style preference signal (used by RunMap)
    settings/settings.ts     # `loadSettings()` + `effective<T>()` helpers over user_settings + user_device_settings. Now offline-first via settings_cache.ts (cache-first read, write-through, drain-on-refresh pending queue, sign-out drop). Mirrors mobile SettingsService — decisions §72 / §79.
    settings/settings_cache.ts  # `LocalStoragePrefsCache` + `InMemoryPrefsCache` (test seam) + pure `applyPrefsChanges`. User- + device-scoped keys (`settings_cache_universal_<userId>`, `..._device_<userId>_<deviceId>`, `..._pending_<userId>_<deviceId>`). 40-test contract in `settings_cache.test.ts`.
    settings/theme.ts        # light/dark/auto theme toggle, persisted in localStorage
    training/training.ts     # VDOT, Riegel, plan generator, week phasing, predictionConfidence (race-predictor data-quality grade)
    training/training.test.ts  # node:test suite for the training engine — `npx tsx --test`
    training/plan_adherence.ts  # pure weeklyDrift (>20% over/under plan) + missedWorkoutAdvice (make-up/skip a missed long run). Web-first; mounted on /plans/[id]. 11 unit tests.
    training/relink_candidates.ts  # pure filterRelinkCandidates — eligible runs to re-link a planned workout to (±7-day window, excludes runs already linked to another workout so plan_progress can't double-count, keeps the current run). Backs the Re-link picker on /plans/[id]/workouts/[wid]; fetchRelinkCandidateRuns in core/data.ts does the owner-scoped fetch. TS↔Dart parity pair (relink_candidates.dart). 9 unit tests.
    training/plan_progress.ts   # pure orderedPlanPhases (base→build→peak→taper marker) + longestCompletedLongRunMetres. Mounted on the /plans/[id] header. 8 unit tests.
    training/race_predictor.ts  # pure predictRaceLadder — multi-distance race-time predictor (5K/10K/Half/Marathon ladder, recency-weighted Riegel anchor, per-rung confidence via predictionConfidence). Reuses riegelPredict + predictionConfidence from training.ts. Backs RacePredictorCard on /dashboard. TS↔Dart parity pair (race_predictor.dart). 11 unit tests. Backlog #11.
    training/plan_serialize.ts  # pure planToMarkdown/planToJson + parsePlanMarkdown/parsePlanJson round-trip. Export menu on /plans/[id]; paste-import disclosure in PlanEditor (/plans/new). 12 unit tests.
    training/plan_bulk_ops.ts   # pure shiftIsoDate + recoveryWorkoutPatch/recoveryWeekVolume. Owner bulk ops on /plans/[id] (shift plan ±N days, mark week recovery). 9 unit tests. Duplicate-week is a separate atomic re-index RPC (duplicate_plan_week, migration 20261205_001 + duplicatePlanWeek in data.ts), not a pure helper — the (plan_id, week_index) unique constraint makes a client-side multi-update unsafe.
    integrations/strava-zip.ts   # Strava bulk-export ZIP importer (parses CSV + per-activity GPX/TCX)
    integrations/garmin-zip.ts   # Garmin bulk import (single .fit OR Account Data .zip; routes inner .gpx/.tcx via parseRouteFile)
    integrations/garmin-fit.ts   # Single FIT-buffer parser (lazy-loads fit-file-parser to keep the integrations bundle small)
    util/push.ts         # Web push subscribe / unsubscribe (registers /sw.js, persists to user_device_settings.prefs.push_subscription)
    util/smart_back.ts   # smartBack() — history-aware back control for detail/create pages reachable from >1 surface (afterNavigate latches an in-app referrer; handle() pops history.back() to it, else falls through to the anchor href). Replaces the copy-pasted afterNavigate+history.back idiom. See conventions.md § Web back links.
    util/exif_strip.ts   # Lossless JPEG marker-walk that drops the APP1 (EXIF/XMP, incl. GPS) segment before photo upload. TS twin of mobile exif_strip.dart; called inside addRunPhoto so a geotagged original never reaches the run-photos bucket ahead of the server worker's async strip.

    routes/privacy.ts      # PrivacyZone type + clipPointsToZones (pure JS, used for owner preview); server-side clipping for non-owner views goes through clip_track_for_user RPC. Decisions §33.
    coach/          # Transport-agnostic core for the /api/coach handler. handler.ts (entry), providers.ts (Anthropic + OpenAI streaming), context.ts (builds the runner profile + plan + recent-runs JSON dump), types.ts, system_prompt.ts. Wrapped twice — once by src/routes/api/coach/+server.ts (SvelteKit dev), once by apps/web/lambda/coach/src/index.ts (production AWS Lambda). Decisions §53.
    training/training_load.ts  # TRIMP / distance-proxy stress score + 90-day daily EWMA → fitness/fatigue/form trio. Pure functions, 10 unit tests. Mounted via TrainingLoadChart on /dashboard. Decisions §34.
    segments/segments.ts     # Pure compute for segment efforts — haversine cumulative distance + timestamp interpolation. 8 unit tests. Used by RunSegmentEfforts on /runs/[id] for client-side auto-effort generation. Decisions §37.
    segments/pace_segments.ts  # NRC-style pace heatmap helpers (`paceBucketForSpeed`, `ageBandFor`, `buildPaceSegments`, `hasTrackTimestamps`). TS port of `apps/mobile_android/lib/widgets/pace_segments.dart` — keep in lockstep. Mounted via the `activity` prop on `RunMap.svelte` (run-detail + share-run); routes never carry timestamps so they fall through to the legacy single line. 11 unit tests in `pace_segments.test.ts`.
    routes/track_projection.ts  # Pure projection helper for the SVG track-preview thumbnails (`projectTrack` with cos(midLat) longitude correction so a square loop renders square at any latitude). Mirrors the `projectTrack` helper in `apps/mobile_android/lib/widgets/track_preview.dart` — keep in lockstep. Used by `TrackPreview.svelte` and `RunTrackPreview.svelte`. 4 unit tests in `track_projection.test.ts`. See [decisions.md § 51](../../docs/architecture/decisions.md).
    routes/route_history.ts  # "Past efforts on this route" panel data (10 unit tests in route_history.test.ts). Mounted on /routes/[id] under the map.
    routes/distance_bands.ts  # Race-distance bands (5K/10K/Half/Marathon/Ultra) for the /routes/heatmap discovery browser — single source of truth for the windows mirrored generically by discoverable_routes_in_bbox (p_dist_min[]/p_dist_max[]). 9 unit tests in distance_bands.test.ts. Web-only (no Dart twin). Decisions §100.
  routes/
    +layout.svelte  # App shell with collapsible sidebar (state persisted in localStorage as `sidebar_collapsed`). Sidebar shape: Dashboard · History · Runs · Gym · Nutrition · Coach · Social. Routes and Plans are NOT standalone sidebar items — both live under the run surface as sub-tabs (Runs · Routes · Plans via RunSurfaceTabs.svelte); the /routes and /plans URLs still resolve.
    social/         # Top-level social hub. ARIA tab strip (Feed default, People, Clubs, Discover) with ?tab= URL state. Hosts SocialFeed + SocialPeople + SocialClubs + SocialDiscover. Discover = cross-club activity search over the search_public_events RPC (public clubs only; category/discipline/cadence/weekday/paid/time-of-day/proximity filters — proximity is "near me / near a place" by the CLUB's geocoded location, never the revoked event meet point; decisions §147).
    feed/           # Thin client-side redirect to `/social?tab=feed`. Kept alive for the sitemap entry, the bell-popover CTA, mobile push deep links, and any external links pinned to the old URL.
    u/[id]/         # Public user profile — display_name, avatar, follower/following counts, recent public runs, Follow toggle. Honours ?tab=runs|followers|following|notifications (notifications gated to isSelf — decisions §38). Identifier is auth.users.id (uuid); URL-safe handles deferred (decisions §31). The activity feed used to live here as a self-only tab; it's now under /social and any legacy ?tab=feed deep link bounces over.
    dashboard/      # Weekly mileage, PBs, calendar heatmap. "This Week" stat card opens PeriodSummary in a modal; the ThisWeekStrip ribbon under the stat grid shows the same week as a 7-day activity bar row (current_week.ts). Multi-modal (data-gated, no flag — §63 amendment): self-hiding Today's-lift + Recent-lifts cards + a self-hiding Today's-nutrition rings card (NutritionRingsCard.svelte — four macro rings vs targets, links to /nutrition; renders only when food was logged today, unfilled when body metrics absent per the Art 9 gate; reuses the /nutrition target + dynamic-TDEE math), and gym sessions folded into the fitness/fatigue/form curve via gym/lift_load.ts (decisions §63, multi_modal.md). The Fitness card discloses when recent lifts are in the fatigue and honours the `exclude_gym_from_readiness` pref (drops lifts from the readiness curve — display-side, run-only curve recoverable; decisions §134).
    dashboard/period/[type]/[date]/  # Standalone period summary — thin wrapper around PeriodSummary, kept for deep links
    history/        # The unified, cross-modal **timeline** (multi_modal.md § History; decisions §63 amendment). Pure read surface over the `activities` view (fetchActivities, windowed to 200) — NO run-list toolbar/filters/pagination/bulk-delete (those moved to /runs). All/Runs/Lifts/Meals kind chips appear once a second modality exists; every tab (incl. Runs) renders the SAME timeline-row shape (no run cards), so the top section is consistent across tabs. One header per tab: the All view shows a `Log` menu (Log run / Log workout / Log food); a single-modality tab (Runs / Lifts / Meals) shows a `View all` link to that modality's page (/runs, /gym, /nutrition) + the single Log action. Each Log opens the shared editor (RunEditor / GymEditor / FoodLogEditor) in an in-place modal and refreshes the feed on save — no navigation. nav glyph is `timeline`.
    runs/           # The dedicated **run-list / management** surface (decisions §63 amendment — un-redirected from the old /history→/runs F14/D3 rename so runs sit parallel to /gym + /nutrition). Full list: source / activity-type / date-range / sort filters, pagination, multi-select bulk-delete, Add-run modal (RunEditor), Heatmap link, localStorage filter persistence + back-nav snapshot. /history's Runs chip links here via "View all". Sidebar item `nav.runs` (glyph `directions_run`).
    runs/heatmap/   # Personal run-track heatmap — the user's OWN tracks (PersonalHeatmap.svelte + lib/run_heatmap.ts). Distinct from the public /routes/heatmap community map. Persona #53.
    runs/[id]/      # Run detail with map, elevation, splits. In-page back-link returns to /runs (history.back() when arrived from /runs or /history so the list snapshot restores).
    routes/         # Tabbed: My routes (saved) + Explore routes (community discovery via RouteExplorer). ?tab=explore deep-links the second tab. Routes now lives under the run surface — the page renders the shared RunSurfaceTabs (Runs · Routes · Plans) strip above its inner My-routes/Explore/Heatmap tablist, and is reached from the /runs Routes sub-tab. The /routes URL keeps resolving for bookmarks, club deep links, and shares.
    routes/new/     # Route builder (MapLibre + OSRM). Auto-routes per waypoint (no Calculate button); per-segment cache in routes/segment_cache.ts so each new pin fetches only its segment (decisions §136). Twin: routing.dart's RouteSegmentCache.
    routes/[id]/    # Route detail
    clubs/          # Thin client-side redirect to `/social?tab=clubs` (preserves `?tab=browse` as `clubs-sub=browse`). The /clubs/[slug] + /clubs/new + /clubs/[slug]/events/* + /clubs/join/[token] sub-routes are unchanged — only the top-level browse landing moved.
    clubs/new/      # Create a club (visibility + join policy)
    clubs/[slug]/   # Club home: feed (threaded) / events / routes / members tabs, pending-requests + invite-link panels for admins. Routes tab lists routes where club_id = this club; admins can create new (links to /routes/new?club=<id>) or transfer one of their personal routes in.
    clubs/[slug]/events/new/      # Admin: create event (one-off OR weekly/biweekly/monthly recurrence)
    clubs/[slug]/events/[id]/     # Event detail + per-instance RSVP + per-event updates
    clubs/join/[token]/           # Public invite-link landing (redeems via join_club_by_token RPC)
    coaching/                     # Coach-athlete roster hub (persona #46): mint/revoke invite links + athlete & coach lists
    coaching/athletes/[id]/       # Coach run-review surface: a linked athlete's recent runs (public+private, RLS §98) + active-plan compliance. fetchAthleteRuns / fetchAthletePlanOverview
    coaching/accept/[token]/      # Public coach-invite landing (redeems via redeem_coach_invite RPC)
    plans/          # Training plans list. Nested under the run surface — renders the shared RunSurfaceTabs (Runs · Routes · Plans) strip as its first child and is reached from the /runs Plans sub-tab (no standalone sidebar item; the /plans URL + its deep links — dashboard CTA, coach plan switcher, notifications, club templates — keep resolving).
    plans/new/      # Unified CREATE HUB for all three reusable-plan engines (decisions §146): a Training / Session / Gym-routine chooser swaps in PlanEditor / SessionPlanEditor / RoutineEditor. ?type= picks the initial branch, ?club= targets a club (one-step club-owned create on the session AND gym branches — session via a direct club-owned insert, gym via the admin-gated `publish_gym_routine_as_template` RPC which leaves a personal source routine; training stays build-then-publish). See [decisions.md §146](../../docs/architecture/decisions.md#146-the-three-reusable-plan-engines-share-one-create-front-door-plansnew-hub-but-not-one-form-or-one-club-create-path) + its 2026-06-14 amendment. Training branch = the editable week-by-week plan wizard (starter picker + club-template adopt + PlanEditor).
    plans/[id]/     # Plan detail: progress ring, today card, week grid + Edit-plan button (PlanMetaEditor) for owner-only meta edits (name, days/week, goal time, rules)
    plans/[id]/workouts/[wid]/   # Workout detail with structured-interval breakdown
    gym/            # Phase 4 multi-modal Gym (decisions §63; sidebar item always present since the §63 amendment). /gym = workout list + PR badges + create modal (GymEditor); /gym/[id] = detail with per-exercise PR chips + edit/delete + a per-exercise "vs last time" hint (previous weighted session's top set + a +/- delta on the heaviest set, via gym/exercise_history.ts#previousExerciseSession; links to that exercise's progression — the progressive-overload cue the all-time PR chips can't give); /gym/records = per-exercise current bests (est. 1RM / heaviest / top volume + last-performed date + session count), linked from the /gym header when any weighted set exists; the /gym header also surfaces a **Sessions** link to /sessions when the user has any session plan (session_planner.md — the only nav entry to the otherwise-orphaned /sessions list); each records card links to /gym/exercise?name=<name> = that exercise's progression over time (headline est.-1RM delta vs first session + a most-recent-first session list with top set / e1RM / volume / a strength-relative bar / a PR badge on new-e1RM sessions; each session links back to its workout). Data in core/data.ts; PR engine gym/gym_prs.ts (parity pair, still client-side for the per-workout temporal badges on /gym + /gym/[id]); records roll-up is now the **`gym_exercise_records` RPC** (server-side SQL aggregation — all-time bests can't be served by a windowed client read, so the aggregation lives in SQL mirroring how run PRs do; `fetchExerciseRecords` in core/data.ts, pinned by pgtap `gym_exercise_records_test.sql` against the gym_prs.test.ts fixture shape); progression roll-up gym/exercise_history.ts (pure, **web-only**, reuses the gym_prs primitives so the numbers can't drift from the badges; mobile mirror tracked in followups.md). e2e tests-e2e/gym/. Weight storage is canonical kg (gym_sets.weight_kg); display + entry honour the `weight_unit` ('kg'|'lbs') pref via format/weight.ts (pure, kg↔lbs) + the weightUnit signal in format/units.svelte.ts (Settings → Preferences toggle). Mobile twin owns the Dart side.
    nutrition/      # Phase 4 multi-modal Nutrition (decisions §63; sidebar item always present since the §63 amendment). /nutrition = Mifflin-St Jeor macro rings vs targets (hidden when body metrics absent), meal-slot daily view, water tracker (localStorage per day) with a bodyweight + exercise-aware daily **hydration goal** (~35 ml/kg, +480 ml/hr of logged exercise, flat 2 L fallback — same `X ml left` / `Goal reached` treatment as the calorie budget), 7-day calorie trend (with a `daily goal` reference line + a `X under/over goal/day` week-summary chip from `nutrition_week.ts`), plus the **Log food** action that opens the shared FoodLogEditor in an in-place modal (the canonical create-flow pattern, consistent with Log workout / Log run). `/nutrition/log` is the thin page wrapper around the same editor, kept for deep links. The editor = Open Food Facts search → inline confirm-portion step → log, manual macro entry fallback. The calorie goal is dynamic-TDEE "base + exercise" (decisions §134): today's runs + gym sessions add their estimated burn on top of the non-exercise base, shown as a `base + exercise` breakdown line. Data + body-metrics queries in core/data.ts (food_log + body_metrics). The rings also show the **calorie budget** — a `X kcal left` / `X kcal over` / `On target` headline chip plus a ceiling-aware over-budget ring state: calories + fat recolour to danger when exceeded, protein + carbs show a target-reached tick instead (overshooting a goal macro is a win, not a warning). Pure libs in lib/nutrition/: nutrition_targets.ts (BMR + base+exercise, parity pair), exercise_calories.ts (run/gym kcal estimator, parity pair), food_search.ts (Open Food Facts, injectable fetcher), nutrition_totals.ts (day aggregation), nutrition_budget.ts (per-macro remaining + `MACRO_IS_CEILING` over/reached logic — **web-only**, mobile mirror tracked in followups.md), hydration.ts (daily water target from bodyweight + exercise minutes + remaining/reached budget — **web-only**, mobile mirror tracked in followups.md), nutrition_week.ts (logged-day average + signed delta vs the daily calorie goal — **web-only**, mobile mirror tracked in followups.md). Body metrics (height on user_profiles + body_metrics weight series, migration 20261216_001) + activity/goal prefs entered in Settings → Preferences under the Art 9 health-consent gate. e2e tests-e2e/nutrition/. Mobile twin owns the Dart side.
    coach/          # Standalone Coach chat — plan switcher (?plan=<id>), configurable runs window (10/20/50/100), grounded-in context strip
    api/coach/+server.ts         # Coach endpoint. Default provider: Claude (ANTHROPIC_API_KEY). Set COACH_PROVIDER=openai + OPENAI_BASE_URL for local Ollama.
    explore/        # Thin redirect to /routes?tab=explore (kept so old links / Android deep links still resolve)
    settings/       # Tabbed layout: account, preferences, integrations, devices, upgrade (donate)
    share/run/[id]/ # Public run share page (no auth required)
    share/route/[id]/ # Public route share page (no auth required)
    learn/          # Public, no-auth, PRERENDERED Learn/guides surface (decisions §161, features/learn.md). /learn hub + /learn/[slug] articles (mdsvex .md bodies) + /learn/category/[category]. All prerender=true (+ entries()); SEO mirrors share/route (canonical / OG / Article+BreadcrumbList JSON-LD via lib/learn/learn_meta.ts). Shell-less + anon in +layout.svelte (path.startsWith('/learn')). Content authored in lib/learn/guides/*.md, indexed by import.meta.glob in lib/learn/guides.ts. Web-only (no twin).
    share/badge/[id]/ # Public achievement-badge share page (no auth). Mirrors share/run: +page.ts SSR via lib/share/share_badge_lookup (public-row-safe columns only, is_public=true), og/badge/[id].png renders the card via lib/share/og_badge_png; the lambda/share-badge/ handler owns it in prod. Badge catalogue + thresholds live in lib/social/badges.ts (the TS source of truth the SQL award fn duplicates). See features/achievements.md + decisions §164.
    live/[id]/      # Live spectator tracking. Real Go live-hub WebSocket path via lib/runs/live_hub.ts when PUBLIC_LIVE_HUB_URL is set; Supabase Realtime channel as fallback when unset; the demo animation is only the no-signal filler. WS path e2e-tested by tests-e2e/live/spectator_websocket.spec.ts (dedicated playwright.livehub.config.ts — boots the real hub binary).
    login/          # Email/password + OAuth sign-in
    auth/callback/  # OAuth redirect handler
  app.css           # Global styles + CSS variables
  app.d.ts          # App-level TypeScript declarations
lambda/
  coach/            # AWS Lambda Function URL handler for /api/coach in production.
                    # src/index.ts wraps $lib/coach/handler with awslambda.streamifyResponse +
                    # HttpResponseStream so SSE streams pass through CloudFront. build.mjs
                    # bundles via esbuild → dist/coach.zip (Anthropic SDK + supabase-js
                    # inlined, ~537 KB). CI's release-web.yml updates the Lambda code on every
                    # web@* tag. See decisions.md §53.
  share-run/        # AWS Lambda Function URL handler for /share/run/* + /og/run/*.png in
                    # production — per-request SSR so a brand-new public run unfurls with the
                    # right per-run <head> + a rendered og:image (generic branded card at 200
                    # for private/deleted ids). build.mjs embeds apps/web/build/index.html as
                    # the SPA shell + copies the arm64 @resvg native binary into the zip. The
                    # matching SvelteKit page + og endpoint carry prerender=false (dev server
                    # owns the path locally). See lambda/share-run/README.md.
  share-route/      # Same shape as share-run for /share/route/* + /og/route/*.png (Web SEO
                    # parity). Reuses buildRouteShareCanonical / buildRouteJsonLd /
                    # buildRouteOgSvg via share_route_lookup / share_route_meta /
                    # share_route_spa_shell / og_route_png. Track is privacy-clipped via
                    # clip_track_for_user. See lambda/share-route/README.md.
  share-recap/      # Same shape as share-run for /recap/share/* + /og/recap/*.png — the
                    # public Year-in-Running "Wrapped" share. Renders the FROZEN
                    # public_recaps snapshot (aggregate-only, no track) via
                    # share_recap_lookup / share_recap_meta / share_recap_spa_shell /
                    # og_recap_png (buildRecapOgSvg, 1200x630). Opt-in + revocable; 200
                    # branded fallback on a missing/revoked recap. The SvelteKit
                    # /recap/share/[id] + /og/recap/[id].png routes (prerender=false) own
                    # the path in dev. infra/ CloudFront+OIDC+release wiring landed
                    # (mirrors share-run/share-route); only terraform apply + first deploy
                    # remain. See lambda/share-recap/README.md.
  share-badge/      # Same shape as share-run for /share/badge/* + /og/badge/*.png — the
                    # public per-badge achievement share. Renders the public,
                    # milestone-safe badge columns (numeric milestone + date, no
                    # track/location) via the share_badge_lookup / og_badge_png path;
                    # 404 HTML but 200 branded-card PNG on a missing/private badge. The
                    # SvelteKit /share/badge/[id] + /og/badge/[id].png routes
                    # (prerender=false) own the path in dev. infra/ CloudFront+OIDC+release
                    # wiring landed (mirrors share-run/share-route/share-recap); only
                    # terraform apply + first deploy remain. See lambda/share-badge/README.md.
```

## Development

```bash
# From the repo root (matches CI):
npm install                              # workspace bootstrap
npm run dev --workspace=apps/web         # Dev server on :7777
npm run build --workspace=apps/web       # Production build
npm run preview --workspace=apps/web     # Preview build on :8888
npm run check --workspace=apps/web       # Type-check
```

(`pnpm i / pnpm dev` from inside `apps/web/` still work locally because of the historical `pnpm-lock.yaml`, but CI runs the npm path.)

## Conventions

- Use Svelte 5 runes syntax (`$state`, `$derived`, `$effect`, `$props`) — not the legacy options API
- TypeScript throughout; `lang="ts"` on all `<script>` blocks
- `@sveltejs/adapter-static` is the only SvelteKit adapter (output dir: `build/`); the coach endpoint is a separate Lambda artifact built from `src/routes/api/coach/+server.ts`
- `BASE_PATH` is empty in production (CloudFront serves at the root). It's only set on a non-root Pages-style mirror, which we no longer use.
- Buttons: don't define `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-outline`, `.btn-danger`, or `.btn-sm` locally — they live in `app.css` globally. Page-specific variants (`.btn-google`, `.btn-save`, etc.) extend the base. See [conventions § Web buttons](../../docs/architecture/conventions.md#web-buttons).
- Modals: don't define `.modal-backdrop`, `.modal`, `.modal-header`, `.modal-close`, `.modal-body`, `.modal-wide`, or `.modal-narrow` locally — they live in `app.css` globally. Every create / edit dialog (clubs, plans, runs, events, goals, device overrides, workout editor, import route, ConfirmDialog) uses the same shape. See [conventions § Web modals](../../docs/architecture/conventions.md#web-modals).
- Cards: for an **elevated** panel (resting shadow + hover lift — the dashboard / nutrition / history-timeline style) use the global `.card-elevated` from `app.css`; don't re-declare a local copy. **Flat** panels (settings / plans / coaching / …) keep their own page-scoped shadowless `.card` — there is deliberately no global `.card`, and you must never add a `box-shadow` to a bare global `.card` name (it would cascade into ~17 flat pages). See [conventions § Web cards](../../docs/architecture/conventions.md#web-cards--card-elevated-is-the-shared-elevated-panel).
- Forms: don't re-declare field chrome (input / textarea / select / label / fieldset / focus ring / radio row / actions / error) in an editor — add `class="editor-form"` to the form root and let the shared `app.css` layer style them; keep only bespoke layout (grids, chips, set tables) scoped. The bordered checkbox option-card is `.toggle-row`. Native checkbox/radio colour comes from the global `accent-color` rule. Mind the Svelte-scoping gotcha (a scoped `label`/`input` rule out-specifies the global layer — delete local copies on migration; prefix inline-label overrides with `.editor-form`). See [conventions § Web forms](../../docs/architecture/conventions.md#web-forms--editor-form-is-the-shared-field-layer).
- Page width: list / detail pages **uncapped** (fill the screen), settings tabs cap at `64rem`, focused single-form pages at `40–48rem`. Padding is `var(--space-xl) var(--space-2xl)`, left-aligned (no `margin: 0 auto`). See [conventions § Web page padding](../../docs/architecture/conventions.md#web-page-padding).
- **`<input type="number" bind:value>` yields a `number`, not a string.** Svelte coerces a numeric input's `bind:value` to `number | null`, even when the bound field is declared `string`. Feeding that straight into a string parser blows up — this is the bug that made *every* weighted gym workout silently fail to save (`parseWeightToKg`'s `.trim()` threw `"raw.trim is not a function"`, uncaught, before the try/catch). When a numeric `<input>` value flows into a string-typed helper, coerce at the boundary (the web `parseWeight` wrapper now does `typeof raw === 'number' ? String(raw) : raw`), or use `inputmode="numeric|decimal"` on a `type="text"` input to keep it a string. `parseFloat`-style parsers tolerate the number; `.trim()`/`.replace()` parsers do not.
- **Pure logic in `.svelte.ts` files can't be unit-tested with raw tsx.** Files with `$state` / `$derived` / `$effect` need the Svelte 5 compiler in the loop; `npx tsx --test src/lib/foo.svelte.test.ts` instantly errors with `ReferenceError: $state is not defined`. If you want unit tests for pure logic that currently lives in a `.svelte.ts` file, **extract the pure parts to a sibling `.ts` file (no runes)** — that's what `route_history.ts` / `pace_segments.ts` / `track_projection.ts` already do next to their `.svelte` callers. Reactive state / signal initialisation stays in the `.svelte.ts` shell. The pure `.ts` sibling becomes node:test-runnable via `npx tsx --test` (see `apps/web/src/lib/*.test.ts`). The fallback is Playwright e2e, but unit-testing the pure layer is much cheaper. **Do not leave half-finished `.svelte.test.ts` files behind** — if the runes-in-tsx attempt fails, either extract the pure logic or skip the unit test and rely on e2e.

## Create-flow modal pattern

Every create surface (`/clubs`, `/plans`, `/runs`, `/history`, `/clubs/[slug]`, `/gym`, `/nutrition`) opens a modal hosting a reusable editor component (`ClubEditor`, `PlanEditor`, `RunEditor`, `EventEditor`, `GymEditor`, `FoodLogEditor`). `/history`'s Log menu hosts all three of RunEditor / GymEditor / FoodLogEditor; `/runs` hosts the RunEditor Add-run modal. Each editor takes an `oncreated` (and where applicable `oncancel`) callback; the host decides whether to close + refresh or navigate to the new entity.

The standalone `/new`-style routes (`/clubs/new`, `/plans/new`, `/runs/new`, `/clubs/[slug]/events/new`, `/nutrition/log`) are kept as **thin page wrappers** around the same editor components so deep links and browser back work unchanged. When you add a new editor, follow this same shape — never duplicate the form between the modal and the standalone route.

The modal shell uses the canonical `.modal-backdrop` / `.modal` / `.modal-header` / `.modal-close` / `.modal-body` classes from `app.css`. Pages and components must not redefine those locally — only field-level layout (e.g. a `.goal-editor-body { display: grid }` for a specific dialog's contents). See [conventions § Web modals](../../docs/architecture/conventions.md#web-modals).
## Deployment

Production plan + cost / observability / rollback: [deployment.md](deployment.md). Hosted on **AWS** (S3 + CloudFront + Lambda + Route 53), Terraform-provisioned (`infra/`), sops + AWS KMS for runtime secrets, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the choice rationale.

Tag `web@*` triggers `.github/workflows/release-web.yml` which: builds the static site → uploads to the prod S3 bucket → updates the coach Lambda → invalidates CloudFront. Push to `main` deploys to the `preview.threkir.com` environment.

## Pull Request Guidelines

- Target branch: `main`
- Keep PRs focused; one feature or fix per PR
- Draft PRs are fine for work-in-progress
