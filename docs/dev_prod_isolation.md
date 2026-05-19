# Dev / prod isolation

Local development must not be able to read or write production data, talk to live payment processors, or burn paid AI spend. This doc is the operating contract; the runtime guard in `apps/web/scripts/env_isolation.mjs` enforces it.

## The rule

When running locally — `pnpm dev:run:web`, `pnpm test:e2e`, or any other `pnpm dev:*` script — every external endpoint that the app talks to must point at a loopback address. Anything else aborts the process with a clear fix-it message.

Loopback / emulator addresses accepted by the guard:

| Address | Used by |
|---|---|
| `http://127.0.0.1:*` | Native dev on the workstation |
| `http://localhost:*` | Same |
| `http://10.0.2.2:*` | Android emulator alias for the host loopback |
| `http://host.docker.internal:*` | Docker-on-Mac / Docker-on-Windows |

## What is guarded

The guard ships with two enforcement points and a shared check.

### 1. Vite dev server (web)

`apps/web/vite.config.ts` wires the `envIsolationGuard()` plugin. On every `vite dev` start the plugin reads `process.env` + `.env.local` and aborts the boot if anything looks non-local. This is the primary control:

- `PUBLIC_SUPABASE_URL` / `SUPABASE_URL` / `OPENAI_BASE_URL` / `LIVE_HUB_URL` / `PUBLIC_LIVE_HUB_URL` / `PUBLIC_EXPORT_HUB_URL` / `PUBLIC_OSRM_URL` / `OSRM_URL` / `PUBLIC_SITE_URL` — must be loopback when set. The PUBLIC_-prefixed pair (`LIVE_HUB_URL` / `EXPORT_HUB_URL`) is what the web client reads at build time; the un-prefixed `LIVE_HUB_URL` is the Dart twin's dotenv form. Both forms are guarded so a stray inherited-shell env doesn't slip past either path.
- `STRIPE_SECRET_KEY` / `PUBLIC_STRIPE_KEY` — refuses `sk_live_…` / `pk_live_…`; expects `sk_test_…` / `pk_test_…`.

### 2. Playwright globalSetup (e2e)

`apps/web/tests-e2e/fixtures/auth.ts` runs the same check before any test signs in. Defends against the inherited-shell-env case: a developer who has `SUPABASE_URL=https://prod.supabase.co` in their `~/.bashrc` (for an unrelated project) would otherwise have every Playwright `getAdminClient()` call hit prod with the seed-user fixtures.

### 3. Unit tests

`apps/web/scripts/env_isolation.test.mjs` has 13 `node:test` cases covering loopback / prod-URL / live-key / override / multi-finding paths. Run via `node --test apps/web/scripts/env_isolation.test.mjs` (or your IDE's test runner). The CI workflow exercises it on every PR.

## The override (escape hatch)

For the rare case a developer genuinely needs to point local at a non-local URL — e.g. running e2e against a per-PR Supabase branch — set:

```bash
ALLOW_PROD_URL_IN_DEV=true
```

The guard prints a one-line warning and continues. Two rules:

1. Never commit a setup that depends on this. Each `.env.example` must work with the guard ON.
2. Never set this in CI without an explicit, documented reason. The CI sweep below detects accidental commits.

## What is NOT guarded by the runtime gate

- The Supabase CLI itself. `supabase link --project-ref <ref>` legitimately points the CLI at prod for one-off ops (`supabase functions deploy …`). Linking is intentional; that's why it's not blocked.
- Direct `curl` or admin-script calls a developer types. We can't intercept those.
- Direct production logins via the Supabase Studio web UI.

What we CAN do: the `/audit/secrets` command (see `.claude/commands/audit/secrets.md`) finds prod keys committed to git history. Run it before any release.

## When the guard fires

Sample message:

```
========================================
[env-isolation guard] Vite dev server refuses to start.

Local dev must not be configured against production endpoints.
Found:

  - PUBLIC_SUPABASE_URL = https://abcdefghijk.supabase.co
      rule: remote-host-in-dev
      fix:  Set PUBLIC_SUPABASE_URL to a loopback URL (e.g. http://127.0.0.1:54321) or unset it.

Power-user override (NOT for daily use):
  ALLOW_PROD_URL_IN_DEV=true

See docs/dev_prod_isolation.md for the full policy.
========================================
```

Each finding tells you the env var, the broken value (key values are redacted as `<redacted live key>`), the rule, and the fix.

## Adding a new guarded env var

When you add an integration that takes a new env var:

1. If it's a URL → append the name to `KNOWN_ENV_VARS` in `apps/web/scripts/env_isolation.mjs`.
2. If it's a key with distinguishable test vs live patterns (Stripe-style) → append a `KEY_PATTERNS` entry.
3. Add a unit test in `apps/web/scripts/env_isolation.test.mjs`.

Keep the matcher conservative: a false positive aborts every dev session. Match only the literal patterns the upstream provider documents.

## Related controls

- [docs/local_testing_stubs.md](local_testing_stubs.md) — what to use *instead* of prod for each upstream (Stripe test mode, RevenueCat sandbox, Ollama for Coach, …).
- [/audit/secrets](../.claude/commands/audit/secrets.md) — finds keys committed to git history.
- [.github/workflows/compliance-drift.yml](../.github/workflows/compliance-drift.yml) — flags PRs that quietly add new outbound hops without doc updates.
