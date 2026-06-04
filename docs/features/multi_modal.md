# Multi-modal layout & IA (Phase 4 — run + gym + nutrition)

Design spec for the navigation, Home, and History surfaces once the app
spans running + gym + nutrition. The data foundation (migration
`20261204_001`, `gym_workouts` / `gym_sets` / `food_log` / `activities`
view) is shipped; this doc is the **layout contract** the
screens get built against. Architecture rationale: [decisions.md § 63](../architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db). Sequencing: [roadmap.md § Phase 4](../product/roadmap.md#phase-4--multi-modal-gym--nutrition).

> **Status:** design only. Everything below ships behind the
> `multi_modal_nav` per-user feature flag (default off). **Sequencing
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
- **Tap `Log` →** a bottom sheet, not a new screen:

```
        ┌─────────────────────────────────┐
        │            Log                  ✕ │
        ├─────────────────────────────────┤
        │  ▷  Start run                     │
        │  ☰  Start lift                    │
        │  🍴 Log meal                      │
        │  ＋ Log snack                     │
        └─────────────────────────────────┘
              ↑ last-used floats to top
```

- **Long-press `Log` = repeat last activity.** Preserves the one-tap
  "start a run" muscle memory the current `Run` tab gives. A runner who
  only ever runs effectively still has a one-gesture start.
- The sheet's **order adapts**: the most recently used capture type
  floats to the top, so a daily lifter sees "Start lift" first.
- **Accessibility:** the `Log` button has an explicit `Semantics` label
  ("Log an activity"); the sheet items are a single focus group; the
  raised button keeps a ≥48 dp touch target.

## Home — a prioritised, self-hiding card stack

> **Status (web — gym slice shipped):** `/dashboard` renders a Today's-lift
> card (when a session was logged today), a Recent-lifts trend card, and a
> first-run "log a lift" footer affordance — all gated on `multi_modal_nav`
> AND data presence, modality coded by the `fitness_center` glyph + label +
> a distinct accent (never colour alone). A pure runner / flag-off user
> sees no new card. Nutrition rings land with the nutrition module; the
> mobile Home reshape is separate work.

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

> **Status (web shipped):** `/runs` gains All/Runs/Lifts/Meals chips + a
> day-grouped unified timeline over `fetchActivities` when `multi_modal_nav`
> is on AND a second modality exists (chips for empty kinds hidden). Rows
> link to their own detail route (`/runs/[id]`, `/gym/[id]`); meals render
> read-only until the nutrition detail route lands. The **Runs** chip drops
> back to the full existing run history (all its source / date / sort
> filters, pagination, bulk-delete); a pure runner / flag-off user sees that
> unchanged page with no chips. Mobile History is separate work.

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
  lift-detail (`/gym/[id]`), meal-detail (`/nutrition/log/[id]`). We do
  **not** build a unified mega-detail; each modality keeps its own
  focused screen.
- **A leading glyph per kind** (▷ run, ☰ lift, 🍴 meal) does the
  type-coding so the chips aren't load-bearing for scanning — colour is a
  secondary cue, never the only one (accessibility).
- **Date grouping** ("Today / Yesterday / Mon 2 Jun") reuses the existing
  `period_summary` date helpers; locale-aware via the gen-l10n
  `DateFormat` layer.
- Filter chips are **client-side** filters over the already-fetched
  window — no round-trip per chip. The `All` chip is default.
- A pure runner with no lifts/meals sees only run rows and the chips for
  the empty kinds are **hidden**, not disabled.

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
  history, not a database — the exercise DB is a depth tier). One tap
  re-logs a recent exercise name.
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

- **Search-driven logging via Open Food Facts** (free, no API key, open
  data — `world.openfoodfacts.org`). Logging is **search → tap → adjust
  portion**, not blank macro entry. A thin `food_search` helper queries
  Open Food Facts, caches recent/frequent picks per user, and falls back
  to manual entry only when nothing matches.
- **Barcode scan** (mobile-only, camera — the one place mobile leads) is
  the fast path on top of the same Open Food Facts lookup; it's a v1.1
  add, not a blocker, but the data layer is shared with search.
- Manual macro entry remains as the **fallback**, not the primary path.

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
- **`nutrition_log_sheet`** composer: **search Open Food Facts → tap a
  result → confirm portion** (the macros autofill from the DB entry); an
  optional meal slot (breakfast/lunch/dinner/snack); manual entry only as
  the no-match fallback. Meal-slot grouping in the daily view.
- **Targets** default from a Mifflin-St Jeor BMR × activity-level
  heuristic (`nutrition_targets.ts` / `.dart`, pure + tested, TS↔Dart
  parity pair), overridable in Settings → Preferences. BMR needs body
  metrics — see **Body metrics & sensitive data** below.
- **Water tracker** is a separate, tap-to-increment row of 250 ml units —
  deliberately the lowest-friction thing on the screen.
