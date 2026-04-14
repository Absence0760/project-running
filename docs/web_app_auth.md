# Web app — authentication

How authentication works in the SvelteKit web app, how to test it locally, and how to wire it up to Supabase for production.

---

## Overview

The web app uses a **client-side auth store** built with Svelte 5 runes. The store manages login state, user data, and token persistence via `localStorage`. Route protection is handled in the root layout with `$effect` redirects — the same pattern used in `project-account-payables-dev`.

For local testing, a **demo login** bypasses OAuth and creates a mock session. In production, login goes through **Supabase Auth** with Google and Apple OAuth providers.

---

## Architecture

```
User visits /dashboard (protected)
  → +layout.svelte $effect fires
  → auth.loggedIn is false
  → goto('/login')

User clicks "Demo Login" (or Google/Apple in production)
  → auth.demoLogin(email) / auth.signInWithGoogle()
  → Token stored in localStorage
  → auth.loggedIn becomes true
  → goto('/dashboard')
  → +layout.svelte renders sidebar + main content
  → $effect fetches user profile if missing
```

---

## Key files

| File | Purpose |
|---|---|
| `src/lib/stores/auth.svelte.ts` | Auth state store (login, logout, user data, reactive getters) |
| `src/routes/+layout.svelte` | Route protection via `$effect`, sidebar with user info |
| `src/routes/login/+page.svelte` | Login page (OAuth buttons + demo login) |
| `src/lib/supabase.ts` | Browser-side Supabase client (for production) |
| `src/lib/supabase-server.ts` | Server-side Supabase client (for production) |

---

## Auth store

**Location:** `src/lib/stores/auth.svelte.ts`

The store is a Svelte 5 runes reactive object. Import it anywhere:

```typescript
import { auth } from '$lib/stores/auth.svelte';
```

### Reactive getters

| Property | Type | Description |
|---|---|---|
| `auth.user` | `User \| null` | Current user profile (null if not loaded) |
| `auth.loggedIn` | `boolean` | Whether a session exists (token in localStorage) |
| `auth.loading` | `boolean` | True during login/fetch operations |
| `auth.isPremium` | `boolean` | Whether the user has a premium subscription |

### User shape

```typescript
interface User {
  id: string;
  email: string;
  display_name: string | null;
  avatar_url: string | null;
  parkrun_number: string | null;
  preferred_unit: 'km' | 'mi';
  subscription_tier: 'free' | 'premium';
}
```

### Methods

| Method | Description |
|---|---|
| `auth.signInWithGoogle()` | Start Google OAuth flow via Supabase (production) |
| `auth.signInWithApple()` | Start Apple OAuth flow via Supabase (production) |
| `auth.demoLogin(email)` | Local testing login — creates a mock session with no backend |
| `auth.fetchUser()` | Load user profile from Supabase (or mock data in demo mode) |
| `auth.logout()` | Clear token, reset state, redirect to `/login` |

---

## Route protection

**Location:** `src/routes/+layout.svelte`

The root layout uses two `$effect` blocks for auth:

```typescript
// Redirect to /login if not authenticated on protected routes
$effect(() => {
  if (browser && !auth.loggedIn && !publicPaths.includes($page.url.pathname)) {
    goto('/login');
  }
});

// Fetch user data if logged in but user object is missing
$effect(() => {
  if (browser && auth.loggedIn && !auth.user) {
    auth.fetchUser();
  }
});
```

### Public vs protected routes

| Route | Access |
|---|---|
| `/` | Public — landing page |
| `/login` | Public — login page |
| `/dashboard` | Protected — requires auth |
| `/runs` | Protected — requires auth |
| `/runs/[id]` | Protected — requires auth |
| `/routes` | Protected — requires auth |
| `/routes/new` | Protected — requires auth |
| `/routes/[id]` | Protected — requires auth |
| `/settings/*` | Protected — requires auth |

