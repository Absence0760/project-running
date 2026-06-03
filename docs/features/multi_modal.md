# Multi-modal layout & IA (Phase 4 — run + gym + nutrition)

Design spec for the navigation, Home, and History surfaces once the app
spans running + gym + nutrition. The data foundation (migration
`20261204_001`, `gym_workouts` / `gym_sets` / `food_log` / `activities`
view, `runs.kind`) is shipped; this doc is the **layout contract** the
screens get built against. Architecture rationale: [decisions.md § 63](../architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db). Sequencing: [roadmap.md § Phase 4](../product/roadmap.md#phase-4--multi-modal-gym--nutrition).

> **Status:** design only. Everything below ships behind the
> `multi_modal_nav` per-user feature flag (default off) until both the
> gym and nutrition lightweight tiers are complete on web + mobile.

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

## Nutrition — lightweight tier surfaces (mirror web `/nutrition`)

Manual macro logging + rings. No food database, barcode, or photo
recognition (all depth tier).

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
- **`nutrition_log_sheet`** composer: item name free text + manual
  calories/protein/carbs/fat + an optional meal slot
  (breakfast/lunch/dinner/snack). Meal-slot grouping in the daily view.
- **Targets** default from a Mifflin-St Jeor BMR × activity-level
  heuristic (`nutrition_targets.dart`, pure + tested), overridable in
  Settings → Preferences.
- **Water tracker** is a separate, tap-to-increment row of 250 ml units —
  deliberately the lowest-friction thing on the screen.
- **Weekly trends** reuse the `mileage_trend_card` pattern (same
  bucketing, same unit-aware rendering) on a second tab/section.

## Cross-modality touches (after both lightweight tiers ship)

- **Home** composes all three modalities per the ordering above.
- **AI Coach** context (web-side `coach/context.ts`) reads recent gym
  sessions + 7-day nutrition averages alongside the run window; mobile's
  coach screen just renders richer answers, no mobile work.
- **Training-load** factors lift sessions as additional stress
  (TRIMP-from-RPE or per-set load) so CTL/ATL/TSB reflect the full
  picture — a `training_load` parity-pair change.
- **Social feed** extends to lift + meal cards gated on `is_public`,
  reusing the existing follower/feed plumbing (the RLS public-read branch
  is already in the foundation migration).

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
- [ ] The runner-only experience is within one card of today's app.
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
| Gym | `screens/gym_screen.dart`, `widgets/gym_compose_sheet.dart`, `screens/gym_detail_screen.dart`, `gym_prs.dart` |
| Nutrition | `screens/nutrition_screen.dart`, `widgets/nutrition_log_sheet.dart`, `nutrition_targets.dart` |
| Local stores | `local_gym_store.dart`, `local_food_store.dart` (mirror `LocalGearStore`, §73) |
| Data access | `packages/api_client` typed gym + food methods |
