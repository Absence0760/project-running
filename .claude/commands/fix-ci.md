---
description: Fix a failing CI job / Playwright shard from a GitHub Actions run. Root-causes the failure, fixes it without coding around it (no retry/timeout/skip band-aids), reproduces locally where possible, and lands coverage so the failure can't return silently.
argument-hint: "<GitHub Actions run URL or run ID> [optional: which job/shard, if known]"
---

Fix the failing CI run `$ARGUMENTS`. Find the real cause, fix it at the root, add coverage, and stop before pushing.

## The two hard rules (these override convenience)

1. **Do not code around the issue.** A red test that catches a real defect is doing its job — fix the defect, not the test. Forbidden "fixes" unless you can prove the failure is pure infrastructure noise *and* name the structural reason the band-aid is the right call:
   - bumping a timeout / retry count / sleep to paper over a slow or racy path
   - adding `.skip` / `xfail` / `continue-on-error` / `fail-fast: false` to hide a failure
   - loosening an assertion, widening a tolerance, or deleting the failing case
   - re-running until green
   If you catch yourself reaching for one of these, stop: you've found the symptom, not the cause.

2. **Add coverage where the gap let the failure through.** Whatever broke, leave behind something that fails loudly and early next time — a pinning test for a code defect, an explicit assertion / health-gate for an infra step, a guard for a missing precondition. Coverage ships in the **same commit** as the fix (`docs/conventions.md` § Test hygiene).

## Procedure

### 1. Pull the failure apart

- `gh run view <id>` to see which job(s) failed and at which step. For a sharded suite, note the exact shard.
- `gh run view --job <job-id> --log` and grep to the **actual error** — the first thing that broke, not the final `exit 1`. Scroll past the harness boilerplate; the real signal is usually an exception, a non-zero command, a 4xx/5xx, or a "deadline exceeded" deep in the step output.
- Quote the failing step name + the error line back to the user so you're both anchored on the same failure.

### 2. Classify it honestly

Decide which of these it is, and say so:

- **Genuine defect** — the app/test/migration is wrong. Fix the defect; pin it with a test.
- **Test bug** — the test asserts the wrong thing or has a race in *its own* setup. Fix the test correctly (not by loosening it).
- **Infra flake** — a CI-environment failure (cold sidecar, slow image pull, port clash, resource limit). The fix is to **remove the fragile dependency or make the step deterministic**, not to retry it. If retries already exist and still failed, that is proof retries are the wrong tool — find what the step is actually waiting on and gate on *that*, or restructure so the fragile operation never happens.

"It passed on the other shards / on re-run" narrows it toward flake, but does **not** license a band-aid — a flake still has a root cause.

### 3. Read the surrounding context before changing it

CI steps in this repo carry long comments documenting prior incidents (cited by run ID) and why the current shape exists. Read them. Your fix should make those comments obsolete by removing the failure mode, and you should update or replace the comments to match — don't leave a comment describing a workaround you just deleted.

### 4. Reproduce locally, then verify the fix locally

Wherever the failure can be reproduced on this workstation, do it — it's the difference between a guess and a fix:

- Backend / e2e: drive the real local Supabase stack (`cd apps/backend && supabase …`, see `apps/backend/CLAUDE.md`). If you must cycle or wipe the user's local stack to get a faithful repro, first check it holds only standard seed data (the three `*@test.com` users) — if there's custom state, **ask before wiping**.
- Web unit / Playwright: run the specific failing spec (`pnpm exec playwright test <file> --shard=…` mirrors CI; `pnpm test` for units).
- Flutter: `melos exec -- flutter test <file>`; if the fix touches `apps/mobile_android/lib/` or `test/`, mirror it with the `mobile-twin-mirror` agent to keep the byte-identical twin intact.
- pgtap / Edge Functions: `supabase test db --local` / `deno test` per `apps/backend/CLAUDE.md`.

Confirm the failure reproduces *before* the fix and is gone *after*. Capture the evidence (counts, status codes, exit codes) — report it, don't just claim it.

### 5. Apply the fix at the lowest sensible layer

- If the same broken pattern appears in **sibling jobs/steps**, fix all of them — don't leave the flake live in `api-client-integration` after fixing it in `e2e-web`.
- Keep the blast radius proportional: prefer the surgical, version-/behaviour-stable change over a broad upgrade that could destabilise unrelated jobs, unless the broad change is genuinely the root fix.
- Match the file's existing voice; if it documents incidents by run ID, document yours the same way.

### 6. Sweep docs

If a doc describes the behaviour you changed (e.g. `docs/testing.md`'s CI-pipeline section describing how a job seeds/boots), update it in the same turn. (`[[feedback_doc_edits_sweep_for_staleness]]`, CLAUDE.md § Docs hygiene.)

### 7. Commit, don't push

- One coherent piece → one commit, fix + coverage + doc update together (`[[feedback_commit_after_each_piece]]`).
- No AI attribution / `Co-Authored-By` / footer in the message (user-level rule).
- A failing-CI fix the user asked for is authorized to commit directly on `main` per the commit-cadence convention. **Never `git push`** — that's a separate, explicit ask.
- Validate before committing where cheap: `python3 -c "import yaml; yaml.safe_load(open('<workflow>'))"` for workflow YAML, the relevant linter/test for code.

## Output

End with: the failing step + root cause (one or two sentences), the fix and *why it's not a band-aid*, the coverage you added, the local verification evidence, and any residual risk worth flagging (e.g. "this is correct only because CI pins CLI 2.84.2 — a version bump would change the assumption"). Keep it tight; the user can read the diff.
