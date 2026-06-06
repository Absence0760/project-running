---
description: Inventory dependency licenses across every toolchain and flag copyleft / unknown / attribution-missing licenses that create legal risk for a shipped proprietary app (web SaaS + App Store / Play binaries) under SOC 2 / GovRAMP
---

Walk every dependency tree in the monorepo, collect the declared license of each package, and flag the ones that create legal risk for shipping this **proprietary** product: a hosted SvelteKit web app, native mobile binaries distributed through the App Store and Play Store, native watch apps, a Go job worker, and Supabase Edge Functions. The org's SOC 2 (all five TSCs) + GovRAMP posture makes a clean, attributable dependency-license inventory a compliance artefact, not a nicety.

## Goal

`/audit/deps` walks the *same* trees for CVEs and version drift; this audit walks them for **legal risk** — a different lens on the same surface. The risks for a closed-source app that ships binaries + serves a hosted product:

- **Strong copyleft (GPL-2.0 / GPL-3.0 / AGPL-3.0 / SSPL)** linked into a *distributed* artefact (a mobile/watch binary) or, for AGPL, into the *hosted server* — these can require releasing source. This is the headline class to find.
- **Weak copyleft (LGPL / MPL-2.0 / EPL)** — usually fine when dynamically linked, but mobile static-linking and the App-Store relink restriction complicate LGPL specifically. Flag for review, don't assume.
- **Permissive-with-attribution (MIT / BSD / Apache-2.0 / ISC)** — fine to ship, but they *require* reproducing the license + copyright notice. For mobile that means a populated "Acknowledgements / Open-source licenses" screen; for web a `NOTICE`/licenses page. Missing attribution is a real (if low-severity) violation.
- **Unknown / unlicensed / custom / dual-licensed** — a package with no SPDX license, a bare "see LICENSE", or a custom license needs a human read. Treat unknown as risk, not as safe.

## What to check

The repo has these dependency trees — collect the declared license for each package in each:

1. **npm workspaces** — `apps/web`, `apps/backend`, root `package.json` (lockfile: `package-lock.json` / per-workspace). These ship in the *hosted* web app (server + client bundle) and the build toolchain. AGPL here = hosted-source exposure; GPL in the client bundle = distribution. Use the SPDX field from each installed package; flag `UNKNOWN`/missing.
2. **Flutter / Dart** — `apps/mobile_android` + `apps/mobile_ios` (byte-identical twin — count a pub dep once, not twice) and every package under `packages/` (`api_client`, `core_models`, `gpx_parser`, `run_recorder`, `ui_kit`). These compile **into the distributed App Store / Play binaries** — the highest-stakes tree for copyleft. Flutter even has a built-in `showLicensePage` / `LicenseRegistry`; confirm whether the app surfaces an acknowledgements screen and whether it's complete.
3. **Deno (Edge Functions)** — `apps/backend/supabase/functions/*` import by URL (`deno.land/std`, `deno.land/x/sentry`, `deno.land/x/zipjs`, `esm.sh/cheerio`, …). No lockfile-of-record for licenses — resolve each imported module's repo + license manually. These run server-side (Supabase), so copyleft is hosting-scope (AGPL matters, GPL less so) — but still inventory them.
4. **Go modules** — `apps/job_worker/go.mod`. Server-side (Fly.io). Walk `go.mod` + the module graph; Go's culture is permissive but verify (some libs are MPL/LGPL).
5. **Native** — `apps/watch_wear` (Gradle dependencies → distributed Wear OS binary) and `apps/watch_ios` (SwiftPM/Xcode → distributed watchOS binary). Both ship to stores; treat like the mobile tree for copyleft.
6. **The first-party packages.** Confirm the repo's own `LICENSE` (and each `packages/*` license field) is consistent and matches the intended proprietary posture — a stray permissive `LICENSE` left in a template, or a missing one, is worth noting.

For each tree, produce: package → version → declared license (SPDX) → where it ships (distributed binary / hosted server / build-only) → risk class.

## Report

- **Critical** — strong copyleft (GPL/AGPL/SSPL) linked into a *distributed* binary (mobile/watch) or AGPL in the *hosted* server, where the obligation could force source release or breach store terms. Name the package, the tree, and the obligation.
- **High** — weak copyleft (LGPL especially, given mobile static-linking + App-Store relink rules) in a shipped binary; an unknown/unlicensed/custom-licensed dependency that ships; a dual-licensed package where the chosen license isn't pinned.
- **Medium** — permissive-with-attribution dependencies shipping **without** the required acknowledgements surface (no mobile open-source-licenses screen, no web licenses/NOTICE page).
- **Low** — build-only / dev-dependency copyleft (doesn't ship, so lower risk but worth recording); cosmetic license-field gaps in first-party packages; an SPDX expression that's valid but worth documenting.

For each finding: the package + version, the tree it lives in, the declared license, whether it's distributed vs hosted vs build-only, the specific obligation, and the remediation (replace the dependency; move it build-only; add the attribution to the acknowledgements screen / NOTICE; get counsel sign-off for a copyleft that must stay). Per the org policy, anything touching SOC 2 / GovRAMP obligations should recommend looping in the CISO / Security Analyst before acting on a Critical/High.

## Useful starting points

- `package.json` (root) + `apps/web/package.json` + `apps/backend/package.json` — npm trees; `npx license-checker --summary` (or `--json`) per workspace is the fast inventory
- `apps/mobile_android/pubspec.yaml` + `packages/*/pubspec.yaml` — Dart trees (the distributed binary); `flutter pub deps` + each package's pub.dev license; check for a `showLicensePage`/acknowledgements screen in the app
- `apps/backend/supabase/functions/` — Deno URL imports (resolve each to its source repo + license)
- `apps/job_worker/go.mod` — Go module graph (`go-licenses report ./...` if available)
- `apps/watch_wear/android/app/build.gradle*` + `apps/watch_ios/` SwiftPM manifests — native store binaries
- `LICENSE` (repo root) + each `packages/*` license field — first-party consistency
- `/audit/deps` — same trees, CVE/version lens; cross-reference so the two stay aligned

## Delegate to

Use the `compliance-auditor` agent: `"Inventory dependency licenses across every toolchain (npm, Flutter/Dart, Deno, Go, native Gradle/SwiftPM) and flag copyleft / unknown / attribution-missing licenses that create legal risk for a proprietary app shipping web SaaS + App Store/Play binaries under SOC 2 / GovRAMP. Write the report to reviews/audit-licenses.md."` Read-only on the codebase — the deliverable is the inventory + risk findings, not changes. This is a compliance artefact, **not legal advice**: every Critical/High should end with "confirm with counsel / loop in the CISO".

## Output → `reviews/`

Persist the inventory + findings to `reviews/audit-licenses.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)): a full package→license table plus findings grouped by severity, each with a `[ ]` status box. If the file exists from a prior run, update it in place (`[x]` resolved with the fix commit, `[~]` deferred with reason) rather than overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
