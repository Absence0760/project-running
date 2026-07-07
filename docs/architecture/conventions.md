# Conventions

House rules for this codebase. Before you reach for "what's the idiomatic way to do this in Flutter / Svelte / Swift", check here — some defaults have been deliberately overridden. If you find code that violates a rule below, fix it as part of the surrounding change. If you find a rule that's wrong, edit this file and mention it in the PR.

Rules are grouped by area below. (Section anchors are deep-linked from `CLAUDE.md` and the review agents, so the headings keep their exact wording.)

**Code style** — [Comments](#comments) · [Naming](#naming) · [Logging](#logging)

**Error handling & architecture** — [Error handling](#error-handling) · [Layered resilience](#layered-resilience) · [Pagination](#pagination--first-page--load-more) · [Dependency discipline](#dependency-discipline) · [Preemptive abstractions — don't](#preemptive-abstractions--dont) · [Backwards compatibility](#backwards-compatibility)

**Bug & quality discipline** — [Fix bugs, don't code around them](#fix-bugs-dont-code-around-them) · [If you see something wrong, fix it](#if-you-see-something-wrong-fix-it)

**Web UI** — [Page padding](#web-page-padding) · [Page titles & sidebar](#web-page-titles-and-sidebar-chrome) · [Material Symbols](#material-symbols-icons) · [Buttons](#web-buttons) · [Svelte 5 `$effect`](#svelte-5-effect--never-read-state-you-write-in-the-same-effect) · [Modals](#web-modals) · [List-page scroll](#web-list-pages--preserve-scroll-on-back-navigation)

**Mobile & cross-platform** — [In-app notifications](#mobile-in-app-notifications--showtopbanner) · [Local-tz date strings](#local-tz-date-strings)

**Testing** — [Testing](#testing) · [Test hygiene](#test-hygiene--review-then-unit-then-e2e)

**Process** — [Commit & PR conventions](#commit-and-pr-conventions) · [Commit cadence](#commit-cadence--one-piece-one-commit-dont-batch-a-session-into-one-lump) · [Docs hygiene](#docs-hygiene)

**Integrations** — [Strava log keys](#strava-integration-log-keys) · [Exceptions](#exceptions)

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
- **The activity timestamp is `started_at` on every modality table** — `runs`, `gym_workouts`, `food_log` (renamed from `logged_at` in `20261208_001`, F8). Don't reintroduce a per-table synonym (`logged_at` / `at`) for "when the thing happened"; the `activities` view depends on the shared name.
- **Two modification clocks, by design — don't conflate them:**
  - `updated_at` = **server clock**, maintained by a server-side trigger (e.g. `runs.updated_at`, `run_comments.updated_at`). Authoritative "when the row was last written server-side."
  - `last_modified_at` = **client-stamped sync clock** on the offline-first tables (`gym_workouts`, `food_log`, `gear`). Set by the client at write time with **no** server trigger — a trigger would clobber the timestamp the newer-wins reconciliation depends on (see [decisions.md § 73](decisions.md) / § 122). A row on these tables therefore has `last_modified_at` but no `updated_at`.
  - Same word "modified," opposite owner. A new sync table uses `last_modified_at` (client-owned); a server-authoritative table uses `updated_at`. Renaming `runs.updated_at` → `server_updated_at` was considered (F8) and rejected: ~50 client read sites for zero behavioural gain. The names stay; this split is the contract.
- Primary keys: `id uuid primary key default gen_random_uuid()` unless the table references `auth.users(id)` directly.
- Foreign keys: `{table}_id`, e.g. `route_id` on `runs`.
- **Owner / authorship columns follow the role, not one blanket name** (F17, [decisions.md § 130](decisions.md)): `user_id` = the activity's actor on an activity row (`runs`, and most tables); `author_id` = who created a piece of user-authored content or a user-defined object (`club_posts`, `run_comments`, `reports`, `segments`, `events`); `owner_id` = who owns an aggregate (`clubs`, `gear`). `created_by` is **not** used — `events` and `segments` were migrated off it to `author_id` in `20261217_001` so every authored-content table matches. (`created_at` / `updated_at` timestamps are unaffected — this is about the *who*, not the *when*.)
- **Boolean columns are `is_<predicate>`** (the SQL mirror of the Dart predicate rule above): `is_public`, `is_dnf`, `is_starred`, `is_featured`, `is_auto_approve`, `is_notifications_enabled`. The pre-F17 outliers (`routes.featured`, `race_sessions.auto_approve`, `device_tokens.notifications_enabled`) were renamed in `20261217_001`; the view / RPC **output** columns that surfaced them (`public_routes.featured`, `discoverable_routes_in_bbox`'s `featured`, `race_sessions_redacted.auto_approve`) were renamed to match, so there's no column-vs-output drift.
- Migration files: `{YYYYMMDD}_{nnn}_{description}.sql`. The `nnn` is the ordinal within a day (`001`, `002`, ...).

### Storage buckets — one bucket per modality, named for the table it backs (F2)

Storage buckets are **per-modality and honestly named**, mirroring the F1
Option A table decision (`runs` stays `runs`; tables are modality-specific, not
folded into a generic `activities` table). The GPS-track bucket is `runs` (it
backs the `runs` table) and run images live in `run-photos`. There is **no
generic `activities` bucket** and no plan for one — a `runs` table writing to an
`activities` bucket would be exactly the table↔bucket-name mismatch this rule
exists to prevent.

- When a future modality grows file attachments (gym progress photos, meal
  photos), it gets its **own** bucket named for its table — `gym-photos`,
  `meal-photos` — not a shared bag. Same RLS path shape (`{user_id}/{...}`),
  same owner-scoped policies.
- Never hardcode a bucket id. Route every `supabase.storage.from(...)` through
  the registry: `BUCKETS` in `apps/web/src/lib/core/schema.ts`,
  `StorageBuckets` in `packages/core_models/lib/src/metadata_keys.dart`, and
  `schema.Bucket*` in `apps/job_worker/internal/schema/schema.go` (F11). The
  literal is decoupled from the call sites, so the name and the registry move
  together if a rename is ever genuinely needed.

### `external_id` namespacing — `provider:native_id` (F10)

Every imported activity row carries `external_id text` namespaced as
`<provider>:<native_id>` so two providers can't collide on the same numeric id.
The format is already universal across all importers and must stay so:

- `strava:{activity_id}` · `garmin:{file_id}` · `parkrun:{event}:{date}` ·
  `csv:{iso}-{distance}-{duration}`. New importers follow the same shape; put
  the prefix-building in one helper (e.g. `garminExternalId`) rather than
  inlining the literal.
- Idempotency is the per-user partial unique index
  `(user_id, external_id) where external_id is not null` (per-user, not global —
  two users legitimately sharing one `strava:<id>` must both keep their row; see
  `20260528000003`). Importers dedupe with `onConflict` on that key.
- The namespace is a **string-prefix convention**, not structural. If a future
  provider's native ids could ever collide across the `:`-prefix boundary,
  escalate to structural `(source, external_id)` columns with the unique index
  over `(user_id, source, external_id)` — a deliberate migration, not an inline
  tweak. Not warranted today: the four-importer prefix scheme has zero collision
  surface.

### Activity-table column checklist — column vs jsonb bag (F6 / decision D4)

The activity tables (`runs`, `gym_workouts`, `gym_sets`, `food_log`) each pair
a set of real columns with a loose `jsonb` bag (`runs.metadata`; the gym/food
tables have no bag yet). When you add an attribute, decide deliberately where
it lives — don't default everything into the bag, and don't promote display-only
telemetry to a column.

**An attribute earns a real column when BOTH hold:**

1. It's present on **most rows** (not a rare source-specific extra), and
2. it is **filtered / aggregated / constrained / read by SQL** — a `WHERE`,
   `ORDER BY`, `GROUP BY`, a `CHECK`, an index, or it's consumed by a view /
   RPC / trigger / RLS policy.

If only (1) holds (present everywhere but purely *displayed*, never queried), it
stays in the bag. If only (2) holds on rare rows, it stays in the bag too.

- **Promoted** (cleared the bar): `runs.activity_type` (CHECK-constrained,
  filtered by the PR engine, read by the `activities` + `public_runs` views,
  drives the gear auto-tag trigger) and `runs.is_dnf` (the PR engine filters
  on it) — both lifted out of `runs.metadata` in `20261207_001`.
- **Stayed in the bag** (display-only telemetry): `avg_bpm`, `steps`,
  `elevation_m` — shown on the run detail, never filtered or aggregated in SQL.

**When you do add a column to an activity table:**

- `snake_case`; use `started_at` for "when it happened" and the right
  modification clock (`updated_at` server-trigger vs client-stamped
  `last_modified_at` — see the SQL clock rule above).
- Give it a `NOT NULL DEFAULT` when a sane default exists, so the generated
  `Insert` types stay optional and un-migrated writers don't hard-fail.
- A narrow string domain needs a `CHECK` **and** a matching TS union in
  `apps/web/src/lib/types.ts`, kept in lockstep (add the pair to
  `check_constraint_unions.mjs` — see backend CLAUDE.md).
- Regenerate both row-type files (`npm run gen:types` + `dart run
  scripts/gen_dart_models.dart`) and update `docs/backend/api_database.md`. If
  you're moving a key **out** of `runs.metadata`, also strike it from
  `docs/backend/metadata.md`.

For a **user preference** (not an activity attribute), the column-vs-bag call is
the user-pref placement rule in [`docs/backend/settings.md`](../backend/settings.md#placement-rule--bag-vs-column-f4) instead.

## `apps/web/src/lib` organisation

Loose modules are grouped into topical subfolders so the lib root doesn't
become a flat dumping ground: `core/` (Supabase queries + client),
`training/`, `routes/`, `segments/`, `social/`, `integrations/`, `backup/`,
`share/`, `settings/`, `runs/`, `format/`, `util/`, `billing/`.

- **A new lib module goes in the matching subfolder**, never loose at the
  root. The only production modules allowed at the lib root are `types.ts`
  (the Run/Route/… overlays) and the generated `database.types.ts` — `gen:types`
  writes the latter there and the path is hard-coded in
  `apps/backend/package.json`. Don't move either.
- **Tests co-locate with their module** (`routes/static_map.ts` →
  `routes/route_preview_helpers.test.ts`). Cross-cutting guard tests that read
  several source files by path (`security_guards.test.ts`,
  `contrast_guard.test.ts`, …) and tests of the two root modules stay at the
  lib root.
- **Import across folders with the `$lib/<folder>/<stem>` alias**, not deep
  relative `../../` chains; siblings within a folder use `./`.
- When a **TS↔Dart parity helper** moves, update its path in the
  `shared-library-syncer` agent table and the reference in this file in the
  same change — they're how the lockstep convention is found.

`src/lib/lib_structure_guards.test.ts` enforces all of the above (root
cleanliness, parity-path existence, and the recursive `src/lib/**/*.test.ts`
unit-test glob) so the structure can't silently erode.

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

The run recorder is the reference — see `_onSnapshot` in `apps/mobile_android/lib/screens/run_screen.dart` and the L0–L4 table in [run_recording.md § Hardening § Layering](../features/run_recording.md#layering).

## Layered resilience

Design so a failure at a higher layer **cannot** break a lower one. "Basics always work" is a product contract, not a nice-to-have.

The rule when adding any feature that touches a mature flow (recording, sync, auth, etc.):

1. **Identify the layer.** What does your feature depend on? Stopwatch (L0), sensors (L1), network (L2), third-party widgets (L3), side-effects (L4). Put it at the highest layer that needs it — don't wire a new visual into the state that drives the clock.
2. **Degrade, don't fail.** If the dependency is unavailable (GPS off, network dead, tile layer crashed), the layers below must still work. Provide a fallback (pedometer distance when GPS is absent, cached tiles when offline, typed errors that leave the recorder usable). Silent stalls and white screens are bugs.
3. **Wrap risky subtrees.** User-facing surfaces that depend on complex third-party widgets (`flutter_map` is the prime example) need a release-mode `ErrorWidget.builder` override so a subtree crash replaces *only* that subtree, not the entire screen. Debug keeps the default red screen.

The canonical write-up with the L0–L4 table and failure modes is [run_recording.md § Hardening § Layering](../features/run_recording.md#layering). Read it before touching the recording stack; copy the pattern when building the next "basics must always work" surface (e.g. sync, auth, navigation).

## Logging

No framework consensus yet — use the platform default:

- Dart: `debugPrint` (or `print` in tests). Do not introduce a logging package without discussion.
- TypeScript / SvelteKit: `console.log` / `console.warn` / `console.error`. Same rule.
- Swift: `print` or `os.Logger` — `os.Logger` preferred for anything that will ship to device.

If you're tempted to add structured logging / a log collector / log levels, stop — bring it to the user first. The app is not at the scale where that pays off.

## Testing

See [testing.md](../testing/testing.md) for the full reference — patterns, fixtures, what's covered, what's deliberately not covered. Short version for conventions:

- **Pure functions first.** If logic can be extracted into a module-level function that takes primitives and returns primitives, do that and test it directly. `run_stats_test.dart` is the model.
- **Dependency injection for filesystem / permissions / sensors.** `LocalRunStore` takes a `Directory` so tests can pass `Directory.systemTemp.createTempSync()`. Follow the same pattern for anything touching the platform.
- **`@visibleForTesting` is the escape hatch.** If a test needs to poke at a private, mark the member `@visibleForTesting` and use it in tests. Don't make things public just to test them.
- **No mocks for things we own.** Build a fake that implements the interface you need. Mock libraries (`mocktail`, `mockito`) are acceptable for third-party boundaries only.
- **No database mocks.** Integration tests that touch Supabase should hit a real local instance (`supabase start`), not a mock client. Drift between a mock and the real schema is the bug we're trying to catch.
- **SECURITY DEFINER + `vault.*` paths get inline DO-block assertions in `seed.sql`.** Edge Function CI doesn't deploy and exercise functions end-to-end, so contract tests for `check_rate_limit`, `get_integration_tokens` etc. live in `apps/backend/supabase/seed.sql` as `do $$ ... raise exception ... end $$` blocks. They run on every `supabase db reset` (locally) but not on production migrations — exactly the semantics we want for tests. Use `set_config('request.jwt.claim.role', ...)` / `request.jwt.claim.sub` to simulate auth contexts; clean up any test rows at the end of the block so the seed leaves no residue. See the trailing "Regression tests" section of `seed.sql` for the canonical shape.

## Pagination — first page + Load more

**Default to a bounded first page on any list that talks to the network or scans an unbounded store.** The shape we follow across web, mobile, and watch:

- **Page size: 20.** Concrete enough to render fast on the slowest device, big enough that most users never tap Load more. Don't twiddle the value per screen — consistency across surfaces is more valuable than micro-tuning.
- **Cursor over offset.** A row id or `started_at`/`created_at` value is stable against concurrent inserts and deletes; offset shifts a row out from under the user. The `before:` parameter on `ApiClient.getRuns` and the `(startedAt, id)` cursor on `fetchFollowingFeed` are the canonical shapes.
- **`hasMore = lastPage.length == pageSize`.** That's the "out of pages" signal — no separate count query.
- **A visible "Load more" footer**, not infinite scroll. Infinite scroll loses scroll position on back-navigation and surprises users on cellular. Reference implementations: `apps/web/src/routes/runs/+page.svelte`, `apps/web/src/routes/feed/+page.svelte`, `apps/mobile_android/lib/screens/runs_screen.dart` (helper: `shouldShowRunsLoadMore`), `apps/mobile_android/lib/screens/feed_screen.dart`.
- **Reset paging on filter/sort change.** If the user narrows the view, drop back to page 1 — don't carry the previous depth. The pure helper for the visibility decision should take primitives so the boundary cases are unit-testable without mounting the screen.
- **Two layers when the client has a local store.** The visible window caps how many cached rows render even when the store has more (`_visibleCount` on the runs screen); a separate `_remoteHasMore` flag drives the cloud cursor. Tap Load more → reveal local first, fetch from cloud only when the local cache is exhausted.
- **Suppress the cloud branch when the active filter has already capped the searchable window.** The cloud cursor walks strictly older than the oldest local row, so when a date-range filter (`today` / `week` / `month` / `year`) has a `from` that the oldest local row already predates, no cloud page can match — hide the button. Reference: `shouldShowRunsLoadMore` in `apps/mobile_android/lib/screens/runs_screen.dart` takes a `filterCutoff` + `oldestLocalStartedAt` for exactly this case. Web's `/history` sidesteps the issue by switching to full-fetch mode whenever `dateRange !== 'all'` — same outcome, different trade-off.

Don't paginate when the bound is intrinsic and small (members of a club ≤ a few dozen, segments on a route ≤ tens, comments on a single run ≤ a handful). When in doubt, paginate — the cost of an unused Load-more button is zero, the cost of a 200-row first paint on a flaky cellular link is a frame drop and a power spike.

## Dependency discipline

- Don't add a dependency to solve a one-function problem. Write the function.
- Don't add a dependency without checking that it's maintained. "Last updated 3 years ago" is a red flag; "no tests" is a red flag; "single maintainer on a personal account" is a red flag. Combine them and it's a veto.
- `melos bootstrap` / `npm install` at the workspace root after changing `pubspec.yaml` / `package.json`. Commit the lockfile updates.

### GitHub Actions: pin to commit SHAs, not tags

Every `uses:` line in `.github/workflows/*.yml` pins the action to a 40-character commit SHA, with a trailing `# vN` comment for human readability:

```yaml
- uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
```

Tag-based refs (`@v4`, `@main`) are mutable — the publisher can force-push a malicious version under the same tag and every workflow that uses it pulls the malicious code on the next run. SHAs are immutable. This applies to ALL workflows, not just secret-touching ones, because `actions/checkout@<sha>` runs with `GITHUB_TOKEN` and a malicious checkout step can read repo contents + write commits.

When upgrading an action: resolve the new SHA via

```bash
git ls-remote https://github.com/<owner>/<repo>.git refs/tags/v5
```

and update both the SHA and the `# vN` comment together. Don't update one without the other.

## Fix bugs, don't code around them

When a test fails or a behaviour is wrong, fix the **root cause** in the code under test. Don't:

- Soften an assertion to make the failing test pass while the bug stays in place ("the badge stays at `connecting` forever" → "assert the badge isn't `live`" leaves the user stuck on a confusing UI).
- Catch an exception only to swallow it so a flaky path stops surfacing — find why the path is flaky.
- Add a special case in a caller that mirrors a missing branch in the callee — fix the callee.
- Inline-comment "TODO: real fix later" and ship — either fix it now or open a roadmap entry naming the symptom + the deadline.

The opposite is also a rule: don't *over-fix*. A bug fix touches the bug; the surrounding cleanup belongs in a separate change ([preemptive abstractions — don't](#preemptive-abstractions--dont)).

How to spot the "coded around" pattern in review:

- A test was added with a negative assertion (`not.toContainText`, `not.toHaveClass`) where a positive one would say more. Negatives usually pin the *absence* of a leak; if the right user-facing outcome has a positive name (e.g. "shows a not-broadcasting state"), the test should pin that.
- A test was rewritten with broader matchers (`/connecting|demo|loading|.*/i`) to absorb the bug's ambiguous output.
- A comment explains why the workaround is OK; if the explanation is "the page sits at X forever, so we just check Y", the page should not sit at X forever.

The `code-reviewer` agent (via `/safe-edit`) actively flags this pattern; the [coverage_snapshot.md](../testing/coverage_snapshot.md) gets bumped only when the underlying behaviour is correct, not when the test was rewritten to tolerate it.

### Never adjust the test to hide an app bug

A specific tightening of the rule above: when a test fails, the only acceptable resolution paths are

1. **The test itself is broken** — wrong fixture (a column name, a missing required field, a unique-constraint collision with seed data), a typo, or a race in the test setup. Fix the test.
2. **The app has a real bug or missing primitive.** Fix the app code. If the app needs a new affordance for the test to be able to wait deterministically (e.g. a `data-realtime-ready` attribute backed by a real readiness signal), add it in the app code — that affordance is a real API, not test scaffolding.

There is no third option. These count as "papering over with the test" and are forbidden:

- Bumping a Playwright `expect`/`toBeVisible` timeout to absorb a flake (`5_000` → `15_000` → `30_000`). The right fix is whatever's making the page take that long.
- Adding `await page.waitForTimeout(N)` between two actions. The right fix is to wait on a real readiness signal (DOM node, state attribute, network response).
- Bumping `--retries` (or relying on Playwright's `retries: 1` to mask a real flake) instead of finding the race.
- `test.skip(…)` / `test.fixme(…)` / `test.fail(…)` against a real bug without an open follow-up that names what's broken and when it'll be fixed.
- Loosening a strict assertion (`toHaveText('Race armed')` → `toContainText(/arm|connect|ready/i)`) to "absorb variance" — the variance IS the bug.
- Replacing a network-level wait with a sleep "because the real signal is unreliable" — the real signal needs fixing.

When you spot a candidate fix that fits one of those patterns, stop and surface the underlying issue. If you cannot fix the app issue in the same session, raise it explicitly — don't half-mask it via the test.

## If you see something wrong, fix it

A sibling rule to the one above. When you're working in a file and notice something **that doesn't look right, doesn't act correctly, or isn't optimal**, fix it in the same session. Don't walk past it on the grounds of "out of scope" — by the time anyone else looks, the broken thing will still be broken AND your touch in the file's git blame will look like a tacit endorsement.

In scope to fix while you're there:

- **Correctness**: a function with an off-by-one, a Boolean inverted, a comparison that's `>` when it should be `>=`.
- **UX / behaviour**: a page that hangs on a state with no clear exit, a button that looks enabled when it's not, an error path that leaves the user nowhere to go.
- **Performance footguns**: a hot-path render that calls `setState` from a per-second callback (see `apps/mobile_android/lib/screens/run_screen.dart` architecture guards), a Postgres query that's missing an obvious index it should have, an N+1 in a list page.
- **Comments + names that lie**: a `// TODO: deprecated, remove` from 18 months ago that's still in use; a `userId` variable that's actually an `auth.users.id` while the codebase otherwise uses `auth.uid`; a comment whose described behaviour no longer matches the code below it.
- **Documented invariants that the code is silently violating**: a missing privacy-zone clip on a non-owner view (`decisions.md §33`), an unqualified `is_run_visible_to(...)` call after the function moved to `private` schema (this session's `d39296f`), an Edge Function with no JWT check (`audit/edge-functions`).
- **Test holes adjacent to the change**: if you're touching a function with no test and the test is one-line obvious, write it.

Out of scope — leave it:

- **Pure style preferences**: a different naming taste, a refactor that re-organises folders, an "I'd write this with a switch instead of an if-chain". Those go in a separate PR if at all (see [Preemptive abstractions — don't](#preemptive-abstractions--dont)).
- **Working code you simply don't recognise**: read it before you decide it's wrong. The byte-identical-twin convention and the layered-resilience contract look unusual until you've absorbed the why.
- **Things the user told you to skip explicitly.** Their call.

The 30-second test for whether to fix in-scope: ask yourself "if a reviewer flagged this, would I agree it's a bug / mis-pattern?" If yes, fix it. If "it's a style thing", leave it.

If the fix is genuinely too big for the current change, write a precise roadmap entry naming the symptom + a deadline + the file path. Don't leave inline `TODO:` markers without one.

The `code-reviewer` agent applies the same lens during `/safe-edit` review: it surfaces "the diff is fine but I noticed X in the surrounding file" as a Low-severity finding, never higher, because forced-fix scope creep is its own problem.

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

Every top-level web page wraps its content in a `.page` div with `padding: var(--space-xl) var(--space-2xl)` (2rem vertical, 3rem horizontal) and is **left-aligned** — do not add `margin: 0 auto`. The constant `var(--space-2xl)` left gutter is the gap between the sidebar and the content; centering with `margin: 0 auto` makes that gap balloon on wide screens whenever the page sets a small `max-width`, and makes navigating between pages feel like the content is jumping around. List and detail pages **do not set `max-width`** — they fill the available width so card grids, week strips, and run lists use the full screen instead of stranding empty space on the right. Focused single-form pages may still cap narrow (40–48rem) and tabbed settings panes cap at 64rem so labelled rows don't stretch awkwardly; everything else stays uncapped. Keep the horizontal padding fixed and don't centre. Public layouts without the sidebar (`/`, `/login`, `/share/...`, `/clubs/join/[token]`, `/live/...`) are exempt because they don't share the chrome and centring is the right call there.

## Web page titles and sidebar chrome

Top-level sidebar-routed pages (`/dashboard`, `/runs`, `/routes`, `/explore`, `/clubs`, `/settings/*`) **don't carry an `<h1>` page-name title** — the sidebar nav already shows the active section, so a heading that reads "Dashboard" / "Runs" / etc. is redundant chrome. Action buttons and explanatory subtitles stay; the redundant heading goes. Detail pages (`/runs/[id]`, `/routes/[id]`, `/plans/[id]`) keep their `<h1>` because that heading is the *content* title (the run's name, the route's name) — not a page label. `/plans` is reachable only from the dashboard (Manage plans link) since most users keep one active plan and the dashboard is the daily-driver entry point.

Sidebar palette is theme-aware via CSS variables in `app.css`: `--gradient-sidebar`, `--sidebar-text`, `--sidebar-text-muted`, `--sidebar-hover-bg`, `--sidebar-active-bg`, `--sidebar-active-text`, `--sidebar-border`, `--sidebar-logo`. Don't hardcode sidebar colours in `+layout.svelte` — flip the variable in the `:root` (light) or `:root[data-theme="dark"]` block instead. The light/dark sidebar gradients differ; the rest of the variables are derived from the same `--color-*` palette so most adjustments only need a one-line change.

The sidebar is collapsible — there's a `menu` / `menu_open` icon button in `.sidebar-head` that toggles between full width (`var(--sidebar-width)`, ~15rem) and an icon-only rail (`var(--sidebar-collapsed-width)`, ~4.5rem). State persists in `localStorage` under the key `sidebar_collapsed` (`'1'` / `'0'`). When collapsed, `.nav-label` and `.user-details` are hidden via `visibility: hidden; width: 0`; the logo is `display: none` so the menu button stands alone on the rail. Don't add features that assume the sidebar is always expanded — width-sensitive content lives in `.main-content`, which has its own `margin-left` transition.

## Material Symbols icons

The web app loads Material Symbols Outlined as a webfont and renders icons via **font ligatures** — `<span class="material-symbols">close</span>`, `<span class="material-symbols">menu_open</span>`, etc. Ligatures only form when the icon name is the only text node inside the span, **with no surrounding whitespace**. That means `<span class="material-symbols">{cond ? 'menu' : 'menu_open'}</span>` works, but breaking the expression onto its own line — leaving newlines and indentation between the tags — makes the browser render the literal text `"menu_open"`. Keep dynamic icon names on the same line as their tags.

The class is always **`material-symbols`** — the one styled in `app.css` with the fixed sizing box and FOUC-clipping (`overflow: hidden`). Don't use `material-symbols-outlined`: that's the bare class the `material-symbols` npm package ships, so icons still render with it, but they skip the app's sizing/clip treatment and fall out of step with every other page. (The gym pages once drifted onto it — see git history.)

## Mobile in-app notifications — `showTopBanner`

On the Flutter apps (`apps/mobile_android`, `apps/mobile_ios`), the canonical transient notification primitive is `showTopBanner(context, message, ...)` from `lib/widgets/top_banner.dart`. It renders a top-anchored pill via `Overlay`, auto-positions below an `AppBar` when one is present, and coalesces to a single banner at a time.

**Don't call `ScaffoldMessenger.of(context).showSnackBar(...)` inside `lib/screens/` or `lib/widgets/`.** Material's floating SnackBar docks at the bottom of the screen, where it overlapped the Pause / Stop / Lap controls on the recording surface — a runner couldn't reach Stop without dismissing a snack first. Top-anchored eliminates that overlap on every screen and gives notifications a consistent shape app-wide. Two architecture-guard tests in `apps/mobile_android/test/architecture_guards_test.dart` (mirrored on iOS) fail any new `showSnackBar` or `ScaffoldMessenger.of(context)` use under those folders.

If the notification has an action (e.g. "Settings" on the GPS-unavailable banner), pass `actionLabel:` + `onAction:`. Tapping the action runs the callback and dismisses the banner.

## Mobile create/edit-entity forms — `showFullScreenForm`

On the Flutter apps, every "add / edit X" form presents as a full-screen dialog built through `showFullScreenForm<T>(context, title:, builder:)` in `lib/widgets/full_screen_form.dart` (see [decisions.md § 129](decisions.md)). It pushes a `MaterialPageRoute(fullscreenDialog: true)` wrapping the body in `Scaffold` + `AppBar(title)` + `SafeArea`; lay the body out with `FullScreenFormBody(children: [...])` and label field groups with `FormSectionLabel`.

**Don't hand-roll a `showModalBottomSheet` or a bare back-arrow page for a create/edit form.** The bottom-sheet shape fought the soft keyboard and dropped its action buttons under the gesture nav bar; the mixed presentations made the same action look different per entry point. Put the heading in the AppBar (not inline in the body). A genuinely complex screen with its own `Scaffold` / `Form` / nested navigation (e.g. `AddRunScreen`) may keep its `Scaffold` but should still be pushed with `fullscreenDialog: true` for the same slide-up + close presentation.

## Local-tz date strings

Don't use `new Date().toISOString().slice(0, 10)` to derive a "yyyy-mm-dd today" or "yyyy-mm-dd of week start" string. `toISOString()` formats in UTC, so in any positive-offset timezone it rolls the date back a day before midnight local — week boundaries snap to the wrong Monday and prev/next navigation jumps two periods at once. Use `formatISO(d)` (or `todayISO()`) from `apps/web/src/lib/training/training.ts` — both build the string from `getFullYear` / `getMonth` / `getDate`, which stay in local time. The same rule applies to Dart on the mobile side: call `DateTime.local()` and format the components yourself, don't go via UTC.

## Web buttons

Canonical button styles live in `apps/web/src/app.css` under the comma-separated `.btn, .btn-primary, .btn-secondary, .btn-outline, .btn-danger` selector, plus the `.btn-sm` size modifier. Every variant works standalone (e.g. `class="btn-primary"`) or with an explicit base (`class="btn btn-primary"`) — they pick up the same padding, font size, radius, and transition.

**Don't redefine these classes in a page or component.** Local copies drift over time and the buttons stop matching across pages — exactly the problem the centralisation solved. If you need a one-off variant, give it a page-specific name (`.btn-google`, `.btn-save`, `.btn-ghost`, `.btn-connect`, ...) and let it extend the canonical class via the markup (`class="btn btn-primary btn-save"`). Avoid overriding the `padding` or `font-size` of the canonical classes — that's how drift starts.

The `/settings/upgrade`, `/login`, and `/` (landing) surfaces deliberately ship larger marketing-CTA buttons; those override the canonical sizes via Svelte-scoped local rules and are documented exceptions, not the pattern.

## Svelte 5 `$effect` — never read state you write in the same effect

A `$effect` that both reads AND writes the same `$state` rune builds a self-trigger loop: the write changes the value, the effect's dep set marks it dirty, the effect re-runs, the write resets it. When the effect is a "reset on prop change" body (`if (open) { foo = parseInitial(); ...; const anchor = foo ?? today; ... }`), the read inside `?? today` adds `foo` to the dep set; any later code path that writes `foo` (e.g. a click handler) re-triggers the reset, silently erasing the user's input.

Two fixes — pick by intent:

- The body should run **only when the trigger prop changes**: `$effect(() => { if (!open) return; untrack(() => { ... }); })`. The reset reads (`foo ?? today`) are wrapped in `untrack` so they don't register as deps. `open` remains the sole signal.
- The body should run **whenever any of its inputs change**: leave the deps as-is, but don't write back to a value the body reads — store the derived result in a separate `$state` or `$derived` so the cycle can't close.

Reproduced concretely on `DateRangePicker.svelte` — a cell click set `pendingFrom`, the open-time `$effect` re-fired because it read `pendingFrom ?? today`, the reset wrote `pendingFrom = null`, and the chip never updated. The diagnostic giveaway: handler runs (verifiable with a `console.log`), state updates to the new value (also visible in the log), but the template re-renders to the prop-reset value.

## Web modals

Canonical modal classes live in `apps/web/src/app.css` (`.modal-backdrop`, `.modal`, `.modal-header`, `.modal-close`, `.modal-body`, plus `.modal-wide` for the form-with-side-panel case and `.modal-narrow` for confirmation-style dialogs). Every dialog in the app uses this shape: a horizontally-centered card **anchored to a fixed top offset** (`top: 4rem`, `transform: translateX(-50%)`), on a 50%-opacity backdrop, with a header bar that holds the title + an `×` close button, and a scrollable body. The top-anchor is deliberate — vertically centring the card pinned its midpoint, so any content-height change inside (tab switch, list grow / shrink, autocomplete suggestions appearing) made the entire card visibly shift up or down. Anchoring the top edge keeps the header still while the body grows downward into the available `max-height: calc(100vh - 6rem)`. Side-drawer / right-rail variants are not the convention — when you find one (`apps/web/src/lib/components/WorkoutEditor.svelte` was the last holdout), convert it.

**Markup contract:**

```svelte
{#if show}
  <div class="modal-backdrop" onclick={close} role="presentation"></div>
  <div class="modal" role="dialog" aria-modal="true" aria-label="...">
    <header class="modal-header">
      <h2>Title</h2>
      <button class="modal-close" type="button" aria-label="Close" onclick={close}>
        <span class="material-symbols">close</span>
      </button>
    </header>
    <div class="modal-body">
      …form / content / actions row at the bottom…
    </div>
  </div>
{/if}
```

**Don't redefine `.modal*` classes in a page or component.** Pages that *host* the modal (e.g. `/clubs`, `/plans`, `/history`, `/clubs/[slug]`, `/dashboard` for goals, `/settings/devices` for overrides) provide local CSS *only* for body-level layout (e.g. `.goal-editor-body { display: grid; gap: 0.9rem }`) — never the backdrop, card, header, or close button. Components that own their own modal (`WorkoutEditor`, `ImportRoute`, `ConfirmDialog`) follow the same rule.

`ConfirmDialog` is the canonical confirmation surface — pass it `title`, `message`, `confirmLabel`, `danger`, `onconfirm`, `oncancel`. Don't roll a one-off `<Confirm>` shape; extend it instead.

## Web cards — `.card-elevated` is the shared elevated panel

The app has **two** card flavours, and the distinction is load-bearing — don't collapse them:

- **Elevated** (resting shadow + hover lift): the canonical `.card-elevated` lives in `apps/web/src/app.css` (next to `.btn*` / `.modal*`). It is `surface + border + radius-lg + space-lg padding + shadow-sm`, with a `:hover` lift to `shadow-md`. Used by the *dashboard-style* summary surfaces — `/dashboard` (today's-lift, recent-lifts, intensity, etc.), `/nutrition` (rings / water / meal log / trend), and the `/history` unified timeline's day panels. **Use this class for any new elevated panel; don't re-declare an identical local `.card`** (that's exactly the drift that left three copies before the 2026-06-04 consolidation). Compose layout with a page-scoped modifier: `class="card-elevated rings-card"`.
- **Flat** (no shadow): ~17 pages (settings, plans, coaching, recap, share, onboarding, …) deliberately use a page-scoped, shadowless local `.card`. These are intentionally *not* elevated. **Do not add a `box-shadow` to a bare global `.card` name** — it would cascade a shadow into every one of those flat pages. There is intentionally no global `.card`; the flat look stays page-scoped until someone does a full design-system pass to name it (`.card-flat`) and migrate all the copies.

When you need an elevated panel: `class="card-elevated"` (+ a layout modifier). When you need a flat panel: keep the existing page-scoped `.card`. Never give the global an unqualified `.card` rule.

## Web forms — `.editor-form` is the shared field layer

Every create / edit editor (`ClubEditor`, `EventEditor`, `RunEditor`, `GymEditor`, `PlanMetaEditor`, `RoutineEditor`, `SessionPlanEditor`, `WorkoutEditor`) shares one field-styling layer in `apps/web/src/app.css`, opted into with `class="editor-form"` on the form / container root. It used to be duplicated per-editor and had drifted into three input backgrounds, two label cases, and two markup conventions; the 2026-06-12 consolidation collapsed ~440 lines of copy into one ~180-line layer.

`.editor-form` styles the **field primitives**: the column container, labels (`<label>` or `.field` + `.field-label`), `.optional` / `.hint` / `.field-hint`, text/number/date/time/search/url/email/tel/datetime-local inputs + textarea + select (surface bg, border, radius, focus ring + `:focus-visible`), the checkbox/radio width reset, `fieldset` + `legend`, the inline `.radio` option row, the bordered `.toggle-row` checkbox option-card, the `.actions` / `.form-actions` row, and the `.error` banner. Canonical label look is **sentence-case bold** (`<label><span>Name</span><input></label>`). Two markup conventions are supported so editors need no restructuring — convention A (the `<label>` is the container) and convention B (`<div class="field"><span class="field-label">…</span><input></div>`).

**Rules:**
- **Don't re-declare field chrome in an editor.** Add `class="editor-form"` and let the layer style inputs / labels / fieldsets / radios / actions / errors. Keep **only** bespoke layout scoped (multi-column `.row` grids, chips, exercise / set grids, search / portion panels).
- **Svelte-scoping gotcha:** an element selector in a component (`label`, `input`) is scoped to `selector.svelte-hash`, which *out-specifies* a bare global class — so the layer only governs once the editor's duplicated scoped rules are **deleted**. When you migrate or add an editor, remove the local copies; don't leave them to "win" by specificity.
- An inline `<label>` override (a radio/checkbox that must sit on one row) needs `.editor-form .my-inline { flex-direction: row }` — the bare `.my-inline { flex-direction: row }` (specificity 0,1,0) loses to the layer's `.editor-form label { flex-direction: column }` (0,1,1) and the control stacks. Prefix inline-label overrides with `.editor-form`.
- The bordered checkbox option-card (activity waiver, charge toggle, share-to-feed, make-public) is `.toggle-row` — don't roll a new `.waiver-toggle` / `.share-row` / `.checkbox-card`.
- Native checkbox / radio colour is the global `accent-color: var(--color-primary)` rule (also in `app.css`), not a per-editor declaration.
- Dense builders (`RoutineEditor`, `SessionPlanEditor`) intentionally use the shared global `.section-label` (uppercase micro-label) for labels that double as set-grid column headers — that's a shared primitive, not duplication, and is left uppercase by design.

## Web list pages — preserve scroll on back-navigation

Any list page that links into a detail page (`/history`, `/routes`, `/plans`, `/clubs`, `/feed`, `/u/[id]`-style surfaces, …) must `export const snapshot` (SvelteKit's [snapshot API](https://svelte.dev/docs/kit/snapshots)) so clicking a row, then `back`, lands the user at the same scroll position they left at. Without this, the page remounts empty, SvelteKit's built-in scroll restoration runs against a 0-height body, and the user is bounced back to the top.

The shape is:

```ts
import type { Snapshot } from './$types';

export const snapshot: Snapshot<{ /* the loaded list + any tab/filter not in localStorage */ }> = {
  capture: () => ({ items, tab }),
  restore: (s) => {
    items = s.items;
    tab = s.tab;
    loading = false;     // skip the loading flash — we already have data
  },
};
```

Then guard the initial fetch in `onMount` so a restored list isn't immediately clobbered by a re-fetch:

```ts
onMount(() => {
  if (items.length === 0) load();
});
```

Capture the heaviest stateful arrays (the items list, pagination cursors), not derived values — derived state recomputes from restored inputs. Filters that already live in `localStorage` don't need to be in the snapshot.

## Web back links — pop to the referrer, don't hardcode a parent

A detail / create page reachable from **more than one surface** must not send `back` to a hardcoded parent. A gym routine opened from a club's Templates tab, a session plan opened from a club event, a route builder launched from a club's Routes tab — each should return to where the user *came from*, not to `/gym/routines` / `/sessions` / `/routes`.

Use the shared `smartBack` helper (`$lib/util/smart_back`): it registers an `afterNavigate` that latches whether there was an in-app referrer, and its `handle` pops history (`history.back()`) when there was one, falling through to the anchor's static `href` on a hard load / deep link. Because `history.back()` is a popstate, it also re-triggers the source list's `snapshot.restore` (see the section above) — so popping to the referrer is strictly better than a hardcoded `href` for scroll/filter preservation too.

```svelte
<script lang="ts">
  import { smartBack } from '$lib/util/smart_back';
  const back = smartBack(); // omit the arg to pop for ANY in-app referrer
</script>

<a class="back-link" href="/gym/routines" onclick={back.handle}>
  <span class="material-symbols" aria-hidden="true">arrow_back</span>
  {t('gym.routine.back')}
</a>
```

Keep the `href` — it is the deep-link / hard-load fallback and the link's semantics. Pass a `match` predicate only when a page must keep its static parent for arrivals from unrelated surfaces; the default (no predicate) pops to any in-app referrer, which is what "back to where I came from" means. The helper is the single home for the `afterNavigate` + `history.back()` idiom that used to be copy-pasted into `runs/[id]`, `clubs/[slug]`, `routes/new`, etc.

## Commit and PR conventions

- Branch: commit locally per-piece, but `origin/main` is protected — changes land only via a PR that passes the single required **CI gate** status check (0 required approvals, a green CI is the merge gate; PR mandatory and admin-enforced; no direct pushes; linear history; conversation resolution required).
- Commits use conventional commit prefixes — `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `build:`, `test:`, `ci:`. Scope optional: `feat(web): ...`, `fix(backend): ...`, `chore(android): ...`.
- Commit message body: one short sentence focused on the *why*, not the *what* — the diff already says what.
- No AI attribution of any kind. No `Co-Authored-By: Claude ...`, no "Generated with Claude Code" footer, no robot/sparkle emoji trailer. Re-read the message before `git commit` and strip these if a skill template tried to add them.
- PR title: same format, short (< 70 chars). Body: 1–3 bullet summary + a test-plan checklist (the `pull-request` skill has the template).
- Keep PRs focused. Unrelated cleanup → separate PR.
- Don't amend published commits. Don't force-push without being asked. Hooks are there for a reason; don't `--no-verify`.
- Never `git push` without being asked. The local commit is the deliverable; pushing is a separate ask.

## Commit cadence — one piece, one commit (don't batch a session into one lump)

Once the user has asked for work, commit **after each discrete piece** as you go. Don't accumulate ten changes across a session and stage them all into one mega-commit at the end. The user wants each piece individually reviewable, bisectable, and revertable; a 1000-line lump-commit defeats `git bisect` for the next regression hunt.

**What counts as a discrete piece (one commit each):**

- A new module + its unit tests — one commit.
- A refactor of an existing module + the adjusted tests — separate commit from the new feature that motivated it.
- A bug fix + the test pinning it — one commit, separate from any surrounding feature work.
- A docs sweep (ADR + per-feature doc + per-app CLAUDE.md edits documenting the same code commit) — one commit, after the code commit it documents.
- Wiring an existing helper into a new call site — separate commit from the helper itself.
- An e2e test file added retroactively for an existing feature — its own commit.

**Self-check:** if you catch yourself thinking "I'll commit at the end after I verify everything passes" — stop. Commit each piece as you go. The final verification is its own piece (or zero-changes, in which case just report green).

**Authorization scope.** "Commit after each piece" is in tension with the older "never commit without being asked" rule. The reconciliation: once the user has asked for a piece of work (or a sequence — "do the punch list", "ship the cache module"), the per-piece-commit cadence is implicitly authorized. The "without being asked" rule still guards against proactively committing speculative work the user didn't ask for, ad-hoc workstation tweaks (port changes, dev-only env), or work that got partially aborted.

Pairs with the "Test hygiene" section below — tests for a piece go in the **same commit** as the piece itself, not a follow-up commit.

## Docs hygiene

Every change that affects documented behaviour updates the docs **in the same turn as the code change**. See the root [`CLAUDE.md`](../../CLAUDE.md) § "Docs hygiene" for the full rule and checklist. Shortest version: if a doc describes the old behaviour, it is wrong the moment you change the code — fix it now, not later.

## Test hygiene — review, then unit, then e2e

Every non-trivial dev change goes through three gates before it's "done." Skipping any of them is allowed only when the change is trivial (typo, comment, single-property style change, dependency-version bump without behaviour change).

1. **Review** — does the change make sense against the project's invariants? Use the `code-reviewer` agent or `/safe-edit` for security-sensitive / migration / recording-stack / parity-helper changes. For everyday work the in-session reviewer pass + `/check` is enough.
2. **Unit tests** — pure logic, codecs, helpers, value classes, validation guards. The patterns are in [testing.md](../testing/testing.md). A change that adds or modifies a pure function should land with the test in the same diff. Bug fixes should land with a regression test that fails without the fix. **No mocks for things we own** still applies.
3. **End-to-end tests — web and backend only.**
   - **Web:** Playwright spec in [`apps/web/tests-e2e/`](../../apps/web/tests-e2e). Smoke + security + data-flow split. Sign-in / cross-user isolation / privacy clipping / CRUD round-trips are the load-bearing categories. Don't add an e2e test for a pure helper — that belongs as a unit test.
   - **Backend:** pgtap in [`apps/backend/supabase/tests/`](../../apps/backend/supabase/tests) for RLS / SECURITY DEFINER / trigger / view contracts; Deno tests next to the Edge Function for security-critical helpers (HMAC, replay window, identity validation, tier transition). Inline DO-blocks in `seed.sql` are fine for SECURITY DEFINER + `vault.*` paths that need the same `request.jwt.claim.*` simulation.
   - **Mobile / watch:** **no e2e equivalent** — Flutter `integration_test` is too slow + flaky on CI and the existing widget tests + cross-platform fixture tests already cover the high-blast paths. The honest discussion is in [testing.md § What's not covered](../testing/testing.md#whats-not-covered-honest).

Use the `/check` command to run review + test-gap-checker + doc-hygiene-checker in parallel against the working diff. It reports gaps; the human decides what to apply. The `test-gap-checker` agent walks the diff, classifies each modified file, and flags missing test surface — it doesn't write tests, it just makes the gap visible.

When a Playwright / pgtap test surfaces a real bug in the app code, fix the bug **first** (separate commit from the test), then make sure the test exists to catch regressions. The order matters: test-without-fix fails CI; fix-without-test means the next regression slips through silently.

**The same-commit rule.** Tests for a piece of work go in the **same commit** as the piece — not a follow-up commit, not "I'll add tests next session." A bug fix lands with the pinning test in the same commit (the test is the bug's headstone — without it, the next regression slips through silently). A new module lands with its unit tests in the same commit. A new web route lands with at least one Playwright e2e in the same commit.

**When a test genuinely isn't viable** (pure docs, runbook updates, infra blocked on credentials, orchestration code that pulls in SvelteKit virtual imports / Supabase / native plugins and would need heavyweight DI to unit-test), say so explicitly in the commit message — `no unit test viable; e2e covers it` is fine, silence isn't. Future you (and future code-reviewer agents) will read the message and either accept the trade-off or argue with it; either way the reasoning is recorded.

## Strava integration log keys

Strava is the only third-party integration whose state changes hit
both the EF stack (`apps/backend/supabase/functions/strava-*`) and
the Go service stack (`apps/job_worker/internal/handler_strava_*`,
`stravahook/`). Cross-stack queries for "all Strava errors in the
last hour" require a stable key vocabulary — otherwise a CloudWatch
or Sentry filter has to or-of-aliases (`activity_id|activityId|...`),
fragile and silently breaks the moment someone adds another spelling.

Use these keys verbatim in every Strava log line and Sentry tag:

| Key | Type | Notes |
|---|---|---|
| `strava.activity_id` | int64 | Strava's numeric activity id. Never `activityId`. |
| `strava.owner_id` | int64 | Strava's athlete id. Never `ownerId`. |
| `strava.status_code` | int | HTTP status from the Strava call. |
| `strava.error_class` | enum | One of `auth`, `rate_limit`, `transient`, `permanent`, `parse`. |
| `strava.endpoint` | string | `oauth_token`, `oauth_deauthorize`, `activities`, `streams`, `webhook`. |
| `alert` | string | Tag for Sentry alerts: `strava_ingest_failure`, `strava_refresh_failure`, etc. |

Don't log raw access / refresh tokens or vault secret labels — they
embed the user UUID. The EFs that hit `vault.update_secret` strip
the `integration_<provider>_<uuid>_<suffix>` pattern before logging.

/audit/strava May 2026 Medium #8.

## Audit & review findings live in `reviews/`

Findings from `/audit/*`, the `code-reviewer` agent, persona hunts, and ad-hoc
reviews go in `reviews/` — gitignored local working notes, one file per audit
area. They are **not** committed (only `reviews/README.md` is) because a
point-in-time list of file:line findings rots the instant the code moves.

When you fix an audit, flip each finding to `[x]` (with the commit hash) in its
`reviews/` file in the *same commit* as the fix; keep deferred items as `[~]`
with a reason (promote durable ones to `roadmap.md` / `followups.md`); and
delete a file once every finding is resolved or its references have gone stale.
Full lifecycle: [`reviews/README.md`](../../reviews/README.md).

## Exceptions

Every rule here has escape hatches for the cases where it genuinely doesn't fit. If you're about to violate one of these rules:

1. Confirm the escape is justified (not just "easier").
2. Leave a one-line comment at the violation site explaining why (this is one of the few cases where a comment is the right answer).
3. If the escape is a recurring pattern, either generalise the rule here or add a new subsection.
