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
| `auth.logout()` | `supabase.auth.signOut({ scope: 'local' })` + clears local state — the sidebar's Sign out. Only invalidates this browser context; swallows the provider error. |
| `auth.logoutEverywhere()` | `supabase.auth.signOut({ scope: 'global' })` + clears local state — the `/settings/account` "Sign out everywhere" affordance. Revokes every refresh token (mobile + watch + other browsers), so a suspected-stolen token stops working. **Fails closed**: throws on a revocation error before the local teardown, so a failed global sign-out never masquerades as success. Both methods route through the `signOutWithScope` seam in `stores/sign_out.ts`. |

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

## Auth error surfacing

Supabase's raw `err.message` ("AuthApiException…", "Failed to fetch") is unlocalized developer jargon. Every rendered `error =` on `/login` routes through `classifyAuthError` + `authErrorMessageKey` in `lib/core/auth_errors.ts`, which maps the failure to one of `offline` / `invalidCredentials` / `rateLimited` / `emailExists` / `emailNotConfirmed` / `weakPassword` / `generic` and resolves the matching `login.error*` i18n key (all six locales). Classification is **structural** — it reads the error's `code` + `status` first (supabase-js `AuthApiError` carries both) and falls back to matching the message, so a plain `TypeError: Failed to fetch` classifies too. Mobile mirrors the branches in `apps/mobile_android/lib/auth_error.dart` (`classifyAuthError` / `friendlyAuthError`) — **keep the two in sync**.

