# Web app — authentication

How sign-in works in the SvelteKit web app: providers, the auth store, identity linking, and how to test it locally.

---

## Overview

The web app uses **Supabase Auth** end-to-end. There is no demo / mock login — sign-in always goes through Supabase, whether you're on `localhost:7777` against a local Supabase stack or on the deployed site against a hosted Supabase project.

Supported sign-in methods:

- **Email + password** (sign-up via `/login`'s "Sign up" toggle, sign-in via the same form). Sign-up asks for the password twice — see [Password confirmation](#password-confirmation) below.
- **Google OAuth** (`signInWithOAuth({ provider: 'google' })`) — gated behind the fail-closed `PUBLIC_GOOGLE_AUTH_ENABLED` flag (`apps/web/src/lib/core/google_auth_flag.ts`). When the flag is off (the default until the Supabase `google` provider is configured) the button renders behind a "Soon" pill and clicking it surfaces the `login.googleSoon` notice instead of starting a redirect — same treatment as the Apple button. Flip the flag (set truthy) the same day you enable the provider; local dev + e2e turn it on in `.env.development`. On mobile the equivalent gate is the presence of `GOOGLE_WEB_CLIENT_ID` — an unconfigured build shows `googleSignInSoon` on tap.
- **Apple OAuth** — *not yet shipped on web.* The button is rendered behind a "Soon" pill and clicking it surfaces a "coming soon" toast (`apps/web/src/routes/login/+page.svelte` `handleAppleSignIn`). Apple Services-ID configuration for the web OAuth flow is the unblocking step. Apple Sign-In *is* wired on mobile via the native `sign_in_with_apple` SDK — see `apps/mobile_android/lib/screens/sign_in_screen.dart`.

Any one user can have **multiple identities linked**. A user who signed up with email can attach Google from `/settings/account` so the same account is reachable from either method. Apple identity linking will follow once the web Apple OAuth flow ships.

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
| `auth.signInWithApple()` | Defined in the store but **not invoked from the UI yet** — the login page's Apple button surfaces a "coming soon" toast. Will be wired once Apple Services-ID setup is complete. |
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

1. **Continue with Google** — `auth.signInWithGoogle()` when `PUBLIC_GOOGLE_AUTH_ENABLED` is truthy; otherwise `handleGoogleSoon` (the fail-closed "coming soon" notice)
2. **Continue with Apple** — `auth.signInWithApple()`
3. **Email + password** — toggles between sign-in and sign-up; both call `supabase.auth.*` directly

OAuth flows redirect to `/auth/callback`, which calls `auth.refreshSession()` and routes to `/dashboard`.

---

## Password confirmation

Both surfaces that **mint** a password — sign-up (`/login?signup=1`) and reset (`/auth/reset`) — take it in two fields and validate the pair through `checkPasswordPair` in `lib/core/auth_gates.ts`. Sign-in and the reset-*request* form don't mint a password and take one field / none.

The rule: at least `MIN_PASSWORD_LENGTH` (6, matching GoTrue's default — `config.toml` sets no `minimum_password_length`), then exact equality. Length is reported first so two matching-but-too-short entries name the fixable problem. **Neither side is trimmed** — whitespace is a real password character and is exactly the typo class the confirmation catches.

**Why this exists.** Sign-up used to take the password in a single field. A typo there is silently baked into the account: GoTrue hashes what was typed, the confirmation email arrives and gets clicked, and the account is then unreachable by its owner. Nothing errors on either side — to the user it's indistinguishable from a forgotten password, and the only tell on our side is a **confirmed account whose `last_sign_in_at` stays null**. That signature cost a real user on 2026-07-16; if a support case looks like it, this is the first thing to check. The gap existed because sign-up and reset were written independently and only reset grew a confirmation, which is why both now share the one helper.

Contract pinned in `lib/core/auth_gates.test.ts` (precedence, exactness, the length boundary); wiring pinned in `tests-e2e/auth/signup-confirm-password.spec.ts`.

> **Mobile has not closed this gap.** `sign_up_screen.dart` still takes the password in a single field, so the same lock-out is reachable from an Android / iOS sign-up.

---

## Email confirmation redirect (signup gap)

Every auth flow that mails a link passes an explicit `emailRedirectTo` / `redirectTo` **except signup**:

| Flow | redirect passed | source |
|---|---|---|
| OAuth (Google/Apple) | `${origin}/auth/callback` | `stores/auth.svelte.ts` |
| Password reset | `${origin}/auth/reset` | `login/+page.svelte` (`resetPasswordForEmail`) |
| Email change | `${origin}/auth/callback` | `settings/account/+page.svelte` |
| **Signup confirmation** | **none** | `login/+page.svelte` (`supabase.auth.signUp`) |
| **Signup (mobile)** | **none** | `packages/api_client/lib/src/api_client.dart` |

When the client sends no redirect, GoTrue falls back to the hosted project's **Site URL** for the confirmation link's landing. On a project whose Site URL is still the Supabase default (`http://localhost:3000`), the confirmation email redirects to `http://localhost:3000/?code=<pkce>` — wrong host, and the app **root** rather than `/auth/callback`.

**Why this is invisible locally / in CI:** `apps/backend/supabase/config.toml` sets `enable_confirmations = false`, so local signup sends no confirmation email at all — the confirm-email redirect path only exists on the hosted project (confirmations ON). Reset-password *does* mail locally and *does* pass a redirect, so it works; the signup gap surfaces only in production.

**Why landing on `/auth/callback` matters (not cosmetic):** the callback page (`auth/callback/+page.svelte`) exchanges the PKCE code, then replays the age/terms consent stamps via `confirm_age_and_terms` and runs the GDPR Art 8 consent gate. For password signup the immediate post-`signUp()` `confirm_age_and_terms` call 401s (no session until confirmation), so the stamp **retry lives on the callback**. A confirmation that lands on `/` (root) skips that retry — `detectSessionInUrl` may still exchange the code, but the consent capture/gate is bypassed.

**A complete fix is two parts, neither sufficient alone:**
1. **Code (shipped)** — web `signUp` sends `emailRedirectTo: ${origin}/auth/callback`. Mobile `signUp` (`packages/api_client`) sends the custom-scheme deep link `com.threkir.app://login-callback` (`ApiClient.kAuthDeepLinkRedirect`), registered as an Android intent-filter (`MainActivity`) + an iOS `CFBundleURLTypes` scheme; `supabase_flutter`'s `app_links` listener completes the PKCE session in-app. Mobile `sendPasswordResetEmail` sends `${WEB_BASE_URL}/auth/reset` (reset stays on web — mobile hosts no reset form).
2. **Dashboard (pending)** — set Site URL to the prod origin and add every redirect target to the allow-list: `https://threkir.com/auth/callback`, `https://threkir.com/auth/reset`, and `com.threkir.app://login-callback` (+ preview origin). See Production setup below.

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

For step-by-step OAuth setup + identity-link test paths, see [`apps/web/local_testing.md` § Testing external integrations](../../apps/web/local_testing.md#testing-external-integrations).

---

## Production setup

For the deployed web app, the same code points at a hosted Supabase project. Set in the deploy environment:

```bash
PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
PUBLIC_SUPABASE_ANON_KEY=<anon-key>
```

Supabase Auth dashboard:

- Set **Authentication → URL Configuration → Site URL** to the prod origin (`https://threkir.com`). A fresh project defaults this to `http://localhost:3000`; leaving it there sends every fallback redirect (notably signup confirmation, which passes no `emailRedirectTo` — see "Email confirmation redirect" above) to localhost.
- Add **every** redirect target to **Redirect URLs**: `https://threkir.com/auth/callback`, `https://threkir.com/auth/reset`, and the mobile deep link `com.threkir.app://login-callback` (+ the preview origin). The allow-list is enforced — a redirect not on it falls back to the Site URL.
- Enable Google and Apple providers under **Authentication → Providers**
- Enable **Allow manual linking** under **Authentication → Settings** so `linkIdentity()` works
- Mirror the same redirect URI in each external provider's app config

Email confirmations and rate limits are configured in the same dashboard. For the auth-email localization hook + custom SMTP (the sender address), see [email.md § Production ops](email.md).

---

## Pro-tier checks

Tier gating is owned by [paywall.md](paywall.md), not this doc — see it for the tier model, the `is_pro()` RPC, the per-tier coach daily caps, the `features.ts` / `<ProGate>` client gate, and the `BYPASS_PAYWALL` local-dev flag (with its exact `NODE_ENV` + local-Supabase-URL guards — do not copy a looser version of that flag from memory).

The one auth-relevant note: `subscription_tier` is read from `user_profiles` and exposed as `auth.user?.subscription_tier`, and `/api/coach/+server.ts` calls the no-arg `is_pro()` RPC (which gates internally on `auth.uid()`). The earlier `is_user_pro(uuid)` variant was dropped in migration `20260516_001_drop_is_user_pro.sql` because the user-id parameter let any authenticated caller probe another user's tier.

---

*Last updated: April 2026 — rewritten against the current auth store; demo-login mode is gone, identity linking documented.*
