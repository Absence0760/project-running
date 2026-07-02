# Multi-modal layout & IA (Phase 4 — run + gym + nutrition)

> **Goal / north star.** The product is a **personal multi-modal training app whose differentiator is cross-modal intelligence** — a Coach that reasons across one athlete's runs, lifts, and nutrition. That, not a co-located stack of cards, is the wedge no incumbent owns ([the thesis](#the-thesis-cross-modality-intelligence-is-the-product-not-the-card-layout)). Every IA decision in this doc exists to make that intelligence *reachable and trusted* — the Train hub gives each modality a home so its data flows into the one load/recovery curve and the Coach's context; the pinned `Ask your coach` entry keeps the intelligence one tap from the default surface; the self-hiding rule protects the pure runner so depth never becomes clutter. Adjacent surfaces (the [community / paid-events layer](club_events.md)) are **additive retention features in service of this goal, not a second product.** When a layout choice trades against making the cross-modal intelligence the centre of the app, the intelligence wins.

Design spec for the navigation, Home, and History surfaces once the app
spans running + gym + nutrition. The data foundation (migration
`20261204_001`, `gym_workouts` / `gym_sets` / `food_log` / `activities`
view) is shipped; this doc is the **layout contract** the
screens get built against. Architecture rationale: [decisions.md § 63](../architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db). Sequencing: [roadmap.md § Phase 4](../product/roadmap.md#phase-4--multi-modal-gym--nutrition).

> **Status:** largely shipped on web + mobile. **Gating amendment (2026-06-04,
> [decisions §63](../architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db)):** the original plan gated the web surfaces behind a
> `multi_modal_nav` per-user flag (default off); web has since been **ungated
> to match mobile** — Gym/Nutrition are always-reachable and the dashboard
> cards + history chips self-hide purely on **data presence**. The flag is
> retired (dormant, read by nothing). Mobile never had the flag. **Wherever a
> status note below still says "behind `multi_modal_nav`" / "flag-off", read
> it as "data-gated" — the flag no longer gates anything.** **Sequencing
> (hardened):** finish the Phase 3 training moat → ship **gym** → validate
> engagement → ship **nutrition (food-DB-backed)** → promote the
> cross-modality intelligence as each module lands. See *Sequencing,
> validation gates & risk controls* below. Data foundation (migration
> `20261204_001` + api_client methods) is shipped.

## The governing principle: a runner who never logs a meal sees today's app

The single biggest risk in going multi-modal is turning a focused
running app into a cluttered everything-app. Every layout decision below
serves one rule:

> **Cards, tabs, and rows self-hide when their modality has no data.** A
> pure runner sees a Home and History that look almost exactly like
> today's. The gym and nutrition surfaces only *appear* once the user
> opts in by logging something.

Two corollaries:

- **Progressive disclosure, not feature parity on screen.** The lightweight
  tier is forms. We never show an empty gym chart or a zeroed nutrition
  ring to someone who doesn't lift or log food.
- **One primary action per screen.** Home answers "what's my day?",
  History answers "what have I done?", Log answers "record something."
  None of them tries to do all three.

## The thesis: cross-modality *intelligence* is the product, not the card layout

Co-locating a run card, a lift card, and a nutrition card on one Home is
**not** a differentiator — it's MyFitnessPal-with-running, and three
silos in one app is worse than three good apps. The wedge no incumbent
owns is the *reasoning across* the three: lifts feeding the same
load/recovery curve a runner already trusts, and a Coach that can say
"you maxed squats and ate 1,400 kcal — move tomorrow's tempo." That
intelligence is the headline; the modules exist to feed it.

Concretely, **the cross-modality layer is built and marketed first-class,
not as polish after the modules.** If we ship gym + nutrition as two more
silos and bolt the intelligence on later, we've built the wrong product.

## Integration model — *inform* (tier 1) vs *command* (tier 2)

The modalities affect each other in two deliberately-separated depths.
The split exists because of **data trust**: lift load is something you
logged (trustworthy); a half-logged food diary is not, and silently
re-writing a training plan from noisy nutrition data is how you give
harmful advice.

**Tier 1 — inform (ships with Phase 4).** Passive, trustworthy, no
auto-mutation of anyone's plan:
- **Lift → recovery/load:** gym sessions feed the *same* CTL/ATL/TSB
  curve as runs (see the lift-load spec below), so a heavy session raises
  fatigue and the recovery advisor + `daysUntilNextHardSession` already
  reflect it. **Run-load and lift-load stay separable** (a `source` tag on
  each daily-stress contribution) so a lift-load modelling bug can never
  silently corrupt the run-only readiness a runner relies on.
- **Run → nutrition targets:** the BMR × activity-level target is
  activity-aware (a high-mileage week nudges the target up), but it does
  not do per-run "you burned X, eat Y."
- **Coach context (shipped):** the Coach *sees* recent lifts + 7-day
  nutrition averages and reasons about them in its answers (advisory — you
  decide). `coach/context.ts` projects a bounded `recent_lifts` array
  (capped per-session summaries) + a `nutrition_7d` daily-average rollup;
  nutrition is gated on the same Art 9 health-consent as DOB/HR, lifts are
  ungated activity data, and both self-hide when nothing is logged.
- **Unified Home / History (web shipped) / social feed.**

**Tier 2 — command (deferred depth tier, explicitly gated on data
trust).** Active auto-adjustment:
- Recommendation engine ("under-fuelling for tomorrow's long run", "skip
  the lift, CTL too high").
- Plan re-planning that factors fuelling + lift load (hooks into the
  missed-session re-planning engine, roadmap Phase 3).
- Coach *writing* meal plans / lift programs.
- Unified Whoop-style recovery score (run + lift + sleep + nutrition).

Tier 2 stays off until logging is reliable (food DB, see below) — never
auto-mutate a plan from data the user can't be bothered to log
accurately.

## How the three modalities work together — separation at storage, integration at compute

The data model deliberately keeps three separate tables (`runs`,
`gym_workouts`/`gym_sets`, `food_log`) with **no foreign keys between activity
rows** — a run never points at a lift, a meal never points at a run. That
separation of concerns is not a barrier to cross-modality intelligence; the
integration happens at a *higher* layer. The mechanism is a shared spine plus
a shared derived layer, not row-to-row links.

```
  LAYER 4  SURFACE          Home cards . Log-sheet suggestions . Coach answers
                            "2x hamstring + glute today, keep it light"
                                          ^
  LAYER 3  REASONING        Coach (LLM, advisory)  +  pure recommender helpers
           "given runs ->   reads Layer 2 signals + recent raw history
            recommend lift"          ^
  ------------------------------- data-trust gate (Tier 1 inform / Tier 2 command)
  LAYER 2  DERIVED SIGNALS  ONE fitness/fatigue/form curve  +  energy/macro balance
           (the merge point)  run stress  +  lift stress  (source-tagged)
                              nutrition adequacy
                                          ^
  LAYER 1  CORRELATION      every table carries (user_id, started_at)
           SPINE            cross-modality query = "this user's time window"
                            the `activities` view is the read-time expression
                                          ^
  LAYER 0  STORAGE          runs        gym_workouts/gym_sets       food_log
           (separation)     |---- no FKs between activity rows ----|
                            each table owns its own shape + constraints
```

- **Layer 0–1 — how they coexist while staying separate.** Every activity
  table carries `(user_id, started_at)`. To ask "what did this user do around
  Saturday's long run," you query a *time window* across the three tables (or
  the `activities` view) — correlation by user + time, **not** referential
  integrity. Separation of concerns therefore costs nothing in the ability to
  reason across modalities. (`food_log` standardises on `started_at` too — see
  the timestamp-naming cleanup in `reviews/audit-db-optimization.md` F8/F17.)
- **Layer 2 — where they actually merge.** This already exists for two of the
  three: `training_load.ts` ↔ `.dart` reduces a run *and* a lift to a daily
  training-stress contribution tagged with `source: 'run' | 'lift'`, summed
  into **one** CTL/ATL/TSB curve (see the Lift training-load spec below).
  Nutrition reduces to daily energy/macro adequacy. After Layer 2 the data is
  no longer "runs vs lifts" — it is modality-agnostic signals: *fatigue,
  readiness, fuelling adequacy.* The `source` tag is what keeps run-only
  readiness recoverable even if the lift contribution has a bug.
- **Layer 3 — reasoning reads the merged signals.** The Coach context
  (`coach/context.ts`, shipped) already pulls recent lifts + a 7-day nutrition
  rollup alongside the run window. Deterministic recommenders are pure,
  parity-paired helpers in the same family as `training.ts` / `gym_prs.ts`.

### Worked example: "recommend exercises given previous runs"

This is a **Layer-3, Tier-2 (command)** feature — active prescription, so it is
gated on the data-trust rule above and ships *after* the Tier-1 inform layer.
The chain reads the shared signals; it does not need the tables merged or
denormalised:

```
  runs (last 7-14d) ──┐
   - volume, load     ├─► run-derived state:
   - descent/eccentric│     high mileage, posterior-chain under-trained,
   - which systems    │     eccentric load from descents, fatigue=high
                      │
  gym_workouts ───────┤─► lift-derived state:
   - what's trained   │     last leg day 6d ago, no hamstring work,
   - recovery, PRs    │     squat PR stale
                      │
  unified curve ──────┤─► readiness: low (banked fatigue from the long run)
  (Layer 2)           │
  food_log (opt) ─────┘─► fuelling: adequate / under
                                          │
                                          ▼
                    exercise_recommender.ts  <->  .dart   (pure, parity-paired,
                                          │         unit-tested like training.ts)
                                          ▼
        ranked suggestions + rationale:
        "50km this week, no posterior-chain work, high fatigue ->
         2x light hamstring + glute accessory, skip heavy squats today"
```

Architecturally the recommender is a **pure helper module** — structured
inputs (the Layer-2 signals + bounded recent history) in, ranked suggestions +
a plain-language rationale out. No DB coupling, fully testable, a TS↔Dart
parity pair. It is surfaced as **advisory** (a Home "recommended" card or a
Log-sheet suggestion); per the Tier-2 gate it never auto-writes a plan, and it
stays off behind `multi_modal_nav` + the food-DB trust gate until logging is
reliable. The same shape generalises to the other Tier-2 ideas
(under-fuelling warnings, "skip the lift, CTL too high") — all of them read
Layer 2, none of them needs a foreign key between activity rows.

## Bottom nav — `Home · History · Log · Social · Settings`

> **SUPERSEDED (shipped 2026-06-11).** This `Home · History · Log · Social ·
> Settings` nav was replaced by the **Fitness-hub redesign** specced below
> ([§ redesign](#proposed-redesign-pending-sign-off--the-train-hub--routes-relocation)):
> bottom nav is now `Home · Fitness · [+]Log · Social · You`, the `History`
> tab is absorbed into Fitness→All, Settings folds into `You`, and Routes
> moved out of Social onto the run surface. The section just below documents
> the *historical* nav; read the redesign section for what ships today.

The `Run` tab disappears as a top-level destination. The centre slot
becomes an **action button**, not a tab.

```
┌───────────────────────────────────────────────┐
│                                                 │
│                  (screen body)                  │
│                                                 │
├───────────────────────────────────────────────┤
│   ⌂        ≡        ╔═══╗        ◎        ⚙     │
│  Home   History    ║ + ║      Social   Settings │
│                    ╚═══╝                         │
└───────────────────────────────────────────────┘
            the raised centre "+" is Log
```

- **Why `Log` is an action, not a tab:** the 5-slot ceiling is real
  (Routes was already folded into Social, §61). A `Run` tab + `Gym` tab +
  `Nutrition` tab is 7 slots. Collapsing the three *capture* entry points
  into one action button keeps the nav at five and groups them by the
  verb the user actually has in mind ("I want to log something").
- **Tap `Log` →** a modality picker (on mobile the centre nav FAB fans these as a **speed-dial of icon-only buttons in a shallow arc around the button** — one top-centre, one down-left, one down-right — `widgets/log_speed_dial.dart`; the History Log FAB keeps a bottom sheet):

```
        ┌─────────────────────────────────┐
        │            Log                  ✕ │
        ├─────────────────────────────────┤
        │  ▷  Log run                       │
        │  ☰  Log lift                      │
        │  🍴 Log food                      │
        └─────────────────────────────────┘
              ↑ last-used floats to top
```

- **Picking a modality navigates to its dwell-in capture page**, not a
  one-shot modal. All three behave the same way: `Log run` → the recorder
  page, `Log lift` → the Gym page, `Log food` → the Nutrition page — each an
  in-shell keep-alive `PageView` page (bottom nav stays visible) you operate
  in for as long as the session lasts (record the run, build a workout over
  several sets, log the day's meals), with that page's own composer one tap
  away. The keep-alive guarantee means an in-progress recording, a half-built
  workout, or the day's food log survives swiping to Home and back. (A run is
  *necessarily* a page — a foreground-service GPS session can't collapse into
  a modal — so Gym + Nutrition match it rather than the reverse.)
- **Long-press `Log` = repeat last activity.** Preserves the one-tap
  "start a run" muscle memory the current `Run` tab gives. A runner who
  only ever runs effectively still has a one-gesture start.
- The sheet's **order adapts**: the most recently used capture type
  floats to the top, so a daily lifter sees "Log lift" first.
- **Accessibility:** the `Log` button has an explicit `Semantics` label
  ("Log an activity"); the sheet items are a single focus group; the
  raised button keeps a ≥48 dp touch target.

## Home — a prioritised, self-hiding card stack

> **Status (web — shipped):** `/dashboard` renders a Today's-lift
> card (when a session was logged today), a Recent-lifts trend card, a
> first-run "log a lift" footer affordance, and a **Today's-nutrition rings
> card** (`NutritionRingsCard.svelte`, when food was logged today) — all gated
> on **data presence** (no flag, §63 amendment), each modality coded by its
> glyph + label + a distinct accent (never colour alone). A pure runner sees
> no new card. The nutrition card reuses the `/nutrition`
> `computeNutritionTargets` + dynamic-TDEE `exerciseCaloriesForDay` math, so
> the four macro rings (kcal / protein / carbs / fat vs targets) agree across
> both surfaces; targets stay null when body metrics are absent (the Art 9
> health-consent gate `/nutrition` already sits behind) and the rings then
> render unfilled rather than zeroed. e2e
> `tests-e2e/dashboard/nutrition-rings.spec.ts`.
>
> **Status (mobile — shipped, G5):** `dashboard_screen.dart` composes a
> self-hiding today's-lift card (`widgets/gym_summary_card.dart`) + today's
> nutrition rings card (`widgets/nutrition_rings_card.dart`) after the
> today's-workout card, each omitted when that modality has no data today,
> 2-up on phones ≥360 dp (else stacked). The dashboard best-effort hydrates
> the gym + food caches + the nutrition target on mount so the cards surface
> on a fresh launch. A **recent-lifts trend card** (`widgets/recent_lifts_card.dart`,
> the five most-recent sessions, each tapping into gym detail) sits below the
> training-load chart, self-hiding when the gym store is empty — mirroring web
> `/dashboard`'s recent-lifts card.

Home is a vertical scroll of cards. The order is **driven by what the
user logs**, not a fixed grid. The ordering algorithm:

1. **Today's actionable card first** — if a training plan has a workout
   scheduled today, the today's-workout card leads (as it does now).
2. **Today's logged modalities next**, most-recently-touched first
   (today's run summary, today's lift summary, today's nutrition rings).
3. **Trend cards** the user has data for (training load, fitness,
   mileage, intensity, weekly goal).
4. Everything with **no data is omitted entirely** — not greyed out, not
   a "start logging" placeholder taking a full card. Empty modalities get
   at most a single slim "＋ Log your first meal" affordance at the very
   bottom, below the fold.

```
  Home                                    (today)
  ┌─────────────────────────────────────────────┐
  │  TODAY · Tempo workout            ▷ Start    │   ← plan card (if any)
  │  6 km · 4:45/km · band tolerance ±8s         │
  └─────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────┐
  │  Today's run            08:14 · 8.2 km       │   ← only if logged today
  │  ▁▂▃▅▆ pace · 42:10                           │
  └─────────────────────────────────────────────┘
  ┌──────────────────────┐ ┌──────────────────────┐
  │ Nutrition       1,840 │ │ Today's lift          │  ← 2-up when both
  │  ◯ kcal  ◯ P  ◯ C  ◯ F│ │ Push day · 5 exercises│     present & compact
  │  72% of 2,550         │ │ 12,400 kg volume      │
  └──────────────────────┘ └──────────────────────┘
  ┌─────────────────────────────────────────────┐
  │  Fitness · Fatigue · Form          (90 days) │   ← existing trend card
  │  ╱╲___╱▔▔                                     │
  └─────────────────────────────────────────────┘
        … mileage / intensity / weekly goal …
```

Density rules so it never becomes a wall of cards:

- **Compact-pair layout:** when two *summary* cards (nutrition rings +
  lift summary) are both present and short, they render 2-up on phones
  ≥360 dp wide; everything else is full-width.
- **One trend card expanded at a time** is the eventual target; v1 ships
  them stacked but each is collapsible to a single-line headline.
- **Section rhythm:** "Today" cards, then a thin divider, then "Trends."
  No section headers shouting in caps — a hairline rule and generous
  whitespace separate them.
- Nutrition is the only **always-live ring widget**; gym and run are
  event summaries (they show what happened, they don't animate).

## History — one timeline, filter chips, separate detail routes

History becomes a single reverse-chronological timeline backed by the
`activities` view (one query, projecting `(id, user_id, kind, started_at,
summary, is_public)`), with filter chips at the top. The view is the
documented cross-modality contract — its column set and the windowed-read +
redaction-boundary guarantees are pinned by
`apps/backend/supabase/tests/activities_view_windowed_test.sql`.

> **Status (web shipped):** `/history` is the unified, cross-modal **timeline**
> — a pure read view over `fetchActivities`. The full run-list management
> surface (filters / pagination / bulk-delete / Add run / Heatmap) lives at its
> own **`/runs`** page (un-redirected from the old F14/D3 `/runs`→`/history`
> rename, §63 amendment) so runs sit parallel to `/gym` + `/nutrition`; the
> sidebar gains a `Runs` item between History and Gym. All/Runs/Lifts/Meals
> chips appear once a second modality has data (data-gated, no flag; empty-kind
> chips hidden); **every tab — including Runs — renders the same timeline-row
> shape** (run rows look like lift/meal rows), so the top section is consistent
> across tabs. Rows link to their own detail route (`/runs/[id]`, `/gym/[id]`);
> meal rows in the timeline stay read-only — the per-meal detail surface is the
> dedicated `/nutrition/[date]/[slot]` route reached from the nutrition day view
> (shipped 2026-06-12; mobile `nutrition_meal_detail_screen.dart`). **One header
> per tab** mirrors the /gym + /nutrition headers: the **All** view shows a
> `Log` menu (Log run / Log workout / Log food); a single-modality tab
> (**Runs** / **Lifts** / **Meals**) shows a `View all` link to that modality's
> page (`/runs`, `/gym`, `/nutrition`) plus the single matching Log action.
> Each Log opens the shared editor in an in-place modal (`RunEditor` /
> `GymEditor` / `FoodLogEditor`) and refreshes the feed on save — no
> navigation. A pure runner (no second modality) sees a chip-less run timeline
> and reaches the full list via the sidebar `Runs` item.
>
> **Status (mobile shipped):** `runs_screen.dart` (the History tab) gains the
> same All/Runs/Lifts/Meals chips + a day-grouped unified timeline
> (`widgets/activity_timeline_list.dart` over the pure `activity_timeline.dart`
> grouper). The timeline is assembled from the **local stores** by
> `lib/local_activities.dart` (`buildLocalActivities` over `LocalRunStore` +
> `LocalGymStore` + `LocalFoodStore`) — offline-first, always all modalities,
> and live (a run/lift/meal logged from the Log FAB shows at once); History
> hydrates the gym + food stores itself on mount. Chips appear once the gym
> store is wired in (multi-modal home shell) AND a second modality has data —
> empty-kind chips hidden; a gym-/meal-only user still sees their timeline
> rather than a "no runs" dead-end. **Every chip — including Runs — is the
> timeline** (mirroring web); each single-modality tab shows a `View all` link
> that pushes that modality's full surface (Runs → `RunsScreen` without a
> `gymStore` = the offline-first run list with range / sort / source filters,
> pagination, bulk-delete; Lifts → `GymScreen`; Meals → `NutritionScreen`). Run
> rows open run-detail (looked up locally, else `fetchRunById`), lift rows open
> `GymDetailScreen`, meals are read-only. The History add FAB mirrors web's
> per-tab Log action: in the cross-modal **All** view it opens the run / lift /
> meal picker (the same `showLogSheet` the home Log FAB uses) and routes the
> pick to that modality's one-shot composer (`AddRunScreen` /
> `showGymComposeSheet` / `showNutritionLogSheet`); a single-modality tab adds
> straight into that modality (Add run / Log lift / Log food). A run-only mount
> (no chips) keeps the plain Add-run FAB. Neither platform gates this behind
> `multi_modal_nav` (retired, §63 amendment) — the "second modality has data"
> gate carries the anti-clutter contract on both.
>
> **Web/mobile parity (converged 2026-06-08):** both platforms now make every
> History tab — including Runs — a unified timeline, with a per-tab `View all`
> link to that modality's full surface. Web links to dedicated pages (`/runs`,
> `/gym`, `/nutrition`); mobile's `runs_screen.dart` pushes the same screens —
> Runs → `RunsScreen` mounted **without** a `gymStore` (which renders the
> dedicated, offline-first run list: filters / sort / pagination / bulk-delete,
> the mobile analogue of `/runs`), Lifts → `GymScreen`, Meals → `NutritionScreen`.
> Mobile uses a pushed route rather than a nav tab because its bottom nav is
> capped at five slots (decisions §63). **Mobile's timeline is built from the
> three LOCAL stores** (`buildLocalActivities` over `LocalRunStore` +
> `LocalGymStore` + `LocalFoodStore`), not the server `activities` view — so it
> works fully offline, always reflects every modality the device has, and
> updates live when a run/lift/meal is logged (the Log FAB writes to those
> stores). The only place the inline run list still shows on the History tab is
> a genuine **pure runner** (no lift/meal logged at all — nothing else to put on
> a timeline) or a run-only mount with no gym store; that's not an offline
> fallback, just "there is only one modality." Web, having no offline concern
> and a sidebar, shows the timeline even for a pure runner. Both correct per
> [§ 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive).

```
  History            [ All ] [ Runs ] [ Lifts ] [ Meals ]
  ──────────────────────────────────────────────────────
  Today
   ▷  Morning run            8.2 km · 42:10        ›
   🍴 Lunch — chicken bowl    640 kcal · 48g P      ›
   ☰  Push day               5 exercises · PR       ›
  Yesterday
   ▷  Easy shakeout          5.0 km · 28:30         ›
   🍴 Breakfast — oats        410 kcal               ›
  ──────────────────────────────────────────────────────
```

- **Each row is one tap to its own detail route** — run-detail,
  lift-detail (`/gym/[id]`), meal-detail. The shipped meal-detail surface is
  the per-slot `/nutrition/[date]/[slot]` route (slot items + macro breakdown +
  a 7-day calorie trend), reached from the nutrition day-view meal-group
  headers rather than from a per-entry id. We do **not** build a unified
  mega-detail; each modality keeps its own focused screen.
- **A leading glyph per kind** (▷ run, ☰ lift, 🍴 meal) does the
  type-coding so the chips aren't load-bearing for scanning — colour is a
  secondary cue, never the only one (accessibility).
- **Date grouping** ("Today / Yesterday / Mon 2 Jun") reuses the existing
  `period_summary` date helpers; locale-aware via the gen-l10n
  `DateFormat` layer.
- **Wide-canvas layout (web).** Day groups flow into a responsive
  multi-column grid (`repeat(auto-fill, minmax(30rem, 1fr))`) so the
  timeline fills the page instead of stranding the right ~40% as dead space;
  it collapses to a single column below ~64rem and on mobile (the Flutter
  timeline is a single-column `ListView` — phones don't have the
  wide-canvas problem).
- Filter chips are **client-side** filters over the already-fetched
  window — no round-trip per chip. The `All` chip is default.
- A pure runner with no lifts/meals sees only run rows and the chips for
  the empty kinds are **hidden**, not disabled.
- **First paint never flips the layout.** On **web** the run-list-vs-timeline
  decision depends on whether a second modality exists, so `/history` holds a
  neutral skeleton until the (server) `activities` feed resolves (the
  `activitiesLoaded` flag), then paints once; back-nav restores the timeline
  state from the page snapshot. On **mobile** there is nothing to wait for —
  the timeline is assembled synchronously from the already-loaded local stores
  (`buildLocalActivities`), so the correct layout paints immediately with no
  spinner gate (the old `Preferences.historyMultiModal` hint was retired with
  the server feed). It updates in place as the stores change.

## Gym — lightweight tier surfaces (mirror web `/gym`)

Free-form log, not a programmed-routine engine. Three screens; the
composer is a modal sheet, matching `gear_form_sheet` / `goal_editor_sheet`.

```
  gym_compose_sheet                        ✕  Save
  ─────────────────────────────────────────────
  Title (optional)   [ Push day              ]
  ─────────────────────────────────────────────
  Bench press                              🗑
    Set 1   [ 8 ] reps  [ 60 ] kg   RPE [ 8 ]
    Set 2   [ 8 ] reps  [ 60 ] kg   RPE [  ]
    ＋ add set
  Overhead press                           🗑
    Set 1   [ 6 ] reps  [ 40 ] kg   RPE [  ]
    ＋ add set
  ─────────────────────────────────────────────
  ＋ add exercise
```

- **Exercise name is free text** (autocomplete from the user's own
  history). One tap re-logs a recent exercise name. The exercise DB
  depth-tier landed additively (migration `20270222_001`, decisions §176):
  catalogue names merge into the same autocomplete and a **Browse
  catalogue** affordance per block opens a searchable, category-filterable
  picker (globals + the user's customs, with inline create-custom) —
  picking fills the name and binds `gym_sets.exercise_id` via the existing
  normalised-key path. Browse self-hides offline / signed-out; free-text
  logging is never required.
- **Sets are rows** with reps + weight + optional RPE; weight stored in
  kg, rendered in the user's unit. Add/remove set and exercise inline.
- `gym_screen` (list) and `gym_detail_screen` (read-only review +
  per-exercise PR badges) round it out.
- **PRs** (`gym_prs.ts` ↔ `gym_prs.dart`, pure + unit-tested parity pair,
  **shipped**) compute heaviest set / most volume / best rep-PR (Epley
  e1rm) per `(user, exercise_name)` via `computeExercisePrs`; `workoutPrs`
  reports which metrics a session newly bettered → a Home card + a "PR"
  badge on the History row + a chip in detail.
- **Not in scope (depth tier):** exercise database, templates, programmes,
  progressive-overload prescriptions, rest-timer.

## Nutrition — surfaces (mirror web `/nutrition`)

> **Hardening change (was the plan's weakest link):** the original
> lightweight tier was *manual macro entry* — type "chicken bowl", then
> hand-enter calories/protein/carbs/fat. That is dead on arrival: nobody
> knows those numbers, MyFitnessPal's entire moat is removing exactly that
> friction, and a food diary that's painful to fill gets abandoned in a
> week. **A food database is therefore pulled forward from the depth tier
> into the first nutrition release — nutrition does not ship without it.**

- **Search-driven logging via two food sources** (shipped web + mobile,
  2026-06-20). Open Food Facts (free, no API key, open data —
  `world.openfoodfacts.org`) AND USDA FoodData Central
  (`api.nal.usda.gov`, key-gated). Logging is **search → tap → adjust
  portion**, not blank macro entry. The `food_search` helper's
  `searchFoodSources` queries both in parallel (OFF first, deduped by
  case-insensitive name+brand) and labels each result by source; the
  composer falls back to manual entry only when nothing matches. USDA is
  **fail-closed on its API key** (`PUBLIC_USDA_FDC_API_KEY` web /
  `USDA_FDC_API_KEY` mobile dotenv): unset → USDA simply absent, OFF still
  works. A partial-failure of one source degrades to the other. TS↔Dart
  parity pair; see [decisions.md § 188](../architecture/decisions.md).
- **Barcode scan** (mobile-only, camera — the one place mobile leads) is
  the fast path on top of the same Open Food Facts lookup; the data layer
  is shared with search. **Shipped (2026-06-20, mobile):** a Scan-barcode
  action in `nutrition_log_sheet.dart` scans an EAN/UPC via `mobile_scanner`
  (BSD-3), normalises it, and looks it up through the OFF product-by-barcode
  endpoint (`lookupBarcode` / `parseOffProduct` in the `food_search` parity
  pair), then drops into the existing confirm-portion flow. No-match and
  scan/lookup failure fall back to search / manual entry; the camera scan is
  wrapped per the L4 layered-resilience contract so it can't break manual
  logging, and camera-permission denial surfaces an inline message +
  Open-settings affordance. Web is **not** a scan surface (no camera-record
  surface); the helper exists on web only for TS↔Dart lockstep.
- Manual macro entry remains as the **fallback**, not the primary path.
- **Dynamic TDEE ("base + exercise").** The daily calorie goal is the
  Mifflin-St Jeor base (activity level treated as your *non-exercise*
  baseline) **plus** the calories burned by today's logged runs + gym
  sessions (`exercise_calories.ts`/`.dart` parity pair). `/nutrition` shows
  the `Goal <base> + <exercise> kcal` breakdown on workout days, so a long-run
  day's goal rises instead of leaving you under-fuelled. Avoids the
  double-count the old activity-multiplier-only target would create
  (decisions §134). *(Shipped on web and mobile — `exercise_calories.dart`'s
  `exerciseCaloriesForDay` is wired into `nutrition_screen.dart`.)*

```
  Nutrition                              Wed 4 Jun
  ─────────────────────────────────────────────
        ◯◯◯        Calories   1,840 / 2,550
        ◯ ring     Protein     132g / 165g
        stack      Carbs       180g / 280g
                   Fat          61g / 85g
  ─────────────────────────────────────────────
  Water   ●●●●●○○○   5 × 250 ml          ＋
  ─────────────────────────────────────────────
  Breakfast                              412 kcal
    Oats + banana            58g C · 12g P    ›
  Lunch                                  640 kcal
    Chicken bowl             48g P · 52g C    ›
  ＋ Log food
```

- **Rings, not bars,** for the daily macro picture — four concentric (or
  a 2×2 of small rings on narrow screens) for kcal / protein / carbs /
  fat against the user's targets. A glance answers "how much room left
  today?"
- **`nutrition_log_sheet`** composer: **search Open Food Facts + USDA → tap a
  result → confirm portion** (the macros autofill from the DB entry, the row
  labelled by source); an optional meal slot (breakfast/lunch/dinner/snack);
  manual entry only as the no-match fallback. Meal-slot grouping in the daily
  view.
- **Targets** default from a Mifflin-St Jeor BMR × activity-level
  heuristic (`nutrition_targets.ts` / `.dart`, pure + tested, TS↔Dart
  parity pair), overridable in Settings → Preferences. BMR needs body
  metrics — see **Body metrics & sensitive data** below.
- **Water tracker** is a separate, tap-to-increment row of 250 ml units —
  deliberately the lowest-friction thing on the screen.
- **Weekly trends** reuse the `mileage_trend_card` pattern (same
  bucketing, same unit-aware rendering) on a second tab/section. The 7-day
  trend header carries two consistency chips from `nutrition_week.ts` (parity
  pair): the calorie **`X under/over goal/day`** delta (`weeklyIntakeSummary`)
  and a **protein consistency** chip **`Protein met/total days`**
  (`weeklyProteinSummary`) — how many of the logged days cleared the protein
  goal, since protein is a floor (endurance-athlete default 1.8 g/kg) the
  runner most often under-hits. The protein chip goes success-green when every
  logged day met the target. Shipped web + mobile (both twins).

> **Status (web shipped):** capture is a **modal** opened from `/nutrition`
> (`FoodLogEditor` hosted in the shared `Modal`), honouring the §210
> "Log → a sheet, not a new screen" contract and matching the gym surface
> (`GymEditor`). The standalone `/nutrition/log` route is kept as a thin
> wrapper around the same editor (deep links + browser back), per the
> create-flow modal pattern in `apps/web/CLAUDE.md`. The portion-confirm
> step is an inline view inside the editor (no nested modal). The
> `/nutrition/log/[id]` meal-detail route is unaffected. Mobile already
> matched this — `showNutritionLogSheet` is a fullscreen dialog, never a
> nav push.

> **Status (meal templates — shipped web + mobile, 2026-06-20, migration
> `20270219_001`, [decisions § 173](../architecture/decisions.md)):** the Nutrition mid-tier "saved meals
> logged with one tap" item. A **`meal_templates` + `meal_template_items`**
> pair (owner-scoped RLS; items mirror the `food_log` row shape) is the
> nutrition twin of gym `gym_routines`. `/nutrition` gains a **"Save as meal"**
> action (promotes the day's logged entries into a named template via
> `templateFromEntries`) + a **self-hiding Meal-templates section** (mirrors the
> gym Routines section) that logs the whole meal with one tap
> (`entriesFromTemplate` → `food_log` rows, slot resolving item → template-
> default → log-time override) or deletes it behind `ConfirmDialog`. The
> `meal_template.ts`↔`.dart` parity pair holds the pure plan↔log shaping; logging
> **copies** into `food_log` (no FK, so deleting a template leaves logged meals
> intact). Mobile mirrors via `LocalMealTemplateStore` (offline-first) + the
> nutrition screen, byte-identical iOS twin. In the Art 20 DSAR export (items
> nested). **Shared/public templates + an edit path stay deferred.**

> **Status (recipe builder — shipped web + mobile, 2026-06-20, migration
> `20270221_001`, [decisions § 175](../architecture/decisions.md)):** the next Nutrition mid-tier item —
> "N ingredients → one logged meal." A **`recipes` + `recipe_ingredients`** pair,
> the sum-into-one sibling of meal templates: logging a recipe writes a **single**
> `food_log` row carrying each ingredient's macros × `quantity`, summed, ÷ a
> `servings` count (so one serving = the per-serving macros under the recipe's
> name). `/nutrition` gains a **"Save as recipe"** action (with a servings field) +
> a self-hiding Recipes section. The `recipe.ts`↔`.dart` parity pair
> (`recipeFromEntries` / `sumRecipe` / `logInputFromRecipe`) holds the arithmetic
> (missing macro contributes 0, never poisons the sum; rounds to 0.1). Same
> instantiate-by-copy contract (no FK). Mobile mirrors via `LocalRecipeStore`,
> byte-identical iOS twin. In the Art 20 DSAR export (ingredients nested).
> **Per-ingredient quantity editing + shared/public recipes + an edit path stay deferred.**

## Cross-modality touches (Tier 1 — ship with Phase 4; this is the headline)

- **Home** composes all three modalities per the ordering above. *(Web gym
  slice shipped — see the Home status note above.)*
- **AI Coach** context (web-side `coach/context.ts`) reads recent gym
  sessions + 7-day nutrition *averages* (not every food row) alongside the
  run window; mobile's coach screen just renders richer answers, no mobile
  work. **Context is bounded** — a fixed cap of recent lifts (`COACH_LIFTS_CAP`)
  + a 7-day rolling nutrition summary, not raw rows — so prompt size + per-
  call cost stay roughly flat as history grows. The daily cap is unchanged.
  *(Shipped — `summarizeRecentLifts` + `summarizeNutrition`, unit-tested;
  nutrition gated on Art 9 health consent.)*
- **Training-load** factors lift sessions as additional stress — see the
  lift-load spec below. A `training_load` parity-pair change. *(Shipped +
  wired into web `/dashboard`.)* The web Fitness card now **discloses** this:
  a transparent note when recent lifts are in the fatigue, and an
  `exclude_gym_from_readiness` pref (Settings → Preferences) that drops lifts
  from the readiness/recovery curve for a pure run-only signal — display-side
  only, the run-only curve stays recoverable (decisions §134). *(Shipped on web
  and mobile — the toggle lives in `settings_preferences_screen.dart` and
  `dashboard_screen.dart` drops lifts from the readiness curve when it's on.)*
- **Nutrition → run guidance is NOT deterministic, by design.** Under-eating
  does not move the readiness ring (auxiliary inputs are kept from corrupting
  run readiness); fuelling adequacy is the AI Coach's soft-reasoning job via
  the 7-day rollup above, not a formula (decisions §134).
- **Social feed** extends to **lift** cards gated on `is_public`, reusing
  the existing follower/feed plumbing. **Shipped (2026-06-12) on web +
  mobile.** Web `SocialFeed.svelte` reads `fetchFollowingActivityFeed` (runs
  via the redacted `public_runs` view + public `gym_workouts` via their
  owner-or-public RLS, merged into one cursor-paged window) and renders a
  distinct lift card (title + set count + total volume + handle + date) with a
  `Lift` filter chip; the public lift links to the new read-only
  `/share/workout/[id]` page, and a public/private toggle + copy-share-link
  action live on `/gym/[id]` (`setGymWorkoutPublic`). Mobile mirrors the lot:
  `feed_screen.dart`'s `_LiftEntryCard` + `Lift` chip over the
  `ActivityFeedEntry` union (`fetchFollowingActivityFeed` in `api_client`), and
  the gym-detail visibility toggle (`gym_detail_screen.dart` →
  `LocalGymStore.updateLocal`, offline-first). Only the headline columns are
  projected into a lift card / share page — no notes / RPE / per-set data leak
  past what the owner made public; engagement (kudos / comments) stays
  run-only. **Meals are NOT feed-shareable in v1** — broadcasting what you ate
  is a privacy footgun with little upside; `food_log.is_public` stays in the
  schema (cheap) but no UI surfaces meal sharing until there's a clear reason.
  Defaults are private regardless.
  > **Redaction boundary (decisions §33).** The `activities` view is
  > `security_invoker`, so base-table RLS decides cross-user visibility.
  > `gym_workouts` / `food_log` keep an "owner or public" read policy, so a
  > non-owner (and anon) sees their public rows *through the view*. `runs`
  > deliberately has **no** public-read policy — non-owner run reads must go
  > through the redacted `public_runs` view, so a public **run** is invisible
  > through `activities` to anyone but its owner. Lift feed cards may read the
  > view (or `gym_workouts` directly); **run** cards stay on `public_runs`.
  > Re-adding a runs public-read policy to "symmetrise" the view would leak
  > unredacted run columns — `activities_view_windowed_test.sql` pins the
  > asymmetry so that can't happen by accident.

### Lift training-load spec (the Tier-1 mechanic — get this right or it pollutes run readiness)

Lifts must contribute to the same daily-stress series that drives
CTL/ATL/TSB, but a wrong lift-stress number degrades the *running*
readiness runners already trust. Rules:

- **Per-session lift stress** = a bounded function of working-set volume
  and, when present, RPE: `stress = k · Σ(reps · weight_kg) · rpeFactor`,
  with `rpeFactor` defaulting to 1.0 when RPE is absent and the constant
  `k` calibrated so a typical hard lifting session lands in the same
  ballpark as an easy-run TSS (≈40–60), not 10× it. Capped per session so
  a data-entry typo (500 kg bench) can't spike the curve.
- **Separable provenance.** Each daily-stress contribution carries a
  `source` (`'run' | 'lift'`). The series sums both for the unified
  recovery view, but the run-only readiness signal can be recomputed from
  run contributions alone. A lift-load modelling change can therefore
  never silently corrupt the run-only numbers — they're recoverable.
- **Pure + parity-paired.** Lives in the `training_load` module
  (`training_load.ts` ↔ `.dart`), unit-tested, behind the same
  calibration discipline as the existing TRIMP/distance stress model.
- **Off until calibrated.** Lift contributions are gated behind the
  `multi_modal_nav` flag like everything else, and the calibration
  constant ships with a test pinning the "hard lift ≈ easy run" target so
  a regression is caught, not shipped.

> **Status (shipped + wired):** the mechanic is implemented in the
> `training_load` parity pair — `computeLiftStress` (capped, RPE-weighted
> tonnage), `aggregateDailyLiftStress`, and an optional `lifts` argument to
> `computeTrainingLoadSeries` that adds a `source`-separable `runStress` /
> `liftStress` split to every `TrainingLoadPoint`. The `CALIBRATION` test
> pins a hard session into the easy-run TSS band and a separability test
> proves the run-only curve is recoverable unchanged. **Now wired** to its
> first consumer: web `/dashboard` fetches the user's gym set history (flag-
> gated), groups it into per-session `LiftForLoad` via the pure, tested
> `gym/lift_load.ts` helper (`liftsFromSetHistory`), and passes it to
> `computeTrainingLoadSeries`, so the fitness/fatigue/form trio, recovery
> advice, and the readiness ring all reflect lifts. `TrainingLoadChart`
> shows a "gym sessions included" hint whenever any `liftStress > 0`. Pure
> runners / flag-off pass `lifts=[]`, so the curve is the unchanged run-only
> series. **Mobile wired too:** `lift_load.dart` (`liftsFromSetHistory`, the
> Dart parity twin) feeds `dashboard_screen.dart`'s logged gym sessions into
> `computeTrainingLoadSeries`, so the mobile fitness/fatigue/form chart + the
> same "gym sessions included" hint reflect lifts. The gym store is empty for
> a pure runner, so the mobile curve stays the unchanged run-only series.

## Sequencing, validation gates & risk controls

The original plan shipped gym + nutrition together. That bundles a
strong-fit modality with a weak-fit, high-friction one and lets the weak
one drag the launch. Corrected order, with explicit gates:

1. **Finish the Phase 3 training moat first** (missed-session re-planning,
   roadmap Phase 3). It directly counters Runna — the most credible
   competitive threat — and is closer to revenue than any Phase 4 module.
   Opening a second big phase while the training story is unfinished is
   the classic single-dev spread-too-thin failure.
2. **Gym first.** Runners cross-train and lift; logging a lift is
   low-friction and high-value, and lift→load is the trustworthy Tier-1
   integration. Ship gym + the lift-load contribution + the gym slice of
   the Coach context.
3. **Validation gate** (decisions §63 escape hatch, formalised): before
   building nutrition, measure gym engagement on the flagged cohort. If
   gym lands, proceed; if it doesn't, the multi-modal thesis is in
   question and nutrition waits.
4. **Nutrition — only with the food DB.** Search-driven (Open Food Facts)
   from day one; never manual-only. Barcode follows.
5. **Promote cross-modality intelligence to first-class** as each module
   lands — it's the wedge, not the card layout.

**Protect the core runner.** Moving Run from a tab to a `Log` action is a
downgrade for the 100%-runner (one tap → two; long-press mitigates but is
discoverable-only). The protection that shipped is the **`keep_run_primary`
Settings toggle** (mobile) that lets a pure runner keep Run as the primary
one-tap action — *not* the `multi_modal_nav` flag. (The original plan here
proposed keeping the flag default-off as the protection; that was superseded
by the 2026-06-04 §63 amendment, which **retired the flag** and ungated web
to match mobile. The cards/chips self-hide on data presence, so a runner who
never opts into gym/nutrition is never worse off either way.) The runner who
never logs a lift/meal must never be worse off.

## Body metrics & sensitive data (compliance — do before any real user data)

The BMR target needs **weight, height, age, sex**. Age + sex already live
on `user_profiles` (added for segments). Weight + height are new and
**sensitive health data** (GDPR special category; Apple Health / Play
Data Safety disclosable). Plan:

- Store current height on `user_profiles`; store **weight as a small
  time-series** (`body_metrics` — `user_id, recorded_at, weight_kg`)
  rather than a single mutable column, because weight trends matter and a
  single column loses history. (New migration when the nutrition module
  starts — additive, owner-scoped RLS, cascade-delete.)
- **DSAR completeness (must-fix):** `gym_workouts`, `gym_sets`, and
  `food_log` are now in the **data-export path** (Go `dataexport`'s
  `FetchExportPersonalDataTables` + the `export-data` EF's
  `buildBackupSpecs`) so the GDPR right-to-know export is complete.
  `gym_sets` has no `user_id` of its own — it cascades from the parent
  workout — so it ships nested inside each `gym_workouts` row via the
  same PostgREST embed `training_plans` uses for its weeks/workouts.
  `body_metrics` (migration `20261216_001`) is now wired into **both**
  paths (`body_metrics.json`); `height_cm` ships in the `user_profiles`
  export entry. `safety_contacts` (migration `20261218_001`) is wired in
  both directions — `safety_contacts_owned.json` (rows the subject owns,
  filtered `owner_id`) and `safety_contacts_as_contact.json` (rows where
  the subject is the confirmed contact, filtered `contact_user_id`). It
  keys on `owner_id` / `contact_user_id`, **not** `user_id`, so the Go
  export-completeness guard's `user_id`-column scan can't auto-flag it —
  it is wired explicitly. The `confirm_token` capability credential is
  omitted from the select projection (same rationale as `coach_athletes`'
  `invite_token`). Account *deletion* is already covered — all
  FK-cascade from `auth.users`, so deleting the auth user removes them —
  but **export is not automatic**, so wire each new modality table into
  the export path as it gains real data; don't ship a modality to real
  users with its data missing from export.
- **Disclosure:** adding nutrition + body metrics changes the privacy
  posture — update the iOS Privacy Nutrition Label, Play Data Safety
  form, and the sub-processor list. Food search now has **two outbound
  hops**: Open Food Facts (`world.openfoodfacts.org`) AND USDA FoodData
  Central (`api.nal.usda.gov`, gated on the fail-closed
  `PUBLIC_USDA_FDC_API_KEY` / `USDA_FDC_API_KEY`) — both receive the typed
  search term. List both as sub-processors; the USDA key being unset is the
  prod gate that keeps that flow dark until sign-off (decisions § 188). Gate
  the nutrition launch on those doc updates (`/audit/*` covers the surfaces).

## `activities` view at scale

The view UNION-ALLs runs (potentially thousands) with the gym branch
reading the **stored** `set_count` + `volume_kg` columns on
`gym_workouts` (no longer per-workout correlated subqueries — F7, migration
`20261214_001`). For the History list:

- Always query it **windowed** (`limit` + `started_at` cursor), never
  unbounded — the History screen paginates like `/history` does. The web
  consumer (`fetchActivities`) always caps with `.limit(…)`; the
  windowed-page-1 + started_at-cursor-page-2 path is pinned in
  `activities_view_windowed_test.sql` so the contract can't silently
  regress to an unbounded `select * from activities`.
- Each base table carries the **shared spine** index `(user_id,
  started_at desc)` (`runs_user_started_at`, `gym_workouts_user`,
  `food_log_user`), so the windowed read is a per-branch ordered index
  scan merged + limited, not a full UNION materialise. The spine is pinned
  by `activities_spine_indexes_test.sql` (MM3).
- `set_count` + `volume_kg` are trigger-maintained derived columns on
  `gym_workouts` (an AFTER INSERT/UPDATE/DELETE trigger on `gym_sets`
  recomputes the parent's totals from scratch). The view reads them as
  flat columns, so a power lifter's history is a per-branch ordered index
  scan, not a fan-out of correlated subqueries. The cache contract (the
  authoritative recompute) is documented in
  [`derived_state.md`](../backend/derived_state.md); the trigger
  maintenance + view correctness are pinned by `gym_workout_totals_test.sql`.

## Empty states & first-run

- A brand-new multi-modal user (flag on, nothing logged) sees today's
  running Home **plus** a single slim footer affordance: "Track lifts and
  meals too — ＋ Log a lift / ＋ Log a meal." One line, below the fold,
  dismissible.
- Tapping it opens the relevant composer. After the first lift/meal, the
  corresponding cards + History rows + filter chips appear automatically.
- No onboarding wizard, no modality picker at sign-up. The app stays a
  running app until the user reaches for more.

## Anti-clutter checklist (enforce in review)

- [ ] No card renders for a modality the user has never logged.
- [ ] No empty chart, zeroed ring, or "0 / 0" stat is ever shown.
- [ ] History filter chips for empty kinds are hidden, not disabled.
- [ ] Type is coded by glyph + label, not colour alone (WCAG).
- [ ] Each screen has exactly one primary action.
- [ ] The runner-only experience is within one card of today's app, and a
      pure runner can keep Run as the one-tap primary action.
- [ ] Lift-load contributions carry a `source` and never corrupt run-only
      readiness; the "hard lift ≈ easy run" calibration test passes.
- [ ] New personal-data tables are in the data-export path before real use.
- [ ] Nutrition logging is search-driven (food DB), never manual-only.
- [ ] Every new string is in all six gen-l10n catalogues.

## File plan (mobile)

Built **web-first then mirrored** (§24); the lightweight tier is forms,
so no device capability is needed in v1 (camera/barcode/photo are depth
tier where mobile leads). Byte-identical iOS twin per [decisions.md § 39](../architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase).

| Concern | Mobile files |
|---|---|
| Nav + Log sheet | `home_screen.dart` (bottom-nav reshape), `widgets/log_sheet.dart` — **shipped (G5)** |
| Home cards | `widgets/nutrition_rings_card.dart`, `widgets/gym_summary_card.dart` — **shipped (G5)** (run summary already lived on the dashboard) |
| History | `screens/runs_screen.dart` (the History tab — hosts the kind chips + unified timeline) + `widgets/activity_timeline_list.dart` + the pure `activity_timeline.dart` day-grouper, assembled from the local stores via `lib/local_activities.dart` (offline-first, not `fetchActivities`) — **shipped** |
| Gym | `screens/gym_screen.dart`, `widgets/gym_compose_sheet.dart`, `screens/gym_detail_screen.dart`, `gym_prs.dart` (pure, parity-paired) |
| Nutrition | `screens/nutrition_screen.dart`, `widgets/nutrition_log_sheet.dart` (search + the v1.1 camera barcode-scan fast-path via `mobile_scanner`), `nutrition_targets.dart` (pure, parity-paired), `food_search.dart` (Open Food Facts + USDA search, source-merged + deduped via `searchFoodSources`, plus `lookupBarcode`/`parseOffProduct` OFF product-by-barcode lookup, pluggable-fetcher seam like `routing.dart`; TS↔Dart parity pair) |
| Body metrics | `body_metrics` table (migration `20261216_001`) + Settings height/weight entry (**mobile shipped (G5)** — `settings_body_metrics_screen.dart`, Art 9 consent-gated height/weight + activity/goal; api_client `grantHealthDataConsent`/`withdrawHealthDataConsent`/`setMyHeightCm`/`recordBodyWeightKg`/`clearBodyWeightHistory`) |
| Lift load | `training_load.ts` / `.dart` gain `liftStress` + `source`-tagged daily contributions (**shipped** — `computeLiftStress` + `aggregateDailyLiftStress` + the `lifts` arg to `computeTrainingLoadSeries`). **Consumers wired on both platforms**: web `web/src/lib/gym/lift_load.ts` and mobile `mobile_android/lib/lift_load.dart` (`liftsFromSetHistory`, pure + tested parity pair) feed each dashboard's load curve; `TrainingLoadChart` (web + mobile) shows the "gym sessions included" hint when `liftStress > 0` |
| Cross-modality | `coach/context.ts` (**web shipped** — bounded `recent_lifts` + 7-day `nutrition_7d` summary, pure `summarizeRecentLifts`/`summarizeNutrition` + tests); web Home gym cards (`/dashboard`); web History timeline (`/history` + `fetchActivities`). **Mobile Home card composition shipped (G5)** — `dashboard_screen.dart` + `widgets/gym_summary_card.dart` + `widgets/nutrition_rings_card.dart` + the recent-lifts trend card (`widgets/recent_lifts_card.dart`); the **unified mobile History timeline is now shipped** (`runs_screen.dart` + `widgets/activity_timeline_list.dart`, assembled from the LOCAL stores via `lib/local_activities.dart` — offline-first, all modalities, not `fetchActivities`) |
| Runner protection | Settings toggle: keep Run as the one-tap primary action — **shipped (G5)** (`Preferences.keepRunPrimary` + the `settings_preferences_screen.dart` switch; tap = one-tap run start, long-press = full Log sheet) |
| Local stores | `local_gym_store.dart`, `local_food_store.dart` (shipped — mirror `LocalGearStore`, §73 / §122; gym stores sets inline). **Now wired into nav/Home (G5):** the gym/nutrition screens + the dashboard hydrate + drain them; still outside the global `main.dart`/`sync_service` sweep |
| Data access | `packages/api_client` typed gym + food + `fetchLatestBodyWeightKg` + the unified-timeline `fetchActivities` (→ `activities` view) + `fetchRunById` (timeline run-row open) methods (shipped); web gym queries in `core/data.ts` (**shipped** — `fetchGymWorkouts` / `fetchGymWorkoutWithSets` / `fetchGymSetHistory` / `createGymWorkout` / `updateGymWorkout` / `deleteGymWorkout`); **web food + body-metrics queries shipped** (`fetchFoodLog` / `createFoodEntry` / `updateFoodEntry` / `deleteFoodEntry` / `fetchLatestWeightKg` / `recordWeightKg` / `clearWeightHistory`) |

**Web gym surfaces (shipped).** Mirrors the mobile gym plan above on the canonical web surface: `routes/gym/+page.svelte` (list + PR badges + create modal), `routes/gym/[id]/+page.svelte` (detail + per-exercise PR chips + edit/delete + a per-exercise **"vs last time"** hint — the previous weighted session's top set with a +/- delta on the heaviest set, via `gym/exercise_history.ts#previousExerciseSession`, linking to that exercise's progression; the progressive-overload cue the all-time PR chips can't give), `routes/gym/records/+page.svelte` (per-exercise current bests — est. 1RM / heaviest / top volume + last-performed + session count — via the **`gym_exercise_records` RPC** (`fetchExerciseRecords`, migration `20261224_001`): all-time bests can't be served by a windowed client read, so the aggregation moved server-side, mirroring how run PRs live in SQL; the SQL metrics are pinned to the `gym_prs.ts` semantics by pgtap. Linked from the `/gym` header once a weighted set exists. Mobile keeps its own client-side records screen — `gym_records_screen.dart` over `exercise_records.dart` — so the two now compute the same bests via different paths, no longer a byte-identical pair), `routes/gym/exercise/+page.svelte` (per-exercise progression over time — read by `?name=` — headline est.-1RM delta vs the first session + a most-recent-first session list with top set / e1RM / volume / a strength-relative bar / per-kind PR badges (Heaviest + Best est. 1RM — the same single-set metrics `/gym/records` tracks, so a heavy single can flag a Heaviest PR without an e1RM PR) on sessions that beat the running best, each row linking back to its workout; via `gym/exercise_history.ts`, also a pure **web-only** roll-up over the `gym_prs` primitives; reached from each `/gym/records` card), `components/GymEditor.svelte` (the composer — free-text exercise name with history autocomplete, inline sets, share-to-feed toggle), `gym/gym_prs.ts` (pure PR engine, parity pair), and the always-present **Gym** sidebar item in `+layout.svelte` (ungated, §63 amendment). E2e: `tests-e2e/gym/gym.spec.ts` + `tests-e2e/gym/records.spec.ts` + `tests-e2e/gym/exercise_history.spec.ts` + `tests-e2e/gym/vs_last_time.spec.ts`. The `weight_unit` (`'kg' \| 'lbs'`) user-pref is **wired on both platforms** (settings.md, F19): storage stays canonical kg (`gym_sets.weight_kg`); display + entry convert via the pure `format/weight.ts` (`formatWeightKg`/`parseWeightToKg`) ↔ mobile `WeightFormat`, driven by the `weightUnit` signal / `activeWeightUnit` and the Settings → Preferences kg/lbs toggle on each side.
| DSAR | `gym_workouts` / `gym_sets` (nested) / `food_log` + `body_metrics` (migration `20261216_001`) all in the export path (**shipped** — see the Body-metrics § above); deletion FK-cascades from `auth.users` |

## Proposed redesign (pending sign-off) — the Train hub + Routes relocation

> **Status: SHIPPED 2026-06-11** — landed as the **Fitness** hub (the working title throughout this section is "Train"; the owner picked **Fitness** because it covers run + gym + nutrition, where "Train" doesn't). Web routes-relocation (drop the `/routes` sidebar item, nest under `/runs` via `RunSurfaceTabs`, `/routes` URL preserved) + the mobile Fitness hub (`Home · Fitness · [+]Log · Social · You`; `fitness_hub_screen.dart` with All/Runs/Gym/Nutrition; History absorbed into All; Settings → `you_screen.dart`; Coach pinned on Home; Routes out of Social into Fitness→Runs) both shipped, iOS twin byte-identical, code-reviewer-clean (keep-alive recording path verified intact). This section supersedes the routes-half of [decisions.md § 61](../architecture/decisions.md#61-social-hub-ia-rename-clubs--social-host-feedpeopleclubs-as-tabs-under-social) and corrects the "Routes was folded into Social" parenthetical in [§ 63](../architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db); the landed ADR is [decisions.md § 139](../architecture/decisions.md#139-routes-is-a-run-modality-surface-mobile-nav-is-a-fitness-hub). **Training Plans nested too (follow-up, 2026-06-11):** the web strip is now `Runs · Routes · Plans` (`/plans` mounts `RunSurfaceTabs` and dropped its standalone `/dashboard` back-link, `/plans` URL preserved); mobile's Fitness→Runs surfaces a Plans entry alongside Routes (`RunsScreen.onOpenPlans` → `PlansScreen`, with `TrainingService` threaded from `home_screen`). See the [decisions.md § 139 amendment](../architecture/decisions.md#139-routes-is-a-run-modality-surface-mobile-nav-is-a-fitness-hub).

### The problem this fixes

The multi-modal expansion left the nav incoherent on **where a modality's *planning tools* live**:

- **Routes is mis-placed on both platforms.** On web it's a **top-level sidebar peer** of Gym/Nutrition (`+layout.svelte` nav item `/routes`), which over-weights a *run-planning tool* as if it were a fourth modality. On mobile it's **buried under Social**, conceptually wrong (a course-planning tool under the people/feed layer) and inconsistent with web. Meanwhile Gym's routines and Nutrition's targets correctly live *inside* their modality surfaces — Routes is the odd one out.
- **Mobile modalities have no persistent front-door.** You can *capture* via `Log` and *review* via History's `View all`, but there's no "go to my running / my gym / my nutrition" home to plan or browse. `Settings` also eats a scarce top-five slot despite being low-frequency.

The fix unifies the rule: **each modality owns its planning assets** — runs own routes + training plans, gym owns routines, nutrition owns targets/recipes — and they all hang off that modality's surface, never as a top-level peer and never under Social.

### Mobile — the Train hub

Bottom nav becomes `Home · Train · [+] Log · Social · You` (still five slots, still a raised centre `Log` action):

```
┌───────────────────────────────────────────────┐
│  Train                                          │
│  ┌──────┬──────┬──────┬───────────┐             │
│  │ All  │ Runs │ Gym  │ Nutrition │             │
│  └──────┴──────┴──────┴───────────┘             │
│   Runs ▸  • Run list                            │
│           • Routes        ← relocated here       │
│           • Training plans                       │
│                                                 │
├───────────────────────────────────────────────┤
│   ⌂        🏃        ╔═══╗        ◎        ◐     │
│  Home    Train      ║ + ║      Social    You    │
│                     ╚═══╝                        │
└───────────────────────────────────────────────┘
```

- **`Train`** is the modality hub. A top sub-tab strip `All · Runs · Gym · Nutrition`:
  - **All** = the unified cross-modal timeline that is the *current* `History` tab — the `History` bottom-nav slot is absorbed here, not deleted. Same offline-first local-store assembly (`lib/local_activities.dart` over the three `Local*Store`s), same `activity_timeline_list.dart` rows, same per-row tap-to-detail. The `History`-tab kind chips become the hub's sub-tabs.
  - **Runs** = the run-management surface (today's `RunsScreen` reached via History `View all`) **plus Routes plus Training plans** as sections/sub-routes within it.
  - **Gym** = `GymScreen` (list + records) + Routines when the gym-programming P1 lands ([gym_programming.md](gym_programming.md)).
  - **Nutrition** = `NutritionScreen` (day/week) + targets.
- **`Log` (+)** is unchanged — the capture sheet (Log run / lift / food → keep-alive capture page), long-press = repeat last. Capture stays separate from the Train *review/plan* surfaces (the verb-vs-modality split §63 established).
- **`Social`** is unchanged (Feed / People / Clubs). **Routes leaves Social** — the mobile Social screen drops any routes entry.
- **`You`** = profile + Settings + subscription + (future) payout account. `Settings` vacates its own slot; the `keepRunPrimary` toggle and all prefs live under `You → Settings`.
- **`Coach` is made the face of Home, not a buried card.** The thesis of this doc is that *cross-modal intelligence is the product* — so the nav must not hide it. Rather than spend a scarce sixth slot (and rather than the demoted "scrollable card" the first draft proposed), **Home gains a persistent, pinned `Ask your coach…` entry at the top** (always visible above the card stack, one tap to the Coach) so the intelligence layer is the first thing on the default landing surface. Web keeps its dedicated `/coach` sidebar item (it has room). Coach stays cross-modal advisory, not a modality, so it is not a Train sub-tab. *Considered and rejected:* a dedicated `Coach` bottom-nav slot displacing `Social` — Social now also hosts paid club classes ([club_events.md](club_events.md)), so it earns its slot; the pinned-Home-entry reconciles the thesis without that trade. This is the one reversible call in the redesign — revisit if Coach engagement warrants a full slot.
- **Home** is unchanged — the prioritised, self-hiding card stack ("what's my day").

The **self-hiding contract holds**: a pure runner opening `Train` sees the Runs sub-tab content and an `All` timeline of only runs; the Gym/Nutrition sub-tabs render their empty-onboarding state but are never forced on them (mirroring today's data-gated cards). The Train hub being always-present is the analogue of today's always-present `Log` sheet — it's the entry point, so it can't itself be data-gated (the §63-amendment chicken-and-egg rule).

Keep-alive note: the in-shell `PageView` capture pages (Run/Gym/Nutrition recorders) stay exactly as the §63 2026-06-08 amendment built them — the Train hub is a *review/plan* destination, distinct from the keep-alive *capture* pages the `Log` action lands on. A live recording is unaffected by navigating to `Train`.

### Web — Routes nests under the Run surface; siblings stay

Web is not slot-constrained, so it keeps the §63 contract of **explicit `Run` / `Gym` / `Nutrition` sidebar siblings** — no Train hub on web. The only structural change:

- **Drop the top-level `/routes` sidebar item.** Routes nests into the run surface: `/runs` gains a sub-tab strip `Runs · Routes · Plans` (the run-modality analogue of `/gym`'s sections). The `/routes` URL is **kept and un-broken** (bookmarks, club deep-links, shares still resolve) — it simply renders inside the run surface's Routes tab instead of as a standalone destination.
- Optionally group the sidebar visually (`Home` · a *Train* group of `History / Runs / Gym / Nutrition` · `Coach` · `Social` · `Settings` footer), but the items stay flat siblings — a label-only grouping, not a collapse.
- Settings stays a web footer item; the future **payout account** surface ([club_events.md](club_events.md)) is user-level under `/settings/payouts`, unaffected.

### Routes relocation — the specifics

Routes becomes a **run-modality surface**, full move (not a library-vs-discovery split):

- The whole `/routes` surface — **my route library, the route builder, and browse-public** — lives under the Run surface (web: `/runs` Routes tab; mobile: `Train → Runs → Routes`). Browsing public running courses is a run-planning act, not a people act, so it travels with the modality.
- **Club-owned routes are unchanged.** The `/clubs/[slug]` Routes tab (`routes.club_id`, see [clubs.md § Club-owned routes](clubs.md#club-owned-routes)) stays on the club page — that's route *ownership within a club*, a separate surface from the personal library.
- No schema change — this is pure IA/nav. `routes`, `saved_routes`, and the route builder are untouched.

### Rollout & tests

Web-first per [§ 24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive):

1. **Web (smaller):** remove the `/routes` nav item in `+layout.svelte`; add the `Runs · Routes · Plans` sub-tabs to `/runs`; keep `/routes` resolving. Update `tests-e2e/cross-cutting/surfaces.spec.ts` (the sidebar-contract test) + add a Routes-under-Runs nav test.
2. **Mobile (larger — the real lift):** reshape `home_screen.dart` bottom nav to `Home · Train · + · Social · You`; build the `Train` hub screen with the `All · Runs · Gym · Nutrition` sub-tab strip (All = the existing timeline widgets; Runs = `RunsScreen` + a Routes section); move Settings under a new `You` screen; drop routes from the Social screen. Byte-identical iOS twin per [§ 39](../architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase) — run `mobile-twin-mirror` after every Dart edit. Pin with Flutter widget tests for the hub sub-tab switch + the relocated Routes entry.
3. **i18n:** new nav labels (`nav.train`, `nav.you`, the Train sub-tab labels) into all six web gen-l10n catalogues + all mobile ARBs.
4. **Docs:** flip the relevant rows here + in [parity.md](../product/parity.md); land the ADR (Appendix); update [clubs.md](clubs.md) (Social no longer hosts routes on mobile) and the per-app CLAUDE.md nav notes.

### Build order across the open proposals (avoid nav thrash)

This redesign, the routes relocation, the gym/nutrition modules, and [club_events.md](club_events.md) all touch overlapping surfaces — the mobile nav (`home_screen.dart`) was *just* rewritten (G5, §63 amendments) and this redesign rewrites it again, so the proposals must be sequenced, not landed ad hoc:

1. **Typed events (club_events.md slice E)** — cheap, additive, no nav change; unblocks the "fitness, not just running" positioning and is its own gate probe. Build first.
2. **Routes relocation (web)** — small; the prerequisite that makes the Train hub coherent.
3. **Train-hub nav redesign (this doc)** — batch the mobile nav rewrite *with* routes relocation so `home_screen.dart` is reshaped **once**, not twice. The Coach-on-Home decision lands here.
4. **Paid events (club_events.md P1)** — gated on slice E's signal + the compliance/legal sign-off.

Gym P1 and nutrition sequencing keep their own gates (gym repeat-rate, nutrition food-DB trust) and are orthogonal to the nav order above.

### Open questions

1. **Hub naming** — *resolved*: shipped as **Fitness** (covers run + gym + nutrition; "Train" was the working title but doesn't cover food).
2. **Does `All`/History also keep a Home presence?** — Home is the dashboard; the full timeline moves to `Train → All`. Decide whether Home keeps a short "recent activity" strip or sends users to the hub for history.
3. **Coach prominence** — *resolved* (above): a pinned `Ask your coach…` entry at the top of Home, not a dedicated slot. Revisit only if engagement data argues for a full slot.

### Appendix — proposed ADR (Routes is a run-modality surface; mobile nav is a Train hub)

Ready to lift into [decisions.md](../architecture/decisions.md) at the next free number when approved (the gym + paid-events specs also hold unlanded numbers — assign sequentially at landing):

> **§N. Routes is a run-modality surface, not a top-level peer or a Social tab; mobile nav reorganises around a `Train` modality hub.** As the app went multi-modal, each modality's planning assets settled inside its own surface — gym owns routines, nutrition owns targets — except Routes, which shipped as a top-level web sidebar peer of Gym/Nutrition *and* (on mobile) under Social. Both mis-frame a run-planning tool. Decision: Routes co-locates under the Run modality on both platforms (my library + builder + browse), full move, no split; club-owned routes stay on the club page (unchanged); the `/routes` URL is preserved so no link breaks. Mobile additionally adopts a `Home · Train · [+]Log · Social · You` bottom nav: `Train` is a modality hub (`All · Runs · Gym · Nutrition` sub-tabs) that absorbs the former `History` tab as its `All` timeline and gives each modality a persistent review/plan front-door; `Settings` folds into `You`; `Log` and the keep-alive capture pages are unchanged. Web keeps explicit Run/Gym/Nutrition sidebar siblings (§63) but drops the standalone Routes item, nesting it under `/runs`. This supersedes the routes-half of §61 and corrects §63's "Routes was folded into Social" note (mobile-only). Pure-runner self-hiding is preserved; the hub is always-present as the entry point (the §63-amendment chicken-and-egg rule), with empty modality sub-tabs rather than forced cards.
