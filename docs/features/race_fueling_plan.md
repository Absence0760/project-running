# Race fueling plan — carbs/hr + fluids synced to the course

> **STATUS: handoff spec, not built.** The deferred fueling half of the
> roadbook ([race_roadbook.md](race_roadbook.md) § Deferred). Self-contained
> brief; read [CLAUDE.md](../../CLAUDE.md) for conventions. Web canonical;
> mobile mirrors; iOS twin byte-identical.

## Context / why

The roadbook is pacing-only by design. This adds the fueling layer: a per-leg
**carbs/hr** + **fluid** plan synced to the aid-station timeline — "carry 3 gels
to Aid 2, refill 500 ml" — and (later) in-run reminders. It fuses the existing
nutrition engine with the route, which no competitor does.

## Reuse (don't re-implement)

- **Roadbook engine** `roadbook.ts ↔ roadbook.dart`: already produces per-leg
  duration + the aid-station schedule. Wrap/extend it; don't fork it.
- **Nutrition parity pairs:** `nutrition_targets.ts ↔ .dart` (BMR/TDEE),
  `exercise_calories.ts ↔ .dart` (run/gym kcal from distance + duration). Use
  the latter to estimate energy burn per leg.
- **Body metrics:** weight from `body_metrics` / `user_profiles` (behind the
  Art 9 health-consent gate — see settings_body_metrics). Used for fluid (~ml/kg)
  + sweat-rate estimates.

## Design

1. **New parity helper** `fuel_plan.ts ↔ .dart`:
   `buildFuelPlan(roadbookLegs, { carbsPerHourG, fluidPerHourMl, heatFactor })`
   → per-leg `{ carbsG, fluidMl, carryToNextAid: { gels, fluidMl } }` + a
   total. Carbs/fluid scale with each leg's **duration** (from the roadbook);
   `carryToNextAid` sums the need between consecutive aid stations (so the
   runner knows what to carry out of each aid). Optionally surface est. kcal
   burn per leg via `exercise_calories`.
2. **Roadbook surface:** a "Fueling" toggle/column on the roadbook page (web)
   + `RoadbookScreen` (mobile) adding the carb + fluid figures + the carry hint.
3. **Settings:** `carbs_per_hour` + `fluid_per_hour` prefs in the universal
   settings bag (defaults ~60–90 g/hr, ~500 ml/hr); a heat toggle bumps fluid.

No new schema (prefs in the existing universal bag).

## Commit cadence

1. `fuel_plan.ts/.dart` helper + unit/mirror tests.
2. Web roadbook fueling column + settings prefs + i18n + Playwright.
3. Mobile mirror (+ iOS twin) + Flutter test.
4. Docs.

## Tests

- Unit: carbs/fluid scale with leg duration; `carryToNextAid` sums the gap
  between aids correctly; heat factor bumps fluid; zero-duration leg → zero.
- Playwright: toggle fueling on the roadbook, assert per-leg carbs + a carry
  hint; changing the carbs/hr pref updates the numbers.
- Flutter widget test for the fueling section.

## Open decisions for the implementer (ask the user if unsure)

- Default carbs/hr + fluid/hr; whether fluid is weight-based (Art 9 gate) or a
  flat default when consent is absent.
- **In-run reminders are likely a separate phase** — they need the run recorder
  + the live workout band (`workout_execution_band.dart`); recommend deferring
  and keeping this feature plan-only.
- Whether to show est. kcal burn per leg (nice, but adds clutter).

## Docs

Extend [race_roadbook.md](race_roadbook.md) (remove from § Deferred), the
nutrition section, a parity row, and an ADR if the fuel model is non-obvious.
