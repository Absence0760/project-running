---
description: Run the full audit sweep — security + privacy + invariants + dep health — in parallel
argument-hint: [security|invariants|deps] (optional area filter)
---

Run the project's full audit sweep. By default, runs every audit; with an argument, runs the named subset.

## Areas

- **security** — `audit/rls`, `audit/storage`, `audit/edge-functions`, `audit/xss`, `audit/secrets`, `audit/public-rows`, `audit/paywall`
- **privacy** — `audit/privacy-zones`
- **invariants** — `audit/twin-parity`, `audit/schema-drift`, `audit/metadata-keys`, `audit/architecture-guards`, `audit/layered-resilience`
- **deps** — `audit/deps`

## Procedure

1. Decide which audits to run based on `$ARGUMENTS`:
   - No argument → all audits
   - `security` → security + privacy
   - `invariants` → invariants subset
   - `deps` → deps only
2. **Spawn one Explore (or general-purpose) agent per audit, in parallel.** Each gets the corresponding `.claude/commands/audit/<name>.md` prompt as its instruction. Send all agent dispatches in a single message with multiple tool calls.
3. While the agents run, run the local checks that don't need an agent:
   - `audit/twin-parity` (a single `diff -rq` — handle inline)
   - `audit/architecture-guards` (run the test suites — handle inline)
   - `audit/schema-drift` (`gen:types:check` + `dart run scripts/gen_dart_models.dart` + `git diff --stat`)
4. **Consolidate findings** into a single report grouped by severity (Critical / High / Medium / Low), then by audit area. For each finding: file:line, what's wrong, the audit that found it.
5. **Recommend a fix order**, but don't apply fixes without explicit confirmation. Critical/High findings should be flagged with "fix this before next deploy"; Medium/Low can be batched.

## Output shape

```
# Audit report — <date>

## Critical (N)
- [audit/<area>] file:line — <one-line>
- ...

## High (N)
- ...

## Medium (N)
- ...

## Low (N)
- ...

## Recommended order
1. ...
2. ...
```

## Notes

- This is read-only. Each sub-audit is read-only by default.
- The report is the deliverable; do not edit code based on findings without asking the user first.
- If an audit finds no issues, list it under a `## Clean` section — easier to spot regression on the next run.
