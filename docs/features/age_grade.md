# Age grading

Age grading scores a race performance against the world-standard time for the
runner's exact age and sex, putting a 68-year-old's marathon and a 24-year-old's
on one 0–100 % scale. It's the metric the masters-runner audience lives by, and
the reason a wrong number is worse than no number: a bogus age grade actively
misleads the exact people who care most.

## What ships

- **parkrun imports** carry a scraped `metadata.age_grade` string (e.g.
  `"54.23%"`). That value is authoritative and always wins when present.
- **Every other standard-distance race** — a manual entry, a Strava/Garmin/FIT
  import — now gets a **computed** age grade on run-detail when the runner's date
  of birth and sex are known and the run's distance matches a standard distance.
  Before this, only parkrun runs showed one.

Surfaced on the run-detail key-stat tile on web
(`apps/web/src/routes/runs/[id]/+page.svelte`) and the mobile twin
(`apps/mobile_android/lib/screens/run_detail_screen.dart` + the iOS twin).

## How it's computed

```
agePct = openStandardSec / (durationSec × ageFactor) × 100
```

- `openStandardSec` — the open-class (world-standard) time for the distance and
  sex.
- `ageFactor` (≤ 1) — the single-year age factor for the runner's age **on race
  day** (not their age today) and sex.

A runner who matches the age standard for their age/sex/distance scores 100 %;
world-record-grade efforts exceed it.

### Inputs and gates

- **Distance** must match a standard distance within ±2 %
  (`AGE_GRADE_DISTANCE_TOLERANCE`). Age grading is only defined at the standard
  distances; the tolerance absorbs the ~1 % a GPS over-reads a certified course
  without grading a 5.4 km jog as a 5 km. The nearest standard wins (8 km vs
  5 mile are 0.6 % apart and disambiguated this way). A non-standard distance →
  no age grade.
- **Sex** must be `male` or `female`. Age grading has no standard for an unset or
  non-binary sex, so those return null (tile hidden) rather than a guess.
- **Age** must fall in the table's 5..99 range.

Standard distances covered (22, ascending): 1 mile, 5 km, 6 km, 4 mile, 8 km,
5 mile, 10 km, 7 mile, 12 km, 15 km, 10 mile, 20 km, half marathon, 25 km,
30 km, marathon, 50 km, 50 mile, 100 km, 150 km, 100 mile, 200 km — including the
ultra distances most apps don't age-grade.

## The data

Factors + open standards are the **USATF Masters Long Distance Running (MLDR)
2025** tables (compiled by Alan Jones + Tom Bernhard, approved 2025-01-10) — the
current road-running age-grade standard (World Masters Athletics adopts this road
series). They are **not** approximated from memory.

- Source: <https://github.com/AlanLyttonJones/Age-Grade-Tables> (`2025 Files`),
  CC0 1.0 (public domain).
- The raw RunScore files + the generator that turns them into the committed data
  modules live in [`scripts/age_grade/`](../../scripts/age_grade/README.md).
- Generated modules: `apps/web/src/lib/runs/age_grade_tables.ts` and
  `apps/mobile_android/lib/age_grade_tables.dart` (identical numbers by
  construction). Swapping to a future WMA edition is a drop-in-and-regenerate.

## Code

- Logic: `apps/web/src/lib/runs/age_grade.ts` ↔ `apps/mobile_android/lib/age_grade.dart`
  — a TS↔Dart parity pair (`matchStandardDistance`, `ageOnDate`,
  `computeAgeGrade`, `ageGradeForRun`, `formatAgeGradePercent`); 12 mirrored
  tests each side. See [decisions.md § 132](../architecture/decisions.md).
