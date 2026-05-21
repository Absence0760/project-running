---
description: Pre-tag readiness gate for a release. Checks the local + remote state of the chosen app (CI green on main, twin parity, schema drift, untracked files, last-tag delta) and reports a green/red checklist. Read-only; never tags.
argument-hint: [app] (mobile_android | mobile_ios | watch_wear | watch_ios | web | backend | worker | osrm)
---

Run a pre-tag readiness audit for one of the per-app release workflows. Report a green/red checklist; never tag, push, or publish anything. The user does the actual `git tag` after they've reviewed the report.

## Why this exists

Every app ships on its own cadence via `<app>@<version>` tags ([docs/releasing.md](../../docs/releasing.md)). Cutting a tag triggers an irreversible publish (Play Internal, Lambda update, Supabase migrate, Fly deploy). A bad tag means rollback work — easy to avoid by checking the obvious gates first.

The gates are scattered (CI status, twin invariant, schema codegen, untracked work, doc drift, last-tag commit window) and the human-eyeball version is unreliable. This command runs them in one shot.

## When to use

**Right fit:** you're about to cut a release and want a single yes/no.

**Wrong fit — refuse:**
- Argument doesn't match a known app from [docs/releasing.md](../../docs/releasing.md).
- The user is on a feature branch (not `main`) — explain that releases tag from `main`, ask whether to switch.

## Procedure

### 1. Validate the argument

Accept exactly one of: `mobile_android`, `mobile_ios`, `watch_wear`, `watch_ios`, `web`, `backend`, `worker`, `osrm`.

If `$ARGUMENTS` is empty, ask the user which app — don't guess.

### 2. Confirm we're on main

```
git rev-parse --abbrev-ref HEAD
```

If not `main`, abort with: "release tags must be cut from `main`; you're on `<branch>`. Switch with `git checkout main && git pull`, then re-run."

### 3. Run the universal gates (every app)

For each, mark **green** / **red** and capture a one-line reason for any red.

#### 3a. Working tree is clean

```
git status --porcelain
```

Empty → green. Anything → red ("uncommitted changes in: <files>").

#### 3b. main is up to date with origin

```
git fetch origin main
git rev-list --count HEAD..origin/main
git rev-list --count origin/main..HEAD
```

Both `0` → green. Behind → red. Ahead → red ("local main has unpushed commits — push first, wait for CI, then re-run").

#### 3c. Latest CI run on main is green

```
gh run list --branch main --limit 1 --json status,conclusion,workflowName,headSha,createdAt
```

`status=completed` and `conclusion=success` → green. Anything else → red ("CI on the head commit is `<status>/<conclusion>` — wait for green or investigate").

If the user has the GitHub CLI but isn't logged in, recommend `gh auth login` and skip — don't fail the whole report.

#### 3d. Twin invariant intact

```
diff -rq apps/mobile_android/lib apps/mobile_ios/lib
diff -rq apps/mobile_android/test apps/mobile_ios/test
diff <(grep -vE '^(name|description):' apps/mobile_android/pubspec.yaml) \
     <(grep -vE '^(name|description):' apps/mobile_ios/pubspec.yaml)
```

All three empty → green. Any drift → red, list the diverged paths.

