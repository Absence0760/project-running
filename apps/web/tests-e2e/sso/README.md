# SSO / OAuth e2e lane

End-to-end coverage of the OAuth login path, run against a **mock OIDC
provider** so it works in CI where real Google / Apple cannot.

## Why a mock — and the one caveat

The app's social-login buttons use Supabase OAuth (`signInWithOAuth`).
GoTrue **special-cases the `google` and `apple` providers** and validates
them against the real Google / Apple, so they cannot be pointed at a
mock. The generic OIDC provider GoTrue accepts with a custom issuer
`url` is **`keycloak`** — so the lane configures
`[auth.external.keycloak]` (in `apps/backend/supabase/config.toml`) to
point at a local mock and drives the flow as `provider: 'keycloak'`.

**Caveat — the one un-exercised piece:** the provider *identity*
(keycloak vs Google) is the only thing this lane does not exercise,
precisely because GoTrue special-cases Google. **Everything downstream of
the provider redirect is the real code path:** `signInWithOAuth` →
GoTrue `/authorize` → mock consent (auto-approve) → `/auth/callback?code`
→ `exchangeCodeForSession` → Supabase session → the post-OAuth age/terms
gate (`/auth/confirm-age`) → the app. Swapping keycloak for google here
is impossible; this is the closest faithful exercise of our OAuth code.

## Pieces

- `scripts/start-mock-oidc.mjs` — boots [`oauth2-mock-server`][oms]
  fronted by a thin path-rewriter. GoTrue's keycloak provider hardcodes
  `{url}/protocol/openid-connect/{auth,token,userinfo,certs}`; the mock
  serves `/authorize`, `/token`, `/userinfo`, `/jwks`, so the front maps
  the keycloak prefix onto the mock's paths. The mock auto-approves
  `/authorize` (no consent form) and signs a token + serves a userinfo
  body for the active identity. `POST /__identity {sub,email}` switches
  the issued identity between specs.
- `../playwright.sso.config.ts` — boots the mock + a dedicated vite dev
  server (`:7779`) and runs only `tests-e2e/sso/`. Chromium launches with
  `--host-resolver-rules=MAP host.docker.internal 127.0.0.1` (see
  networking below).
- `oauth_full_flow.spec.ts` — the happy paths (new user → age/terms gate
  → app; returning user → straight to `/dashboard`).
- `callback.spec.ts` — the `/auth/callback` failure surfaces (invalid /
  missing code). They live in the lane because they pin the same OAuth
  landing page.

## Networking

GoTrue runs inside the Supabase `auth` container and reaches the mock on
the host via `host.docker.internal` (mapped to the host gateway). GoTrue
sends the **browser** to that same `url` in the authorize redirect, but
`host.docker.internal` does not resolve on the host — so the Playwright
config launches Chromium with a host-resolver rule mapping it to
`127.0.0.1`, where the mock binds. The mock therefore listens on
`0.0.0.0` and pins its issuer `url` to `http://host.docker.internal:PORT`
(it must equal what GoTrue calls, or the token exchange fails with
"Unknown issuer url").

## Provider config

`config.toml`'s `[auth.external.keycloak]` is `enabled = true` with
`url` / `client_id` / `secret` via `env()`. When those vars are unset
(every other job + local dev) the provider is inert: GoTrue fetches the
OIDC endpoints lazily at request time, so an unreachable url never breaks
`supabase start`, and nothing initiates a keycloak sign-in. The lane sets
them at `supabase start` time. The values are **non-secret test
placeholders**, not real credentials:

| env var | value used in CI |
|---|---|
| `SSO_MOCK_OIDC_CLIENT_ID` | `sso-e2e-client` |
| `SSO_MOCK_OIDC_SECRET` | `sso-e2e-secret-not-real` |
| `SSO_MOCK_OIDC_URL` | `http://host.docker.internal:9888` |

`additional_redirect_urls` includes `http://localhost:7779/auth/callback`
(the SSO dev-server port) so GoTrue accepts the lane's `redirect_to`.

## Running locally

The lane needs a Supabase stack started with the keycloak env vars set.
To avoid disrupting a shared `apps/backend` stack, run it against an
**isolated** instance: copy `apps/backend/supabase` to a throwaway dir,
give it a distinct `project_id` + shifted host ports, then:

```
export SSO_MOCK_OIDC_CLIENT_ID=sso-e2e-client SSO_MOCK_OIDC_SECRET=sso-e2e-secret-not-real SSO_MOCK_OIDC_URL=http://host.docker.internal:9888
supabase start --workdir /path/to/iso
```

Point the web dev server + fixtures at it (`.env.development.local` for
`PUBLIC_SUPABASE_URL`/`PUBLIC_SUPABASE_ANON_KEY`, and
`SUPABASE_STATUS_WORKDIR=/path/to/iso` so the admin fixture resolves the
isolated stack), then:

```
SUPABASE_STATUS_WORKDIR=/path/to/iso pnpm test:e2e:sso
```

Against the shared `apps/backend` stack the same vars must be exported
before `supabase start`, and the SSO dev port must be in
`additional_redirect_urls` (it already is).

[oms]: https://www.npmjs.com/package/oauth2-mock-server
