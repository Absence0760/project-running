# Conventions

House rules for this codebase. Before you reach for "what's the idiomatic way to do this in Flutter / Svelte / Swift", check here — some defaults have been deliberately overridden. If you find code that violates a rule below, fix it as part of the surrounding change. If you find a rule that's wrong, edit this file and mention it in the PR.

## Comments

**Default is zero comments.** Write one only when the comment answers *why*, not *what*. Good reasons:

- A hidden constraint or invariant that isn't visible from the types.
- A workaround for a specific upstream bug (name it — "upstream: flutter_map#1234").
- A surprising branch that a reader will otherwise assume is a mistake.
- A `// generated` / `// do not edit` marker on files a script owns.

Bad reasons (do not do these):

- Narrating the code. `// set distance` above `distance = x`.
- "Used by X" cross-references that rot.
- Issue numbers / task IDs / PR links in source files — they belong in the commit message.
- Multi-paragraph doc blocks on internal functions. If a function needs that much explanation, extract it.
- `// TODO` without an owner and a concrete next step. A lone `// TODO: fix this` is noise.

If you deleted code, do not leave a `// removed X because Y` stub behind. The commit history has that context.

## Naming

### Dart

- Classes: `PascalCase`. Files: `snake_case.dart` (standard Dart style).
- Private members: leading underscore. Don't mix public + private prefixed with `_`-to-mark-unused — just delete the unused thing.
- Constants: `lowerCamelCase` for member-level (`static const defaultTimeout`), `SCREAMING_SNAKE` only for compile-time `const` at the library level if you really want the emphasis — prefer lowerCamelCase.
- Generated column constants live on the row class: `RunRow.colStartedAt`, `RouteRow.colDistanceM`. Don't duplicate them at module level.
- Booleans read as predicates: `isRecording`, `hasTrack`, `shouldAutoPause`. Not `recording`, `track`, `autoPause`.

### TypeScript

- Types / interfaces: `PascalCase`. Functions and variables: `camelCase`. Files: `kebab-case.ts` for new files unless colocating with an existing `snake_case.ts` pattern.
- Database rows come from `database.types.ts`; use `Omit<RowType, 'field'> & { field: NarrowType }` to overlay narrow unions, never re-declare the row shape. See [schema_codegen.md](schema_codegen.md).
- Svelte components: `PascalCase.svelte`.

### Swift