(This applies to every release — even a `web` release: a stale twin will fail the next mobile release CI, and it's cheaper to fix here.)

#### 3e. Schema codegen is in sync

```
dart run scripts/gen_dart_models.dart
git diff --stat packages/core_models/lib/src/generated/db_rows.dart \
                apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/generated/DbRows.kt
```

No diff → green. Diff → red ("regenerated row classes differ — commit `dart run scripts/gen_dart_models.dart` output before tagging").

For the TS side, document that the user can run `npm run gen:types:check --workspace=apps/backend` separately — it needs a running Supabase stack which we don't want to spin up just for this report. Note it in the output as **manual** with a one-liner the user can copy.

### 4. Run app-specific gates

#### `mobile_android` and `mobile_ios`

- Find last tag: `git describe --tags --match "<app>@*" --abbrev=0` (`<app>` = `mobile_android` or `mobile_ios`).
- Count commits since: `git rev-list --count <last-tag>..HEAD`. Zero → red ("no new commits since `<last-tag>` — nothing to release").
- List the commits: `git log --oneline <last-tag>..HEAD -- apps/<app> packages/ apps/backend/supabase/migrations/`. Show as the **changelog draft** in the report — useful for the GitHub Release notes.
- Check for new migrations since the last `<app>` tag (the migrations apply server-side via `backend@*` but app code may depend on them): list any `apps/backend/supabase/migrations/*.sql` newer than the last `backend@*` tag and flag them as a **migration ordering concern** if the user is about to ship `<app>` ahead of `backend`.

#### `watch_wear` and `watch_ios`

Same as above but scoped to `apps/<app>`.

#### `web`

- Last tag: `git describe --tags --match "web@*" --abbrev=0`.
- Commits since: `git rev-list --count <last-tag>..HEAD`. Zero → red.
- Confirm `apps/web/lambda/coach/build.mjs` builds (run `node apps/web/lambda/coach/build.mjs` if it exists; success → green). The release workflow re-runs this; failing here is a pre-flight catch.
- Note: production hits `threkir.com` / `www.threkir.com` (per [`apps/web/deployment.md`](../../apps/web/deployment.md)), preview at `preview.threkir.com`. Mention which one this tag will deploy to.

#### `backend`

- Last tag: `git describe --tags --match "backend@*" --abbrev=0`.
- New migrations since: `git log --oneline <last-tag>..HEAD -- apps/backend/supabase/migrations/`. List them — these will run on the linked project.
- Flag any migration whose name suggests destructive changes (`drop`, `delete`, `revoke`, `truncate`) as a **review carefully** entry. Don't block; let the user judge.
- Edge functions changed since: `git log --oneline <last-tag>..HEAD -- apps/backend/supabase/functions/`. List them.

#### `worker` and `osrm`

- Last tag, commits-since count, scope to `apps/job_worker/` (worker) or `apps/osrm/` if it exists. Treat zero-commits as red.

### 5. Build the report

```
# Release readiness — `<app>@<proposed-version>`

## Universal gates

| Gate | Status | Detail |
|---|---|---|
| Working tree clean | ✓ / ✗ | ... |
| main pushed + ahead-of/behind | ✓ / ✗ | ... |
| CI green on HEAD | ✓ / ✗ | ... |
| Twin invariant | ✓ / ✗ | ... |
| Schema codegen (Dart + Kotlin) | ✓ / ✗ | ... |
| Schema codegen (TS) | ⚠ manual | run `npm run gen:types:check --workspace=apps/backend` |

## App-specific (`<app>`)

| Gate | Status | Detail |
|---|---|---|
| Last tag | — | `<app>@<x.y.z>` (<n> days ago) |
| Commits since last tag | ✓ / ✗ | <count> commits |
| ...app-specific extras... | | |

## Changelog draft (commits since `<app>@<x.y.z>`)

- abcd123 commit subject
- ...

## Verdict

<ALL GREEN — ready to tag with `git tag -a <app>@<version> -m '...'`>
or
<NOT READY — fix the red items above first>
```

### 6. Hand off

End with:

> If everything's green, the next step is:
> ```
> git tag -a <app>@<version> -m '<short summary>'
> git push origin <app>@<version>
> ```
> I won't run those — that's your call.

**Do not tag, do not push, do not auto-fix any of the red gates.** This command is read-only.

## Notes

- The whole thing should take under a minute. If a gate hangs (e.g. `gh run list` on a slow connection), skip it with a `⚠ skipped — <reason>` row rather than blocking the report.
- `gh` is required for the CI-status check. If unavailable, fall back to a one-line note: "install `gh` to auto-check CI; manual: open the Actions tab and confirm green on the head commit".
- This command does NOT replace [`docs/releasing.md`](../../docs/releasing.md). It's a pre-flight, not the release procedure itself.
