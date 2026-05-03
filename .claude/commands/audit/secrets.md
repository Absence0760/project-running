---
description: Find server-only secrets that may have leaked into a client bundle or git
---

Audit for secrets / env vars / API keys that should be server-only but are reachable from a client bundle, a public asset, or git history.

## Goal

The Supabase anon key is fine in the client bundle by design. The service-role key is not. Anthropic / OpenAI / OSRM / MapTiler / Strava / parkrun keys depend on which side of the trust boundary they sit on. Find any key that's on the wrong side.

## What to check

1. **`.env*` and `.envrc` files.** They should be in `.gitignore`. Run `git log --all --full-history -- '.env*' '.envrc'` to confirm none have ever been committed. If one has, the key is permanently exposed regardless of removal — flag for rotation, not deletion.
2. **Client-bundle leakage (web).** Vite / SvelteKit env vars prefixed `PUBLIC_` are inlined into the client bundle. Anything else in `import.meta.env` is server-only. Grep the codebase for `process.env.SECRET_*`, `process.env.SERVICE_ROLE`, etc. — anything referenced from a `+page.svelte` / `+layout.svelte` / `$lib/*.ts` (non-server) file is in the client bundle. Confirm only `PUBLIC_*` vars are touched there.
3. **`+server.ts` vs `+page.ts`.** Server-only env should only be referenced in `+server.ts`, `+layout.server.ts`, `+page.server.ts`, `hooks.server.ts`, and `apps/web/src/routes/api/*/+server.ts`. Anywhere else is a client bundle.
4. **Edge Function env.** `apps/backend/supabase/functions/*/index.ts` has access to function secrets via `Deno.env.get(...)`. Confirm function-local secrets are set in the function dashboard, not committed to `config.toml`.
5. **Mobile client config.** `apps/mobile_android/lib/main.dart` initialises Supabase with `url` + `anonKey`. Confirm no service-role key is hardcoded. Check `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist` for legitimacy — those are public-by-design but still warrant a glance.
6. **Build-time injection.** GitHub Actions workflows under `.github/workflows/` may export secrets to `env:` blocks for the build step. Verify each `env:` line uses `${{ secrets.X }}` and that no secret leaks via `echo` / `set -x` / verbose logging.
7. **Public-asset leak.** Search `apps/web/static/`, `apps/mobile_android/android/app/src/main/res/`, `apps/mobile_ios/ios/Runner/Assets.xcassets/` for any file that contains a key — sometimes pasted into a comment of an asset config.
8. **Recent commits.** `git log --all -S 'sk_' -S 'service_role' -S 'SUPABASE_SERVICE_ROLE_KEY' --source --pretty=fuller` — the `-S` "pickaxe" finds commits that added or removed the literal string. A single touch is enough to require rotation.

## Report

- **Critical** — a service-role / API key is in git history or a client bundle. Recommend rotation now.
- **High** — env reference in a path that compiles into the client bundle. Recommend moving to `+server.ts` proxy.
- **Medium** — overscoped key (e.g. read-and-write Strava key when only read is needed).
- **Low** — undocumented env intent, missing example in `.env.example`.

For each: the literal env var or filename, where it's referenced, what should change.

## Useful starting points

- `apps/web/src/routes/api/coach/+server.ts` — the canonical server-only-key pattern (ANTHROPIC_API_KEY)
- `apps/backend/supabase/config.toml`
- `.github/workflows/*.yml`
- `apps/web/.env.example` if it exists, otherwise `apps/web/svelte.config.js` for env access patterns

Read-only. Recommendations only — never paste a found key into the report. Identify by name + location.