**Unconfirmed email (issue #486).** A user who signs up but never clicks the confirmation link can't sign in. GoTrue signals this two ways: the dedicated `email_not_confirmed` code, **or** the OAuth-style `invalid_grant` error carrying the descriptive message `"Email not confirmed"`. The classifier checks the specific email-not-confirmed condition (code **or** message) **before** the generic `invalid_credentials`/`invalid_grant` branch — the ordering matters, because that branch also matches `invalid_grant`, so a message-only signal would otherwise fall through to a misleading "wrong password" banner. On this classification `/login` sets `resendFor` to the attempted email, which renders a **Resend confirmation email** button inside the error banner; clicking it calls `supabase.auth.resend({ type: 'signup', … })` and shows the privacy-preserving `login.confirmationResent` copy ("If that email is registered, we've sent a new confirmation link.") — deliberately non-committal so it isn't a user-enumeration oracle (matches the reset-request posture; see issue #454 on enumeration). Note local Supabase runs with `enable_confirmations = false`, so this path only fires against the hosted project — see "Email confirmation redirect" below.

Mapping pinned in `lib/core/auth_errors.test.ts` (incl. the `invalid_grant` + "Email not confirmed" ordering case); surfacing pinned in `tests-e2e/auth/email-not-confirmed.spec.ts` (intercepts the token endpoint, asserts the specific banner + resend button).

---

## Password confirmation

All three surfaces that **mint** a password — sign-up (`/login?signup=1`), reset (`/auth/reset`), and change-password (`/settings/account`) — take it in two fields and validate the pair through `checkPasswordPair` in `lib/core/auth_gates.ts` (change-password reaches it via `changePassword`, which runs the pair check first and then the current-password step-up below). Sign-in and the reset-*request* form don't mint a password and take one field / none. **If you add a fourth, route it through the same helper.**

On mobile the password-minting surfaces are sign-up (`sign_up_screen.dart`) and the change-password dialog on `settings_account_screen.dart` — there is no reset screen — and sign-up routes through the Dart twin `auth_gates.dart` (whose `minPasswordLength` re-exports `kPasswordMinLength` from `auth_validation.dart`). **The two helpers are a TS↔Dart parity pair: keep the rule in lockstep.**

The rule: at least `MIN_PASSWORD_LENGTH` (a re-export of `PASSWORD_MIN_LENGTH` from `auth_rules.ts` — 8, enforced server-side via `minimum_password_length` in `config.toml`, prod via the dashboard Auth settings), then exact equality. Length is reported first so two matching-but-too-short entries name the fixable problem. **Neither side is trimmed** — whitespace is a real password character and is exactly the typo class the confirmation catches.

**Why this exists.** Sign-up used to take the password in a single field. A typo there is silently baked into the account: GoTrue hashes what was typed, the confirmation email arrives and gets clicked, and the account is then unreachable by its owner. Nothing errors on either side — to the user it's indistinguishable from a forgotten password, and the only tell on our side is a **confirmed account whose `last_sign_in_at` stays null**. That signature cost a real user on 2026-07-16; if a support case looks like it, this is the first thing to check. The gap existed because sign-up and reset were written independently and only reset grew a confirmation, which is why both now share the one helper.

Contract pinned in `lib/core/auth_gates.test.ts` (precedence, exactness, the length boundary); wiring pinned in `tests-e2e/auth/signup-confirm-password.spec.ts` and `tests-e2e/settings/account.spec.ts`. The settings tests exercise the rejection branches only — a successful save there would rotate the shared fixture user's password out from under every other spec.

On mobile the contract is pinned in `test/auth_gates_test.dart` (17 mirror cases, one per web case) and the wiring in `test/sign_up_screen_test.dart`. Mobile has no e2e tier by design (`docs/testing/testing.md § What's not covered`), so the widget test is the wiring pin.

## Change password requires the current password (issue #381)

`/settings/account` used to call `supabase.auth.updateUser({ password })` straight off the ambient session. Every path that yields a live access token for a signed-in user — `localStorage` copied off an unlocked device, an XSS anywhere in the authenticated app, a debugging token pasted into a ticket — was therefore a **permanent account takeover**: the holder sets a new password, and the owner is locked out of their own account with no knowledge of the old one required (OWASP ASVS V2.1.14 / CWE-620). The `password_changed_notification` mail is detection after the fact, not prevention.

The section now takes a **Current Password** field and proves it before the write. The rule lives in `lib/core/password_change.ts` (`changePassword`), which the page drives with two injected effects so the ordering and the fail-closed posture are unit-testable:

1. `checkPasswordPair(new, confirm)` — the same local check as every other minting surface, run first so a typo in the new field never burns a sign-in attempt against GoTrue's rate limit.
2. A non-empty current password (`current_missing`).
3. `verifyCurrentPassword` → `supabase.auth.signInWithPassword({ email, password: current })`. **Only an error-free response counts as proof.** A rejection, a thrown network error, and a session carrying no email all resolve the same way: `current_invalid`, and `updateUser` is never reached.
4. `updateUser({ password })`.

`/auth/reset` deliberately does **not** come through here. That flow is already gated by a single-use recovery token mailed to the address on file — the same proof, by another route — and adding a current-password field there would break the one flow a user reaches *because* they don't know their password.

**Accounts with no password.** A Google / Apple signup has nothing to prove, and there is no client-side signal that reliably says so (GoTrue does not add an `email` identity when an OAuth account later sets a password, so inferring from `getUserIdentities()` would fail *open* for exactly those accounts). Rather than guess, the section carries an **Email me a reset link** button — `resetPasswordForEmail(auth.user.email)` → `/auth/reset`. Possession of the mailbox is the alternative proof, and unlike the session it isn't something the token holder has. That keeps the documented "set a password so you can sign in on the Wear OS watch app" path working without an exception in the step-up.

Contract pinned in `lib/core/password_change.test.ts` (7 cases: the happy path, wrong password, empty current, a verifier that throws, pair-check precedence over the network call, the length/mismatch precedence, and a failed update). Wiring pinned in `tests-e2e/settings/account.spec.ts` (`change password — step-up + validation`), which additionally aborts `PUT /auth/v1/user` so a regression can't rotate the shared fixture user's password out from under every other spec.

**Mobile still has the hole.** `settings_account_screen.dart`'s change-password dialog calls `ApiClient.updatePassword` (→ `updateUser`) off the ambient session with no current-password field, exactly as web did. Web is canonical (§24) so the rule landed here first; porting `changePassword` to Dart — at which point `password_change.ts` becomes a parity pair — is tracked in [`followups.md § Mobile`](../product/followups.md). Until then it is web-only and `auth_gates` remains the only shared half.

## Change email

A signed-in user can migrate their account to a new address from `/settings/account` (issue #245) — the escape hatch for someone who has lost access to their sign-up mailbox and would otherwise have to delete + re-register, losing all history. The email field stays read-only; a **Change email** affordance reveals a new-address input that calls `supabase.auth.updateUser({ email }, { emailRedirectTo: ${origin}/auth/callback })`. This starts GoTrue's **secure email change**: a confirmation link goes to **both** the current and the new address, and `auth.user.email` does not flip until both are followed. Because the SDK writes its returned user back into the session store, the "old address" shown in the pending note is **snapshotted at request time** (`pendingOldEmail`), not read back off the store. The UI validates the new address client-side first (loose `<input type="email">`-shape check, must differ from the current one — the server stays the authority) and, on a successful request, collapses the editor and shows a persistent **confirmation-pending** banner naming both inboxes.

The confirmation mails themselves are rendered by the `auth-email` Edge Function's `email_change` (to the new address) + `email_change_current` (to the current address) catalogue keys — present in all six locales, with the secure double-send fan-out handled by `planSends` in `functions/auth-email/lib.ts`. No backend change was needed for #245; the templates already existed.

Wiring pinned in `tests-e2e/settings/account.spec.ts` (`change email — request path`): the reject branch (unchanged/invalid address, no request fired) and the request branch (PUT `/auth/v1/user` **stubbed** so USER_A's real address isn't rotated out from under the other specs, then asserting the pending state).

**Mobile** mirrors this: a **Change email** tile on `settings_account_screen.dart` opens a dialog with the same validation → `ApiClient.updateEmail(newEmail)` (`updateUser` with `emailRedirectTo: kAuthDeepLinkRedirect`) → a persistent pending note on the tile subtitle. Pinned in `test/settings_account_email_test.dart`. The `looksLikeEmail` shape check reuses `auth_validation.dart`.

## Password visibility toggle

Every obscured web password field carries a show/hide eye toggle — the password that mints an account shouldn't be typed blind. The toggle is a shared `components/PasswordInput.svelte` (issue #487, extending the original `/login`-only #225 work): `/login` sign-in + sign-up (password + confirm), `/auth/reset` (new + confirm), and the `/settings/account` change-password fields all use it. It flips the input between `type='password'` and `type='text'`, carries a state-tracking localized `aria-label` (`login.showPassword` / `login.hidePassword` in all six locales) plus `aria-pressed`, and exposes a `toggleDisabled` prop the `/login` form binds to `!hydrated` — a pre-hydration click would silently do nothing, same treatment as the submit button. Wiring pinned in `tests-e2e/auth/password-visibility.spec.ts` (`/login` sign-in + sign-up independence, and the `/settings/account` change-password field).

On mobile every obscured field routes through `widgets/password_field.dart` (`PasswordField`) — sign-up (password + confirm), sign-in, and the settings change-password dialog — with the `authShowPassword` / `authHidePassword` ARB keys as the toggle's tooltip / a11y label. Pinned in `test/password_field_test.dart` plus the independent-toggles case in `test/sign_up_screen_test.dart`.

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

## Consent is enforced server-side, not just by the client redirect (issue #382)

The Art 8 age/terms gate above (`confirm_age_and_terms` + the `/auth/confirm-age` redirect) is a **client-side UX layer**. On its own it was bypassable: a direct `curl` to GoTrue `/auth/v1/signup`, or closing the tab before `/auth/callback` replays the stamp, yields an `authenticated` account whose `user_profiles.age_confirmed_at IS NULL` — and until now every RPC/RLS was silent on the column, so that account had full functional use of the app. Art 8 consent is invalid when the controller can't show the affirmative act happened, and the downstream Art 9 processing (location traces, workouts, food, body metrics) is then unlawful ab initio.

The enforcement beneath the redirect is a **fail-closed `BEFORE INSERT` trigger** (`private.enforce_consent()`, migration `20270424000004_consent_write_gate.sql`) on the core personal-data content tables — `runs`, `gym_workouts`, `food_log`, `body_metrics`, `routes`. An `authenticated` caller (a user JWT) cannot insert their first row of activity/health data until `confirm_age_and_terms()` has stamped `age_confirmed_at`; the guard raises `42501`. The reusable helper is keyed on `auth.uid()` (the RLS insert check already forces `new.user_id = auth.uid()`), so the caller's stamp is the row's stamp.

Two carve-outs keep legitimate flows working:

- **The consent-stamping path is never gated.** `user_profiles` carries no trigger, so `confirm_age_and_terms()` (which creates/updates the profile row) always succeeds — a brand-new user stamps, then writes.
- **A null `auth.uid()` (service_role / backend jobs) passes through.** Async importers/webhooks (the Strava webhook runs as service_role) have no interactive consent context; gating them would break ingestion. The bypass this closes is an `authenticated` account with no stamp, which always has a non-null `auth.uid()`. The parkrun importer runs under the *user's* JWT, so it is gated too — and passes for the consented users who reach it.

**Prod deploy is gated on CISO / legal sign-off** (privacy-boundary change) per the compliance-sign-off rule — the code lands now, fail-closed, behind that deploy gate. Pinned by `apps/backend/supabase/tests/consent_write_gate_test.sql`.

---

## Sign-up must not be an account-existence oracle (issue #399)

A sign-up form that tells you "that email already has an account" is a **user-enumeration oracle** — anyone can probe whether an address is registered. GoTrue only hides this when **email confirmations are ON**: a duplicate `signUp()` then returns a session-less success that is byte-for-byte identical to a fresh sign-up needing confirmation. With `enable_confirmations = false` a duplicate instead throws `422 user_already_exists`, which classifies as `emailExists` and would otherwise render the distinct "that email already has an account" message.

Whether prod has confirmations on is **dashboard-managed and invisible from the repo**, so the security property must not depend on it. Two independent layers hold it closed:

1. **Code (defence-in-depth, shipped).** The sign-up call site neutralises the reveal in `login/+page.svelte`: on an `emailExists` outcome it shows the **same neutral `login.checkEmail` info banner** a fresh sign-up shows, instead of the distinct error. The decision is the pure `signUpErrorRevealsAccountExistence(kind)` predicate in `core/auth_errors.ts` (unit-tested in `auth_errors.test.ts`; the wiring is pinned by `tests-e2e/auth/login.spec.ts`). **Login is deliberately untouched** — an existing email on the sign-in form classifies as `invalidCredentials`, which is the standard, non-enumerable response. The `emailExists` kind + `login.errorEmailExists` copy still exist for any non-sign-up surface; only the sign-up context is neutralised. **Mobile carries the same defence** (issue #454): `sign_up_screen.dart`'s catch block folds an `emailExists` outcome into the same neutral check-your-email state a fresh confirmation-pending sign-up shows, via the twinned `signUpErrorRevealsAccountExistence(kind)` predicate in `auth_error.dart` (unit-tested in `auth_error_test.dart`, wiring pinned by `sign_up_screen_test.dart`); the iOS twin is byte-identical.
2. **Deploy gate (the real fix — pre-deploy security checklist item).** **Production GoTrue MUST run with `enable_confirmations = true`.** With it off, a confirmed-immediately sign-up also leaks existence through timing/side-channels the neutral banner can't fully mask, and the whole confirmation-redirect + Art 8 consent-gate path above assumes confirmations are on. This is a **pre-deploy gate, verified in the Supabase dashboard**, not a code toggle — see Production setup below.

**Local config stays `enable_confirmations = false` on purpose.** Flipping it locally would break the e2e sign-up flow (`tests-e2e/auth/login.spec.ts` signs a fresh user up through the UI and expects an immediate session → `/onboarding`; that only works when sign-up returns a session with no email-click step) and add a Mailpit round-trip to every local ad-hoc sign-up. The code defence-in-depth makes the enumeration property hold regardless of the toggle, so local dev keeps the frictionless path and prod carries the gate.

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
- **Pre-deploy security gate:** confirm **Authentication → Providers → Email → Confirm email** is **ON** (`enable_confirmations = true`). This closes the sign-up user-enumeration oracle (issue #399, see "Sign-up must not be an account-existence oracle" above). The code neutralises the distinct account-exists message regardless, but the durable fix is confirmations enabled in prod — verify it as part of the release checklist, not just at first setup.

Email confirmations and rate limits are configured in the same dashboard. For the auth-email localization hook + custom SMTP (the sender address), see [email.md § Production ops](email.md).

---

## Pro-tier checks

Tier gating is owned by [paywall.md](paywall.md), not this doc — see it for the tier model, the `is_pro()` RPC, the per-tier coach daily caps, the `features.ts` / `<ProGate>` client gate, and the `BYPASS_PAYWALL` local-dev flag (with its exact `NODE_ENV` + local-Supabase-URL guards — do not copy a looser version of that flag from memory).

The one auth-relevant note: `subscription_tier` is read from `user_profiles` and exposed as `auth.user?.subscription_tier`, and `/api/coach/+server.ts` calls the no-arg `is_pro()` RPC (which gates internally on `auth.uid()`). The earlier `is_user_pro(uuid)` variant was dropped in migration `20260516_001_drop_is_user_pro.sql` because the user-id parameter let any authenticated caller probe another user's tier.

---

*Last updated: April 2026 — rewritten against the current auth store; demo-login mode is gone, identity linking documented.*
