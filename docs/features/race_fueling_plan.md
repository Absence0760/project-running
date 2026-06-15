# Race fueling plan — carbs/hr + fluids synced to the course

> **STATUS: shipped (2026-06-14).** Web canonical (`/routes/[id]/roadbook`
> Fueling toggle) + mobile (`RoadbookScreen`) + iOS twin byte-identical. The
> fueling half of the roadbook ([race_roadbook.md](race_roadbook.md) §
> Fueling). Read [CLAUDE.md](../../CLAUDE.md) for conventions. In-run
> reminders are a deferred separate phase (see § Decisions made).

## Context / why

The roadbook is pacing-only by design. This adds the fueling layer: a per-leg
**carbs/hr** + **fluid** plan synced to the aid-station timeline — "carry 3 gels
to Aid 2, refill 500 ml". It fuses the nutrition rates with the route, which no
competitor does. In-run reminders are a deferred separate phase.

## Reuse (it builds on, doesn't re-implement)

- **Roadbook engine** `roadbook.ts ↔ roadbook.dart`: produces the per-leg
  duration + aid-station schedule. `fuel_plan` consumes its legs — it does not
  fork the pacing model, so fueling inherits the grade-adjusted-effort
  allocation for free (a long climb leg gets proportionally more fuel).
- **`runCalories`** (run kcal from distance + duration) computes the optional
  per-leg energy figure when a bodyweight is present.

## Design (as shipped)

1. **Parity helper** `apps/web/src/lib/routes/fuel_plan.ts` ↔
   `apps/mobile_android/lib/fuel_plan.dart` (iOS twin byte-identical):
   `buildFuelPlan(roadbookLegs, { carbsPerHourG, fluidPerHourMl, heatFactor?,
   gelCarbsG?, weightKg? })` → per-leg `{ carbsG, fluidMl, kcal, carryToNextAid?:
   { carbsG, fluidMl, gels } }` + `{ totalCarbsG, totalFluidMl }`. Carbs/fluid
   scale with each leg's **duration** (from the roadbook). `carryToNextAid` is
   present on the start leg + each refill checkpoint whose services include
   water/food, summing the fuel needed to reach the next refill (inclusive).
   `heatFactor` (default 1; `HEAT_FLUID_FACTOR` = 1.5) multiplies fluid only.
   `kcal` is computed via `runCalories` only when a bodyweight is passed.
   Defaults: 60 g/hr carbs, 500 ml/hr fluid, 25 g/gel. 9 unit/mirror tests each
   side.
2. **Roadbook surface:** a "Fueling" toggle on the roadbook page (web,
   URL-backed) + `RoadbookScreen` (mobile, screen-local) adding per-leg carb +
   fluid columns + the carry hint, plus a "Heat" toggle. kcal is computed but
   not shown.
3. **Settings:** `carbs_per_hour` (g/hr) + `fluid_per_hour` (ml/hr) prefs in the
   universal settings bag (defaults 60 / 500), editable on Settings →
   Preferences. See [settings.md](../backend/settings.md).

No new schema (prefs in the existing universal bag).

## Commit cadence

1. ✅ `fuel_plan.ts/.dart` helper + unit/mirror tests.
2. ✅ Web roadbook fueling toggle + Heat toggle + settings prefs + i18n (6
   locales) + Playwright.
3. ✅ Mobile mirror (+ iOS twin) + ARB keys (7 ARBs) + Flutter test.
4. ✅ Docs.

## Tests

- Unit: carbs/fluid scale with leg duration; `carryToNextAid` sums the gap
  between aids correctly; heat factor bumps fluid; zero-duration leg → zero.
- Playwright: toggle fueling on the roadbook, assert per-leg carbs + a carry
  hint; changing the carbs/hr pref updates the numbers.
- Flutter widget test for the fueling section.

## Decisions made

- **Flat per-hour rates, not weight-derived.** `carbs_per_hour` / `fluid_per_hour`
  are plain per-hour prefs (60 / 500 defaults), deliberately **not** a
  weight-based sweat-rate / ml-per-kg model — that keeps the feature out of the
  Art 9 health-special-category consent gate. The weight-derived fluid model
  (behind the gate) is the deferred upgrade.
- **Heat is a non-persisted toggle.** The "Heat" toggle multiplies fluid only
  (`HEAT_FLUID_FACTOR` = 1.5); it is a screen/URL toggle, not a stored pref, so
  the saved baseline stays moderate-conditions.
- **kcal is computed but not shown.** `buildFuelPlan` returns a per-leg `kcal`
  (via `runCalories`, only when a bodyweight is present) for a possible later
  surface, but the UI omits it to avoid clutter.
- **In-run reminders deferred to a separate phase.** They need the run recorder
  + the live workout band (`workout_execution_band.dart`); this feature ships
  plan-only.

See [decisions.md § 155](../architecture/decisions.md#155-the-race-fueling-plan-extends-the-roadbook-engine-with-flat-per-hour-rate-prefs-not-weight-derived-sweat-estimates)
for the full rationale.

## Docs

Cross-references: [race_roadbook.md](race_roadbook.md) § Fueling,
[settings.md](../backend/settings.md) (`carbs_per_hour` / `fluid_per_hour`),
[parity.md](../product/parity.md) (Race fueling plan row), and
[decisions.md § 155](../architecture/decisions.md).
