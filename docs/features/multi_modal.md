# Multi-modal layout & IA (Phase 4 — run + gym + nutrition)

Design spec for the navigation, Home, and History surfaces once the app
spans running + gym + nutrition. The data foundation (migration
`20261204_001`, `gym_workouts` / `gym_sets` / `food_log` / `activities`
view, `runs.kind`) is shipped; this doc is the **layout contract** the
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
- **Coach context:** the Coach *sees* recent lifts + 7-day nutrition
  averages and reasons about them in its answers (advisory — you decide).
- **Unified Home / History / social feed.**

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
`activities` view (one query, `(kind, started_at, summary)`), with filter
chips at the top.

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
- **PRs** (`gym_prs.dart`, pure + unit-tested) compute heaviest set / most
  volume / best rep-PR per `(user, exercise_name)` → a Home card + a "PR"
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

- **Home** composes all three modalities per the ordering above.
- **AI Coach** context (web-side `coach/context.ts`) reads recent gym
  sessions + 7-day nutrition *averages* (not every food row) alongside the
  run window; mobile's coach screen just renders richer answers, no mobile
  work. **Context is bounded** — a fixed cap of recent lifts + a 7-day
  rolling nutrition summary, not raw rows — so prompt size + per-call cost
  stay roughly flat as history grows. The daily cap is unchanged.
- **Training-load** factors lift sessions as additional stress — see the
  lift-load spec below. A `training_load` parity-pair change.
- **Social feed** extends to **lift** cards gated on `is_public`, reusing
  the existing follower/feed plumbing. **Meals are NOT feed-shareable in
  v1** — broadcasting what you ate is a privacy footgun with little upside;
  `food_log.is_public` stays in the schema (cheap) but no UI surfaces meal
  sharing until there's a clear reason. Defaults are private regardless.

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
- **DSAR completeness (must-fix):** the new `gym_workouts`, `gym_sets`,
  `food_log` (and future `body_metrics`) tables **must be added to the
  data-export path** (Go `dataexport` + the `export-data` EF) so the
  GDPR right-to-know export is complete. Account *deletion* is already
  covered — all four FK-cascade from `auth.users`, so deleting the auth
  user removes them — but **export is not automatic** and is a real gap to
  close as each table gains real data. Track it; don't ship a modality to
  real users with its data missing from export.
- **Disclosure:** adding nutrition + body metrics changes the privacy
  posture — update the iOS Privacy Nutrition Label, Play Data Safety
  form, and the sub-processor list (Open Food Facts becomes an outbound
  hop). Gate the nutrition launch on those doc updates (`/audit/*` covers
  the surfaces).

## `activities` view at scale

The view UNION-ALLs runs (potentially thousands) with per-workout
subqueries for set count + volume. For the History list:

- Always query it **windowed** (`limit` + `started_at` cursor), never
  unbounded — the History screen paginates like `/runs` does.
- The per-workout subqueries are fine at individual-user scale (a user
  has tens of workouts, not millions); if a power lifter's history ever
  makes them hot, fold set_count + volume into stored columns on
  `gym_workouts` maintained by a trigger. Not needed at launch.

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
| Lift load | `training_load.ts` / `.dart` gains `liftStress` + `source`-tagged daily contributions |
| Cross-modality | `coach/context.ts` (bounded gym + 7-day nutrition summary); `home_screen` card composition |
| Runner protection | Settings toggle: keep Run as the one-tap primary action |
| Local stores | `local_gym_store.dart`, `local_food_store.dart` (shipped — mirror `LocalGearStore`, §73 / §122; gym stores sets inline; not yet wired into nav/sync — lands with the screens) |
| Data access | `packages/api_client` typed gym + food methods (shipped); web `data.ts` gym + food queries |
| DSAR | add `gym_workouts` / `gym_sets` / `food_log` / `body_metrics` to the export path |
