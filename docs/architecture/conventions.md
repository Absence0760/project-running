# Conventions

House rules for this codebase. Before you reach for "what's the idiomatic way to do this in Flutter / Svelte / Swift", check here — some defaults have been deliberately overridden. If you find code that violates a rule below, fix it as part of the surrounding change. If you find a rule that's wrong, edit this file and mention it in the PR.

Rules are grouped by area below. (Section anchors are deep-linked from `CLAUDE.md` and the review agents, so the headings keep their exact wording.)

**Code style** — [Comments](#comments) · [Naming](#naming) · [Logging](#logging)

**Error handling & architecture** — [Mobile pure helpers](#mobile-pure-helpers-live-in-lib-and-a-screen-is-never-another-screens-library) · [Error handling](#error-handling) · [Layered resilience](#layered-resilience) · [Pagination](#pagination--first-page--load-more) · [Dependency discipline](#dependency-discipline) · [Preemptive abstractions — don't](#preemptive-abstractions--dont) · [Backwards compatibility](#backwards-compatibility)

**Bug & quality discipline** — [Fix bugs, don't code around them](#fix-bugs-dont-code-around-them) · [If you see something wrong, fix it](#if-you-see-something-wrong-fix-it)

**Web UI** — [Page padding](#web-page-padding) · [Page titles & sidebar](#web-page-titles-and-sidebar-chrome) · [Material Symbols](#material-symbols-icons) · [Buttons](#web-buttons) · [Svelte 5 `$effect`](#svelte-5-effect--never-read-state-you-write-in-the-same-effect) · [Modals](#web-modals) · [List-page scroll](#web-list-pages--preserve-scroll-on-back-navigation)

**Mobile & cross-platform** — [In-app notifications](#mobile-in-app-notifications--showtopbanner) · [OS share sheet](#mobile-os-share-sheet--sharefilesfrom--sharetextfrom-never-share_plus-directly) · [Local-tz date strings](#local-tz-date-strings)

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

**A bag key that criterion (2) filters on cannot be rescued later with an
expression index** — promoting it is the only fix, so weigh (2) as if the index
were never an option. `create index … ((metadata ->> 'key'))` is unusable as an
index qual in any query **RLS enforces**, because `jsonb_object_field_text` is
not `LEAKPROOF`: the planner may not evaluate a non-leakproof qual below an RLS
security qual, so the expression stays a heap `Filter` and only the leading
plain columns reach `Index Cond`. `jsonb_contains` (`@>`, the GIN path) and
`jsonb_exists` (`?`) are not leakproof either, so no jsonb access path escapes
it. Measured against `gym_routine_history`'s own predicate as `authenticated`
over 60 000 synthetic `gym_workouts` (one account holding 2 008 sessions, 153 on
the target routine): the existing `(user_id, started_at desc)` index reads 1 278
heap blocks / 1 296 buffers in 1.7 ms; adding the partial expression index makes
it **slower** (1 277 heap blocks, 1 300 buffers, 2.5 ms — identical heap work
plus a second index to walk and to maintain on every write); the same predicate
over a promoted plain `uuid` column reads 154 heap blocks / 158 buffers in
0.37 ms, because `uuid_eq` is leakproof and a plain `Var` invokes no function at
all. The exception is a path where RLS does not apply — `service_role`, or a
`SECURITY DEFINER` function owned by the table owner — where the expression
index *is* used; don't flip an RPC's security model to buy a plan, though (the
gym aggregates are uniformly `security invoker` with a load-bearing explicit
`auth.uid()` filter, and that is worth more than the milliseconds).

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
  several source files by path (`privacy_guards.test.ts`,
  `contrast_guard.test.ts`, …) and tests of the two root modules stay at the
  lib root.
- **Import across folders with the `$lib/<folder>/<stem>` alias**, not deep
  relative `../../` chains; siblings within a folder use `./`.
- A **TS↔Dart parity helper** is registered in two places: the root
  `CLAUDE.md` lockstep bullet (what a session reads) and the
  `shared-library-syncer` agent's table (what the agent works from). Adding,
  moving or retiring one means editing both in the same change, plus the
  reference in this file. `scripts/check_parity_pair_registry.mjs` fails the
  PR when the two disagree in either direction, or when either points at a
  file that no longer exists (decisions.md § 604).

`src/lib/lib_structure_guards.test.ts` enforces all of the above (root
cleanliness, parity-path existence, and the recursive `src/lib/**/*.test.ts`
unit-test glob) so the structure can't silently erode.

## Mobile pure helpers live in `lib/`, and a screen is never another screen's library

Mobile's `lib/` root is deliberately flat (the web subfolder rule above is
web-only), so the rule here is about *which layer*, not which folder:

- **A pure function belongs in a `lib/<topic>.dart` module, never in a
  `lib/screens/` or `lib/widgets/` file** — even when only one screen calls it
  today. A reduction parked in a widget file is only reusable by importing a
  screen, and the second consumer then has no good option.
- **A screen may import another screen to navigate to it** (`MaterialPageRoute`
  needs the widget class) **but never for a non-widget symbol.** If you find
  yourself writing `import 'other_screen.dart' show someHelper;`, the helper is
  in the wrong file — move it, don't import it. An import cycle between two
  screens is the symptom; misplaced logic is the cause (decisions.md § 695).
- **Tests follow the code.** Cases that never mount a widget belong in the
  helper's own `test/<topic>_test.dart`, not in a screen's widget-test file.
- Mobile-only glue is fine and common — it is **not** automatically a TS↔Dart
  parity pair. Only register a pair when web genuinely has the same reduction;
  see the parity-registry bullet above.

## Error handling

### Where validation belongs

- **System boundaries only.** User input, external API responses, file parsers, deserialisation of untrusted JSON. Validate once, then trust the types.
- **Internal code does not defensively validate.** If a function takes a `Run run`, it trusts that `run.id` is non-empty because `Run` says so. Don't add `if (run.id.isEmpty)` checks inside internal layers — the type system is the contract.

### How to fail

- **Dart:** throw `Exception` / `StateError` / `ArgumentError` for truly exceptional conditions. Prefer returning `null` or a sum-type-style result for "expected miss" (e.g. `fetchRunById` returning `null` when the ID is unknown). Don't catch and swallow — if a caller can't handle it, let it propagate.
- **TypeScript:** throw `Error` or a subclass at the boundary; return `null` / `{ ok: false, error }` shapes for expected failures within the app. Don't `catch (e) { console.log(e) }` and continue — either handle it meaningfully or let it propagate.
- **Swift:** use `throws` + `Result` at API boundaries; `do/catch` only at the outermost view or service layer. `try?` is acceptable for best-effort reads where `nil` is a valid outcome.

### A failed read is not an empty result

**"We could not find out" and "there is nothing" are different answers, and a
surface must never give the first as the second.** This is the single most
common bug class the UX sweeps keep turning up, because the wrong version
looks completely normal: a data helper logs the error, returns `[]` / `null`,
and the page renders its ordinary empty or not-found state. The user is then
told something false about their own data — "No safety contacts yet" to a
runner who has three, "Run not found" to the owner of a run that exists, a
brand-new-looking dashboard to someone with two years of history — with no
error, no retry, and no way to tell it apart from real loss.

Rules:

- **Report the failure separately from the result.** Return `{ items, error }`
  (or `{ item, error }`) rather than collapsing both into `[]` / `null`. The
  established names are the `fetchXWithError` siblings and, where a helper has
  a single caller, changing the helper itself. Alternatively `throw` and let
  the caller catch — pick one per helper, don't do both.
- **Keep a genuine miss distinguishable.** A read that succeeded and matched
  nothing is still an empty result: preserve it. `supabase-js` gives
  `PGRST116` for `.single()` no-rows and `{data: null, error: null}` for
  `.maybeSingle()` — those are misses, not failures.
- **A partial read failure fails the whole read.** A parent row whose children
  failed to load is not a parent with no children. Returning
  `{workout, sets: []}` draws a populated header over an empty body and
  presents the failure as the user's data being empty — worse, it invites an
  action (Start, Save, Adopt) against content that was never read.
- **Never seed a write from a failed read.** If a save replaces a set —
  `delete` + re-`insert`, an RPC that overwrites, a form that round-trips
  defaults — an unknown baseline must block the write, not fill it with
  emptiness. Fail closed and offer a retry.
- **The page needs a third state.** Loading / error+retry / content, with the
  error branch ordered *before* the empty and not-found branches. A page that
  clears `loading` only on the success path skeletons forever when the read
  rejects; put it in a `finally`.

The exception is an **auxiliary** read (see below): something genuinely
additive, like a suggestion chip or an attached-plan panel, degrades to absent
rather than failing the page — but say so in a comment, because from the
outside a degraded auxiliary read and a swallowed primary one look identical.

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
4. **A `try` covers what it `await`s, not what it starts.** `return someAsyncCall();` inside a `try` hands the future to the caller before it completes, so a rejection lands upstream of your `catch` and any fallback in it silently never runs — the failure mode is a degradation path that reads as handled and is dead. Write `return await …` whenever the `try` is there to catch something. Dart 3.13's `unawaited_return_in_try_block` flags this; see `decisions.md` § 595 for the case that motivated it.
5. **Independent fetches get independent error state.** A screen that loads several unrelated sections (a profile's Runs / Achievements / Followers / Following / Notifications tabs) must give each its own loading + error + retry, not bundle them into one `Future.wait` under a single `try`/`catch` — one failed call there blanks every section, including the ones that succeeded. Only a fetch the whole page structurally needs (the profile header's summary) may gate the page; each per-section fetch owns a scoped `ErrorState` + Retry. See `apps/mobile_android/lib/screens/profile_screen.dart` (`#508`).

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

### An `overrides` entry is a security pin, and it is checked as an outcome

The root `package.json` carries four dependency overrides — `cookie`, `devalue`, `undici`, `brace-expansion` — each nudging a transitive dependency off a version with a live advisory that its own parent has not bumped past. The reason for each lives in `_overrides_rationale` beside them; drop one only when upstream's own lockfile has moved past it.

They are declared **twice on purpose**: `pnpm.overrides` in pnpm's flat spelling (`"@sveltejs/kit>cookie"`) and the npm-style top-level `overrides` in npm's nested-object spelling, because `parity-types` / `build-web` / `cross-client-roundtrip` install with `npm ci` off `package-lock.json` while the Playwright, live-hub, export-hub and SSO lanes install with `pnpm install --frozen-lockfile` off `pnpm-lock.yaml`. Both must agree, or half of CI installs a patched tree and half does not.

- **Never hand-edit an `overrides:` block in a lockfile.** Change `package.json` (both declarations), then run `pnpm install --lockfile-only` and commit both lockfiles.
- **A declared pin is not an applied pin.** `pnpm install --frozen-lockfile` compares the declaration and stops there, so a lockfile that records the override and resolved around it looks healthy to it. npm's lockfile does not record the declaration at all — it records the outcome.
- `scripts/check_pnpm_overrides.mjs`, in the `parity-types` job (also `pnpm check:pnpm-overrides`), fails the build when a lockfile is missing the block, when the two declarations disagree, and when any resolved copy in either lockfile's package tree — nested copies included — falls outside a pin. It never rewrites a lockfile: regenerating one re-resolves the whole graph, which is a human's change to review ([decisions.md § 730](decisions.md)).

### GitHub Actions: pin to commit SHAs, not tags

Every `uses:` line in `.github/workflows/*.yml` pins the action to a 40-character commit SHA, with a trailing `# vN` comment for human readability:

```yaml
- uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
```

Tag-based refs (`@v4`, `@main`) are mutable — the publisher can force-push a malicious version under the same tag and every workflow that uses it pulls the malicious code on the next run. SHAs are immutable. This applies to ALL workflows, not just secret-touching ones, because `actions/checkout@<sha>` runs with `GITHUB_TOKEN` and a malicious checkout step can read repo contents + write commits.

It applies to **commented-out lines too**, and to composite actions under `.github/actions/`. A commented reference is not dead code — it is what someone uncomments on the day they are trying to ship, which is the worst day to discover the pin ([decisions.md § 711](decisions.md)); and Dependabot's github-actions ecosystem scans `.github/workflows` plus a *root* `action.yml` only, so a reference inside a composite action gets no update PRs either.

When upgrading an action: resolve the new SHA via

```bash
git ls-remote https://github.com/<owner>/<repo>.git 'refs/tags/v5*'
```

A release tag is often **annotated**, so its own object hash is not the commit — take the `refs/tags/v5^{}` row, or dereference through the API (`git/ref/tags/v5` → `git/tags/<sha>` → `.object.sha`). Update both the SHA and the `# vN` comment together; don't update one without the other. `scripts/check_toolchain_pins.mjs`, in the `workflow-lint` job, fails the build on a tag pin and on a SHA pin with no version comment.

The same principle covers the programs a step runs, not just the actions it uses: **`npx <bin>` / `pnpm exec <bin>` may only name a binary a declared dependency provides.** When nothing declares it, `npx` resolves the name against the public registry and executes the newest answer — no pin, no lockfile entry, no integrity hash, in a job holding this checkout and its `GITHUB_TOKEN`. The web unit suite ran that way for its whole life ([decisions.md § 764](decisions.md)); `scripts/check_workflow_binaries.mjs`, in the same job, now refuses it, and an unmapped binary fails rather than being skipped.

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

### A wait must name a signal only the thing being waited on can produce

The rule behind the "real readiness signal" clause above, and the one three separate CI flakes broke at once ([decisions.md § 579](decisions.md)). A check that observes something *correlated* with readiness passes early and turns into a flake that reads as a bug somewhere else:

- **`pumpEventQueue()` is not a wait on an async service.** It runs a fixed number of event-loop turns; a cycle doing real disk I/O can outlast them, and the assertion then reads pre-completion state. Give the service a `@visibleForTesting` accessor that returns the in-flight future and `await` it. A fire-and-forget that outlives its test also writes into the directory `tearDown` just deleted — same defect.
- **An intermediary's error is not a readiness signal.** A gateway answers `502/503/504` precisely *because* it could not reach the thing you are waiting for. Probe for a status the upstream itself authors (a handler's own `405`, a real password grant's `200`) and treat the 5xx family as not-ready.
- **An inner deadline must fit inside the outer budget**, or the outer one always fires first and the specific diagnosis underneath is dead code. Prefer a deadline re-armed on progress over one multiplied by the number of expected steps.
- **When a stall has two possible causes, check the cheap one first.** A firmware that stops receiving GPS and a runner who stopped moving look identical from inside the recorder; a wait on distance that cannot tell them apart blames the wrong component every time.

### A CI failure names the step that produced it

The sibling on the reporting side, and the same class of confident-but-wrong sentence ([decisions.md § 711](decisions.md)). A step condition of `failure()` is true for a failure *anywhere earlier in the job*, so a diagnosis printed from a trailing on-failure step speaks for every step above it — `parity-types` ended in one that printed "database.types.ts is out of sync with the Supabase schema" and told the reader to run `npm run gen:types`, which is what a web unit-test failure five steps up produced.

- **A diagnosis lives in the step it describes**, as `if ! cmd; then echo "::error::<what broke>"; echo "<how to fix it>"; exit 1; fi` — the form the `twin-parity` and `schema-codegen-drift` jobs already use. Scoping a trailing step with `steps.<id>.outcome == 'failure'` is the other legal shape; a bare `failure()` is not.
- **An on-failure step that claims nothing is fine.** Uploading a Playwright report or staging a sim log under `if: failure()` asserts nothing about which step failed. The rule is about claims, not about running on failure.
- **A job whose name cannot say which check broke owes a diagnosis per step, and which jobs those are is derived rather than listed.** A job running two or more of this repo's own guards is bundled by that fact — nothing has to remember to register it, which is how three such jobs went years without one ([decisions.md § 764](decisions.md)). The steps asked are its named `run:` steps plus every guard step named or not, so deleting a step's name is not a way out. Splitting such a job so its name does the work is the alternative, and it costs a hosted-runner slot on every PR *and* a line in the `CI gate`'s `needs:` list; per-step annotations surface on the checks summary for free.
- **Every job in `ci.yml` is named in the `CI gate` aggregator's `needs:` list.** That aggregator is the single required status check and it passes when every job it needs passed **or was skipped**, so a job outside the list has a red that blocks nothing and reads as one more green row. A `needs:` entry naming no job fails too.
- **A check that must block a merge is a JOB in `ci.yml`, not a workflow of its own.** An aggregator's `needs:` can only name jobs in its own file, so a check in `foo.yml` gates nothing however red it goes — three of them have shipped that way ([decisions.md § 775](decisions.md), [§ 862](decisions.md), [§ 865](decisions.md)), each with a path filter that made its absence indistinguishable from its success. A workflow of its own is for work that is release-time (a tag), advisory, scheduled, or event-driven. Bundle into an existing install-free job where one shares the subject rather than adding a job per check; the per-step `::error::` above is what makes that readable. A guard's own unit suite is held to the same rule and enforced by the census in `check_ci_diagnostics.test.mjs`: it has to be run from `ci.yml`, or named in `SUITE_OFF_THE_GATE` with a reason ([§ 863](decisions.md)).

`scripts/check_ci_diagnostics.mjs`, in the `workflow-lint` job, fails the build on the first three; its own suite carries the guard-and-suite census behind the fourth.

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

## A constant with more than one home is registered, and the guard reads every home

A value written in two places drifts. The repo already enforces two shapes of
this — `scripts/check_parity_pair_registry.mjs` for a TS↔Dart function pair,
`apps/web/scripts/check_constraint_unions.mjs` for a CHECK's value set against
its TS union — and between them sits every threshold, bucket boundary,
vocabulary, size cap and eligibility list copied into SQL, out of SQL into two
clients, from one SQL function into the next, or across the Rust / Kotlin /
Swift / Go rails. Four of those had already diverged when the class was first
swept ([decisions § 787](decisions.md)).

When you write a value that a second language also has to know:

- **Register it in `scripts/check_shared_constants.mjs`.** An entry names every
  home, extracts the value from each, and states what a drift costs. The
  registry lives in the script rather than in markdown so it has exactly one
  home itself.
- **Read the rails; never transcribe one.** A test that restates the other
  side's number is a snapshot: it stays green while the thing it describes
  moves. `scripts/check_watch_ble_uuids.mjs` is the model — it parses both
  sources.
- **A rail that extracts nothing is a failure, not a match.** Two empty sets
  agree. Both the guard and any hand-written mirror must fail loudly when the
  shape they read changes.
- **A vocabulary a guard cannot point at is a vocabulary nothing guards.** An
  anonymous inline union — `status: 'reviewed' | 'dismissed'` written out at
  three call sites — is a rail with no name, and `check_constraint_unions.mjs`
  filed four of those as "no client enumerates this column" while sixteen
  spellings of them shipped ([decisions § 817](decisions.md)). Name the
  vocabulary once, in one exported declaration, and derive any narrower use of
  it (`Exclude<FinisherStatus, 'finished'>`) rather than re-typing the subset.
- **Where the language cannot make the lookup exhaustive, the guard reads the
  lookup itself.** Web's `Record<Union, X>` label maps need no rail because
  `tsc` checks them; a Dart `switch` over a `String` cannot be exhaustive, so
  it silently falls to `default:` when its CHECK grows and it gets a `switch`
  rail instead ([§ 818](decisions.md)). Do NOT install a const list beside the
  switch for the guard to read — that is a second declaration nothing checks
  against the switch, the [§ 641](decisions.md) shape. Point the rail at the
  authority.
- **Resolve SQL by replay, not by filename.** The body a function has in
  production is the one the last `create or replace function` wrote, and that
  is routinely in a migration named after something else. Reading the migration
  that first introduced a value certifies the value it used to have.
- **Some shapes do not belong in the registry.** A formula written three times
  (`challenge_goal`'s ceiling) is not a literal, and extracting one constant out
  of it certifies nothing about the shape around it; two homes that hold
  deliberately *different* numbers in a stated relation (the 48 h Postgres
  live-ping window against the 24 h Redis TTL) are not an equality. Pin those
  with mirror suites and say so where the numbers are written.

## A client input bound goes in `column_limits`, and it has to sit inside the column's CHECK

A composer or numeric field whose column carries a CHECK is one edit away from a
raw postgres error the runner cannot act on — a `23514` naming a constraint and
no field, or a `22003` when the column's `numeric(p, s)` precision is the
binding ceiling. Four fields were in that state when the class was swept
([decisions § 792](decisions.md)).

- **State the bound once per client**, in `apps/web/src/lib/core/column_limits.ts`
  and `apps/mobile_android/lib/column_limits.dart`, keyed by
  `<table>.<column>`. The key is the locator: `check_shared_constants.mjs`
  splits it, resolves that column's live CHECKs by replaying every migration,
  intersects them with the precision ceiling, and proves the client's bound sits
  inside. Nothing restates a number the database owns.
- **Stricter than the column is fine; looser is the bug.** The comparison is
  containment, not equality — a club post capped at 1200 against a 4096 column
  is a product decision. What is not fine is the two clients disagreeing, which
  the guard checks separately: a stricter phone silently truncates what the web
  accepted.
- **`min` / `max` on a web input are only real inside a form.** A card that
  saves from a button's `onclick` never runs the browser's constraint
  validation, so the attributes are decoration and the gate has to be in the
  code (issue #677, and § 792 again). Mobile has no native validation at all.
- **A bound is stated in the unit the field is TYPED in.** A weight column is
  kilograms and the field may be pounds, so convert — rounding the floor UP and
  the ceiling DOWN, or the range advertises a value its own gate refuses.

## A narrowed select gets a narrowed row type, derived from the same column list

A `.select()` that enumerates columns instead of `'*'` is a good thing — `geom`
duplicates `waypoints` purely for server-side spatial queries and doubles the
wire payload, `start_point` leaks a run's start location, `shadow_hidden` is
moderation state the client has no business reading. What is not fine is
handing the resulting rows back under the table's full row type. The absent
fields are `undefined` at runtime under a type that declares them, so a
consumer that reads one gets `undefined` with the compiler's blessing: no
throw, no error, and a `{#if}` that can never be true. `routes` shipped that
way — eleven of twenty-two columns absent behind `Route`
([decisions § 1294](decisions.md)).

- **Declare the projection once and derive both halves from it.** The column
  tuple is the source: `as const satisfies readonly (keyof Row)[]`, so a column
  a migration dropped fails to compile; the wire string is `join`ed from it and
  the row type is `Pick`ed from it. A hand-written `Pick<Row, …>` beside a
  hand-written select string is two declarations and the [§ 641](decisions.md)
  shape — they agree until they don't. `apps/web/src/lib/routes/route_list_columns.ts`
  is the model.
- **The narrowed type is what the fetcher returns**, not what one careful
  consumer annotates. A return type of the full row is the lie; every consumer
  that has to remember to narrow it is a consumer that will forget.
- **Pin it at compile time, because no runtime test can see it.** A read of an
  absent field yields `undefined` rather than throwing, so the assertions are
  `@ts-expect-error` on each withheld column and an `Exclude<…> extends never`
  on the set — checked by `svelte-check`, not by `tsx --test`. Mutation-test
  both directions: widening the type must leave the `@ts-expect-error`s unused,
  and dropping a projected column must fail the consumers.
- **A view that withholds a column is filled, not cast.** Where two reads merge
  into one list, the narrower half supplies the difference with values that
  state what is true ([§ 1229](decisions.md)) — and the fill's coverage is a
  type-level claim, so it cannot be partially right.

## Local stores — a directory transition is serialised, not just atomic

`writeStringAtomic` gives each in-flight write its own `.tmp` sibling and renames
it over the target, so a crash leaves either the old file or the whole new one.
That is a guarantee about ONE write. It says nothing about two *operations* over
the same directory, and every mobile store operation is a multi-step directory
transition: write the row then the index, delete the row then rewrite the index,
write every row then prune, delete every file.

So every directory-mutating entry point on every local store —
`OfflineSyncStore`, `LocalRunStore`, `LocalRouteStore` — runs on one serial
chain, `serialiseStoreWrite` in `core_models`, and a new one must go on it too.
Five properties are load-bearing and a change that weakens any of them reopens a
measured bug (decisions § 821, § 828, § 829):

- **Whole-directory, not per-id.** `clear`, `rewriteAll`, `loadAll` and the index
  flush touch files no row id names, so per-id exclusion still lets them race a
  row write.
- **Keyed on the directory, not the instance.** All instances of a store type
  share one directory — `offline_store_wipe.dart` relies on exactly that to wipe
  from a throwaway instance — so a per-instance lock leaves a sign-out `clear()`
  free to delete the temp file of the live screen's in-flight write.
- **The chain never becomes an error future.** A failed write reports to its own
  caller; it must not reject every write queued behind it.
- **Re-entrant on its own key.** The stores share `_persistIndex` /
  `_persistSyncedIds` / `_persistOwnerTags` across ~30 entry points, so a helper
  that queued behind its own caller would deadlock — silently, with no error and
  no completion. A nested call on the same key runs inline.
- **Nothing with unbounded latency inside a chained body.** No network call, no
  untimed lock. Queueing behind a bounded operation is safe; queueing behind one
  that may never return is a durability gap, not a race fix.

Two things stay OFF the chain, and both are the recording stack. The in-progress
recorder path (`saveInProgress` / `clearInProgress` / `loadInProgress`) owns
`in_progress.json`, which nothing chained touches, and already has its own
skip-don't-queue exclusion; `WatchIngestQueue.enqueue` writes a fresh uuid
nothing else names, and its `drain` awaits an upload per file. **An L0/L1 write
must never be able to queue behind a directory operation** — a write that never
lands is worse than the race. Pin that with a test that holds the chain open
through a never-completed `Completer` and asserts the recording write still
lands, not with a timing assertion.

Store durability is one mechanism, not a menu. A `FileLock` alongside the chain
is not defence in depth: POSIX record locks are owned by the process, so they
exclude neither a second store instance nor a second isolate (§ 829). What
survives an interleaved isolate is the merge-never-replace in each sidecar
writer.

The corollary for tests: a widget test's UI signal is usually the in-memory row,
which `persist` installs synchronously *before* its file write. Tearing a temp
directory down on that signal deletes a `.tmp` mid-rename. Wait on the file (or
on `debugWritesSettled`, which every chained store exposes), which is also the
only thing that actually pins the offline-first durability the surface is
claiming.

## Feature gates — one parser, and a define a release build can actually read

Every fail-closed feature gate on either client parses its env string through the
canonical helper, never a hand-written comparison:

- Web: `isTruthyFlagValue` from `core/env_flag.ts`.
- Mobile: `isTruthyFlagValue` from `lib/env_flag.dart`.

The two are a registered parity pair, so the accepted set is one contract across
both platforms: `1` / `true` / `yes` / `on`, trimmed and case-insensitive; unset,
empty, `false`, `0`, or anything unrecognised reads as OFF. Fail-closed means a
gate can only be turned ON by an explicit affirmative — never left on by a typo.

A copy of that chain is what this rule exists to stop. Eight modules carried one
before decisions § 709, and the narrowest of them accepted two of the four values,
so `WEIGH_IN_GATE=yes` silently left an Art 9 surface off while the same string
enabled every other gate. Both suites now scan for the pattern and fail on a new
copy; on web, every `*_flag.ts` module must additionally reach the canonical
parser, directly or through one named delegate.

A flag whose parser belongs to a TS↔Dart parity pair (`off_route_alert`,
`plan_adaptive_replan`) keeps its named function and delegates to the canonical
one — on **both** sides, in the same change, or the pair diverges.

**One binding module per flag, and the surfaces read the gate — never the key.**
A flag's env key and its fail-closed guard live together in a `*_flag` module
(`nearby_flag.dart` / `off_route_flag.dart` / `adaptive_fitness_flag.dart` /
`weigh_in_flag.dart`; on web the `*_flag.ts` layer), which exports the key const
and a named gate getter. A surface imports the getter. It does not spell
`dotenv.env['KEY']` / `env.PUBLIC_KEY` itself, because a guard written at the
call site is only as good as that call site: four mobile gates all failed closed
while their bindings sat at five call sites in two idioms, two of them duplicates
and two private to a screen and therefore unassertable (decisions § 822). The
mobile suite fails on a gate key read literally outside its own module, and on a
gate that throws rather than answering `false` against an uninitialised dotenv.

**On mobile the gate is not finished until the key is in `main.dart`'s
`String.fromEnvironment` bridge.** Release builds never load `.env.development`
(decisions § 13), so the bridge is the only path a value has into `dotenv`: a key
read at runtime but absent from it is readable in debug and unreachable in
production. Three sign-off-gated flags shipped in exactly that state. Add the
`String.fromEnvironment` const *and* the matching `'KEY=$def'` entry — the
reachability guard in `env_flag_test.dart` fails on either half missing. Whether
a release *workflow* passes the define is a separate deploy-time decision, and
the place to record it is `apps/<app>/deployment.md`.

## Backwards compatibility

This is a pre-launch codebase with no shipped users. Backwards-compatibility shims are almost never warranted:

- Don't keep a dead enum case "in case someone relies on it".
- Don't rename a field and re-export the old name.
- Don't leave a deprecated function alongside the new one with a `@deprecated` annotation unless the switchover is genuinely multi-PR.
- Just change the code, run the build, fix the compile errors.

When you genuinely need a migration (e.g. on-disk data format changing), write the migration, not a permanent dual-read path.

## Web page padding

Every top-level web page wraps its content in a `.page` div with `padding: var(--page-padding-y) var(--page-padding-x)` and is **left-aligned**. **Read the tokens, never the `--space-*` pair they resolve to** — they are 2rem / 3rem at desktop and narrow to `--space-lg` / `--space-md` below 40 rem, where a 3rem gutter each side costs 96px of a 320px screen on top of the 72px sidebar rail ([§ 535](decisions.md)) — do not add `margin: 0 auto`. The constant `var(--space-2xl)` left gutter is the gap between the sidebar and the content; centering with `margin: 0 auto` makes that gap balloon on wide screens whenever the page sets a small `max-width`, and makes navigating between pages feel like the content is jumping around. List and detail pages **do not set `max-width`** — they fill the available width so card grids, week strips, and run lists use the full screen instead of stranding empty space on the right. Focused single-form pages may still cap narrow (40–48rem) and tabbed settings panes cap at 64rem so labelled rows don't stretch awkwardly; everything else stays uncapped. Keep the horizontal padding fixed and don't centre. Public layouts without the sidebar (`/`, `/login`, `/share/...`, `/clubs/join/[token]`, `/live/...`) are exempt because they don't share the chrome and centring is the right call there.

## Web page titles and sidebar chrome

Top-level sidebar-routed pages (`/dashboard`, `/runs`, `/routes`, `/explore`, `/clubs`, `/settings/*`) **don't carry an `<h1>` page-name title** — the sidebar nav already shows the active section, so a heading that reads "Dashboard" / "Runs" / etc. is redundant chrome. Action buttons and explanatory subtitles stay; the redundant heading goes. Detail pages (`/runs/[id]`, `/routes/[id]`, `/plans/[id]`) keep their `<h1>` because that heading is the *content* title (the run's name, the route's name) — not a page label. `/plans` is reachable only from the dashboard (Manage plans link) since most users keep one active plan and the dashboard is the daily-driver entry point.

Sidebar palette is theme-aware via CSS variables in `app.css`: `--gradient-sidebar`, `--sidebar-text`, `--sidebar-text-muted`, `--sidebar-hover-bg`, `--sidebar-active-bg`, `--sidebar-active-text`, `--sidebar-border`, `--sidebar-logo`. Don't hardcode sidebar colours in `+layout.svelte` — flip the variable in the `:root` (light) or `:root[data-theme="dark"]` block instead. The light/dark sidebar gradients differ; the rest of the variables are derived from the same `--color-*` palette so most adjustments only need a one-line change.

The sidebar is collapsible — there's a `menu` / `menu_open` icon button in `.sidebar-head` that toggles between full width (`var(--sidebar-width)`, ~15rem) and an icon-only rail (`var(--sidebar-collapsed-width)`, ~4.5rem). State persists in `localStorage` under the key `sidebar_collapsed` (`'1'` / `'0'`). When collapsed, `.nav-label` and `.user-details` are hidden via `visibility: hidden; width: 0`; the logo is `display: none` so the menu button stands alone on the rail. Don't add features that assume the sidebar is always expanded — width-sensitive content lives in `.main-content`, which has its own `margin-left` transition.

## Material Symbols icons

The web app loads Material Symbols Outlined as a webfont and renders icons via **font ligatures** — `<span class="material-symbols">close</span>`, `<span class="material-symbols">menu_open</span>`, etc. Ligatures only form when the icon name is the only text node inside the span, **with no surrounding whitespace**. That means `<span class="material-symbols">{cond ? 'menu' : 'menu_open'}</span>` works, but breaking the expression onto its own line — leaving newlines and indentation between the tags — makes the browser render the literal text `"menu_open"`. Keep dynamic icon names on the same line as their tags.

The class is always **`material-symbols`** — the one styled in `app.css` with the fixed sizing box and FOUC-clipping (`overflow: hidden`). Don't use `material-symbols-outlined`: that's the bare class the `material-symbols` npm package ships, so icons still render with it, but they skip the app's sizing/clip treatment and fall out of step with every other page. (The gym pages once drifted onto it — see git history.)

**The font is a subset, so adding a new icon means regenerating it.** `apps/web/src/lib/assets/material-symbols-subset.woff2` carries only the icons this tree names — 347 of the font's 4271, 74 KB against the full font's 3866 KB ([decisions § 780](decisions.md)). The set is derived from the source, not hand-listed: element text at every render site, plus every quoted `[a-z0-9_]+` literal under `src` that the upstream font can render, which is how a name reaching the span through `{item.icon}` gets found. Adding an icon the subset does not carry fails `build-web` with the name in the message; fix it with `pnpm gen:icon-font` and commit the regenerated `.woff2` **and** its `.json` manifest. `@font-face` and `font-display: block` live in `app.css` — `block` is deliberate, because for a ligature font every other value paints the icon's NAME in the fallback face while it loads.

## Mobile in-app notifications — `showTopBanner`

On the Flutter apps (`apps/mobile_android`, `apps/mobile_ios`), the canonical transient notification primitive is `showTopBanner(context, message, ...)` from `lib/widgets/top_banner.dart`. It renders a top-anchored pill via `Overlay`, auto-positions below an `AppBar` when one is present, and coalesces to a single banner at a time.

**Don't call `ScaffoldMessenger.of(context).showSnackBar(...)` inside `lib/screens/` or `lib/widgets/`.** Material's floating SnackBar docks at the bottom of the screen, where it overlapped the Pause / Stop / Lap controls on the recording surface — a runner couldn't reach Stop without dismissing a snack first. Top-anchored eliminates that overlap on every screen and gives notifications a consistent shape app-wide. Two architecture-guard tests in `apps/mobile_android/test/architecture_guards_test.dart` (mirrored on iOS) fail any new `showSnackBar` or `ScaffoldMessenger.of(context)` use under those folders.

If the notification has an action (e.g. "Settings" on the GPS-unavailable banner), pass `actionLabel:` + `onAction:`. Tapping the action runs the callback and dismisses the banner.

## Mobile OS share sheet — `shareFilesFrom` / `shareTextFrom`, never `share_plus` directly

On the Flutter apps, every hand-off to the OS share sheet goes through `shareFilesFrom(context, files: …)` or `shareTextFrom(context, text: …)` in `lib/share_sheet.dart`. That module is the only file under `lib/` allowed to import `package:share_plus/share_plus.dart`.

The reason is iPadOS, and it is not cosmetic. UIKit presents `UIActivityViewController` as a **popover** there and refuses to present one without a non-empty source rect inside the host view; share_plus's iOS plugin turns a missing or empty anchor into a `PlatformException`, so the sheet never appears and the share silently fails. The apps ship to iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), and every one of the 21 share call sites in the tree once omitted the anchor — an optional parameter that Android and iPhone never miss is one nobody remembers.

So the helper takes the `BuildContext` it derives the anchor from as a **required positional** parameter. There is deliberately no overload that accepts a bare `Rect`, and none that accepts nothing: a caller cannot express a share without an anchor. Derivation degrades rather than throwing (the invoking widget's own global bounds, clipped to the view; else a small rect at the view's centre; else a one-pixel rect at its origin) because a share is an L4 auxiliary effect — a screen must not go down because its anchor could not be resolved. It never yields an empty rect, since an empty rect is the failure itself.

Four source guards in `apps/mobile_android/test/architecture_guards_test.dart` (mirrored on iOS) hold this: nothing but the helper imports `share_plus`, nothing but the helper names `Share.share*` or `SharePlus.instance`, every `ShareParams` the helper builds carries `sharePositionOrigin`, and every entry point's first parameter is a `BuildContext`.

## Mobile async gaps — the `mounted` check goes BEFORE the `setState`, not after

On the Flutter apps, every `setState` reached after an `await` needs `if (!mounted) return;` between the two. During the gap the runner can pop the route, sign out, or be navigated away by a deep link; `setState` on a defunct `State` throws, and the throw only ever happens to someone who left mid-request.

Write the guard **immediately after the await that opened the gap** — not after the `setState`, and not only on the failure arm. Both were real: `runs_screen.dart` set `_syncing = false` and asked about `mounted` on the next line, and the route-detail tag row checked only inside its `catch` while the success arm wrote straight through (issue #734, 34 sites).

`apps/mobile_android/test/post_await_setstate_guard_test.dart` (mirrored on iOS) scans `lib/` and fails on the next one. It is deliberately precision-tuned — a guard that lives in a helper the method calls is not seen — so a hit is a real finding, and the allowlist is empty on purpose. A dialog `await` counts: `showDatePicker`, `confirmDestructive` and `Navigator.push` all open the same gap as a network call.

## Mobile distances and paces render through the unit pref, never a hand-rolled divide

A user-facing distance, pace, speed or elevation on the Flutter apps is formatted by `UnitFormat` (with an explicit `DistanceUnit`) or, on a surface that carries no `Preferences` dep, by the top-level `formatDistanceForPref` / `formatPaceForPref` / `formatElevationForPref` in `lib/preferences.dart`. **Never `'${(metres / 1000).toStringAsFixed(2)} km'`** — that is the shape that leaves a mile-unit runner reading kilometres, and it has been swept out of the browse surfaces twice now (#733 target pace, #734 race calendar / event photos / event results / last-run card).

Two corollaries. **Don't add a second formatter beside the shared one** — `social_service.dart` grew its own km-only `fmtPace`, so the event target-pace metric disagreed with the unit-aware distance printed next to it. And **an i18n key names the concept, not the unit**: the message takes an already-formatted `{distance}`, so `racesKmAway` was renamed to `racesDistanceAway`; a key that claims kilometres is how the next edit reintroduces them.

## Mobile typed numbers are read by `parseTypedDecimal`, never `double.tryParse`

A number the user typed arrives as the text of a `TextEditingController`, and five of the seven shipped locales (de, es, fr, pt, pt_BR) put a **comma** on the decimal key. `double.tryParse` understands only a dot, so a raw parse loses the value in one of two silent ways. Behind an `inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]` filter the comma is deleted before the parse runs at all and "5,2" reads as **52** — a 5.2 km run saved as 52 km, and a weigh-in of 72,4 kg saved as 724. Without such a filter the parse returns null and the field is dropped on the floor, which is how manual food macros lost every gram a German user typed.

So read typed text with `parseTypedDecimal` (`lib/typed_decimal.dart`) and filter the field with `typedDecimalInputFormatters`. It takes either separator, resolves a grouping separator the way a reader would (of two separators the rightmost is the decimal point, and a separator that repeats can only be grouping), and refuses the `NaN` / `Infinity` literals `double.tryParse` accepts. **Machine-formatted input is not its business** — CSV columns, Strava exports and API JSON stay on `double.tryParse`, where a dot is the only correct separator and a comma is a delimiter. Two source guards in `architecture_guards_test.dart` fail the suite on a `double.tryParse` over `.text` and on a filter that admits `.` but not `,`.

## Web money crosses the minor-unit boundary through `minor_units`, never `/ 100`

Every `*_cents` column holds a Stripe amount in the currency's **minor** unit, and 100 is not that unit's scale in every currency. Stripe stores a zero-decimal currency (JPY, KRW, VND, CLP, ISK, XOF…) in its **base** unit — a ¥1,000 donation arrives as `1000` — and a three-decimal one (BHD, JOD, KWD, OMR, TND) in thousandths, where it further requires the amount to be a multiple of 10. So convert with `fromMinorUnits(amountMinor, currency)` / `toMinorUnits(amountMajor, currency)` in `src/lib/format/minor_units.ts`, which reads the scale off the currency (Intl first, with Stripe's explicit tables as the fallback). A blanket `/ 100` renders that yen donation as ¥10 on a public feed; a blanket `* 100` charges a host a hundredfold.

`formatPrice` takes a **major**-unit amount and sets no fraction-digit override — the currency's own convention is the correct one, and forcing two prints ¥1,000.00 and truncates KWD 1.500 to 1.50. A source guard in `minor_units.test.ts` fails the suite on a hard-coded 100 beside a cents identifier.

## Mobile create/edit-entity forms — `showFullScreenForm`

On the Flutter apps, every "add / edit X" form presents as a full-screen dialog built through `showFullScreenForm<T>(context, title:, builder:)` in `lib/widgets/full_screen_form.dart` (see [decisions.md § 129](decisions.md)). It pushes a `MaterialPageRoute(fullscreenDialog: true)` wrapping the body in `Scaffold` + `AppBar(title)` + `SafeArea`; lay the body out with `FullScreenFormBody(children: [...])` and label field groups with `FormSectionLabel`.

**Don't hand-roll a `showModalBottomSheet` or a bare back-arrow page for a create/edit form.** The bottom-sheet shape fought the soft keyboard and dropped its action buttons under the gesture nav bar; the mixed presentations made the same action look different per entry point. Put the heading in the AppBar (not inline in the body). A genuinely complex screen with its own `Scaffold` / `Form` / nested navigation (e.g. `AddRunScreen`) may keep its `Scaffold` but should still be pushed with `fullscreenDialog: true` for the same slide-up + close presentation.

**Every form passes a real `isDirty:` predicate.** `showFullScreenForm` wraps its Scaffold in `DiscardGuard` (`lib/widgets/confirm_discard.dart`), which probes the predicate at pop time and confirms before discarding ([decisions.md § 478](decisions.md)). A new form sheet must wire one (compare current inputs against the loaded entity or create-defaults — including un-committed sub-editor input); a hand-rolled form screen wraps its own `Scaffold` in `DiscardGuard` directly. Explicit Cancel buttons pop via `Navigator.maybePop` so they meet the guard; save-success pops bypass it.

## Mobile status colours — `AppSemanticColors`, not new hex literals

On the Flutter apps, good/warning/bad/crown colouring comes from the `AppSemanticColors` theme extension in `packages/ui_kit` (`AppSemanticColors.of(context)` / `.ofTheme(theme)` — `success`/`warning`/`danger`/`crown` + their `on*`, AA-guarded per brightness by `app_semantic_colors_test.dart`; [decisions.md § 477](decisions.md)). **Don't add new Tailwind/Material hex literals for a status role**, and never pair a status fill with `Colors.white` — use the token's `on*`. (`colorScheme.error`/`onError` fails AA as a *fill* pair — 3.85:1 — it is a foreground-on-surface colour; see § 477.) The issue #666 V3 sweep migrated the legacy literals, and `status_color_literal_guard_test.dart` (both mobile twins) now fails any banned status hex or `Colors.green`/`amber`/`red` swatch outside its allowlists: the fixed-PNG share cards (`run_share_card`, `route_share_card`, `finisher_certificate_card`, which deliberately don't follow the device theme) plus count-pinned chart/map DATA palettes (pace ramp, heat scales, map markers) — data colours are not status roles, so they keep fixed hues. A base token is used as a bare **foreground** too (the signed readiness delta), so `app_semantic_colors_test.dart` holds each base to 4.5:1 as text on the card and the scaffold, not only 3:1 as a banner fill.

The guard scans **`lib` and `packages/ui_kit/lib`**. It used to walk `lib` alone, so moving a palette into the shared package took its hexes out of reach without touching the allowlist — a file that is no longer scanned needs no exemption. When a shared package starts carrying colour, add its root to `_roots`, not an exemption.

**A cartographic colour stays on the map.** A hue picked to survive arbitrary basemap tiles — a route line, a pin, a scrim — is correctly a fixed hex, because there is no theme surface behind it to measure against. The moment the same hue names the same state in the **chrome** around the map it stops being cartographic and becomes an unmeasured accent: the route heatmap's "kept on map" violet had reached a sheet icon, a list-row icon and a button border, where a single fixed value cannot be right in both brightnesses (3.828:1 light and 3.817:1 dark on the surface those three used, but 2.902:1 one container deeper). So **chrome takes a theme token** (`colorScheme.primary` there, 7.766–11.005:1), the legend link is carried by the icon's own shape fork rather than by hue, and the map's hex is count-pinned in the literal guard so a fourth chrome site cannot land unmeasured. This is not a licence to add hexes: a hue earns an entry by being drawn on tiles, not by being hard to theme.

## Mobile muted text — `onSurfaceVariant`, never a 3:1 colour source

`colorScheme.outline` is a **3:1 boundary token** ([§ 487](decisions.md)): correct for a hairline, a border, a divider, or an icon tint, and wrong for type. Measured against the real tokens it reads **4.058:1 on the light card**, 3.486:1 on light `surfaceContainerHighest` and 2.952:1 on dark `tertiaryContainer` — short of WCAG 1.4.3's 4.5:1 for the 11–14 sp body and label type that reached for it. It *does* clear AA on the dark card (5.117:1), which is the point: `outline` cannot be **relied on** as text, while `onSurfaceVariant` can (8.459:1 light card, 9.474:1 dark card, 5.465:1 on its worst real background).

So: **muted type takes `colorScheme.onSurfaceVariant`** (or `onSurface` where the type is its surface's headline). A blanket ban on `outline` would be wrong, so `outline_text_token_guard_test.dart` (both mobile twins, scanning `lib` + `packages/ui_kit/lib`) classifies each occurrence by its innermost enclosing constructor and fails only the text ones. A colour held in a local, returned from a helper, or produced by a `switch` arm cannot be classified from syntax — several of those did feed a `TextStyle` — so it is a third verdict that fails unless count-pinned per file, on the § 480 model. The ratios are computed in `packages/ui_kit/test/outline_token_contrast_test.dart`.

**The rule is not about one token — it is about every colour source that carries no 4.5:1 guarantee.** Round 12 of #666 found the same defect one layer down: the plan-calendar workout-kind palette painted its kind LABEL, at 1.973 / 2.373 / 1.589:1 on the light completed-day fill, in hues no ban list carried. So the guard scans three families, each with a correct non-text use, and all three fail in text position:

- the **boundary tokens** — `colorScheme.outline`, `colorScheme.outlineVariant`, `theme.dividerColor` (3.531:1 on the light card, 3.029:1 on the completed-day fill);
- the **`ChartPalette` scales** — `series` / `zones` / `ramp` / `kinds`, every entry measured to 1.4.11's 3:1 and none of them to 4.5:1;
- **raw `Color(0x…)` literals**, which carry no measurement at all — count-pinned per file, each entry naming the *fixed* surface (a rasterised share card, a map basemap chip) and the ratio that justifies it.

Two rules cover what the constructor walk cannot see. A **`foregroundColor:` argument** is type wherever it appears, but its enclosing constructor is `TextButton.styleFrom(`, which also takes a `backgroundColor` — so the *parameter name* is matched directly (two button labels were painted in an unmeasured `#8B5CF6`, 3.828:1 on the light card). And a **`Color`-returning helper holding raw hexes** is exactly the round-12 shape — a private `static Color _kindColor(ThemeData, WorkoutKind)` duplicated across two widgets, whose `switch` arms have no enclosing constructor at all — so every such declaration must be named in an allowlist with where its value lands. That is what forces a new palette into a measured home instead of into a widget's private helper.

**The boundary tokens are never thinned.** `colorScheme.outline`, `colorScheme.outlineVariant` and `theme.dividerColor` are guarded at 3:1 and nothing more, so an alpha forfeits the floor outright — 0.6, the strongest multiplier that had been used, composites `outline` to 2.134:1 on the light card. The same guard fails any `.withValues(alpha:)` / `.withOpacity()` on the three, with no allowlist, because there is no headroom to allow. If you want a fainter mark, pick a token that guards the level you want; if you want a *tint*, tint a token that has foreground headroom and write down the composited ratio.

## Web status colours — the `app.css` tokens, not new hex literals

Same rule on web, same shape of guard. Good/warning/bad/crown colouring comes from the token vocabulary in `apps/web/src/app.css` — `--color-success` / `-warning` / `-danger` plus their `-text` (theme-aware foreground), `-light` (tint fill) and `-strong` (solid fill under white text) pairs, and `--color-crown` / `--color-on-crown` — all held to WCAG AA **per theme** by `contrast_guard.test.ts`. **Don't add a new Tailwind/Material hex literal for a status role.** A literal opts out of that per-theme guarantee in whichever theme nobody eyeballed, and `app.css` is the one place the vocabulary may be spelled.

`status_color_literal_guard.test.ts` fails any of 39 named status hues outside its allowlists. Three narrow exemption classes, each pinned to an **exact occurrence count** so the allowlist can only shrink and a new literal in an exempted file still fails:

- **`app.css` custom-property declarations.** Only declaration lines, not the whole file — a *rule* in `app.css` is still scanned, which is what caught `.btn-primary` pairing a frozen `color: #FFFFFF` with a `--color-primary` fill that flips to a light coral in dark (2.081:1; `--color-on-primary` reads 9.120:1).
- **DATA palettes** — badge tier metals, medal metals, chart series, cartographic markers. (Workout-kind tints left this list in round 12: they became `--kind-1..6`, measured per theme, after the four surfaces that carried their own copy of the three hexes were found painting labels at 1.85–2.77:1.) Per § 480's line: a colour that *communicates state on a theme surface* is a status role and takes a token; a colour that *is data* keeps its fixed hue.
- **Fixed canvases** that never follow the device theme — the `@media print` sheet (white paper, so a token would resolve to the *screen* theme and print dark-on-dark) and the race-day brand hero.
- **DATA palettes** — badge tier metals, medal metals, workout-kind tints, chart series, cartographic markers. Per § 480's line: a colour that *communicates state on a theme surface* is a status role and takes a token; a colour that *is data* keeps its fixed hue.
- **Fixed canvases** that never follow the device theme — the `@media print` sheet (white paper, so a token would resolve to the *screen* theme and print dark-on-dark), the race-day brand hero's verdict green, and `/runs/[id]`'s map overlay pill. A fixed canvas is exempt from *theming*, not from contrast, and it owes a guard of its own — see § Web boundaries. Two literals on such a canvas **invert** relative to the theme: the pill's hairline reads 6.084:1 as the old border value and 2.366:1 as the 3:1 line token, and its label read 1.402:1 as `--color-text-secondary`.

Two things the sweep behind it taught, both worth carrying forward. **The frozen fill is the commoner defect, not the frozen ink**: a confidence chip's `#d1fae5` read 14.253:1 against the dark card it sat on — a pale mint panel blazing on dark purple — while its own ink was a respectable 4.835:1, so a fix justified only on foreground contrast misses the worse half. And **the naive token swap can be much worse than the literal**: a gold star over a *fixed* 0.65-black scrim reads 4.196:1 as `#fbbf24` and 1.123:1 as `--color-crown`, because crown is deliberately the dark gold for light surfaces. Measure it on the surface the site actually paints ([decisions.md § 503](decisions.md)).

Round 13 **inverted the ban into a complete register**, because a named-hue list cannot close the hole it leaves — the next frozen fill just picks a fortieth hue, and § 511 had logged the size of that hole (172 literals across 29 files carrying hues outside the status vocabulary). Every six-digit literal outside `app.css`'s declaration lines must now appear in `REGISTER` with an **exact count and a role** from a closed vocabulary: `cartographic`, `brand-mark`, `brand-hue`, `data`, `fixed-canvas`, `gradient-stop`, `svg-art`. The named-hue rule is kept for its *message* (for a status role, "route it onto the token" is always the answer), not for its reach.

§ 536 **retired an eighth role, `theme-pair`** — a literal declared once per theme as a local custom property, the entry recording the debt. Its only holder was RouteHeatmap's kept-route violet, and the honest reading is that a theme-keyed value is never a reason to freeze a hex: it is a token nobody has minted yet. Keeping the role would keep the cheap option available exactly where the durable one is obvious, so the violet became `--color-route-pinned` and the role went with it. Two numbers worth carrying: as of § 536 the register held **95 painted literals across 19 files** (not the 308 an earlier count reported — that figure swept in `app.css`'s own 186 declarations and 27 hexes inside comment prose), and the scan reached `.svelte` / `.css` only, so the **199** six-digit literals in `.ts` were outside it. Those are not unexamined — `basemap_contrast.ts` holds most of them and `basemap_contrast.test.ts` grades each against real basemap samples at 3:1 — but "complete" means complete over the two style extensions.

§ 546 **took the register into `.ts`, and split the rules by whether their remedy exists.** The `199` figure decomposed the same way the `308` had: **87 painted in 11 production `.ts` files, 72 inside `.test.ts` fixtures, 40 in comment bodies.** The named-hue ban and the dead-fallback rule *stay* on `.svelte` / `.css`, and that is now a decision rather than an omission — their failure message is "route it onto the token", and in `basemap_contrast.ts` that is impossible (MapLibre parses paint values itself and throws on a `var()`) while a rasterised share card has no theme to follow at all. **A guard whose remedy the caller cannot perform teaches the next round to loosen the assertion.** The complete register asks for a *role*, which every `.ts` literal can answer, so it is the rule that reaches `.ts`. Both halves also shrank that round: the style side to **92 across 18 files** (the privacy-zone circle's three reds moved onto `mapZoneBoundary`), the `.ts` side to **76 across 9** (five card builders stopped spelling the same two palettes). Two consequences worth knowing before editing one: two of the `.ts` entries (`route_markers.ts` at 7 literals, `pace_segments.ts` at 6) are **TS↔Dart parity pairs**, so a value change there is a two-platform change; and the `.test.ts` exclusion is asserted **non-empty**, because a scope decision that has quietly stopped excluding anything has become dead machinery (§ 534).

**A rasterised card's palette lives in one module.** `lib/share/og_card_palette.ts` holds the light card (run / route / badge unfurls) and the dark one (recap unfurl + the in-app recap share PNG), each ink carrying its measured ratio and the ground it was measured against. Five card builders had each spelled these independently — 22 literals for 9 values, the two recap cards byte-identical — and two cards of the same product drifting apart is invisible until someone sees the unfurl and the shared PNG side by side. A card keeps only the hues that are genuinely its own (the route card's start / finish caps).

That settles a question § 511 deferred: it considered a "no hex in a border" rule and declined it as a second allowlist duplicating the first. **There is one register, and it is keyed on `(file, hue)` — never on the CSS property** — so a border literal is an entry like any other, and a test asserts both surviving border literals are in it. Two role distinctions carry weight. A third party's **logo geometry** is theirs to tone (`brand-mark`: the Google "G", Apple's required black); the same party's **hue reused as our own paint** is not covered by that requirement (`brand-hue`), and measured on the tinted disc it lands on rather than on the bare surface, five of six provider glyph inks miss 1.4.11's 3:1 floor. And where a literal is a measured failure the register records it as an **open debt with its figure and the ground it was measured on**, as a frozen set — a register whose point is completeness must be able to say "known bad, not yet fixed", or the honest finding gets dropped to keep the suite green.

**A map overlay's contrast is owed to the basemap, and the basemap is not the theme.** `basemap_contrast.ts` holds every colour the seven map surfaces paint, keyed on `basemapIsDark` (which sits beside `buildMapStyleUrl` and shares its slug switch, so URL and palette cannot drift). Keying on `prefers-color-scheme` is wrong in both directions, because the map-style preference decouples basemap luminance from the OS theme: `outdoors` is a light basemap under a dark OS, `dark` and `satellite` are dark ones under a light OS. Two facts shape the module and are pinned as tests rather than left as comments: **a translucent casing cannot carry the floor** (2.273:1 at 0.25 over the dark sample), so every line clears its ground unaided; and **a label halo is ground-coloured on purpose** (1.038 / 1.148:1), so it holds a glyph apart from mid-tone map *features*, not from the land fill, and the ink must clear the ground on its own.

Every rung is graded against **four** grounds, not two: the dark land sample, and — because land is the *pale* end of a light basemap — the light land sample, the light-basemap water fill, and the keyless OSM raster backdrop. **A rung that clears its tightest ground by a fraction of a percent has not cleared it** (§ 522 / § 535): the privacy-zone circle's single `#dc2626` read 3.011:1 over light-basemap water against a 3:1 floor, and no single red does better because a red dark enough for the pale grounds fails the dark one — so it split into `mapZoneBoundary`'s pair like every other rung (§ 546). A surface may own its **slug table** (the route builder does, for `hybrid` imagery-with-labels), but never the *precedence* that turns a slug into a URL nor the *classification* of that slug's luminance: `styleUrlForSlug` and `basemapIsDarkForSlug` are the two halves, and `map_surface_basemap_guard.test.ts` fails any registered surface that calls `maptilerStyleUrl` itself. Skipping that precedence skips the keyless OSM-raster fallback, which on web also drops the basemap **credit** — MapLibre reads it out of whichever style document loaded, so no style means no attribution, a licensing gap and not a cosmetic one (§ 491).

**A gradient is a fill, and its palest stop sets the ink.** `gradient_foreground_guard.test.ts` reads each text-bearing ramp out of the source, extracts its stops, and measures the declared foreground against every one — bare and under each declared translucent veil at that veil's own peak. It pins the expected stop *count* per ramp for the reason § 511 gave about floors read out of the tree: a regex that matches nothing must not pass. Overlapping veils are measured one at a time when they peak at opposite corners, because stacking them asserts a composite no pixel shows.

## Web boundaries — `--color-border` is a line, `--color-fill-subtle` is a fill

**A border token is a line or a fill, never both** — § 503's rule for status tokens, one role over. `--color-border` is the *one* line token and its whole guarantee is WCAG 1.4.11's **3:1** against every surface a boundary is drawn on (3.906 / 3.531 / 3.313 / 3.112 light, 3.330 / 3.911 / 4.068 dark, in lockstep with mobile's `AppTheme.parchmentLine` / `duskLine` — [decisions.md § 487](decisions.md)). It shipped at 1.458:1 on the light card, which meant web had **no** token guaranteeing a visible boundary while mobile's whole card/divider grammar rested on one. In light the card fill is `#FFFFFF` on a `#F7F3EC` page — 1.116:1 apart — so the hairline is the only separation there is, which is exactly the "visual information required to identify a UI component" 1.4.11 sets at 3:1.

So: **draw every border, outline and divider in `--color-border`, and every subtle neutral *fill* in `--color-fill-subtle`.** The second holds the value the first shipped with, so a progress-bar track, an inactive bar cell, the neutral metadata chip, a button hover and a skeleton shimmer stop did not move when the line token was raised. Three rules, all in `contrast_guard.test.ts` with both-direction fixtures, because the split is decided by the **CSS property** and nothing else:

- **A fill token may not draw a `border` / `border-*` / `outline`.** `background` is out of scope in both directions — eight dividers here are legitimately a 1px background or a grid-`gap` show-through in `--color-border` — and `stroke` is too, because a chart gridline is reference ornament inside a graphic rather than a component edge, and is the one class deliberately left below the floor.
- **The line token may not paint text.** 3:1 cannot reach AA's 4.5:1; muted type is `--color-text-tertiary`. A **quoted** `'var(--color-border)'` is banned outright rather than classified, because syntax cannot decide it — the plan surfaces' `rest` workout entry was handed to a `--kind` custom property that the consumer applied to a 3px stripe *and* to the label's `color:`, so one entry was a boundary and text at once.
- **The line token may not be thinned** toward `transparent` or toward a surface token. Mixing it with an *accent* is not a thinning and is spared: the 19 `color-mix(<accent> N%, var(--color-border))` borders here all move contrast **up**, because the accent is darker than the line in light and lighter than it in dark.

**A gradient needs its own foreground contract.** Neither a hex nor a token fixes a gradient whose stops straddle the mid-luminance band: white on `--gradient-primary` read 2.081 / 2.153:1 on its light-mode third stop and its two dark-mode stops. Identity avatars therefore take `--gradient-avatar`, two stops built from token pairs that flip *together* with `--color-on-primary`, and the guard resolves **every** stop rather than the pair it was written with. Where the fill is a per-entity hue rather than a token, pick the foreground by **computed** contrast and clamp the fill out of the dead band — `format/avatar.ts` is a faithful port of mobile's `identity_avatar.dart` ([decisions.md § 481](decisions.md)); at `hsl(h, 50%, 55%)` a fixed white fails AA on 297 of the 360 hues and the better of white-and-ink still bottoms out at 3.975:1.

**A fixed canvas is exempt from *theming*, not from contrast, and it needs a guard that derives its own floor.** The race-day hero follows no theme, so nothing on it was ever checked against a surface token — and so nothing on it was checked at all. Build such a canvas from the theme-**independent** `-strong` fills (already held to white-on-AA and forbidden a dark override), then composite every veil the surface layers on top over the **worst** stop *including the midpoint*, which neither end measures. Inset sub-panels on a mid-tone canvas must be **deeper** than it, not lighter: a light veil spends the only foreground's headroom, so a 0.10–0.12 white veil left its own white text at 4.274–4.463:1 where 0.12 black gives 6.578:1.

## Chart and band palettes — per brightness, separated by luminance, computed

A DATA palette (chart series, a segmented band) is still bound by WCAG 1.4.11: every mark carrying meaning alone owes **3:1 against the surface it is drawn on**, in *both* brightnesses. One fixed set of hues almost never clears that in both — so a data palette is declared **per brightness** (web: tokens in `app.css`'s three theme blocks; mobile: a `light` / `dark` pair resolved off `theme.brightness`) and the two platforms carry the same values, checked by a lockstep test rather than by comment.

Separate the marks by **luminance, not hue**: a WCAG ratio is computed from relative luminance alone, so a luminance ladder *is* a greyscale ladder, which is what survives red-green colour-vision deficiency. Ramp direction inverts with the background ([decisions.md § 489](decisions.md)).

Pairwise 3:1 between marks is often unreachable — *n* marks need 3^(n−1) and sRGB offers 21:1, so four bands are the ceiling and five are impossible. When it is, say so and pick the mechanism that does work: for a segmented bar, hold every band to 3:1 against the surface and draw the gaps between segments **in that surface colour**, so each boundary is delineated by a separator guaranteed visible against both its neighbours. The current pairs are `--chart-fitness/-fatigue/-form` ↔ `ChartPalette.series`, `--zone-1..5` ↔ `ChartPalette.zones`, and `--kind-1..6` ↔ `ChartPalette.kinds`.

**On mobile, all four scales live in one place: `ChartPalette` in `packages/ui_kit`** — categorical `series`, ordinal `zones`, sequential `ramp` (plus `bar`, the single-series fill, which is `ramp.last`), and categorical `kinds`, the six planned-workout marks. Every ratio is computed by `packages/ui_kit/test/chart_palette_test.dart`. **`colorScheme.primary` is not a chart colour**: its hue is not stable across brightnesses (dusk in light, coral in dark), so a mark painted in it means "data" in one theme and echoes an interaction affordance in the other — which is how web's split bar ended up with its two halves 1.032:1 apart ([decisions.md § 503](decisions.md)). Every chart card also wears one header, `ChartCardHeader`, whose eyebrow takes `onSurfaceVariant` — **not `colorScheme.outline`, which is 4.058:1 on the light card and is a 3:1 *boundary* token, not a text colour**. `chart_surface_guard_test.dart` (both mobile twins) count-pins both tokens per chart surface and requires each to reference the header and the palette.

**A new categorical scale is a sibling, not an extension.** `kinds` could have been more entries on `series`, and is not: `series` *means* the three training-load curves and is pinned at three by the web lockstep, so overloading it would conflate two unrelated legends and break a guard in the other language's suite. A sibling keeps one home and one guard shape while each scale keeps its own cardinality and its own floor.

**A scale that paints TEXT is the case to look for, and the answer is usually to stop.** The workout-kind palette was both a 3 px cell edge and the colour of the kind label, so it owed 1.4.3's 4.5:1 rather than 1.4.11's 3:1 — and six categorical entries cannot reach 4.5:1 apart on a pale surface without collapsing into six near-blacks. Minting a second, 4.5:1 twin scale was measured and rejected: on dark, `tertiaryContainer` caps the range at 9.324:1, so six rungs from 4.5:1 up can step only 1.157 apart — indistinguishable in greyscale, which is the failure the ladder exists to prevent. The mark keeps the hue at 3:1; the label takes a text token; **identity is carried by the localized kind WORD, which every site already renders**, so hue is redundant reinforcement rather than the sole channel ([decisions.md § 489](decisions.md)'s colour-only rule). Nine kinds share six marks, which is itself proof hue cannot name a kind.

**An alpha multiplier is not a contrast argument.** A token guarded at 3:1 stops being guarded the moment a caller thins it: the training-load gridlines drew `outline` at 0.5 and then multiplied by another 0.45 inside the painter, compositing to 1.297:1 on the light card — a labelled scale whose lines could not be seen. Read the token at full opacity, or compute the composited ratio and write it down. For the three boundary tokens the rule is absolute and guarded — see § Mobile muted text.

**For a non-boundary token, "measured" is the whole rule, and the measurement is registered.** `primary`, `onSurface`, `primaryContainer`, `surface` and the rest *do* have headroom, so a ban would be wrong — but a thinning is only legitimate once someone has computed it on the surface it actually paints. `thinned_token_register_test.dart` (both mobile twins) count-pins every surviving thinning per file, and each entry states the role and the number, so a new alpha fails until it is measured. Three obligations, by role: **text** owes 4.5:1 composited; an **icon, border, or any mark that carries meaning** owes 3:1 composited — and a border that is the only thing separating a panel from its page is a mark however decorative it looks; a purely decorative **wash** owes nothing but is still recorded, because a fill's alpha changes what its own children composite against. A **fill whose presence is a state signal is not a wash**: at the alphas these use (1.00–1.26:1 against the untinted neighbour) the tint cannot be the cue, so 1.4.1 needs a non-colour one beside it. And un-thinning is not always the fix — the calorie goal line's `secondary` reads 2.767:1 on the light card at *full* strength, so the defect was the token choice and it took the mark token instead. Every number is computed in `packages/ui_kit/test/thinned_token_contrast_test.dart`, which pins each repair in both directions: the replacement clears its floor **and** the value it replaced did not.

**An `Opacity` widget is a second multiplier** and compounds with any alpha inside it: a plan-calendar out-of-month numeral drawn at `onSurfaceVariant` × 0.4 inside `Opacity(0.55)` composited to 1.432:1. More generally, **an `Opacity` around a subtree containing text is a contrast multiplier on that text, so its value is bounded above by WCAG 1.4.3 rather than chosen by taste** — and both the glyph and the fill behind it are inside the layer, so measure the pair *after* dimming, not the glyph against an undimmed fill. It is not a layout knob either way: `Opacity` sizes and positions its child exactly as if absent. The two surfaces that dim a subtree to mean "out of scope" (adjacent-month calendar cells, retired gear) share one bounded token, `AppTheme.dimmedSubtreeOpacity`; `dimmed_subtree_opacity_test.dart` derives the bound and pins the value inside it.

**Never assert a ratio you did not compute**, in code, comment, or commit message — every figure in this section was measured against the real tokens, and the audit that prompted them was wrong in both directions more than once.

## Chart scales — a normalised plot must still show magnitude

A min/max-normalised series drawn without an axis shows shape and hides scale: CTL 45 and CTL 450 render pixel-identically. Any plot that normalises to its own extremes owes a labelled y-scale — a gutter, round ticks off a 1/2/5×10^n ladder, and gridlines. On web, y labels go in a **CSS gutter beside** the SVG when the chart uses `preserveAspectRatio="none"`; text inside that viewBox is stretched horizontally at every viewport width.

## Mobile component themes — style in `AppTheme`, not at the call site

On the Flutter apps, presentation that every instance of a widget should share lives in `packages/ui_kit/lib/src/theme/app_theme.dart` (both the `light` and `dark` getters), never repeated per call site. Five contracts are now themed, each guarded by a test in `packages/ui_kit/test/` ([decisions.md § 482](decisions.md) and [§ 487](decisions.md)):

- **Lines.** There is **one line token per brightness** — `AppTheme.parchmentLine` / `AppTheme.duskLine`, each ≥ 3:1 against the surfaces it is drawn on (WCAG 2.2 SC 1.4.11). It is pinned in three places at once, because Material 3 reads three different names for the same job: `ThemeData.dividerColor` (hand-drawn `Border`s), `DividerThemeData.color` (`Divider`/`VerticalDivider`), and `colorScheme.outlineVariant` (`Divider`'s M3 default, `TabBar`'s divider). **Never write a literal grey for a hairline** — read `theme.dividerColor`. A *text* colour is a different bar (4.5:1) and takes `onSurfaceVariant`, not the line token — and not `colorScheme.outline` either (see § Mobile muted text).
- **App bars.** `AppBarThemeData.backgroundColor` is a `WidgetStateColor` that resolves a distinct fill in the `scrolledUnder` state, with `surfaceTintColor` disabled (the seeded tint is off-palette). Don't pass `backgroundColor:` to an `AppBar` — a plain colour resolves the same in both states and re-flattens the bar.
- **Bottom sheets.** `bottomSheetTheme` owns background, top radius, drag handle and `clipBehavior`; a call site names only what it genuinely differs on. `useSafeArea` is **not** a theme field, so the rule is per call: **`isScrollControlled: true` implies `useSafeArea: true`**, or a tall sheet paints under the status bar. `bottom_sheet_safe_area_guard_test.dart` (both twins) fails the pair.
- **Text fields.** `inputDecorationTheme` names the outlined language at radius 12. **Don't declare `border: OutlineInputBorder()` at a call site** — it re-pins the radius to Material's default 4. A field that is deliberately a different component (a filled borderless search box, a pill composer) still says so locally.
- **Cards.** The card theme carries **no horizontal margin**. Horizontal insets are the layout's job, so every card in a list starts at its parent's padding edge; a card that insets itself lands at a different left edge from its siblings. The vertical 4 stays, because stacked-card sites rely on it for separation.
- **Accent coral is two tokens, a fill and a mark.** `AppTheme.coralDeep` is the light theme's accent **fill** — the FAB background and the navigation bar's indicator tint — and nothing else: at 2.767:1 on parchment it can carry neither a glyph nor type. `AppTheme.coralMark` is the accent **foreground**, and is light `colorScheme.secondary` for that reason (≥ 4.566:1 on every light surface). Dark needs no split: its `secondary` is `lilac`, already legible. The mark value is web's `--color-secondary-text` and the fill value is web's `--color-secondary`, and both halves of that lockstep are asserted from `apps/web/src/lib/contrast_guard.test.ts`.

**A component theme owes the same measurement a call site does, on the surface the widget actually paints.** `AppTheme` is where the tokens are declared, which is exactly why nobody re-measures it — two of its own pairings shipped under 1.4.11's 3:1 for a year. Both were found only by asking what pixel sits behind the mark, per [§ 503](decisions.md): the navigation bar's **selected icon is drawn inside the indicator pill**, not on the bar, so the tint is its background (`coralDeep` read 2.337:1 there and 2.767:1 on the bar — the flattering figure was the one on the bar); and a **FAB is a fill with its own elevation and shadow**, so the boundary is not the fill's to earn and the *glyph* is what owed the ratio (the fix moved the foreground to `ink`, 5.757:1, not the fill). `packages/ui_kit/test/app_theme_nav_fab_contrast_test.dart` computes all of it in both brightnesses and pins each repair in both directions.

## Mobile type sizes — a step on the scale, never a `fontSize:` literal

`AppTheme`'s `textTheme` exists so no call site has to name a size ([decisions.md § 482](decisions.md)). It resolves the Material 3 steps plus one override — `labelSmall` at 11 px, the declared micro-label floor — giving **11 / 12 / 14 / 16 / 22 / 24** and up; `packages/ui_kit/test/type_scale_test.dart` pins them, in both brightnesses and inside a pumped tree (read straight off `AppTheme.light`, `textTheme` carries *no geometry at all* — Material applies the locale's geometry in `ThemeData.localize` at build time, so a scale test that reads the getter compares nulls and passes for the wrong reason).

So: **name the step.** `theme.textTheme.<step>`, or `.copyWith(...)` on it when only weight, colour or letter-spacing differs. Where the ambient `DefaultTextStyle` is already that step, **drop the argument** rather than restating it — `Material` supplies `bodyMedium`, a `TextField` `bodyLarge`, a `CircleAvatar` `titleMedium`, all pinned by the same test. Two things to know before choosing:

- **A value between two steps snaps upward.** 13 was the commonest literal in the tree (eight sites) and is not a step at all; every one went to 14. Never shrink type to reach a step.
- **Naming a step replaces the ambient style, it does not merge into it.** The M3 geometry styles are `inherit: false`, which is only safe because every step already carries `onSurface`. Inside a host that supplies its own foreground — a button, a chip — dropping the `fontSize:` is right and naming a step would repaint the label.
- **A theme override that displaces a step has to restate it, and that literal belongs in `AppTheme`.** Some Material component themes resolve `theme ?? defaults` as an **OR, not a merge**: `RawChip` takes `chipTheme.labelStyle ?? chipDefaults.labelStyle`, so the `labelStyle` that exists to carry the selected/unselected `WidgetStateColor` ([§ 476](decisions.md)) displaced M3's `labelLarge` whole and left every chip label in the app sizeless, landing on the ambient 14 by coincidence. The size is now restated in `AppTheme` beside the colour — the theme's own definition of a step is the one legitimate home for a `fontSize:` literal, count-pinned like the other exemptions. Keep `inherit: true` when you do it, so the locale geometry's family and baseline still arrive by merge, and check the value against all three of Material's geometries before hardcoding it (`labelLarge` is 14 / w500 / 0.1 / 1.43 in every one; only the baseline differs).

`font_size_literal_guard_test.dart` (both mobile twins, scanning `lib` + `packages/ui_kit/lib`) fails a numeric `fontSize:` and classifies by enclosing constructor, because one case is genuinely not on the scale: `IdentityAvatar.fontSize` sizes an initial inside a circle whose diameter the caller chose, so it is a **graphic** argument. A named constant or a read off the scale (`kMapAttributionFontSize`, `theme.textTheme.labelSmall?.fontSize`) is the durable form and needs no exemption. The recorded exemptions are count-pinned per file on the § 480 model — the fixed-canvas share rasterisers, map overlay chips and pins, two load-bearing graphics (`BoxFit.scaleDown` per § 497), and `ErrorWidget.builder`, which has no `Theme` ancestor at all.

## Mobile stat cells — ui_kit `StatTile` in a `StatGrid`

A metric shown as a value over the name of the thing it measures is ui_kit's `StatTile`, at one of three emphases — `.small` (a dense secondary grid cell, icon-led), `.medium` (a live-updating column, and the only tier with tabular figures, because a proportional digit changes the value's width every second), `.large` (a hero row) — never a new private class. Twelve of those had accumulated by round 11 of the #666 audit, drifting to six value type sizes, two label sizes and two muted colours ([decisions.md § 509](decisions.md)).

**A value may only shrink; a label may truncate.** `.medium` and `.large` scale the value+unit pair with `BoxFit.scaleDown`, which needs a **bounded** parent — an intrinsically-sized cell in a `Row(mainAxisAlignment: spaceAround)` has no bound, so the row bursts instead of the number shrinking. Lay a stat row out with `StatGrid`, which bounds every cell by construction and derives its column count from the width a cell needs at the current text scale (`kStatCellMinWidth`, scaled); with four or fewer cells that fit it is byte-identical to the `Row` of `Expanded` it replaces. Muted text is `onSurfaceVariant`, never `colorScheme.outline`.

A list group's uppercased eyebrow is ui_kit's `SectionHeader`. It is deliberately distinct from `ChartCardHeader` (the chart-card title, with a note slot) and from a `titleMedium` *section title*, which is a heading rather than an eyebrow. `apps/mobile_android/test/stat_tile_guard_test.dart` (mirrored on iOS) closes both class sets: a new stat-named `StatelessWidget` or a new `_SectionHeader` fails until it is either migrated or listed with the reason it is not one.

## Mobile empty states — ui_kit `EmptyState`

On the Flutter apps, a whole-surface "nothing here yet / not found" state renders ui_kit's `EmptyState` (icon 48, `all(32)` padding, titleMedium title, bodySmall body, optional CTA — reusing `ErrorState`'s icon size and padding; [decisions.md § 485](decisions.md)), never a hand-rolled centred `Text` or bespoke icon column; tiny inline empty hints inside a larger card/list section stay inline. `architecture_guards_test.dart` fails any `class …EmptyState` declared in `lib/`.

## Mobile loading surfaces — never a bare centred spinner

On the Flutter apps a loading surface says what is coming, and holds the space it will occupy. **Never `Center(child: CircularProgressIndicator())`** — it reports only that something is happening, occupies none of the room the content needs, and lands the arriving frame as a re-layout instead of a fill. Choose by the shape of the surface that is loading ([decisions.md § 492](decisions.md) for the primitives, § 502 for the per-surface split):

- **Rows in a bounded host** (a tab body, a `Scaffold` body, a settings form, a chat pane inside an `Expanded`) → `ListSkeleton(rows:, rowHeight:, hasLeading:)`. It owns a non-scrolling viewport, so it clips rather than overflowing when the host is short.
- **One section of an already-laid-out scrollable** (a comment list under a run, a picker inside a dialog) → `ListSkeleton.section(...)`. Same rows at intrinsic height, no viewport, so it is safe where the incoming height is unbounded and the default constructor would throw.
- **A genuinely mixed layout** (a map plus stats, a detail body of prose and controls) → `FullBodyLoader(kind:, label:)`.
- **A composite** — compose the primitives into the shape the surface settles into rather than reaching for a fourth thing; `profile_screen`'s header-plus-tabs load is a `section` block, a `Divider`, and an `Expanded(ListSkeleton(...))`.

ui_kit carries no localisations, so every one of these takes a `label` for the screen reader — pass `l10n.commonLoading` rather than a literal. `architecture_guards_test.dart` fails any bare centred spinner in `lib/`.

## Mobile shared controls — three widgets a screen may not rebuild by hand

Three cross-cutting shapes had drifted to one bespoke copy per call site, and each is now a `packages/ui_kit` widget with a source guard in `apps/mobile_android/test` (and its iOS twin). All three bans exist because the drift is invisible in review: every individual copy looks reasonable, and only the fleet reads wrong ([decisions.md § 541](decisions.md)).

- **`ProgressBar`, never a bare `LinearProgressIndicator`.** Eleven bars had five heights, four radii and four track colours. A bar owes 1.4.11's 3:1 **twice** — the track against the page (so an empty bar is not nothing) and the fill against the track (so you can see where it ends) — and no colour pays both: chaining two 3:1 steps needs 9:1 between the page and the weakest fill, and `AppSemanticColors.warning` is 5.499:1 from parchment, capping the best possible answer at 2.345:1 light / 2.563:1 dark. So the track is chosen for the fill axis (`surfaceContainerHighest`, worst fill 4.724 / 4.997) and the component boundary is a **drawn hairline** in the § 487 line token (3.531 / 3.330). A fill you pass must clear 3:1 on that track — `colorScheme.error` does not (2.991:1 light); pass `AppSemanticColors.danger`.
- **`StatusPill`, never a hand-built stadium `Container` around a `Text`.** Twenty-four of them carried nine paddings and four spellings of the label size, two of which (`labelMedium` and `bodySmall`) are the same 12sp. The pill has two sizes and the padding, the type step, the glyph size and the dot size all follow the size — a call site picks *which pill*, never a number. Two survivors are count-pinned with reasons in `status_pill_guard_test.dart`; a new one needs a reason of that kind, not a new padding.
- **`ChoiceChipRow`, never `SegmentedButton`.** The segmented control divides its width equally and then truncates the labels inside — no ellipsis, no fade, no overflow banner. Ten of eleven sites lost characters against real Roboto; two lost them at 1.0x. The ban is **allowlist-free**: the one site that measured clean did so for two labels in seven locales, which is a coincidence and not a property.

Two habits these three carry, both general:

- **Derive the numbers.** The bar is 6 tall because Material's own fill lane is 4 and a hairline costs 1 each side; the pill's glyph is the label size plus two; the chip row's spacing is one value. A derived number survives a type-scale change and a picked one does not.
- **Prove the fix on the painted tree.** All three suites read the *rendered* decoration, size or colour back off the widget rather than re-stating the token, and each was proved to fail by perturbing the source — the progress bar's fill-vs-track assertion still passed with the old invisible track, which is exactly why both of its axes are asserted separately.

## Mobile tap targets — no `VisualDensity.compact` on IconButtons

On the Flutter apps, every `IconButton` keeps a ≥48dp tap target (WCAG 2.5.8 / the Material touch-target floor). **Never set `visualDensity: VisualDensity.compact` on an IconButton** — compact density subtracts 8dp per axis *after* constraint resolution, so it shrinks the hit area to ~40dp even when the button carries an explicit `BoxConstraints(minWidth: 48, minHeight: 48)` (measured by hit-testing; the earlier "keep compact, add the constraint" idiom from issue #255 was a placebo — see [decisions.md § 435](decisions.md)). For visual tightness shrink the *icon* (`size:` / `iconSize:`) and keep the 48dp box; don't declare sub-48 `constraints:` and don't cap the button with a sub-48 `SizedBox`. `apps/mobile_android/test/tap_target_guard_test.dart` (mirrored on iOS) scans all of `lib/` and fails any of the three patterns. Labeled buttons (Text/Filled/Outlined/Segmented) may keep compact density: they retain a ≥40dp padded target plus a wide label surface, which clears WCAG 2.5.8's 24px floor — the 48dp floor is the icon-button spec, where the glyph is the whole target.

## Mobile fixed boxes and OS text scale — four mechanisms, chosen by what the box is for

On the Flutter apps a literal dimension around localized or numeric text is a bug waiting on a device setting. Android and iOS both let a user take text to 2x, and unlike a narrow viewport that failure is **silent**: a `Text` too wide for its `SizedBox` is cropped with no overflow stripe and no exception, so the user reads a wrong number rather than a broken layout. **Locale is the same axis** — French "DÉMARRER" and Portuguese "Carboidratos" break boxes English never does, at 1.0x.

Pick the mechanism from what the box is *for* ([decisions.md § 497](decisions.md) for the vertical axis, § 500 for the horizontal):

1. **The box grows.** A layout box in a scrollable column takes `ConstrainedBox(minHeight:)`/`(minWidth:)` instead of a fixed one.
2. **The dimension is text-derived and scales.** A chart label lane or an aligned numeric column reads `MediaQuery.textScalerOf(context).scale(n)`. This preserves the 1.0x geometry exactly and — unlike a per-row intrinsic width — keeps a column of rows aligned.
3. **The text scales down into the graphic.** Text inside a fixed-size graphic whose size is load-bearing (a progress ring, a calendar day dot, an avatar, a bar whose *width* encodes a value) takes `BoxFit.scaleDown`: 1.0x is untouched and a larger setting is fitted to what the graphic can hold, which beats the crop it replaces.
4. **The row reflows.** Horizontal-only. A `Row` whose children are all text becomes a `Wrap`; `WrapAlignment.spaceAround`/`spaceBetween` lay a single run out exactly as the `Row` did, so 1.0x is unchanged and the reflow happens only when the content genuinely does not fit. Prefer it to ellipsis wherever a truncated label stops being a name.

**`SegmentedButton` is not usable where its intrinsic width can exceed its parent.** § 486 exempted it from the narrow-width sweep because it has no knob to bind; the same fact makes it fail under text scale in both directions — given room it overruns the parent, given none it squeezes its segments and clips the labels inside them with no ellipsis and no exception. Use chips in a `Wrap` (as `mileage_trend_card.dart` does) when the labels are localized and the container is a card.

**Measure, don't assert.** `flutter_test` renders in a fixed-advance font, so an absolute "it fits" claim measured there is not a claim about a device. Pin the *derivation* instead — that a lane grew by the same factor as the text it holds, or that a label's box stayed inside its container — and verify absolute fits against a real proportional font before quoting a figure.

**An aligned text lane is `TextLane` (ui_kit), never a `SizedBox`.** Mechanisms 1 and 2 collapse into one widget for the commonest shape — a set number, a date, a rank, a weekday leading a row. `TextLane(width: n, child: Text(...))` reads `n` as a floor scaled by `MediaQuery.textScalerOf`, so 1.0x geometry is preserved exactly, the lane tracks the scale, and a translation that still outruns it widens the lane rather than losing characters. Note the two *different* symptoms a fixed lane produces, because only one of them looks like a bug: a label with a break opportunity ("28 de mar.", "Série 12") **reflows inside the box** and makes its row taller than the rest of the column, while one without ("Desaquecimento", "120:00", "#999", "dom.") **paints straight over the lane beside it** — a `SizedBox` does not clip. `apps/mobile_android/test/text_lane_guard_test.dart` (mirrored on iOS) scans `lib/` and fails any literal-width `SizedBox`/`Container` whose direct child is a `Text`, or a `Column`/`Row` of nothing but `Text`; a fixed-size graphic keeps its box and takes mechanism 3 instead, and is not matched.

**A lane's floor is unbounded, so check what it can starve.** `TextLane` grows past its floor, and a `Row` lays its non-flexible children out before giving what is left to `Expanded` — so a very long term can take the whole row and leave the value zero width. Where the pair cannot share a line at 2x (a term beside its value, not a short lane beside a body), reflow with mechanism 4 rather than letting the lane win.

## Mobile adaptive width — `WidthClass`

On the Flutter apps, wide-layout recompositions key off `widthClassOf(context)` from `lib/adaptive_width.dart` — `compact` (<600dp) / `medium` (600–839dp) / `expanded` (≥840dp, a 10" tablet or landscape foldable). **Gate every wide-layout branch on `WidthClass.expanded`, never `medium`:** the `flutter_test` default surface is 800dp logical, so a `medium` gate would silently route every existing phone-oriented widget test through the wide path (see [decisions.md § 256](decisions.md)). Single-column reading surfaces (feed, timeline, settings, gym, nutrition, event detail) cap at `kContentMaxWidth` (720dp) and center **through `contentColumn(context, body)`** from the same file; multi-column compositions (dashboard, plan detail) pass their own wider `maxWidth` to it. Do not hand-roll the `widthClassOf` + `Center` + `ConstrainedBox` idiom — writing it out each time is why only four of 75 screens had a clamp at all (decisions § 538), and `adaptive_width_test.dart` fails any screen that names `kContentMaxWidth` without calling the helper. A surface whose point is to be full-bleed — a map, a heatmap — takes no clamp. When adding an expanded variant to a screen, ship both an expanded-layout test (set `tester.view.physicalSize` / `devicePixelRatio` to a ≥840dp logical surface) and a compact/medium regression pin that the default surface keeps the phone composition.

## Mobile fixed bands above a `TabBarView`

A header laid out above `Expanded(TabBarView)` in a non-scrolling `Column` is not merely long when its content grows — it takes the tab bodies' height, and then the `Column` overflows. **Every text child of such a band needs a `maxLines`**, because the band's height is the sum of its children and only the unbounded ones can move it. Neither `clubs.description` nor `user_profiles.display_name` carries a DB length constraint, and even at their composers' caps both overflowed a 320dp phone at default text scale (decisions § 537). Where the clamp hides prose, put the whole text one tap away in a scrollable sheet rather than expanding in place — an in-place expand re-creates the starvation. Guard the **derivation** (the header/tabs split does not move with content length), never a dp fit: the `flutter_test` font is wider than the device's, so an absolute fit is unmeasurable in CI (§ 500).

## Mobile FAB clearance — `fabScrollClearance`, never a hand-picked number

On the Flutter apps, a scroll view that a `FloatingActionButton` floats over reserves `fabScrollClearance(context)` at its bottom edge (`lib/fab_clearance.dart`), and a two-FAB column passes `fabCount: 2`. `Scaffold` paints the button over the body with its bottom `kFloatingActionButtonMargin` above the content bottom, lifted clear of `minViewPadding`, so the occluded band is `padding.bottom + 16 + fab height` — a number nobody guesses right. Before this rule four screens reserved nothing at all and six reserved four different values, of which the largest still under-cleared a stacked pair. The helper reads `MediaQuery.padding`, not `viewPadding`, so it composes with an enclosing `SafeArea` or a parent `Scaffold` that already has a `bottomNavigationBar` — both report zero, which is exactly where adding the inset again would leave a dead band. **Don't re-read `viewPaddingOf(context).bottom` beside it**, and don't wrap the FAB itself in a `Padding` for the same inset: `Scaffold` already applies it. `architecture_guards_test.dart` fails any new FAB screen that does either.

## Mobile app-bar actions — `AppBarActions`, three slots

On the Flutter apps, a screen with more than two toolbar actions builds them with `AppBarActions` (`lib/widgets/app_bar_actions.dart`). A Material toolbar spends 72dp before the title and 48 per action, so the title gets `width - 88 - 48n`: six actions on a 360dp phone measure **0dp of title**. The widget promotes the head of the list into whatever slots remain and folds the rest into one overflow menu, so ordering `actions` by how often the screen's user reaches for them is the whole design decision. A `destructive: true` action is never promoted — a toolbar icon carries no label, and a mis-tap should not be one step from the dialog (see [decisions.md § 498](decisions.md)); it renders last, behind a divider, in the error colour. Pass a widget that opens its own menu (a share `PopupMenuButton`) through `pinned` rather than `actions`: menus don't nest.

## Mobile tab strips — `AppTabBar`, and nobody picks `isScrollable`

On the Flutter apps, a sub-surface tab strip is `AppTabBar` (ui_kit) with a controller and a list of resolved labels. It measures the labels at the current text scale against the width it is given and derives `isScrollable` from whether they fit; a scrollable strip takes `TabAlignment.start`, never Material 3's `startOffset` default. Before this rule the fitness hub left the flag unset (filled, 46dp, flush at x=0) while social, profile and club detail set it true (`startOffset`'s 52dp left indent), so switching between the two sibling hubs moved the strip 26dp taller and slid the first tab 52dp right at the same time. **Icons are not a parameter**: they are the only thing that makes a strip 72dp instead of 46, and club detail's six text tabs show that tab count does not earn the extra height. `tab_strip_guard_test.dart` (both twins) fails any bare `TabBar(` or `Tab(` under `lib/`.

## Mobile detail maps — `detailMapHeight(viewport)`, from the constraints

On the Flutter apps, a hero map at the top of a detail scroll view takes `detailMapHeight(viewport.maxHeight)` (`lib/detail_map_height.dart`) from a `LayoutBuilder` wrapped around the scroll view. Four screens had each picked a number — 320, 320, 300, 280 — and none reflowed: the wide branch only fires at ≥840dp, so a 667×375 landscape phone kept the compact layout with a ~295dp viewport that a 320dp map filled outright. **Take the height from the constraints, not from `MediaQuery` arithmetic**: a `Scaffold` with an app bar has already removed the status bar and the toolbar from its body, so subtracting either again double-counts it, and which insets an enclosing `SafeArea` consumed is not knowable from the leaf. `detail_map_height_test.dart` (both twins) fails any `height:` literal on a box whose child is a map.

A test that reaches content below such a map must not drag by a fixed offset — the map's height moves with the surface, and a drag that starts *on* the map is claimed by `FlutterMap` rather than the list. Pump a tall surface so the whole body builds, as `dashboard_card_alignment_test` does.

## Mobile cards name themselves; a section header heads a group

On the Flutter apps, a card that needs a title carries it *inside* as `ChartCardHeader` (ui_kit), matching web's `<section class="card-elevated"><h2>`. An external section header is for a **group** of cards plus that group's action — the dashboard's goals section is the one that qualifies. Consequently a stack of self-heading cards separates by the card theme's own vertical margin and nothing else, and `_kSectionGap` marks only a real block boundary. Before this rule the dashboard changed grammar halfway down: an external `_SectionHeader` plus a 24dp gap above, then two cards hand-rolling the same `titleMedium` heading internally *and* padding themselves with a trailing `SizedBox(height: 24)`, one inlining a copy of `ChartCardHeader`'s typography, and one more with a `TextButton` beside a `titleMedium` — measured, the seams came out at three different values. `chart_surface_guard_test.dart` requires every dashboard card to reference `ChartCardHeader`, forbids `textTheme.titleMedium` in a card widget, and count-pins `_SectionHeader` at its one group use; `dashboard_card_rhythm_test.dart` asserts the stack repeats one gap and that the gap equals the card theme's margin.

## Mobile run rows — `RunListTile`, one row for every list of runs

On the Flutter apps, every list of runs draws `RunListTile` (`lib/widgets/run_list_tile.dart`): `.owned` from a local `Run` (selection mode, unsynced marker, inline track), `.public` from a `RunRow` plus the profile owner's id so a non-owner thumbnail is clipped server-side. Four surfaces had forked it — different leading widths, icon colours, distance weights, subtitle grammars and trailing slots, one of them under a comment claiming it mirrored another. **Two named constructors, not nullable parameters**, because the surfaces differ in which fields exist (§509). Deliberately not folded in: `activity_timeline_list`'s `_ActivityRowTile`, the cross-modal row over the `activities` view's thin `summary` jsonb, which has no `track_url` to draw and whose tinted avatar names the modality. `run_row_guard_test.dart` (both twins) pins the list of run surfaces, forbids a run thumbnail outside the shared row, and pins the cross-modal exclusion in both directions.

## Mobile motion — `AppMotion`'s rungs, and a loop that stops rather than hurries

On the Flutter apps, an animation's duration comes from `AppMotion` (`packages/ui_kit/lib/src/motion.dart`) — `brief` (200 ms, an element changing in place), `standard` (300 ms, an animated scroll or page change), `pulse` (1500 ms, a repeating loop) — and its curve from `AppMotion.curveStandard` / `curveEmphasised` / `curveOvershoot` / `curveLinear`. Each rung is the **modal value of its role** in what was already shipping, so the tier moved the off-mode sites and left the majority alone; a new role with no mode to derive from gets a documented local, not an invented fourth rung (the indeterminate-progress cadences — typing dots at 600, skeleton shimmer at 900, `ActivityLoader`'s web-ported 720/1050/1500 gait — are that case). `reduce_motion_test.dart` (both twins) fails any `Curves.` outside `motion.dart` and requires every rung to have an adopter.

**Reduce-motion is not a duration problem, and the framework only half-covers it.** Flutter scales a one-shot `forward`/`reverse`/`animateTo` to 5 % when `MediaQuery.disableAnimations` is set, so implicit widgets and one-shot controllers are handled already. It does **not** touch `repeat()` — `AnimationController._animateToInternal` holds the scale and `repeat` does not, for the reason its own source gives — and it does not touch an animated scroll, because `DrivenScrollActivity` runs on an `AnimationController.unbounded` that defaults to `AnimationBehavior.preserve`. Those two are the whole gap:

- **A repeating controller is driven by `syncMotionLoop(context, controller)` from `didChangeDependencies`**, never by a bare `..repeat()` in `initState`. Under reduce-motion it *stops* and parks at a rest value, so nothing ticks — animating faster still costs a frame callback per frame, and on the recording screen that ran for the length of the run. Driving it from `didChangeDependencies` is also what lets the runner flip the OS switch mid-session.
- **An animated scroll goes through `motionScrollTo`**, which calls `jumpTo` under reduce-motion. Feeding `animateTo` a zero duration is not an alternative: `DrivenScrollActivity`'s constructor asserts `duration > Duration.zero`. `PageController.nextPage` is the same activity and takes the same branch (`jumpToPage`).
- **`AnimatedSize` / `AnimatedCrossFade` may not be given `Duration.zero` either** — `RenderAnimatedSize` completes a zero-duration controller inside its own `performLayout` and asserts on re-dirtying itself. Render the target child directly instead of the animating widget. Everything else (`AnimatedSwitcher`, `AnimatedContainer`) takes `motionDuration(context, rung)` happily.
- **Motion is L4.** On the recording stack, wrap the `syncMotionLoop` call in its own try/catch + `debugPrint` so a halo cannot reach the trace, the camera or the clock.

Two animations deliberately do **not** collapse, and a new one that plays continuously should say which case it is: `run_detail_screen`'s trace replay and `undo_bar`'s countdown ring. The first is playback the user pressed play on and can stop (WCAG 2.2.2 is met by the control, and killing it would remove the feature); the second reports a real deadline, and a vestibular user needs the remaining time as much as anyone.

On web the same decision is already in force and needs no mirror: `app.css` carries the global `@media (prefers-reduced-motion: reduce)` net (pinned by `a11y_guards.test.ts`) plus per-component blocks, and `--transition-fast` / `--transition-base` are its duration rungs. Mobile's derived `brief` landing on 200 ms — web's existing `--transition-base` — is a convergence, not a copy.

## Local-tz date strings

Don't use `new Date().toISOString().slice(0, 10)` to derive a "yyyy-mm-dd today" or "yyyy-mm-dd of week start" string. `toISOString()` formats in UTC, so in any positive-offset timezone it rolls the date back a day before midnight local — week boundaries snap to the wrong Monday and prev/next navigation jumps two periods at once. Use `formatISO(d)` (or `todayISO()`) from `apps/web/src/lib/training/training.ts` — both build the string from `getFullYear` / `getMonth` / `getDate`, which stay in local time. The same rule applies to Dart on the mobile side: call `DateTime.local()` and format the components yourself, don't go via UTC.

## Web buttons

Canonical button styles live in `apps/web/src/app.css` under the comma-separated `.btn, .btn-primary, .btn-secondary, .btn-outline, .btn-danger` selector, plus the `.btn-sm` size modifier. Every variant works standalone (e.g. `class="btn-primary"`) or with an explicit base (`class="btn btn-primary"`) — they pick up the same padding, font size, radius, and transition.

**Don't redefine these classes in a page or component.** Local copies drift over time and the buttons stop matching across pages — exactly the problem the centralisation solved. If you need a one-off variant, give it a page-specific name (`.btn-google`, `.btn-save`, `.btn-ghost`, `.btn-connect`, ...) and let it extend the canonical class via the markup (`class="btn btn-primary btn-save"`). Avoid overriding the `padding` or `font-size` of the canonical classes — that's how drift starts.

The `/settings/upgrade`, `/login`, and `/` (landing) surfaces deliberately ship larger marketing-CTA buttons; those override the canonical sizes via Svelte-scoped local rules and are documented exceptions, not the pattern.

## Web file pickers — a button drives the input, never a `<label>` wrapping it

A native `<input type="file">` cannot be styled, so every picker hides it. The
tempting shorthand — a `<label>` wrapping a `hidden` input — leaves the control
with **no focusable element at all**: the input is out of the tab order and a
label is not a control, so clicking the label is the only way to open the
chooser. Four shipped that way (`/settings/integrations` twice,
`/clubs/[slug]/events/[id]`'s results CSV import, and `ImportRoute`'s drop
zone — whose own comment claimed keyboard users had a Browse button).

The idiom is a real `<button type="button">` whose `onclick` forwards to a
bound, off-screen input:

```svelte
<button type="button" class="my-btn" onclick={() => picker?.click()}>Choose file</button>
<input bind:this={picker} type="file" accept=".csv" onchange={onPick} style="display: none" />
```

**Not extracted into a shared component**, deliberately: the button carries each
surface's own component-scoped class (`.browse-btn`, `.import-file`, `.zip-btn`),
and Svelte's scoped styles do not reach into a child component's markup, so a
wrapper would force every caller to restyle or to leak its rules through
`:global()`. What generalises is the guard —
`a11y_picker_guards.test.ts` sweeps every template, bounding each `<label>` at
its own closing tag before looking inside it.

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

## Destructive actions — confirm OR undo, never both, and never a fake undo

A destructive action gets **exactly one** guard. Pick it by asking whether the
action can honestly be reversed:

- **Undoable** → call `deferDestructive` (`$lib/stores/undo.svelte`) and drop the
  `ConfirmDialog`. The row leaves the caller's local list immediately and the
  server mutation is **held** for the undo window, so `Undo` cancels a timer
  rather than compensating for a completed delete — it cannot fail. Restore by
  snapshotting the list (`const before = rows; rows = rows.filter(...)`) and
  putting the snapshot back, so ordering survives; if the delete cascades
  children server-side, filter the children out too or the list renders orphans.
- **Not undoable** → keep the `ConfirmDialog`. Use it when the delete cascades
  something the actor could not reconstruct, or when the row is an authored
  reusable artefact rather than a line of data (a routine, a saved meal, a
  plan).

**One intent, one undo — including a bulk delete.** Dismissing a collapsed group
of N notifications is a single intent, so it takes a single slot: one `commit`
that deletes all N ids in one query and one `restore` that puts the whole list
snapshot back. The queue's one-slot rule is about *separate* intents (a second
destruction commits the first); it is not a per-row rule and needs no widening
for bulk. Don't coalesce two separate intents into one bar — "Undo" would then
have to mean "undo both", which the user never asked for.

**A delete inside a modal may use undo, but the bar has to be in the trap.**
`Modal.svelte` traps Tab (the page behind is still in the DOM, there is no
`inert`), so a fixed bar over it is pointer-only unless the trap admits it. Any
rendered `[data-modal-trap-include]` host outside the dialog joins the ring,
appended **after** the dialog's own controls — the offer is a consequence of what
the user just did in the dialog, so that is where it reads (WCAG 2.4.3), and the
order must not depend on where the host sits in the layout. `UndoBar`'s
always-mounted region carries the attribute, so nothing pending means no extra
focusables and the ring is unchanged. Escape still exits, so widening the ring
does not create a keyboard trap (2.1.2) — what it fixes is 2.1.1, an affordance
that was not operable by keyboard at all. Pinned by
`src/lib/undo_modal_trap_guard.test.ts` plus a keyboard-only leg in
`tests-e2e/settings/gear.spec.ts`; **do not re-derive the "in-modal deletes must
confirm" rule**, it was resolved, not deferred.

Two things are forbidden. **Both guards on one action** — a modal followed by an
undo bar is two dismissals for one intent, and the modal is what teaches users to
click through without reading. And **an "Undo" that cannot actually reverse the
action**: a re-insert mints a new id, cannot restore cascaded children, and
cannot re-upload a deleted Storage object's bytes, so it hands back a different
row while claiming otherwise. If a class of action genuinely needs restore
after the fact, that is a soft-delete/trash feature — a `deleted_at` column, a
read-path filter and a retention story — scope it, don't fake it.

**A counter or badge that reads from the server moves on `commit`, not on
`defer`.** While the offer stands the row is still there and still unread, so the
truthful count includes it; decrementing early puts the badge at odds with every
`refresh()` for the whole window — indefinitely, for a user on the no-time-limit
setting. The list is the optimistic surface; a server-sourced aggregate is not.

**A timed undo is an accessibility surface.** WCAG 2.2.1 requires the limit be
turnable-off, adjustable, or extendable; the `undo_window_s` preference
(`/settings/preferences` on web, Settings → Preferences on mobile, registered in
[settings.md](../backend/settings.md)) carries a `0` = *no time limit* choice, and
hover/focus (web) or backgrounding (mobile) pauses a running window. Keep the
countdown out of the announced region — a ticking number re-announces on every
tick — and never let the bar steal focus. A platform that only *reads* the pref
fails 2.2.1: whatever surface offers a timed undo has to offer the adjust route
too.

### On mobile the same rules hold, with a different host

`deferDestructive` lives in `lib/widgets/undo_bar.dart` and takes the same
`DeferredDestruction { message, commit, restore, onCommitError }`. Three things
are mobile-specific:

- **The host is a root `Overlay` entry, never a `SnackBar`.** A snack bar is
  rendered inside its route's `Scaffold`, and a modal route's barrier carries
  `BlockSemantics`, which drops the whole route beneath it from the compiled
  semantics tree. Measured in `undo_bar_test.dart`: a snack bar raised while a
  dialog is up produces **no semantics node at all**, so TalkBack and VoiceOver
  can neither announce nor reach it — WCAG 2.1.1, the same violation web fixed by
  widening its Tab ring. An `Overlay.insert` entry lands above every existing
  entry including the barrier, so it stays reachable. This is why an in-sheet
  delete needs no exemption on this platform, and `showSnackBar` is separately
  banned in `lib/screens` / `lib/widgets` by an architecture guard.
- **A route pop does not flush.** The queue is a top-level singleton and its
  timer belongs to it, not to a `State`, so a pop cannot discard a pending
  commit — the mutation still lands. Web flushes on navigation because its bar
  describes a list the user has left; forcing an early commit here would be the
  only way to *lose* the offer, so we don't.
- **Therefore `commit` may not touch a `BuildContext` and `restore` must be
  mount-guarded.** Resolve `message` and any error copy before the call, capture
  app-scoped services (the api client, a store) in the closures, and open
  `restore` with `if (!mounted) return;`. Each adopting list is rebuilt from the
  server (or from the local store) on its next load, so an undo whose surface has
  gone self-heals. All three are pinned per call site by the
  `deferred-commit undo outlives its surface` group in
  `architecture_guards_test.dart`.

## Web cards — `.card-elevated` is the shared elevated panel

The app has **two** card flavours, and the distinction is load-bearing — don't collapse them:

- **Elevated** (resting shadow + hover lift): the canonical `.card-elevated` lives in `apps/web/src/app.css` (next to `.btn*` / `.modal*`). It is `surface + border + radius-lg + space-lg padding + shadow-sm`, with a `:hover` lift to `shadow-md`. Used by the *dashboard-style* summary surfaces — `/dashboard` (today's-lift, recent-lifts, intensity, etc.), `/nutrition` (rings / water / meal log / trend), and the `/history` unified timeline's day panels. **Use this class for any new elevated panel; don't re-declare an identical local `.card`** (that's exactly the drift that left three copies before the 2026-06-04 consolidation). Compose layout with a page-scoped modifier: `class="card-elevated rings-card"`.
- **Flat** (no shadow): ~17 pages (settings, plans, coaching, recap, share, onboarding, …) deliberately use a page-scoped, shadowless local `.card`. These are intentionally *not* elevated. **Do not add a `box-shadow` to a bare global `.card` name** — it would cascade a shadow into every one of those flat pages. There is intentionally no global `.card`; the flat look stays page-scoped until someone does a full design-system pass to name it (`.card-flat`) and migrate all the copies.

When you need an elevated panel: `class="card-elevated"` (+ a layout modifier). When you need a flat panel: keep the existing page-scoped `.card`. Never give the global an unqualified `.card` rule.

## Web status / accent colour tokens — pick the variant for the JOB

The `--color-warning` / `--color-secondary` / `--color-accent-cyan` (and `--color-success` / `--color-danger`) base tokens in `apps/web/src/app.css` are tuned for **tints, borders and dark mode** — they are *light* accents and FAIL WCAG 1.4.3 as foreground text on a light surface (warning 2.05:1, cyan 2.30:1, secondary 3.06:1 on white; issue #368). Each status/accent has purpose-built variants — use the one matching the job, never the base token, for these two jobs:

- **Solid status BACKGROUND with white text** (toasts, offline banner): use the theme-independent `--color-<status>-strong` (dark in both themes, AA with `#fff`). Never as a `color:` — dark-on-dark in dark mode.
- **Foreground TEXT / ICON** (a stat value, a chip label, an inline warning): use the **theme-aware `--color-<token>-text`** variant (dark on light surfaces, reverts to the base hue on dark surfaces; ≥4.5:1 both themes, incl. on the same-hue chip tint). A blind swap to `-strong` here fails dark mode (2.98:1). For a status word tinted toward the body text on a same-status chip, `color: color-mix(<status> N%, var(--color-text))` is also valid within the mix caps below.

`contrast_guard.test.ts` enforces all three: `-strong` stays theme-independent + AA-with-white and is never used as text; every `-text` token clears AA as text (surface + chip) in all three theme blocks; and no source file uses a bare `--color-warning` / `-secondary` / `-accent-cyan` as a `color:`. Add a new accent that needs a foreground use → add its `-text` pair (light dark-value + dark base-value) and it's covered automatically.

## Web identity accents — an identity hue is a FILL and an `-ink`, never one value doing both

The same split applies to hues that are **identity rather than status**: the seven per-section sidebar accents, the seven integration-provider brand hues, the verified-club ribbon. These were frozen hexes at their call sites and each one was asked to be *both* the tint and the glyph on that tint, which no single value can be in two themes ([decisions.md § 529](decisions.md)). Measured: `#8FBF9F` as a 3 px rail on the light card **2.075:1**, `#4E7C5E` as a glyph on the dark one **2.359:1**, all seven nav glyphs **1.594–2.659:1** on their own 14 % disc over the light sidebar (1.219–1.911 on the 24 % hover disc), Strava's `#FC4C02` **2.921:1** on its own 12 % disc.

So each identity hue is a pair in `app.css`: **`--section-<x>` / `--provider-<x>` is the fill or tint, `--section-<x>-ink` / `--provider-<x>-ink` is what every glyph, thin rail, border and label takes.** The fill stays theme-fixed (it *is* the identity); the ink is theme-keyed — the accent itself wherever a pastel already clears near-black, a darkened rung for light, a lightened one for dark.

**Move lightness, never hue.** The ink is its accent with the lightness changed and nothing else, so the hues a user has learned survive the split: every ink is within 2.6° of its accent's hue angle. That is what makes the split safe for identity, because **luminance was never the separator here** — seven categorical marks cannot be pairwise 3:1 (six such steps need 729:1 and sRGB offers 21:1), and the seven accents sit 1.003:1 apart. It follows that colour must stay a *secondary* cue on any such surface: the glyph shape and the localized label carry the section, colour only speeds the scan.

Two things the guard learned the hard way, both worth repeating:

- **Measure on the ground the rule actually paints, not the one the base rule declared.** The provider discs looked far worse than they were because the per-provider rule *replaces* `.integration-icon`'s `--color-bg-tertiary` background outright — the ground is the card, which moved Strava from 2.375 to 2.921:1 and cleared four of the six failures recorded against it.
- **Pick the floor from what the element IS.** An `aria-hidden` SVG mark owes WCAG 1.4.11's 3:1, not AA text — the verified ribbon was never failing at 3.127:1. The *label beside* an accent mark usually is text, though, and that is what got missed: the dashboard's gym CTA is 0.85rem/600 (not large text) and read **4.346:1** light / **3.949** dark.

`contrast_guard.test.ts` composites every tint share the tree paints (14 / 18 / 20 / 24 %) over every page step and both sidebar gradient stops, in all three theme blocks; pins the ≤3° hue-angle drift and per-pair hue non-regression; reads each provider's `rgba()` brand tint out of the integrations stylesheet so tint and ink cannot drift; and asserts the two-tone verified mark from both ends (the ribbon on the card *and* the `#fff` check on the ribbon — lightening for dark cannot be paid for out of the check). The e2e half is `tests-e2e/cross-cutting/sidebar-section-accents.spec.ts`: a `color-mix(…, transparent)` over a gradient has no single computed background to measure, so the browser test pins the cascade instead — a typo'd token name leaves the custom property unset and every glyph silently falls back to the inherited text colour with no build error.

## Web boundaries on a tinted surface — mix the surface's own accent into the line

`--color-border` is the one LINE token and its whole guarantee is WCAG 1.4.11's 3:1 ([decisions.md § 518](decisions.md)). It clears that on the plain surfaces with very little to spare — **3.906:1** on the light card, **3.330:1** on the dark one — so a card that tints itself with an accent spends the remainder: on `color-mix(var(--color-primary) N%, var(--color-surface))` the dark line reads **3.000:1 at 6 %** and **2.539:1 at 14 %**.

So: **a boundary drawn on an accent-tinted surface mixes that surface's own accent into the line**, at roughly twice the tint's share — `border: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border))` on a 12 % primary tint. That widens the gap rather than closing it, because the border mix moves the line further toward the accent than the tint moved the surface, and it tracks the card's hue automatically. Thirteen call sites already did this before the rule was written, and mobile arrived at the same shape independently (`route_detail_screen.dart`'s marker chip: a 0.10 alpha fill under a 0.20 alpha border of the same colour).

**Do not mint a second line token for it.** The tint's share and its hue are both per-card free variables, so a fixed second value is tuned for one tint and wrong at the next — and it restores the fail-open default § 518 removed, where a plain `border: 1px solid var(--color-border)` is right everywhere by construction. Nor does reducing the tints work: for the plain dark line to clear 3:1 the cap is 5 % on a primary tint, 3 % on the palest kind tint, and 2 % over `--color-bg-tertiary`, which is deleting the tint rather than tinting less.

Two corollaries, both measured:

- **`--color-border` may not edge `--color-fill-subtle`.** They are the same value one generation apart (§ 518 moved the fills onto the line token's old value), so they sit **2.678:1** light / **2.508:1** dark from each other, and in dark the gap cannot be opened from the fill's end at all: it would have to drop to luminance 0.02211 to reach 3:1, and `--color-surface` is at 0.01496, so a chip would fall from 1.328:1 to 1.110:1 against the card it sits on. A control whose fill flips to the subtle fill on hover moves its **edge** instead — `.btn-secondary:hover` takes `--color-primary`, following `.btn-outline:hover`.
- **Measure where the border lands, not what the token is.** § 518 recorded eight tinted cards as failing at 2.551–2.998:1; seven of them never painted the bare token, and the real residue was five sites a token-level reading could not see plus one it hid. `contrast_guard.test.ts` now resolves each rule's tint stops and the border colour that actually applies to that rule's subject — including through a file-local custom property and through a `:hover` rule that moves the edge — and asserts 3:1 per theme.

## Web type sizes — 11 px is the floor, and `--font-size-section-label` is the step to reach for

Mobile pins **11 px** as the smallest type any surface may use (`labelSmall`, [decisions.md § 482](decisions.md)). Web owes the same conformance floor, and until round 13 had nothing enforcing it: **45** `font-size` declarations sat below it, the narrowest at 8 px, and `PlanCalendar`'s `.kind-pill` dropped to 8.8 px under a 40 rem media query on the one plan surface every phone user opens.

`font_size_floor_guard.test.ts` reads the floor **out of `app_theme.dart`** so the two platforms cannot drift, then fails any `rem`/`px` `font-size` **at or under** `var(--font-size-section-label)` (0.7rem = 11.2 px — headroom over the floor, not an exact meet, so § 522's no-later-multiplier rule does not bite it).

**At or under the token, spell the token — a floor alone cannot enforce this.** § 525 counted the hand-spelled micro-labels twice and got a different wrong answer each time; recomputed in § 536 there were **80** literals spelling `0.7rem` and **49** using the token. All 80 sat 0.2 px *clear* of the floor, so a `px < FLOOR` predicate could never reach them, and six more declarations sat on exactly 11.00 px where a strict `<` also spares them. All 80 are on the token now, and the three at-floor micro-labels with them (132 uses), and the guard carries three predicates: at-or-under the token with a named allowlist, strictly-under the floor pinned as a population of **9**, and — with **no allowlist at all** — no literal anywhere may spell the token's own value. A graphic can justify text smaller than a type step; nothing justifies a value indistinguishable from the token until the token moves.

It is a **floor** guard, not mobile's "name the step" literal guard, and the difference is structural rather than convenience: mobile's scale is closed at seven steps on one `textTheme`, so a literal is always a step spelled by hand or a value between two. Web's CSS carries ~1860 numeric `font-size` declarations against three named size tokens, so a literal ban would need an allowlist longer than the code and would assert nothing.

**When a narrow viewport no longer fits the text, tighten the box or let the text reflow — never shrink the type.** SC 1.4.4 and 1.4.10 both ask for reflow, and a `min-height` already permits the row to grow. This is the single most common way the floor gets broken, and a source scan cannot prove the fix: what fails is a higher-specificity media-query override winning over a compliant base rule, so the resolved-cascade half lives in Playwright (`tests-e2e/plans/calendar.spec.ts`, `tests-e2e/cross-cutting/week-strip-type-floor.spec.ts`). `PlanCalendar`, `CurrentWeekStrip` and `ThisWeekStrip` each carried the identical shrink; all three have lost it.

The allowlist is **12 declarations across 5 files**, of which exactly 9 are under the floor, each a named exemption rather than an unexamined literal. Classify by reading the **site's markup, not its file**: `ElevationProfile`'s `.extreme-text` and its `.y-label` / `.x-label` axis ticks (real SVG text) and `RouteBuilder`'s `.km-marker` / `.waypoint-marker-label` (numerals inside 20 px and 26 px map pins) are text-inside-a-graphic — a label merely *near* a drawing, like a heatmap legend's HTML "Less"/"More" beside an aria-hidden gradient bar, is plain debt. The three at exactly 11.00 px that *were* real micro-labels on theme surfaces — `BadgeGrid`'s `.badge-tier`, `RoutePreviewScrubber`'s `.title` and `.ends` — went onto the token in § 536.

An `em` is not exempt, only unresolvable *statically* — it compounds with whatever the ancestor resolved to. Count-pinned at six so a micro-label cannot evade the floor by switching unit, and each is classified: three are Material Symbols glyph sizing (an icon's `font-size` is the glyph's box, and a legibility floor on an icon asserts the wrong thing) and three are real text, measured with `getComputedStyle` in `tests-e2e/cross-cutting/type-floor-em-units.spec.ts`.

## Web reflow — a page must fit 320 CSS px, and what cannot reflow scrolls inside its own box

WCAG **1.4.10** asks that no page require horizontal scrolling at a 320 px viewport. The conformance test is the derivation, never a pixel: `document.documentElement.scrollWidth <= clientWidth`. That form is also the only one that tolerates the criterion's own exemption — an inner scroller — so never assert an absolute width ([decisions.md § 500](decisions.md), § 535).

What breaks it is almost never a page. Five mechanisms account for every failure the round-15 sweep found across 34 of 47 static routes:

- **A flex or grid item defaults to a content-derived minimum.** `min-width: auto` floors an item at its min-content width, so it refuses to shrink and the document grows instead. This is what made every page overflow at once: `.main-content` is `flex: 1` in the app shell, and `min-width: 0` on that one rule took `/dashboard` from 752 px to 472 at a 360 px viewport.
- **A fraction track floors at min-content too.** Write `minmax(0, 1fr)`, not `1fr`. A `fieldset` needs an explicit `min-width: 0` for the same reason — the UA sheet gives it `min-width: min-content`.
- **`minmax(FIXED, 1fr)` cannot reflow below `FIXED`.** Write `repeat(auto-fit, minmax(min(24rem, 100%), 1fr))`. The `min()` is a no-op wherever the container is wider and is the whole fix wherever it is not.
- **Read `--page-padding-y` / `--page-padding-x` on a page wrapper**, never the `--space-*` pair they resolve to. The tokens narrow below 40 rem; a hardcoded 3 rem gutter costs 96 px of a 320 px screen on top of the 72 px rail.
- **A row of a title plus actions wraps.** `flex-wrap: wrap` on the row, and no `flex-shrink: 0` on the actions.

**Truncation is not a reflow strategy.** `white-space: nowrap` makes the whole string the element's min-content width, so a `nowrap` + `overflow: hidden` + `text-overflow: ellipsis` box grows the page rather than truncating — and `min-width: 0` on the element itself does not clamp that contribution in Chrome. Clamp the *container* (a grid item takes `min-width: 0`), or let the text wrap.

**Content whose axis is its information may scroll itself.** A data table takes the `.table-scroll` wrapper (`max-width: 100%; overflow-x: auto`, plus `tabindex="0"` so the region is reachable without a mouse). A segmented control, a tab strip and a multi-column set grid scroll as one block, because splitting a continuous track across two rows destroys the control rather than reflowing it — and rows inside such a scroller need a shared explicit `min-width`, or each sizes to its own content and the columns stop lining up.

**A long unbroken token is the same bug in text form.** An env-var name, an id or a URL offers the line breaker no opportunity, so its min-content width is the whole string. `app.css` gives `:not(pre) > code` `overflow-wrap: anywhere` — `anywhere`, not `break-word`, because only `anywhere` counts toward the intrinsic minimum, which is the size that widens the page.

**Measure the narrowest fit, not the pass at 320.** Bisect the viewport width at which a route stops fitting; that number is renderer-independent, and "passes at 320" is not. CI's Linux font stack measures 12-20 px wider than macOS, which is how a route with a 318 px narrowest fit passed a developer's 320 px check and failed CI at 330 (§ 535 amendment). Keep new surfaces at or under ~280 px.

`tests-e2e/cross-cutting/reflow-narrow-viewport.spec.ts` drives 16 routes at 300, 320 and 360 px — the 300 px row is renderer headroom, not a stricter reading of the criterion. Add a route to it when you add a surface with a grid, a toolbar or a table. The measurement contract itself lives in `tests-e2e/fixtures/reflow.ts`, shared with `reflow-seeded-routes.spec.ts`, which supplies runtime fixtures for the five families that render from no seed.

**A "0 elements measured" result is a missing anchor until you have ruled that out.** The reflow measurement is taken inside the page region, so a route with no `<main>` reports zero content no matter what is in the database — and that reads exactly like absent fixtures. Confirm the landmark exists before attributing an empty measurement to data ([decisions.md § 543](decisions.md)).

## A shell-less route owns its own `<main>` landmark

`+layout.svelte` renders three branches. The signed-in shell and the anon-allowed content branch each wrap the slot in `<main id="main-content">` behind a skip link. The third — `isShellless()`, covering `/`, `/login`, the `/auth/*` flows, `/onboarding`, `/safety/confirm`, and everything under `/share/`, `/live/`, `/learn`, `/clubs/join/` and `/coaching/accept/` — renders a bare `<slot />` and gives its routes nothing. **A page added to that family must render its own `<main id="main-content">`, in every branch a visitor can reach**, or it ships with no main region at all (WCAG 1.3.1). Eleven of twenty-four did; see § 543.

Two things make this easy to get wrong:

- **Put the landmark on an element that already exists** where that element is a flex child of the page shell (`<section class="hero">` becomes `<main class="hero">`). A new wrapper moves the flex child and reflows the page. Wrap only where the child centres itself inside any full-width parent.
- **Every branch of the chain needs one, not just the one you were looking at.** The commonest form of this defect is a landmark in the *not-found* card while the found entity renders a bare `<section>` — which passes any "does this file contain a `<main>`" check. `src/lib/shellless_landmark_guards.test.ts` derives the family from the layout and enforces branch consistency; a landmark in some branches of a top-level `{#if}` chain but not others fails it.

Do **not** solve this by putting one `<main>` in a shared wrapper like `SharePageShell`: it nests each page's `<header>` inside `main`, demoting it from `banner`, and `recap/share/[id]` uses that component while sitting inside the layout's own `<main>`, which would produce two landmarks.

## A sentence is a catalogue key, not a template plus a fragment

A message that interpolates a fragment carrying its own grammar will double it. The notification templates said `"{name} gave kudos to your {dist}"` and filled `{dist}` with `"your run"` when a run had no recorded distance, so every locale shipped a doubled possessive: "your your run", "deinem deinen Lauf", "a tu tu carrera", "à ton ta course", "à sua sua corrida", "あなたのあなたのラン" ([decisions.md § 536](decisions.md); mobile's twin was `profileNotifYourRun`).

**Give each branch its own whole-sentence key.** No fragment can be fixed here rather than replaced: German needs the dative "deinem" after the kudos verb and the accusative "deinen" after the comment verb, and French "course" is feminine where an interpolated "5,2 km" is masculine, so one template and one fragment cannot both be grammatical. Interpolate **data** (a name, a distance, a count) and never a phrase that carries a determiner, a preposition, or an inflection the surrounding template also carries.

**Guard it derivationally, and not with a repeat check.** The obvious rule — reject a back-to-back repeated token — **spares German**, whose doubling is two different inflections of the one possessive. `notification_phrasing.test.ts` renders every branch in every shipped locale, counts second-person possessives, and pins the population (`SUPPORTED_LOCALES.length * 8` — 56 renders at seven locales, derived so a new locale widens the guard rather than escaping it); the pre-fix string from each locale sits in a must-flag fixture table.

**A kind is an identifier, not a label.** Hand-capitalising a database enum value prints English on a localized page and loses whatever the catalogue adds — `long` is "Long run", not "Long". Route it through the presentation helper (`workoutKindLabel` / `planPhaseLabel` in `lib/training/workout_labels.ts`), whose map is asserted total over the generated `workout_kind` enum so an unmapped kind fails instead of falling back to the raw string. `workout_labels.test.ts` scans the `x.charAt(0).toUpperCase() + x.slice(1)` **shape** across the tree rather than keying on identifiers containing "kind": the defect it closed was written through a one-letter alias, and a name-keyed matcher demonstrably spares it. The three surviving sites are count-pinned and named, one of them still a defect (`activityLabel` on `/coaching/athletes/[id]`, which has no catalogue vocabulary to route onto yet).

## Web CSS custom properties — a fallback is a default, never a substitute for the token

**Never write `var(--some-token, #hex)` for a token that isn't declared in the token layer.** It reads as a defensive default and is actually the opposite: the declaration is pinned to that literal in *both* themes, permanently, and never tracks light/dark at all. It is strictly worse than the bare `var(--x)` form, which at least collapses to something inherited — and unlike the bare form it *looks* deliberate at the call site, so it survives review. The issue #666 round-10 sweep found **130** such references across **39** files (`#666` muted text at 2.815:1 on the dark card; white on a primary fill at 2.081:1 in dark, because `--color-primary` flips from dark teal to light coral).

The rule the guards draw is **existence, not syntax**:

- A fallback on a token the **same file** declares is legal — it's the documented default for a component custom property a parent sets per instance (`style:--x={...}`).
- A fallback on a token that is **not** declared anywhere is banned. Either use the right existing token, or declare the new one in `app.css` (all three theme blocks if it carries colour; a `var()`-alias in `:root` alone if it just follows another token, like `--chip-bg: var(--color-fill-subtle)`).
- **A *colour* fallback on a token `app.css` declares globally is also banned** — the per-instance-default rationale doesn't survive the token being global. Nothing sets `--color-primary` per instance, so the fallback can never apply, and all 25 of them were frozen at a value the token had long since moved off (`#4f46e5`/`#3b82f6`/`#2563eb` for a primary that is now teal, `#e5e7eb` for a cream border, `#374151` for near-black text). Dead code that reads as the colour at the call site is worse than no comment: the next editor believes the blue. `status_color_literal_guard.test.ts` fails any hex fallback, of any digit length, on a global `app.css` token; the non-colour ones (spacing, radii, shadows, z-index) and the nested `var(--a, var(--b))` chains are out of that rule's declared scope.

`css_token_guard.test.ts` fails the build on either form of undeclared reference, and its `MATCHER_FIXTURES` table pins the matcher in both directions (10 must-flag, 8 must-spare) because the whole distinction rests on one `[,)]` character class.

**A dead fallback also blinds the other CSS guards, so strip it when you touch a line.** `color: var(--color-warning, #b45309)` resolves to the token — the fallback is never used — yet it slipped past `contrast_guard.test.ts`'s foreground ban for the same one-character reason, painting 2.048:1 warning text while reading as guarded. 28 live §503 violations were hiding this way (8 on `--color-warning`/`--color-success`, 20 on `--color-danger`). Both guards now match `[,)]`. It happened again one level down when the global-token fallbacks were deleted: `contrast_guard` reads the *deepest same-hue chip tint out of the source*, and a `color-mix(… var(--color-danger, #d33) 22%, transparent)` was invisible to that read, hiding a `--color-danger-text` label at 4.250:1 on the block toggle's hover state.

Two traps worth naming, both measured: `--color-bg-tertiary` is **byte-identical to `--color-surface` in dark**, so it can't be the fill for anything sitting on a card (1.000:1); and a token whose *name* describes a layout slot that doesn't exist (`--app-header-h`) should be deleted, not declared.

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

## Web share URLs — the path is defined once, the base belongs to the caller

Every public path an entity has is spelled in exactly one builder, and the builder takes the base as a parameter. There are **two** such paths per entity, not one: the share page (`build<X>ShareCanonical`) and its unfurl image (`build<X>OgImageUrl`). Never interpolate a base into a path at a call site — `${window.location.origin}/share/run/${id}` is the defect, `buildRunShareCanonical(window.location.origin, id)` is the same URL with the path defined once. Which base depends on the *use*, and both are correct: a `<head>` canonical resolves against `PUBLIC_SITE_URL` (the public home of the content is not whichever host the reader is on), while a copy-to-clipboard link resolves against `location.origin` (a preview host has to yield a preview link). See [decisions.md § 520](decisions.md) / [§ 531](decisions.md) / [§ 546](decisions.md).

- **An `og:image` must be absolute.** It is fetched by a remote crawler off-site, so unlike an in-app `href` it genuinely can get the origin wrong. A page whose `<head>` advertises the same image at two URLs — absolute in its JSON-LD, root-relative in its `og:image` — fails invisibly.
- **A root-relative `/share/…` in an `href` is fine.** It is an in-app navigation and cannot get the origin wrong, which is the failure the rule is about. Routing those through a builder would read as `buildRunShareCanonical('', id)` at every call site — a legible template traded for an obscure one.
- **Calling a share-canonical builder is not a canonical fold.** `/recap/[year]` calls one for its copy-link and emits no `<link rel="canonical">`; it belongs in no row of `seo.md`'s consolidation table, because a recap has no share id until the runner publishes.
- `share_url_source_guard.test.ts` registers every construction site with an **exact count** and a reason, in both directions: a count that rises is a second spelling of a path that already has a builder, one that falls is a builder that lost its last caller.

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

## Linking another user's row — never to an owner-scoped route

Several read paths are deliberately scoped to the viewer: `fetchRunById` filters `.eq('user_id', userId)`, because it is the only read path that downloads the **unclipped** GPS track. A page whose only row source is such a fetch renders its "Run not found" empty state for anyone else's row — a real, public row presented as deleted. That is still the shape of every `/gym/[id]`-style owner surface.

So: **a surface that renders someone else's row links to the public twin, not the owner surface.** `/share/run/[id]`, `/share/workout/[id]`, `/share/event/[id]`, `/u/[id]`. The social feed, a club roster, a challenge leaderboard, a segment board, a notification about a followee's activity — all of these are other-people surfaces, and the public twin is additionally the right target because it is anon-reachable and indexable while the app routes sit behind the layout auth-gate. Only `/history`, `/runs`, `/dashboard` and friends list the viewer's own rows and may use the owner route.

This is not a cosmetic difference: the failure is silent and looks exactly like a deleted row, so it survives review and reads as correct in a screenshot taken by the owner. `apps/web/src/lib/cross_user_link_guards.test.ts` pins the feed; extend it when a new cross-user surface ships.

**The other half of the rule: an owner surface a stranger can plausibly reach needs a non-owner branch, not a 404.** People paste the URL out of their address bar. `/runs/[id]` used to 404 a public run for everyone but its owner — the only signed-in surface where a follower could comment on a run was `/share/run/[id]`, which is why several e2e specs navigated there (issue #666). It now resolves entitlement separately from the owner read (`fetchPublicRunAttribution` → a `public_runs` row, i.e. `is_public = true`) and mounts `RunShareView` for a non-owner. Two structural rules make that safe, and both are pinned in `cross_user_link_guards.test.ts`:

- **The non-owner row never enters the owner state.** `run` is assigned only from `fetchRunById`; a non-owner takes a sibling `{#if}` branch. Every owner affordance (edit, delete, visibility, gear, save-as-route, rematch) lives inside the owner branch, so suppression is structural rather than a list of `{#if isOwner}` guards that a later edit can forget.
- **The non-owner branch renders through the existing public component**, so the privacy-zone clip stays single-sourced: `RunShareView` is the one place that calls `fetchClippedTrackForRun` (decisions §33). A hand-rolled non-owner renderer would be one `fetchTrackByPath` away from serving the unclipped trace.

The same rule reaches the Go worker's notification deep links — `run_completed` fires at a *followee's followers*, so it links to `/share/run/{id}`. See `docs/features/email.md § Architecture` for the deep-link contract and its route-tree guard.

## Deep links that leave the app must resolve forever

A URL in an email, a push payload, an SMS, or a share sheet is **outside our deploy**. Once sent it cannot be corrected: it sits in an inbox or a notification tray and a later fix only changes what *future* links say. Two rules follow.

1. **Assert that the target resolves, not that the string matches.** A test pinning `base + "/notifications"` passes forever while `/notifications` is not a route. Guards should check the emitted path against the real route tree (`apps/job_worker/internal/notification_link_guard_test.go` walks `apps/web/src/routes` for exactly this) or exercise it end-to-end.
2. **Changing what a link emits is only half a fix.** Add the redirect route so the already-sent shape keeps resolving, and treat that route as permanent.

Prefer emitting a **stable id** and letting web resolve it (`/events/[id]` → `/clubs/{slug}/events/{id}`) over baking a mutable slug into a link that will outlive the rename.

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

## A value domain gets ONE vocabulary, and a destination gets a name of its own

Two rules from the same failure — a user-facing name that more than one place
was allowed to decide (decisions § 547, generalised in § 572).

**A closed value domain has exactly one catalogue namespace and one resolver.**
When a column's value set is fixed by a CHECK constraint (`activity_type`,
`workout_kind`, `surface`, `join_policy`, `role`, an RSVP `status`, …), every
surface that names a value resolves through the one helper — web
`runs/activity_type.svelte.ts#activityTypeLabel` and
`i18n/enum_labels.svelte.ts` (`routeSurfaceLabel` / `joinPolicyLabel` /
`clubRoleLabel` / `rsvpStatusLabel`), mobile
`activity_type_labels.dart#activityTypeLabel`. Register a new union in
`i18n/enum_labels.ts` and the guard picks it up. Do NOT mint
`<surface>.activity<Value>` keys for a picker, a filter chip and a detail
header: seven such namespaces existed for five values and they disagreed
*inside* a locale (German `hike` was both "Wandern" and "Wanderung"), and four
of them silently omitted a value, which is what made `/runs/[id]` print the raw
token "stroller" in every language. Corollaries:

- **Never hand-capitalise an identifier in place of a label.**
  `x.charAt(0).toUpperCase() + x.slice(1)` (and its Dart template form
  `'${x[0].toUpperCase()}${x.substring(1)}'`) prints English on a localized
  page and loses whatever words the catalogue adds. Both platforms carry a
  tree-wide source sweep with a *named* allowlist — web in
  `training/workout_labels.test.ts`, mobile in `activity_type_vocabulary_test.dart`
  — so a new one fails wherever it lands, and an entry must say why the value
  cannot be resolved (an open vendor string like a FIT `sub_sport` can; a closed
  domain cannot).
- **Never interpolate the stored token into the DOM.** `{route.surface}`,
  `{club.join_policy}`, `{club.viewer_role}`, `{run.activity_type}` — nine such
  renders shipped, and they read as English in all six locales while the page
  around them was translated. `i18n/enum_vocabulary.test.ts` scans every
  template for the shape in **text position only**: picking an icon, a class or
  a prop off the value (`title={seg.role}`, `class="tl-{seg.role}"`) is
  legitimate and never shown.
- **Derive the value set, don't restate it.** The guards parse the CHECK out of
  the migration or the union out of `types.ts`, so widening the domain fails the
  build until every catalogue carries the new key.
- **The key-shape sweep does not see abbreviations.** `clubHome.roleOptionDirector`
  named `race_director` and no matcher keyed on the value can catch it; widening
  the tail to any word swallows `plansPage.statusActive`. The blind spot is
  pinned as a must-spare fixture rather than papered over — when you add a
  vocabulary, hand-sweep for abbreviated duplicates once.
- **An unrecognised value renders VERBATIM, never title-cased.** A title-cased
  token is indistinguishable from a real translation and hides the drift on
  exactly the surface where it would be noticed.
- **A narrow surface truncates; it does not get its own shorter words.** The
  Wear OS pre-run chip carried four abbreviated activity labels on the theory
  that a 56 dp `maxLines = 1` chip needed them. Measured, its label box is
  32 dp and the abbreviations overflowed it too (`Caminar` 38 dp, `ウォーク`
  40 dp) while the long words the same chip already shipped ran to 60 dp
  (`Kinderwagen`) — so the fork bought a fourth vocabulary and no fit
  (decisions § 713). Ellipsis plus a full `contentDescription` is how a cramped
  surface handles a long word. If a constrained surface ever genuinely does
  need shorter forms, they are a *documented abbreviation table* with a row per
  locale, agreed as such — never a quietly different translation.

**Two destinations may not have names a reader cannot tell apart.** A
destination's name is the thing a user searches for, so "Coach" (the AI chat)
beside "Coaching" (the human coach↔athlete roster) is a contradiction on one
surface. `i18n/destination_names.test.ts` compares every top-level destination
name pairwise **in every locale**, because the collision is a property of the
words: separating the two in English can leave them colliding in German, and
nothing else would notice (its first run found "Über"/"Übersicht" and
"Einstellungen" naming both Settings and its Preferences tab). Add a new
sidebar item, popover entry or Settings tab to `DESTINATION_KEYS`.

## A shipped locale catalogue is derived from disk, never listed by hand

A translation catalogue that no runtime path resolves to costs bytes in every
build and reaches nobody, and nothing about the file says so — it looks exactly
like a catalogue that works. European Portuguese shipped that way twice, first
missing from `supportedLocales` and then, after that was fixed, missing from a
language picker that spelled its six options out beside a seven-entry supported
list (decisions § 740).

So the rule is that **the set of locales a surface offers is derived from the
supported set, not written down beside it** — web's picker is
`{#each SUPPORTED_LOCALES}`, mobile's builds from `supportedLocales`. And the
supported set itself is held to the catalogue directory by a guard:
`apps/mobile_android/test/architecture_guards_test.dart § locale reach` and
`apps/web/src/lib/i18n/locale_reach.test.ts`. Adding a locale means adding the
file and letting the guard name every declaration site that has not caught up
(on mobile that is `supportedLocales`, `localeLabels`, `_exact`,
`_baseToLocale`, the generated delegate, `l10n_parity_test.dart`'s own list and
the iOS bundle's `CFBundleLocalizations`); deleting one means deleting the file
and doing the same in reverse. The base-language fallback is the single rule a
catalogue may legitimately fail, because a base tag can point at only one
variant per language, and that carries a reason-per-entry allowlist with a
companion test asserting each entry is still exempt.

Distinct from key parity, which `messages_parity.test.ts` and
`l10n_parity_test.dart` already own: those prove a *shipped* locale is
complete, this proves the shipped set is the set that exists.

## A size budget measures what one reader downloads, not what the build emits

A total over every emitted file is the right metric for a dependency: a dep
splits into two lazy chunks and every reader still fetches both eventually, so
summing them is what stops code-splitting being mistaken for a saving. It is
the wrong metric for an artifact only *some* readers ever request. The web
bundle ceiling summed the message catalogues, of which a reader fetches one, so
each new language charged every reader ~88 KB they would never download and the
ceiling had to be raised — pt-PT moved it 2400 → 2700 while the largest chunk
stayed byte-identical, and the gate's sensitivity to a rogue dep fell by one
language's worth every time (decisions § 771).

So the rule is that **a build artifact only some readers fetch gets a budget of
its own, sized per artifact rather than summed**, and the shared budget keeps
only what every reader downloads whatever they are. `MAX_CATALOGUE_KB` in
`scripts/check_web_bundle_budget.mjs` is per catalogue and never totalled, so a
new locale cannot move it and a bloated one still trips it; `MAX_CODE_KB` holds
everything unconditional and stays fixed as languages ship. The total of the
optional population is still *reported*, deliberately — a number nobody may
gate on is the one that cannot silently become a ceiling again.

Two things decide which side an artifact falls on, and neither is its file
type. **Ask what a reader actually fetches**: the English catalogue is
statically imported as the synchronous fallback dict, so it is in the shared
chunk every reader downloads before a locale is negotiated — it is
unconditional weight and it sits in the code budget, even though it is a
translation. And **classify from the build's own module graph, not from a
filename**: client chunks are content-hashed with no name component, so the
mapping comes from vite's manifest, and a chunk that stops being separately
loadable disappears from it — which the guard fails on by name rather than
letting the bytes land in the other budget under the wrong diagnosis.

**A budget's population is every file the build emits, not the file types
someone thought of.** The same walk matched `*.js` and `*.css` only, so fonts,
images and prerendered HTML — 33 files and 4058 KB gzipped, one of them a
3866 KB unsubsetted icon font — were outside all three ceilings entirely
(decisions § 775). `MAX_ASSET_KB` now holds every non-JS/CSS emitted file, per
file for the reason catalogues are per catalogue: a reader loads one prerendered
page and one favicon. Where one artifact genuinely has to exceed a ceiling,
**exempt it by name with its own number, never by widening the ceiling** — and
make the exemption fail when it stops describing the build, both when it matches
nothing and when the artifact it covers has shrunk back under the general
ceiling. The same shape governs `GRANDFATHERED_VIOLATIONS` in
`apps/backend/scripts/check_migration_online_safety.mjs`, and for the same
reason: a moving boundary exempts things nobody has read, a name cannot.

## A tab index is an ordered enum, never a raw int

`initialTab` on a tab host takes a named enum whose declaration order IS the
strip order, and the labels, the views, the FAB switch and any deep link all
read that one order (`ProfileTab`, `FitnessTab`, `SocialTab`). Do not take an
int and clamp it: the clamp is what *hid* § 490's live bug rather than catching
it — a stale `initialTab: 3` literal stayed in range after the tab set changed,
so the notification bell opened the wrong tab in silence. With an enum, out of
range is unrepresentable, so the test to write is not a clamp test but the
property a clamp cannot give: every value opens its own tab, and the strip is
exactly as long as the enum.

## Mobile embedded surfaces name a Settings destination, they don't acquire it

A surface that sits inside a nav destination — a sub-tab of `SocialScreen`, a
card on the dashboard, a widget in a sheet — links into Settings by calling
`openSettings(SettingsDestination.x)` from `settings_destination.dart`.
`HomeScreen` drains the parked intent and pushes the screen with the
dependencies it already holds. Do NOT thread `Preferences` /
`SettingsSyncService` / `ApiClient` down through the intermediate hosts so a
leaf can build a settings screen: that makes each host carry dependencies it has
no other use for, and the next surface that wants a Settings link is a different
host with a different set to thread (decisions § 710). Naming a path in prose —
"turn this on in Settings → Preferences" — is the same gap, one step worse: it is
a link the reader has to walk by hand, and it must be re-translated into six
catalogues every time the settings IA moves.

Two limits are real, and both are reasons to keep the direct `Navigator.push`:

- **The caller must have nothing to do when the screen closes.** A parked intent
  is fire-and-forget and cannot report a pop, so a caller that awaits the push
  and refreshes on return (`nutrition_screen.dart`'s `_openBodyMetrics`) keeps
  its own push.
- **A surface that already holds the dependencies for its own reads keeps its
  own push.** `run_detail_screen.dart` reads `Preferences` throughout; routing
  its "Set max HR" button through the seam would trade a button that works
  wherever the screen is pushed for one that needs the shell above it.

Adding a destination means adding an enum value and its arm in the shell's
`switch` — the arm is exhaustive, so a new value fails the build until it is
wired. Only *pushable* sub-screens are destinations; the Settings landing is
embedded in the You tab, so opening it is a tab switch, not a push.

## Step a date through the calendar, never through a fixed `Duration`

A local calendar day is 23 or 25 hours across a DST transition, so
`someDate.add(Duration(days: n))` — which adds absolute time — walks off the
calendar. On a fall-back a midnight cursor lands at 23:00 the *previous* day:
the date repeats, the last day of a window is never produced, and every offset
past the transition is shifted by one. Step dates with `DateTime(y, m, d + n)`
(or `addDays` in `training.dart`), which normalises through the calendar. Web's
twins take the same shape via `Date.setDate()`; `Date.getTime() + n * 86_400_000`
is the same bug in TypeScript.

The exceptions are real but narrow: a `DateTime.now()` or `.toUtc()` receiver is
an *instant*, and a genuine elapsed-time span (a rolling 90-day cutoff, an API
query bound, a search horizon) means 24-hour blocks and should stay that way.
Mark those `// elapsed-time: <why>` — `calendar_day_arithmetic_guard_test.dart`
fails the mobile suite on every unmarked site, because this class had already
been fixed four times in isolation before the fifth bought the guard
(`decisions.md § 589`).

## Parse a date-only string as a calendar day, an ISO timestamp as an instant

`new Date('2026-11-15')` is **UTC midnight** — ECMA-262 gives the date-only form
that special case — so rendering it through any local-time formatter shows the
day before at every negative offset. A `date` column names a calendar day and
must read the same in Auckland and Los Angeles; a `timestamptz` names an
instant and genuinely belongs to different days in different places.

Web's shared `formatDate` / `formatDateShort` / `formatRelativeTime`
(`$lib/format/time`) now handle both: a bare `yyyy-mm-dd` is built from its
calendar components (local midnight), anything else falls through to the normal
parse. **Prefer them over a hand-rolled parse** — the older idioms
(`new Date(iso + 'T00:00:00')`, a `split('-')` + `new Date(y, m-1, d)` helper)
are correct but were each invented locally, and the one place that *didn't*
hand-roll it was the shared helper every call site trusted (`decisions.md § 607`).

When you must parse inline, `T00:00:00` (no `Z`) is the shortest correct form.
Never format a `date` column with a bare `new Date(iso)`.

Timezone-dependent behaviour is invisible under the e2e suite's global
`timezoneId: 'UTC'`, so a test for this class must set the zone itself —
`process.env.TZ` per case in a unit test, `test.use({ timezoneId })` in
Playwright — and must be confirmed to fail against the unfixed code.

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

**A new `handler_envelope.test.ts` case lands with the mutation that kills it.** The three mutation guards (`check_pgtap_refusal_assertions.mjs`, `check_edge_function_test_vacuity.mjs`, `check_served_envelope_mutations.mjs`) all derive their population, so a new pgtap refusal or a new Deno unit case is measured the moment it exists. The served-host one cannot: its operator is a table of named source edits, so it enforces coverage instead — a case the baseline ran that no mutation claims **fails the build**, and so does a mutation naming a case that no longer exists. Adding a case to that file therefore means adding the entry in `apps/backend/scripts/check_served_envelope_mutations.mjs` that opens the gate the case names, in the same change. That is the point rather than the friction: the entry is where you find out whether the assertion discriminates, and three of the file's cases turned out not to ([decisions § 815](decisions.md)).

**A test waits on a condition, never on a duration.** A fixed sleep, a fixed number of `pump`s, or a bounded loop that silently falls through when its deadline expires are all the same defect: the test is guessing how long some async work takes, so it passes on a developer machine and fails on a loaded CI runner. Wait on the observable thing instead — the future the trigger hands back, the row the save writes, the widget the state change mounts — with a deadline whose only job is to turn a hang into a named failure. On mobile that is `pumpUntil` / `holdFinish` in `apps/mobile_android/test/pump_until.dart`; on web, Playwright's auto-waiting `expect` rather than `waitForTimeout`. Never widen a timeout to make a test pass — that is the same rule as "don't inflate a timeout or a retry to hide a bug", applied to the harness. The exception is a delay that *models elapsed time* (a debounce window, a throttle, a signal blackout, a hanging fetcher proving a `.timeout()` fires): there the duration is the test's subject. See [decisions.md § 715](decisions.md).

**When a test genuinely isn't viable** (pure docs, runbook updates, infra blocked on credentials, orchestration code that pulls in SvelteKit virtual imports / Supabase / native plugins and would need heavyweight DI to unit-test), say so explicitly in the commit message — `no unit test viable; e2e covers it` is fine, silence isn't. Future you (and future code-reviewer agents) will read the message and either accept the trade-off or argue with it; either way the reasoning is recorded.

## Every compilable file belongs to a tsc root, and each package root guards its own coverage

TypeScript does **not** merge `include` across `extends`. A tree therefore belongs to no program until somebody says so, and a plain-JavaScript file in a program with `checkJs` off is read and asserted about by nothing. That combination is how the Playwright tree ([decisions § 749](decisions.md)), then `apps/web/scripts/` + eight production Lambda handlers + the service worker ([§ 752](decisions.md)), then all 35 of the repo's own guard scripts + the CloudFront Function at the edge ([§ 757](decisions.md)) each sat outside every typecheck for as long as they had existed.

The rule, in three parts:

1. **A new tree gets a root, not a widened `include`.** Widening an existing root means pasting a generated list (SvelteKit's) into a committed file and re-pasting it whenever the generator changes, which goes stale silently. A separate `tsconfig.<thing>.json` that `extends` the shared strictness base is the durable shape. Some trees *cannot* share a program at all — a service worker's `WebWorker` lib and `DOM` both declare `Event`; a CloudFront Function's runtime has no `Promise` — and for those the separate root is what makes the check mean anything.
2. **Declare `types` explicitly.** The automatic type-root scan does not fire under this config chain and `moduleResolution: bundler` skips `node:`-prefixed specifiers, so a Node-side root without `"types": ["node"]` reads every `process` as an unresolved name — and one that appears to work is usually borrowing a `/// <reference types="node" />` from a dependency, one bump away from vanishing.
3. **Each package root carries a coverage guard, and the guard names no tree.** It reads the `tsconfig*.json` files beside it, resolves each root's effective `include` by following `extends` until one declares it, and requires every compilable file git reports in its scope to match one — so a root added later counts the moment it exists and a tree added later is uncovered the moment it appears. Two guards exist today (`apps/web/scripts/tsconfig_coverage.test.mjs` and `scripts/tsconfig_coverage.test.mjs`) because one cannot state the other's coverage: the first must resolve SvelteKit's *generated* config and so needs a `svelte-kit sync`, the second must run against a bare checkout. Where two guards divide a repo between them, **each asserts the other still exists** — the seam is the part that opens silently. A tree a `tsc` root genuinely cannot read (the Deno Edge Functions, whose `npm:` / `jsr:` / `https:` specifiers tsc cannot resolve) is exempted *by derivation from that toolchain's own config file*, never by a hardcoded path, and the exemption names the lane that does cover it — see 4.

4. **A tree with its own compiler gets its own lane and its own coverage guard, and that guard derives the file set from the lane.** The Edge Functions are the case: `deno check`, not `tsc`, so there is no root to add them to ([decisions § 762](decisions.md)). The lane is a CI step whose command *derives* what it checks (`files=$(find … -name '*.ts')`), never a list of paths — the sibling `deno test` step in the same job was once three hardcoded paths and silently missed four `*.test.ts` files added afterwards. The guard then does not restate the file set either: it reads the workflow, lifts that step's own expression out of it, runs it, and compares the result against every compilable file git reports under the tree, so the two cannot disagree. Check the tests too. A test that does not typecheck is as free to assert something impossible as any other module, and the first run over the Edge Functions found one that was.

Every root is reachable as an npm script and runs in CI; the guard asserts both, because a typecheck nothing runs is not a typecheck. Bringing a tree in for the first time is a **defect hunt, not a formatting pass**: across § 752, § 757 and § 762 the majority of the error count was one diagnostic (an unannotated parameter, a missing `@returns {never}`) and the residue was real — dead config silently ignored on every build, an unvalidated env var that would 404 the whole site, and ten CI guards that could pass vacuously, throw instead of reporting, or not see the very thing they existed to police. Fix those; never reach for `// @ts-ignore`, `any`, or a loosened option. And read a zero as a question rather than an answer: the one Edge Function reporting no errors before § 762 was the one whose thirteen client parameters were annotated `SupabaseClient` — that is `SupabaseClient<any>` — so it was the least-checked file in the tier and looked like the best-typed one.

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

## Doc checkboxes — three states, and a partial box names where the rest is tracked

Surveys of open work are built by grepping `- [ ]`. That instrument sees two of
the three states this repo actually writes, so every `- [~]` is invisible to it:
issue #789 was assembled that way and missed the category whole. Until now the
marker also had no stated meaning outside `reviews/`, where
[`reviews/README.md`](../../reviews/README.md) defines it as *deferred* — close
to the opposite of the "built, not yet live" sense the docs tree had adopted.
`docs/custom_watch/roadmap.md` read it a third way again, and one line there
carried `[~]` while its neighbour, in the same build state, carried `[ ]` under
that file's own bench-verification rule.

<!-- doc-checkbox-states -->

- `[ ]` open — none of it has shipped
- `[x]` done — all of it has shipped, and nothing is holding it back
- `[~]` partial — some has shipped and some has not, which includes a feature
  whose code is merged but which no user can reach yet: an unset credential, a
  flag defaulting off, a sign-off still owed. Say in the bullet which half is
  which, and link the file tracking the open half

<!-- /doc-checkbox-states -->

There is no fourth state. `scripts/check_doc_checkboxes.mjs` reads the block
above rather than restating it, so a new marker has to be documented here before
it can appear in a doc, and it holds `reviews/README.md` to the same *set* of
markers — the two describe different meanings on purpose, but a state added to
one belongs in the other.

The link is what keeps the category reachable. A `[~]` links
[`followups.md`](../product/followups.md) or
[`roadmap.md`](../product/roadmap.md), because those are the files a survey
reads, and the open half has to exist there as an ordinary `- [ ]` box that a
grep can find. This is the rule `reviews/README.md` § 2 already states for a
deferred finding, applied to the tree the surveys walk. A document that is a
dated snapshot rather than a live list says so with `<!-- doc-checkbox-frozen -->`
and is exempt from the link — [`followups_archive.md`](../product/followups_archive.md)
is a verbatim capture of the day it was taken, and rewriting its boxes to satisfy
a rule written afterwards would destroy the one thing it is for. That
declaration lives in the file it describes, so the guard carries no list of
exceptions.

## A merge gate and an agent name each have exactly one definition

Two invariants about this repo's own tooling, both guarded in `apps/web/src/lib/ci_workflow_guards.test.ts` because both fail *green*:

- **Only `ci.yml` may declare a job named `CI gate`.** That job name is the required status check on `main`. GitHub does not require every check sharing a name to pass, so a second, trivially-passing emitter can satisfy branch protection while the real jobs are still queued — observed on #457, removed by #577. If `ci.yml` ever needs to skip work on a docs-only diff, skip the heavy *jobs* and let the gate job still report from `ci.yml`.
- **An agent's `name:` is unique across `.claude/agents/**`.** Claude resolves a subagent by that frontmatter name, never by path, so two files declaring one name are two definitions of one agent and which answers is unpredictable. Putting a copy in a different directory does not separate them.

Both have been breached by an automated sync from the `templates` repo, which is additive by path and therefore blind to a name it collides with, so neither rule can rely on review alone.

## A revoke names every channel the grantee can reach the object through

A `REVOKE` is not a statement about a role, it is a statement about one **entry** in an ACL, and Postgres admits a role through the broadest entry it holds. So a revoke that names one channel while the role holds another withholds nothing, reports success, and leaves no trace in the catalogue for a state assertion to find later — the statement is the only place the intent was ever legible. This has now shipped twice, on two object classes.

- **Columns.** `revoke select (col) on t from anon` is a no-op while `anon` holds table-level SELECT, because `has_column_privilege` answers off the broader grant ([decisions § 781](decisions.md)). The prescription is the opposite order: revoke the table-level privilege, then `grant select (…)` the columns the client may read.
- **Functions.** `revoke execute on function f() from public` withholds `anon` on a workstation CLI image and **nothing** on the CI and Cloud image, where Supabase's `alter default privileges` hands every new `public` function an EXECUTE grant to `anon`, `authenticated` and `service_role` **by name**. `revoke ... from anon` is the no-op on the other image. Neither single-grantee form is portable, so the house form names both — `revoke execute on function public.f(args) from public, anon;` — and adds `authenticated` when no client role should hold it at all ([decisions § 799](decisions.md), [§ 800](decisions.md), [§ 827](decisions.md)).

Three rules follow, and they generalise past these two cases:

- **`drop function` / `drop table` takes the ACL with it.** A signature change re-issues the image default, so any migration that drops and recreates must re-emit its `revoke` / `grant` pair or a withholding decision is silently reverted. No migration is wrong on its own words when this happens, which is why a text replay cannot catch it.
- **A statement guard and a state guard are different guards, and a no-op revoke needs both.** The statement guard (`check_migration_column_revoke_noop.mjs`, `check_migration_function_revoke_noop.mjs`) replays the migration set in version order and reports a revoke whose other channel is still at its default at the end — so a repair is a later migration rather than an edit to the guard, and neither carries an allowlist. The state guard is a pgtap catalogue assertion (`anon_execute_contract_test.sql`, `column_grant_lockdown_registry_test.sql`) that answers the question the statement guard cannot: *is the object actually closed*, including for an object nobody ever wrote a revoke for. Write both, or the class reopens through whichever half you skipped.
- **A privilege change reaches every surface that exercises the privilege.** Closing an ACL moves the refusal outward: a body that used to return null on a null `auth.uid()` now raises `42501` at the grant, so a test asserting the inner answer breaks. pgtap is not the whole search space — grep the function names across `tests-e2e/` too.

Before withholding, read the **reference graph**, not just the call sites. A SECURITY INVOKER body and an RLS policy expression are both privilege-checked against the *querying* role, so a function named by a policy `to public` on a table `anon` can read must keep its grant or an anonymous read turns into `42501` ([decisions § 746](decisions.md)). `is_challenge_visible` is the live example.

## A guard parses its input, or refuses it — it never pattern-matches a language

A CI guard's whole value is that its verdict is true, so a guard that reads its input approximately is worse than no guard: it is a green tick over text nobody looked at. Four of them were found doing exactly that ([decisions § 770](decisions.md), after [§ 757](decisions.md)), and the repair is the same four rules every time.

- **A delimiter that can be quoted, nested or escaped is not a splitter.** `split(';')` over SQL fragments every `$$` body — 3441 real statements became 7366 pieces across the committed migrations — and a `--` eaten before anything knew whether it opened a comment swallowed a statement's own terminator. Lex the language (`apps/backend/scripts/sql_lex.mjs` does it for Postgres, `scripts/markdown_lines.mjs` for the Markdown registries) or do not claim to read it. Markdown's version of this is that a table row's wrapping pipes are BOTH optional, so `line.startsWith('|')` is not a row detector — GFM's rule is stateful and a row written without one renders identically ([decisions § 774](decisions.md), [§ 779](decisions.md)).
- **Ask the tool that already knows.** git knows which files a diff ADDED (`--diff-filter=A`); inferring it from a `@@ … +1` hunk header was wrong 22 times in 28. The same goes for a version a lockfile resolves, a job list a workflow declares, a path a `package.json` names.
- **Two facts in the same file are not two facts in the same scope.** A cache key belongs to its job, a `NOT VALID` to its action, an `env:` to its file. Matching per file because that is what a `readFileSync` hands you produces a verdict about a pairing that does not exist.
- **Input the guard cannot read is refused, loudly, naming the file.** Never consumed to end of input, never caught into an empty result, never skipped. A guard that reports a clean tree over something it failed to parse is the failure mode all three rules above collapse into.
- **A filter that routes around a lexer's limitation is a scope reduction, and it comes out the day the limitation does.** `check_watch_wire_vectors.mjs` read 7 of 521 phone-side test files because the shared Dart lexer could not blank a file whose strings interpolated; the narrowing was honest and documented, and it still meant a golden spelled without a magic byte in it sat outside the sweep with nothing to report it ([decisions § 816](decisions.md)). Fix the reader, then widen the scan back and re-measure — the widening is where the next defect surfaces. And where a lexer is shared, one of its suites reads the WHOLE tree it is meant to handle: `comment_strip.test.mjs` lexes all 1056 committed Dart files on the phone rail in about 0.4 s, which is the only reason the hole cannot reopen silently.

And where a rule genuinely has a blind spot, the guard **reports the blind spot** — `check_ci_diagnostics.mjs` lists the steps it does not ask to diagnose themselves — rather than leaving its boundary in a paragraph someone has to re-derive.

## Exceptions

Every rule here has escape hatches for the cases where it genuinely doesn't fit. If you're about to violate one of these rules:

1. Confirm the escape is justified (not just "easier").
2. Leave a one-line comment at the violation site explaining why (this is one of the few cases where a comment is the right answer).
3. If the escape is a recurring pattern, either generalise the rule here or add a new subsection.