- Follow [Apple's API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) — that's the canonical reference for the watch app.
- `WorkoutManager`, `HealthKitManager`, `CheckpointStore` — one class per file, files named for the class.

### SQL

- Table names: plural, `snake_case` (`runs`, `routes`, `user_profiles`).
- Column names: `snake_case`. Timestamp columns: `{verb}_at` (`created_at`, `started_at`, `last_sync_at`).
- Primary keys: `id uuid primary key default gen_random_uuid()` unless the table references `auth.users(id)` directly.
- Foreign keys: `{table}_id`, e.g. `route_id` on `runs`.
- Migration files: `{YYYYMMDD}_{nnn}_{description}.sql`. The `nnn` is the ordinal within a day (`001`, `002`, ...).

## Error handling

### Where validation belongs

- **System boundaries only.** User input, external API responses, file parsers, deserialisation of untrusted JSON. Validate once, then trust the types.
- **Internal code does not defensively validate.** If a function takes a `Run run`, it trusts that `run.id` is non-empty because `Run` says so. Don't add `if (run.id.isEmpty)` checks inside internal layers — the type system is the contract.

### How to fail

- **Dart:** throw `Exception` / `StateError` / `ArgumentError` for truly exceptional conditions. Prefer returning `null` or a sum-type-style result for "expected miss" (e.g. `fetchRunById` returning `null` when the ID is unknown). Don't catch and swallow — if a caller can't handle it, let it propagate.
- **TypeScript:** throw `Error` or a subclass at the boundary; return `null` / `{ ok: false, error }` shapes for expected failures within the app. Don't `catch (e) { console.log(e) }` and continue — either handle it meaningfully or let it propagate.
- **Swift:** use `throws` + `Result` at API boundaries; `do/catch` only at the outermost view or service layer. `try?` is acceptable for best-effort reads where `nil` is a valid outcome.

### What not to catch

- `StateError` / `TypeError` / precondition failures — these are bugs. Let them crash in debug, let crash reporting catch them in release.
- Every possible exception. A blanket `try { ... } catch (_) {}` is a bug in waiting.

### Isolate auxiliary effects

An **auxiliary effect** is anything non-essential to the core stats/state that can still throw: TTS announcements, network pings (race feed, analytics), platform channels (lock-screen notification, BLE), third-party sensor streams, route math against user-imported data. When multiple of these live in the same handler (`_onSnapshot` is the canonical example), they must not cascade into each other or into the core state update.

Rules:

- **Core state first, unconditionally.** The `setState` / state mutation that drives the visible numbers (elapsed, distance, pace) runs before any auxiliary block, with no try/catch around it. It's trusted — if it throws, that's a real bug and we want the crash.
- **Each auxiliary effect in its own try/catch.** One per logical block. On catch, `debugPrint` and move on — never silently swallow to a lower level (no `catch (_) {}`), never re-throw from an auxiliary block into the core.
- **Never widen to a single outer try/catch.** `try { setState(...); ping(); tts(); ... } catch (_) {}` hides which effect failed and lets a late effect cancel an earlier one's commit.
- **Label the layer in a comment** when the intent isn't obvious (`// L4 — race ping`) so a later reader knows why the block is walled off.

The run recorder is the reference — see `_onSnapshot` in `apps/mobile_android/lib/screens/run_screen.dart` and the L0–L4 table in [run_recording.md § Hardening § Layering](run_recording.md#layering).

## Layered resilience

Design so a failure at a higher layer **cannot** break a lower one. "Basics always work" is a product contract, not a nice-to-have.

The rule when adding any feature that touches a mature flow (recording, sync, auth, etc.):

1. **Identify the layer.** What does your feature depend on? Stopwatch (L0), sensors (L1), network (L2), third-party widgets (L3), side-effects (L4). Put it at the highest layer that needs it — don't wire a new visual into the state that drives the clock.
2. **Degrade, don't fail.** If the dependency is unavailable (GPS off, network dead, tile layer crashed), the layers below must still work. Provide a fallback (pedometer distance when GPS is absent, cached tiles when offline, typed errors that leave the recorder usable). Silent stalls and white screens are bugs.
3. **Wrap risky subtrees.** User-facing surfaces that depend on complex third-party widgets (`flutter_map` is the prime example) need a release-mode `ErrorWidget.builder` override so a subtree crash replaces *only* that subtree, not the entire screen. Debug keeps the default red screen.

The canonical write-up with the L0–L4 table and failure modes is [run_recording.md § Hardening § Layering](run_recording.md#layering). Read it before touching the recording stack; copy the pattern when building the next "basics must always work" surface (e.g. sync, auth, navigation).

## Logging

No framework consensus yet — use the platform default:

- Dart: `debugPrint` (or `print` in tests). Do not introduce a logging package without discussion.
- TypeScript / SvelteKit: `console.log` / `console.warn` / `console.error`. Same rule.
- Swift: `print` or `os.Logger` — `os.Logger` preferred for anything that will ship to device.

If you're tempted to add structured logging / a log collector / log levels, stop — bring it to the user first. The app is not at the scale where that pays off.

## Testing

See [testing.md](testing.md) for the full reference — patterns, fixtures, what's covered, what's deliberately not covered. Short version for conventions:

- **Pure functions first.** If logic can be extracted into a module-level function that takes primitives and returns primitives, do that and test it directly. `run_stats_test.dart` is the model.
- **Dependency injection for filesystem / permissions / sensors.** `LocalRunStore` takes a `Directory` so tests can pass `Directory.systemTemp.createTempSync()`. Follow the same pattern for anything touching the platform.
- **`@visibleForTesting` is the escape hatch.** If a test needs to poke at a private, mark the member `@visibleForTesting` and use it in tests. Don't make things public just to test them.
- **No mocks for things we own.** Build a fake that implements the interface you need. Mock libraries (`mocktail`, `mockito`) are acceptable for third-party boundaries only.
- **No database mocks.** Integration tests that touch Supabase should hit a real local instance (`supabase start`), not a mock client. Drift between a mock and the real schema is the bug we're trying to catch.

## Dependency discipline

- Don't add a dependency to solve a one-function problem. Write the function.
- Don't add a dependency without checking that it's maintained. "Last updated 3 years ago" is a red flag; "no tests" is a red flag; "single maintainer on a personal account" is a red flag. Combine them and it's a veto.
- `melos bootstrap` / `npm install` at the workspace root after changing `pubspec.yaml` / `package.json`. Commit the lockfile updates.

## Preemptive abstractions — don't

Three similar lines is better than a premature helper. A "generic" wrapper written when only one caller exists is worse than the caller's own inline code. Extract when the third caller arrives, not before.

Specifically:

- Don't write a `BaseScreen<T>` until there are three screens that genuinely share the same lifecycle.
- Don't write a `Store<T>` abstraction when `LocalRunStore` and `LocalRouteStore` are the only two stores in the codebase.
- Don't build a plugin system for importers when `health_connect_importer.dart` and `strava_importer.dart` are the only two and they share ~zero code.
- Don't refactor in a bug-fix PR. Split the refactor into its own change.

## Backwards compatibility

This is a pre-launch codebase with no shipped users. Backwards-compatibility shims are almost never warranted:

- Don't keep a dead enum case "in case someone relies on it".
- Don't rename a field and re-export the old name.
- Don't leave a deprecated function alongside the new one with a `@deprecated` annotation unless the switchover is genuinely multi-PR.
- Just change the code, run the build, fix the compile errors.

When you genuinely need a migration (e.g. on-disk data format changing), write the migration, not a permanent dual-read path.

## Web page padding

Every top-level web page wraps its content in a `.page` div with `padding: var(--space-xl) var(--space-2xl)` (2rem vertical, 3rem horizontal) and is **left-aligned** — do not add `margin: 0 auto`. The constant `var(--space-2xl)` left gutter is the gap between the sidebar and the content; centering with `margin: 0 auto` makes that gap balloon on wide screens whenever the page sets a small `max-width`, and makes navigating between pages feel like the content is jumping around. Set `max-width` per-page (lists go wide, forms stay narrow), keep the horizontal padding fixed, and don't centre. Public layouts without the sidebar (`/`, `/login`, `/share/...`, `/clubs/join/[token]`, `/live/...`) are exempt because they don't share the chrome and centring is the right call there.

## Web page titles and sidebar chrome

Top-level sidebar-routed pages (`/dashboard`, `/runs`, `/routes`, `/explore`, `/plans`, `/clubs`, `/settings/*`) **don't carry an `<h1>` page-name title** — the sidebar nav already shows the active section, so a heading that reads "Dashboard" / "Runs" / etc. is redundant chrome. Action buttons and explanatory subtitles stay; the redundant heading goes. Detail pages (`/runs/[id]`, `/routes/[id]`, `/plans/[id]`) keep their `<h1>` because that heading is the *content* title (the run's name, the route's name) — not a page label.

Sidebar palette is theme-aware via CSS variables in `app.css`: `--gradient-sidebar`, `--sidebar-text`, `--sidebar-text-muted`, `--sidebar-hover-bg`, `--sidebar-active-bg`, `--sidebar-active-text`, `--sidebar-border`, `--sidebar-logo`. Don't hardcode sidebar colours in `+layout.svelte` — flip the variable in the `:root` (light) or `:root[data-theme="dark"]` block instead. The light/dark sidebar gradients differ; the rest of the variables are derived from the same `--color-*` palette so most adjustments only need a one-line change.

## Commit and PR conventions

- Branch: `dev` is the working branch. `main` is the PR target. See [decisions.md § 6](decisions.md).
- Commits on `dev` use conventional commit prefixes — `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `build:`, `test:`. Scope optional: `feat(android): ...`, `fix(web): ...`.
- PR title: same format, short. Body: 1–3 bullet summary + a test-plan checklist (the `pull-request` skill has the template).
- Keep PRs focused. Unrelated cleanup → separate PR.
- Don't amend published commits. Don't force-push without being asked. Hooks are there for a reason; don't `--no-verify`.

## Docs hygiene

Every change that affects documented behaviour updates the docs **in the same turn as the code change**. See the root [`CLAUDE.md`](../CLAUDE.md) § "Docs hygiene" for the full rule and checklist. Shortest version: if a doc describes the old behaviour, it is wrong the moment you change the code — fix it now, not later.

## Exceptions

Every rule here has escape hatches for the cases where it genuinely doesn't fit. If you're about to violate one of these rules:

1. Confirm the escape is justified (not just "easier").
2. Leave a one-line comment at the violation site explaining why (this is one of the few cases where a comment is the right answer).
3. If the escape is a recurring pattern, either generalise the rule here or add a new subsection.
