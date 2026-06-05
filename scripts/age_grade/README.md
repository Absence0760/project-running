# Age-grade factor tables

The age-grade percentage shown on run-detail (for non-parkrun races, when the
runner's DOB + a standard race distance + a duration are known) is computed by
the `age_grade.ts` ↔ `age_grade.dart` parity pair against the **embedded factor
tables generated here**. We deliberately do **not** approximate the factors from
memory — a wrong age-grade % misleads the exact masters-runner audience that
values the metric — so the numbers are taken verbatim from the authoritative
published tables.

## Source

`source_2025/AgeGrade.*` are the **USATF Masters Long Distance Running (MLDR)
2025** age-grade tables, compiled by Alan Jones and Tom Bernhard and approved
2025-01-10. They are the current road-running age-grade standard (the WMA /
USATF road tables — World Masters Athletics adopts this road series).

- Upstream: <https://github.com/AlanLyttonJones/Age-Grade-Tables> →
  `2025 Files/AgeGrade.zip` (the RunScore-format tables) + `Readme.txt`.
- Licence: **CC0 1.0 Universal** (public domain) — free to embed, including
  commercially.
- `source_2025/Readme-2025.txt` is the upstream readme, kept for provenance.

### File format (RunScore)

One file per standard distance (`AgeGrade.5k`, `AgeGrade.hm`, `AgeGrade.42k`, …):

```
M  0:12:49        <- open-class (world-standard) time, male
F  0:13:54        <- open-class time, female
M 5  0.5990       <- male age-5 factor
...
M 99 0.xxxx
F 5  0.7220       <- female age-5 factor
...
F 99 0.xxxx
```

Ages run 5..99 (95 single-year rows per sex). The marathon ships as both `42k`
and `26m` with identical standards; the generator keeps `42k` (mapped to the
certified 42 195 m) and drops the `26m` duplicate.

### Age-grade formula

```
agePct = openStandardSec / (actualTimeSec * ageFactor) * 100
```

A runner who exactly matches the age standard for their sex/age/distance scores
100 %; world-record-grade efforts can exceed it.

## Regenerating / swapping editions

```
node scripts/age_grade/gen_age_grade_tables.mjs
```

writes both committed data modules:

- `apps/web/src/lib/runs/age_grade_tables.ts`
- `apps/mobile_android/lib/age_grade_tables.dart`

To adopt a future edition, drop the new `AgeGrade.*` files into a
`source_YYYY/` dir, point `SRC` at it, and re-run. Never hand-edit the generated
modules — they must stay byte-faithful to the source and identical across the
two platforms.