Public routes render without the sidebar. Protected routes render inside the app shell (sidebar + main content area).

---

## Login page

**Location:** `src/routes/login/+page.svelte`

Three login methods:

1. **Continue with Google** — calls `auth.signInWithGoogle()` (Supabase OAuth)
2. **Continue with Apple** — calls `auth.signInWithApple()` (Supabase OAuth)
3. **Demo Login** — calls `auth.demoLogin(email)` for local testing without a backend

On success, all three redirect to `/dashboard`.

The demo login section is intended for development only and should be removed or hidden behind an environment flag before production deployment.

---

## Session persistence

Sessions are stored in `localStorage` under the key `auth_token`.

- On login, the token is written to `localStorage`
- On page load, the store checks for an existing token and sets `auth.loggedIn = true`
- On logout, the token is removed from `localStorage`
- If the backend returns 401 (token expired/revoked), the token is cleared and the user is redirected to `/login`

---

## Local testing

No backend or Supabase instance is needed for local testing.

### Steps

```bash
cd apps/web
pnpm install
pnpm dev
# Opens at http://localhost:7777
```

1. Visit `http://localhost:7777` — you'll see the landing page
2. Click **Open Dashboard** or any nav link — you'll be redirected to `/login`
3. In the **Local testing** section, enter any email and click **Demo Login**
4. You're now authenticated with mock data — sidebar shows your name, all pages are accessible
5. Click **Sign Out** in the sidebar footer to log out

### Demo login behaviour

- Creates a mock session with a fake token
- Loads a hardcoded user profile (name: "Jared Howard", unit: km, tier: free)
- All pages display mock run/route data — no backend calls are made
- Token persists across page refreshes (stored in localStorage)

---

## Production setup (Supabase Auth)

When the Supabase backend is running, replace the mock implementations in `auth.svelte.ts`:

### 1. Wire up OAuth methods

```typescript
import { supabase } from '$lib/supabase';

async function signInWithGoogle() {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: `${window.location.origin}/dashboard` },
  });
  if (error) throw error;
}

async function signInWithApple() {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'apple',
    options: { redirectTo: `${window.location.origin}/dashboard` },
  });
  if (error) throw error;
}
```

### 2. Wire up user profile fetch

```typescript
async function fetchUser() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return;

  const { data } = await supabase
    .from('user_profiles')
    .select('*')
    .eq('id', session.user.id)
    .single();

  user = data;
}
```

### 3. Wire up logout

```typescript
async function logout() {
  await supabase.auth.signOut();
  user = null;
  loggedIn = false;
}
```

### 4. Listen to auth state changes

Add a Supabase auth listener in the store to handle token refresh and session expiry:

```typescript
if (browser) {
  supabase.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_IN' && session) {
      loggedIn = true;
      fetchUser();
    }
    if (event === 'SIGNED_OUT') {
      user = null;
      loggedIn = false;
    }
  });
}
```

### 5. Environment variables

Set these in `.env.local`:

```bash
PUBLIC_SUPABASE_URL=https://xxx.supabase.co
PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

### 6. Remove demo login

Remove or gate the `demoLogin` method and the demo section in the login page behind a `DEV` environment check before deploying to production.

---

## Sidebar user display

When authenticated, the sidebar footer shows:

- **Avatar** — first letter of the user's display name in a coloured circle
- **Name** — `auth.user.display_name` (falls back to email)
- **Email** — `auth.user.email`
- **Sign Out** button — calls `auth.logout()` and redirects to `/login`

---

## Adding role-based access

The current implementation doesn't have roles (all authenticated users see the same UI). To add role-based visibility later, follow the same pattern as `project-account-payables-dev`:

```typescript
// In auth.svelte.ts — add role helpers
function hasRole(role: string): boolean {
  return user?.roles?.includes(role) ?? false;
}

// In components — conditionally render
{#if auth.hasRole('premium')}
  <PremiumFeature />
{/if}
```

---

*Last updated: April 2026*
