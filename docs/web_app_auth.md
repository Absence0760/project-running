# Web app — authentication

How sign-in works in the SvelteKit web app: providers, the auth store, identity linking, and how to test it locally.

---

## Overview

The web app uses **Supabase Auth** end-to-end. There is no demo / mock login — sign-in always goes through Supabase, whether you're on `localhost:7777` against a local Supabase stack or on the deployed site against a hosted Supabase project.

Supported sign-in methods:

- **Email + password** (sign-up via `/login`'s "Sign up" toggle, sign-in via the same form)
- **Google OAuth** (`signInWithOAuth({ provider: 'google' })`)
- **Apple OAuth** (`signInWithOAuth({ provider: 'apple' })`)

Any one user can have **multiple identities linked**. A user who signed up with email can attach Google and Apple from `/settings/account` so the same account is reachable from any of those methods.

---

## Auth store

**Location:** `src/lib/stores/auth.svelte.ts`

A Svelte 5 runes module that wraps Supabase's `supabase.auth.*` and exposes a reactive `user` / `loggedIn` / `loading` triple. Import it anywhere:

```typescript
import { auth } from '$lib/stores/auth.svelte';
```

### Reactive properties

| Property | Type | Description |
|---|---|---|
| `auth.user` | `User \| null` | Current user profile (null while loading or signed out) |
| `auth.loggedIn` | `boolean` | Whether a Supabase session exists |
| `auth.loading` | `boolean` | True during the initial `getSession()` round-trip |

### `User` shape

```typescript
interface User {
  id: string;
  email: string;
  display_name: string | null;
  avatar_url: string | null;
  parkrun_number: string | null;
  preferred_unit: 'km' | 'mi';
  subscription_tier: 'free' | 'pro' | 'lifetime';
}
```

The shape is hydrated from `user_profiles` on every sign-in. If the row doesn't exist yet (first-ever sign-in), the store upserts a default row with `preferred_unit: 'km'` and `subscription_tier: 'free'`.

### Methods

| Method | Description |
|---|---|
| `auth.signInWithGoogle()` | Kicks off Google OAuth via Supabase; redirects to the provider |
| `auth.signInWithApple()` | Kicks off Apple OAuth via Supabase; redirects to the provider |
| `auth.refreshSession()` | Re-reads the Supabase session (useful after OAuth return) |
| `auth.logout()` | `supabase.auth.signOut()` + clears local state |

Email/password sign-in is wired directly in `/login/+page.svelte` via `supabase.auth.signInWithPassword(...)` and `supabase.auth.signUp(...)` — it doesn't go through the store.

The store also installs `supabase.auth.onAuthStateChange(...)` on first import so any future sign-in (an OAuth round-trip, an identity link, a token refresh) re-hydrates `auth.user` automatically.

---

## Route protection

**Location:** `src/routes/+layout.svelte`

A single `$effect` redirects unauthenticated visitors to `/login` for any non-public route:

```typescript
$effect(() => {
  if (browser && !auth.loading && !auth.loggedIn && !isPublic($page.url.pathname)) {
    goto('/login');
  }
});
```

Public routes (no auth, no sidebar):

- `/` — landing page
- `/login` and `/auth/callback`
- `/share/run/[id]/`, `/share/route/[id]/`
- `/live/...` — public spectator pages
- `/clubs/join/[token]/` — public invite-link landing

Everything else renders inside the authenticated app shell (sidebar + main content).

---

## Identity linking

The "Sign-in Methods" card on `/settings/account` lists every identity attached to the current user (one per provider) and lets the user link a missing one or unlink an existing one.

### Wire format

- **Read**: `supabase.auth.getUserIdentities()` → `{ identities: [{ provider, identity_data, created_at, ... }] }`
- **Link**: `supabase.auth.linkIdentity({ provider, options: { redirectTo: '/auth/callback' } })` — kicks off an OAuth round-trip identical to fresh sign-in. On return, the new identity is attached to the existing `user_id`.
- **Unlink**: `supabase.auth.unlinkIdentity(identity)`. Supabase blocks unlinking the last remaining identity; the UI also disables the button client-side with a "you need at least one" tooltip.

### Supabase prerequisites

Identity linking is **opt-in** in Supabase. If `linkIdentity()` returns `manual_linking_disabled`, flip on **Auth → Settings → Allow manual linking** in the dashboard, or set `enable_manual_linking = true` under `[auth]` in `apps/backend/supabase/config.toml` for local. Without this flag the link buttons surface the error inline; nothing else breaks.

### UI

`apps/web/src/routes/settings/account/+page.svelte`:

- Brand-true SVG icons for Google (4-colour G) and Apple (white-on-black wordmark), reused from `/login`
- Provider rows show provider label + email from `identity_data` + linked-on date
- Per-provider unlink button, disabled when only one identity remains

---

## Login page

**Location:** `src/routes/login/+page.svelte`

Three sign-in methods, all hitting Supabase Auth:

1. **Continue with Google** — `auth.signInWithGoogle()`
2. **Continue with Apple** — `auth.signInWithApple()`
3. **Email + password** — toggles between sign-in and sign-up; both call `supabase.auth.*` directly

OAuth flows redirect to `/auth/callback`, which calls `auth.refreshSession()` and routes to `/dashboard`.

---

## Session persistence

Sessions are managed by `@supabase/supabase-js` itself:

- The session token is stored in `localStorage` under the Supabase-managed key (`sb-<project-ref>-auth-token`)
- On reload, the store calls `supabase.auth.getSession()` and hydrates from any saved token
- Token refresh happens automatically; `onAuthStateChange` fires when the user object changes
- On logout, `supabase.auth.signOut()` clears the storage key and broadcasts SIGNED_OUT to all tabs

There is **no app-level `auth_token` key**. The app trusts the SDK to manage session storage.

---

## Local testing

Sign-in always uses Supabase, even locally — there is no demo mode. The seeded user `runner@test.com` / `testtest` is the standard baseline.

```bash
cd apps/web
pnpm install
pnpm dev   # → http://localhost:7777
```

### Email + password (no provider config needed)

1. Visit `/login` → enter `runner@test.com` / `testtest` → click **Sign In**
2. The seed user already has runs, routes, and an active plan, so the dashboard is populated immediately

### OAuth providers

Local OAuth requires the provider's client ID + secret to be set in `apps/backend/supabase/config.toml` (`[auth.external.google]` / `[auth.external.apple]`). The provider's allowed redirect URIs need to include both `http://localhost:7777/auth/callback` and Supabase's own callback (`http://localhost:54321/auth/v1/callback`).

For step-by-step OAuth setup + identity-link test paths, see [`apps/web/local_testing.md` § Testing external integrations](../apps/web/local_testing.md#testing-external-integrations).

---

## Production setup

For the deployed web app, the same code points at a hosted Supabase project. Set in the deploy environment:

```bash
PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
PUBLIC_SUPABASE_ANON_KEY=<anon-key>
```

Supabase Auth dashboard:

- Enable Google and Apple providers under **Authentication → Providers**
- Add the production origin (e.g. `https://run-app.example.com/auth/callback`) to **Authentication → URL Configuration → Redirect URLs**
- Enable **Allow manual linking** under **Authentication → Settings** so `linkIdentity()` works
- Mirror the same redirect URI in each external provider's app config

Email confirmations and rate limits are configured in the same dashboard.

---

## Pro-tier checks

`subscription_tier` is read from `user_profiles` and exposed as `auth.user?.subscription_tier`. Two helpers wrap the gating:

- Server side: the `is_user_pro(uid)` SQL RPC, used by `/api/coach/+server.ts` to bypass the 10/day cap.
- Client side: `apps/web/src/lib/features.ts` reads the tier and exposes `isLocked(featureName)`. `<ProGate feature="..." />` renders an upsell when locked.

For local development, set `BYPASS_PAYWALL=true` in `apps/web/.env.local` to skip every tier check server-side without flipping `subscription_tier` in the database.

---

*Last updated: April 2026 — rewritten against the current auth store; demo-login mode is gone, identity linking documented.*
