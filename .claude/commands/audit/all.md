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
2. **Spawn the right agent per audit area, in parallel.** Send all dispatches in a single message with multiple tool calls.
   - Security + privacy areas (`rls`, `storage`, `edge-functions`, `xss`, `secrets`, `public-rows`, `paywall`, `privacy-zones`): each is a separate `repo-security-auditor` invocation, with the audit area passed as the prompt's first sentence. Seven of these run together; each gets the corresponding `.claude/commands/audit/<name>.md` body as its full instruction.
   - `metadata-keys`: spawn `metadata-key-keeper` for the per-key sweep, OR an Explore agent if you need broader codebase scan beyond a single diff.
   - `deps`: a single Explore agent with the `deps.md` prompt is fine — the work is mostly running each tool in turn.
3. While the agents run, run the local checks that don't need an agent:
   - `audit/twin-parity` — single `diff -rq` (or invoke `mobile-twin-mirror` if there's drift to fix; otherwise handle inline)
   - `audit/architecture-guards` — run the three test suites inline
   - `audit/schema-drift` — `gen:types:check` + `dart run scripts/gen_dart_models.dart` + `git diff --stat` (or invoke `schema-change-coordinator` if drift is from an in-progress migration)
   - `audit/layered-resilience` — read-walk the recording stack inline (no agent today; Explore is overkill for a single-file walk)
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