- **Weekly trends** reuse the `mileage_trend_card` pattern (same
  bucketing, same unit-aware rendering) on a second tab/section.

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
  wired into web `/dashboard`.)*
- **Social feed** extends to **lift** cards gated on `is_public`, reusing
  the existing follower/feed plumbing. **Meals are NOT feed-shareable in
  v1** — broadcasting what you ate is a privacy footgun with little upside;
  `food_log.is_public` stays in the schema (cheap) but no UI surfaces meal
  sharing until there's a clear reason. Defaults are private regardless.
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
> series.

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
discoverable-only). Therefore: keep `multi_modal_nav` default-off until
we've measured **run-start friction + retention on the flagged cohort**,
and ship a Settings toggle that lets a pure runner keep Run as the
primary one-tap action. The runner who never opts into gym/nutrition must
never be worse off.

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
  export entry. Account *deletion* is already covered — all
  FK-cascade from `auth.users`, so deleting the auth user removes them —
  but **export is not automatic**, so wire each new modality table into
  the export path as it gains real data; don't ship a modality to real
  users with its data missing from export.
- **Disclosure:** adding nutrition + body metrics changes the privacy
  posture — update the iOS Privacy Nutrition Label, Play Data Safety
  form, and the sub-processor list (Open Food Facts becomes an outbound
  hop). Gate the nutrition launch on those doc updates (`/audit/*` covers
  the surfaces).

## `activities` view at scale

The view UNION-ALLs runs (potentially thousands) with the gym branch
reading the **stored** `set_count` + `volume_kg` columns on
`gym_workouts` (no longer per-workout correlated subqueries — F7, migration
`20261214_001`). For the History list:

- Always query it **windowed** (`limit` + `started_at` cursor), never
  unbounded — the History screen paginates like `/runs` does. The web
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
| Nav + Log sheet | `home_screen.dart` (bottom-nav reshape), `widgets/log_sheet.dart` |
| Home cards | `widgets/nutrition_rings_card.dart`, `widgets/gym_summary_card.dart` (run summary card exists) |
| History | `screens/history_screen.dart` (reads the `activities` view) |
| Gym | `screens/gym_screen.dart`, `widgets/gym_compose_sheet.dart`, `screens/gym_detail_screen.dart`, `gym_prs.dart` (pure, parity-paired) |
| Nutrition | `screens/nutrition_screen.dart`, `widgets/nutrition_log_sheet.dart`, `nutrition_targets.dart` (pure, parity-paired), `food_search.dart` (Open Food Facts client, pluggable-fetcher seam like `routing.dart`) |
| Body metrics | `body_metrics` table (new migration when nutrition starts) + Settings height/weight entry |
| Lift load | `training_load.ts` / `.dart` gain `liftStress` + `source`-tagged daily contributions (**shipped** — `computeLiftStress` + `aggregateDailyLiftStress` + the `lifts` arg to `computeTrainingLoadSeries`). **Web consumer wired**: `web/src/lib/gym/lift_load.ts` (`liftsFromSetHistory`, pure + tested) feeds the dashboard load curve |
| Cross-modality | `coach/context.ts` (**web shipped** — bounded `recent_lifts` + 7-day `nutrition_7d` summary, pure `summarizeRecentLifts`/`summarizeNutrition` + tests); web Home gym cards (`/dashboard`); web History timeline (`/runs` + `fetchActivities`). `home_screen` card composition is the pending mobile mirror |
| Runner protection | Settings toggle: keep Run as the one-tap primary action |
| Local stores | `local_gym_store.dart`, `local_food_store.dart` (shipped — mirror `LocalGearStore`, §73 / §122; gym stores sets inline; not yet wired into nav/sync — lands with the screens) |
| Data access | `packages/api_client` typed gym + food methods (shipped); web gym queries in `core/data.ts` (**shipped** — `fetchGymWorkouts` / `fetchGymWorkoutWithSets` / `fetchGymSetHistory` / `createGymWorkout` / `updateGymWorkout` / `deleteGymWorkout`); food queries pending |

**Web gym surfaces (shipped).** Mirrors the mobile gym plan above on the canonical web surface: `routes/gym/+page.svelte` (list + PR badges + create modal), `routes/gym/[id]/+page.svelte` (detail + per-exercise PR chips + edit/delete), `components/GymEditor.svelte` (the composer — free-text exercise name with history autocomplete, inline sets, share-to-feed toggle), `gym/gym_prs.ts` (pure PR engine, parity pair), and the `multi_modal_nav`-gated **Gym** sidebar item in `+layout.svelte`. E2e: `tests-e2e/gym/gym.spec.ts`. Weight is entered/shown in kg today; the `weight_unit` (`'kg' \| 'lbs'`) user-pref key is registered (settings.md, F19) but **not yet wired** — storage stays canonical kg (`gym_sets.weight_kg`) and the display/entry converter that reads the key still has to land.
| DSAR | `gym_workouts` / `gym_sets` (nested) / `food_log` in the export path (**shipped**); `body_metrics` pending its migration |
