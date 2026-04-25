# Review: apps/web/src/routes/

Web routes audit — static-adapter compatibility, auth/route protection, code↔docs drift, bugs, feature drift vs Android, paywall consistency, dead routes.

## Scope
- Files reviewed: 44 route files + supporting lib files (`auth.svelte.ts`, `features.ts`, `supabase.ts`, `svelte.config.js`)
- Focus: static-adapter compatibility, auth, docs drift, bugs, web↔android drift, paywall, dead routes
- Reviewer confidence: high — every route file was read in full; cross-referenced against all named docs

---

## Priority: high

### H1. `flows.md` documents a demo-login path that does not exist
- **File(s)**: `docs/flows.md:24-50`
- **Category**: bug (doc lie about a real flow)
- **Problem**: `flows.md` § "Sign in — web" describes a "Demo login" path (`auth.demoLogin(email)`) that bypasses OAuth and creates a mock session. That method does not exist in `auth.svelte.ts`, is not called from `login/+page.svelte`, and there is no such flow in the codebase. `web_app_auth.md` explicitly contradicts it ("There is no demo / mock login"). Any engineer reading `flows.md` first will implement dead integration tests against a fictitious entry-point.
- **Evidence**:
  ```
  // docs/flows.md:24
  1. **Demo login** (local dev + preview deploys): bypasses OAuth, creates a mock session in
     `localStorage`, no Supabase round-trip. Entry point:
     `src/routes/login/+page.svelte` → `auth.demoLogin(email)`.

  // docs/flows.md:50
  - The demo login path does not produce a Supabase JWT, so any code that calls an Edge
    Function or a REST endpoint with `Authorization: Bearer <token>` will fail under demo login.
  ```
  `auth.svelte.ts` exports no `demoLogin` method; `login/+page.svelte` contains no call to it.
- **Proposed change**:
  ```diff
  - 1. **Demo login** (local dev + preview deploys): bypasses OAuth, creates a mock session in
  -    `localStorage`, no Supabase round-trip. Entry point:
  -    `src/routes/login/+page.svelte` → `auth.demoLogin(email)`.
  - 2. **Supabase Auth** (production): ...
  + 1. **Supabase Auth**: ...
  ```
  Delete the entire "Demo login" bullet and the "Watch out" note that discusses it (lines 46-50).
- **Risk if applied**: none — the described path doesn't exist so nothing can break.
- **Verification**: `grep -r "demoLogin" apps/web/src/` should return no matches after removal.

---

### H2. Run detail page renders randomised fake splits on every render
- **File(s)**: `apps/web/src/routes/runs/[id]/+page.svelte:468-480`
- **Category**: bug
- **Problem**: The `splits` derived store uses `Math.random()` for both per-km pace variance and elevation. Every reactive re-evaluation (e.g. after editing the title, toggling a segment card) produces different values for the splits table. The splits also bear no relation to the actual GPS track — even when a real track is present, the km-by-km pace is invented. Android computes real splits from the GPS track timestamps (`run_detail_screen.dart:1048-1082`).
- **Evidence**:
  ```typescript
  let splits = $derived.by(() => {
      ...
      return Array.from({ length: numSplits }, (_, i) => {
          const variance = (Math.random() - 0.5) * 20;   // invented pace delta
          const splitPace = avgPaceSec + variance;
          const elevation = Math.round((Math.random() - 0.3) * 15); // invented elevation
          return { km: i + 1, pace_s: Math.round(splitPace), distance_m: splitDistance, elevation_m: elevation };
      });
  });
  ```
- **Proposed change**: Replace with a GPS-based computation using the run's `track` array:
  ```diff
  - let splits = $derived.by(() => {
  -     ...uses Math.random()...
  - });
  + let splits = $derived(run?.track ? computeRealSplits(run.track, run.distance_m) : []);
  ```
  `computeRealSplits` walks `track` cumulative distance, records the timestamp at each km boundary, and derives per-km pace from `(ts_at_km_end - ts_at_km_start) / 60`. When track has no per-point `ts`, return `[]` and hide the section rather than showing fabricated data. The elevation per split follows the same boundary slice.
- **Risk if applied**: Runs without a track (manual entries, some imports) will show an empty splits section instead of invented numbers. That is the correct behaviour.
- **Verification**: Open a run recorded from Android (which has a real track with timestamps). Splits table values should stay constant across tab switches and title edits.

---

### H3. Dashboard "This Week" uses Sunday-start; rest of app uses Monday-start
- **File(s)**: `apps/web/src/routes/dashboard/+page.svelte:185-192`
- **Category**: bug
- **Problem**: The dashboard computes `weekStart` using `now.getDate() - now.getDay()`, where `getDay()` returns 0 for Sunday — so the week always starts on Sunday. `docs/settings.md:50` declares a `week_start_day` universal setting defaulting to `'monday'`. `runs/+page.svelte:46-49` explicitly comments "Monday-start week, matching Android's `weekStartLocal`". The mismatch means a Monday run can appear in "This Week" on the Runs page but not on the Dashboard stats card, and the week boundary jumps a day depending on which surface you look at.
- **Evidence**:
  ```typescript
  // dashboard/+page.svelte:185-187
  const weekStart = new Date(now);
  weekStart.setDate(now.getDate() - now.getDay()); // Sunday = 0 → Sunday-start
  weekStart.setHours(0, 0, 0, 0);

  // runs/+page.svelte:46-49 — correct Monday-start
  const dow = (d.getDay() + 6) % 7; // 0 = Mon
  d.setDate(d.getDate() - dow);
  ```
- **Proposed change**:
  ```diff
  - weekStart.setDate(now.getDate() - now.getDay());
  + const dowMon = (now.getDay() + 6) % 7; // 0 = Mon, matching Android + Runs page
  + weekStart.setDate(now.getDate() - dowMon);
  ```
  Long-term, read the user's `week_start_day` setting and branch on `'sunday'` vs `'monday'` (same pattern as `runs/+page.svelte`).
- **Risk if applied**: Users in Sunday-default locales see the "This Week" distance drop on Sunday morning instead of Monday morning. Correct per the declared universal default.
- **Verification**: On a Sunday, check that the Dashboard "This Week" stat matches the Runs page "This week" filter count.

---

### H4. `training.md` documents wrong token budget for coach
- **File(s)**: `docs/training.md:29`
- **Category**: bug (doc lie about a real flow)
- **Problem**: `training.md` states "Model: `claude-sonnet-4-5`, 1024 output tokens". The actual `TIER_LIMITS` in `api/coach/+server.ts` are `free: { maxTokens: 768 }` and `pro: { maxTokens: 2048 }`. The 1024 figure was the pre-tier single limit and is now wrong for both tiers. Anyone using this doc to estimate response quality or latency for either tier gets the wrong number.
- **Evidence**:
  ```typescript
  // api/coach/+server.ts:59-62
  const TIER_LIMITS = {
      free: { dailyLimit: 10, maxTokens: 768, maxRunsLimit: 30 },
      pro:  { dailyLimit: Number.POSITIVE_INFINITY, maxTokens: 2048, maxRunsLimit: 200 },
  };
  ```
  ```
  // docs/training.md:29
  - Model: `claude-sonnet-4-5`, 1024 output tokens.
  ```
- **Proposed change**:
  ```diff
  - Model: `claude-sonnet-4-5`, 1024 output tokens.
  + Model: `claude-sonnet-4-5`. Output tokens: 768 (free tier) / 2048 (Pro tier). Context window: 30 runs (free) / 200 runs (Pro).
  ```
- **Risk if applied**: none.
- **Verification**: Values match `TIER_LIMITS` in `api/coach/+server.ts:59-62`.

---

## Priority: medium

### M1. `/auth/callback` misleading comment about hash vs query string
- **File(s)**: `apps/web/src/routes/auth/callback/+page.svelte:10-12`
- **Category**: bug
- **Problem**: The comment says "Supabase redirects here with auth code in the URL hash" but the code reads `window.location.search.substring(1)` — the query string, not the hash. `createBrowserClient` from `@supabase/ssr` defaults to PKCE flow which delivers the `code` in the query string (`?code=…`). The comment is wrong; the code is correct. However, if a future developer changes `window.location.search` to `window.location.hash` based on the comment, OAuth will silently break.
- **Evidence**:
  ```typescript
  // auth/callback/+page.svelte:10-12
  // Supabase redirects here with auth code in the URL hash
  const { error: authError } = await supabase.auth.exchangeCodeForSession(
      window.location.search.substring(1)   // actually query string, not hash
  );
  ```
- **Proposed change**:
  ```diff
  - // Supabase redirects here with auth code in the URL hash
  + // Supabase PKCE flow: auth code arrives in the query string (?code=…), not the hash.
  ```
- **Risk if applied**: none.
- **Verification**: OAuth sign-in continues to succeed after the comment change.

---

### M2. `settings/account/+page.svelte` swallows save errors silently
- **File(s)**: `apps/web/src/routes/settings/account/+page.svelte:146-176`
- **Category**: bug (missing error handling)
- **Problem**: `handleSave` awaits both the `user_profiles` update and the `user_settings` upsert without checking the returned `error` from either call. If either fails (RLS violation, network error, schema mismatch), `saved = true` is still set and "Saved!" is shown to the user. The user believes their profile was persisted when it wasn't.
- **Evidence**:
  ```typescript
  async function handleSave() {
      ...
      await supabase.from('user_profiles').update({   // error never checked
          display_name: displayName || null,
          parkrun_number: parkrunNumber || null,
      }).eq('id', auth.user.id);
      ...
      saved = true;   // shown regardless of whether DB write succeeded
  ```
- **Proposed change**:
  ```diff
  - await supabase.from('user_profiles').update({
  -     display_name: displayName || null,
  -     parkrun_number: parkrunNumber || null,
  - }).eq('id', auth.user.id);
  + const { error: profileError } = await supabase.from('user_profiles').update({
  +     display_name: displayName || null,
  +     parkrun_number: parkrunNumber || null,
  + }).eq('id', auth.user.id);
  + if (profileError) { showToast(`Save failed: ${profileError.message}`, 'error'); saving = false; return; }
  ```
  Apply the same pattern to the `user_settings` upsert below it.
- **Risk if applied**: Users who were silently failing now see error toasts. No data-loss risk.
- **Verification**: Temporarily break RLS on `user_profiles` for the test user; clicking "Save Profile" should now show an error toast instead of "Saved!".

---

### M3. `flows.md` documents `supabase-server.ts` SSR client that doesn't exist in this codebase
- **File(s)**: `docs/flows.md:49`
- **Category**: inconsistency (doc drift)
- **Problem**: `flows.md` states "Watch out: `apps/web/src/lib/supabase.ts` is the browser client. `supabase-server.ts` is the SSR client." There is no `supabase-server.ts` in the repo. The web app is adapter-static; there is no SSR client. This note also warns about cookies bridging them, which is irrelevant for a static SPA.
- **Evidence**:
  ```
  // docs/flows.md:49-50
  - `apps/web/src/lib/supabase.ts` is the browser client. `supabase-server.ts` is the SSR client.
    They do not share a session object — cookies bridge them.
  ```
  `find apps/web/src/lib -name "supabase*.ts"` returns only `supabase.ts`.
- **Proposed change**: Replace the "Watch out" bullet with the actual architecture:
  ```diff
  - - `apps/web/src/lib/supabase.ts` is the browser client. `supabase-server.ts` is the SSR
  -   client. They do not share a session object — cookies bridge them.
  + - `apps/web/src/lib/supabase.ts` is the only Supabase client. It is a browser-side client
  +   (`createBrowserClient` from `@supabase/ssr`). There is no SSR client; the app is fully
  +   static (`adapter-static` with `fallback: index.html`). The JWT lives in `localStorage`.
  ```
- **Risk if applied**: none.
- **Verification**: `find apps/web/src/lib -name "supabase*.ts"` confirms there is exactly one file.

---

### M4. `/clubs/join/[token]` `return_to` redirect after login is never honoured
- **File(s)**: `apps/web/src/routes/clubs/join/[token]/+page.svelte:36`, `apps/web/src/routes/login/+page.svelte:14-16`
- **Category**: bug
- **Problem**: When an unauthenticated user lands on a club invite link, the page redirects them to `/login?return_to=%2Fclubs%2Fjoin%2F<token>`. The login page ignores this parameter entirely — after successful sign-in it always goes to `/dashboard`. The invite token is lost and the user has to find the link again.
- **Evidence**:
  ```svelte
  <!-- clubs/join/[token]/+page.svelte:35-37 -->
  <a href="/login?return_to={encodeURIComponent($page.url.pathname)}" class="btn-primary">
      Sign in
  </a>
  ```
  ```typescript
  // login/+page.svelte:14-16 — return_to is never read
  $effect(() => {
      if (browser && !auth.loading && auth.loggedIn) {
          goto('/dashboard', { replaceState: true }); // always /dashboard
      }
  });
  ```
- **Proposed change**: In `login/+page.svelte`, read `return_to` and redirect there after login:
  ```diff
  - goto('/dashboard', { replaceState: true });
  + const returnTo = $page.url.searchParams.get('return_to');
  + goto(returnTo ?? '/dashboard', { replaceState: true });
  ```
  Apply the same change in `handleEmailSubmit`'s `goto` call.
- **Risk if applied**: If `return_to` is user-supplied it could be an open redirect. Validate against `window.location.origin` before redirecting: `returnTo && returnTo.startsWith('/') ? returnTo : '/dashboard'`.
- **Verification**: Click a club invite link while logged out; after signing in, you should land back on the `/clubs/join/[token]` page, not `/dashboard`.

---

### M5. Run detail Splits section shows fabricated elevation (feature drift vs Android)
- **File(s)**: `apps/web/src/routes/runs/[id]/+page.svelte:477`
- **Category**: inconsistency (web vs Android)
- **Problem**: This is the elevation-specific sub-issue of H2. Even for runs that do have a GPS track with per-point elevation, the splits table's elevation column is fully random. Android's `run_detail_screen.dart:1048-1082` computes real per-km elevation gain/loss from the GPS track. The web shows a plausible-looking but invented column that contradicts the elevation gain shown in the key stats above it (which is real, computed by `elevationGainMetres`).
- **Evidence**:
  ```typescript
  const elevation = Math.round((Math.random() - 0.3) * 15); // line 477 — invented
  ```
  Key stats on the same page (line 317): `let realElevationGain = $derived(run?.track ? elevationGainMetres(run.track) : 0)` — this one is real.
- **Proposed change**: Compute per-km elevation gain/loss from the GPS track slice between km boundaries (same data walk as the pace computation proposed in H2). When track has no elevation data, omit the elevation column from the table header and rows.
- **Risk if applied**: Runs without elevation data on track points show the Elev column header disappearing — correct.
- **Verification**: Import a GPX from an elevation-rich route and verify the splits elevation column sum approximates the key stats "Elevation" value.

---

### M6. Coach endpoint accepts JWT in request body instead of Authorization header
- **File(s)**: `apps/web/src/routes/api/coach/+server.ts:49`, `apps/web/src/lib/components/CoachChat.svelte:202`
- **Category**: inconsistency
- **Problem**: The JWT is sent inside the JSON body (`access_token: token`) rather than as an `Authorization: Bearer` header. This is non-standard. Proxies and CDN logging configurations that strip bearer headers won't affect this, but some WAF rules that log or redact request bodies may capture the raw token. The more standard pattern is the Authorization header; the endpoint already demonstrates it knows the pattern (it uses `Authorization: Bearer` when constructing the Supabase client on line 104).
- **Evidence**:
  ```typescript
  // CoachChat.svelte:195-203
  const res = await fetch('/api/coach', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
          messages, plan_id: planId, recent_runs_limit: runsLimit,
          access_token: token   // JWT in body
      })
  });
  ```
- **Proposed change**: Move the token to an `Authorization` header and remove it from the body:
  ```diff
  - headers: { 'content-type': 'application/json' },
  - body: JSON.stringify({ messages, plan_id: planId, recent_runs_limit: runsLimit, access_token: token })
  + headers: { 'content-type': 'application/json', 'Authorization': `Bearer ${token}` },
  + body: JSON.stringify({ messages, plan_id: planId, recent_runs_limit: runsLimit })
  ```
  In `+server.ts`, extract the token from `request.headers.get('authorization')?.replace('Bearer ', '')` and remove `access_token` from `CoachRequest`.
- **Risk if applied**: Old clients (e.g. cached tabs) sending the body field get a 401 until they refresh. Rolling this change requires both sides to change together.
- **Verification**: After change, send a request with only the header; the endpoint should respond with a valid coach reply.

---

### M7. `legal/licenses` route is unreferenced dead code
- **File(s)**: `apps/web/src/routes/legal/licenses/+page.svelte`
- **Category**: dead-code
- **Problem**: There are two routes that render `<LicenseList />`: `/legal/licenses` and `/settings/licenses`. No file in `apps/web/src/` links to or references `/legal/licenses`. It is unreachable from any navigation surface. The settings tab at `/settings/licenses` is the linked-from version.
- **Evidence**:
  ```
  apps/web/src/routes/legal/licenses/+page.svelte  — identical single-line: <LicenseList />
  apps/web/src/routes/settings/licenses/+page.svelte — identical
  ```
  `grep -r "/legal" apps/web/src/` returns no results.
- **Proposed change**: Delete `apps/web/src/routes/legal/licenses/+page.svelte` and its parent `legal/` directory.
- **Risk if applied**: Any external links that pointed to `/legal/licenses` (e.g. from an older share of the settings URL) will 404. Given it's not in any internal nav, the audience is negligible.
- **Verification**: After deletion, `pnpm build` completes without reference errors.

---

## Priority: low

### L1. `auth/callback/+page.svelte` does not handle the case where `goto('/dashboard')` runs before `auth.refreshSession()` completes hydrating the user
- **File(s)**: `apps/web/src/routes/auth/callback/+page.svelte:20-21`
- **Category**: bug (low severity — recoverable)
- **Problem**: After `exchangeCodeForSession` succeeds, `auth.refreshSession()` is awaited, which calls `supabase.auth.getSession()` and then **does not await** `fetchUser` (it's explicitly fire-and-forget, line 43 in `auth.svelte.ts`). So `goto('/dashboard')` can run while `auth.user` is still null (profile not yet hydrated). The dashboard mounts, `auth.user?.id` is null, the settings load is skipped, and units default to km. On subsequent ticks `onAuthStateChange` fires, `fetchUser` completes, and the page re-renders correctly. For most users this is invisible, but the VO2max settings load and goal load each check `auth.user?.id` and silently no-op on that first tick.
- **Evidence**:
  ```typescript
  // auth.svelte.ts:40-43
  async function refreshSession() {
      const { data: { session } } = await supabase.auth.getSession();
      if (session) {
          loggedIn = true;
          loading = false;
          fetchUser(session.user.id, session.user.email ?? '').catch(console.error); // not awaited
  ```
- **Proposed change**: Await `fetchUser` inside `refreshSession` before resolving:
  ```diff
  - fetchUser(session.user.id, session.user.email ?? '').catch(console.error);
  + await fetchUser(session.user.id, session.user.email ?? '');
  ```
  This makes the callback's `goto('/dashboard')` run after the user profile is loaded. The trade-off is a slightly longer callback page flash. The existing non-awaited path was chosen for perf; comment should explain the known side-effect.
- **Risk if applied**: Callback page visible ~50-200ms longer (one DB round trip). No functional regression.
- **Verification**: On a fresh OAuth sign-in, open the Network tab; the `/dashboard` page should load with `auth.user` already populated (no second render with unit preference changing).

---

### L2. Calorie estimate on run detail is hardcoded to 70 kg body weight
- **File(s)**: `apps/web/src/routes/runs/[id]/+page.svelte:75`
- **Category**: inconsistency (web vs Android)
- **Problem**: `estimatedCalories = Math.round(70 * 1.0 * run.distance_m / 1000)` uses a hardcoded 70 kg and a MET factor of 1.0 (effectively just a unit conversion). Android's run detail screen uses actual body weight from the user's profile and a proper `~1 kcal/kg/km` formula. The web always shows "as if 70 kg" regardless of user weight, silently wrong for every non-70-kg runner.
- **Evidence**:
  ```typescript
  // runs/[id]/+page.svelte:75
  let estimatedCalories = $derived(run ? Math.round(70 * 1.0 * run.distance_m / 1000) : 0);
  ```
- **Proposed change**: Read `body_weight_kg` from the `user_settings.prefs` bag (already loaded on this page via the settings import in `onMount`) and use it in the formula. If absent, omit the Calories stat tile entirely rather than showing a wrong number.
  ```diff
  - let estimatedCalories = $derived(run ? Math.round(70 * 1.0 * run.distance_m / 1000) : 0);
  + let bodyWeightKg = $state<number | null>(null); // set from prefs in onMount
  + let estimatedCalories = $derived(run && bodyWeightKg ? Math.round(bodyWeightKg * run.distance_m / 1000) : 0);
  ```
- **Risk if applied**: Users who previously saw a "calories" number see it disappear until they set body weight in settings. Add a tooltip or settings nudge to the empty state.
- **Verification**: Set body weight in Settings. Open a run. Calories tile should change to reflect actual weight.

---

### L3. `explore` route is not in the sidebar `navItems`
- **File(s)**: `apps/web/src/routes/+layout.svelte:38-46`
- **Category**: inconsistency
- **Problem**: `/explore` is a real route (public route discovery) referenced from `routes/+page.svelte` as a button and from `routes/[id]/+page.svelte` for back-nav. It is not listed in the sidebar `navItems` array, so there is no keyboard-accessible or visible top-level navigation entry for it. Users who don't know about the Routes page button can't discover it. `docs/web_app_auth.md` and the app CLAUDE.md both list it as a real feature.
- **Evidence**: `navItems` in `+layout.svelte:38-46` lists: dashboard, runs, routes, plans, coach, clubs, settings. No explore entry.
- **Proposed change**: This may be intentional (explore is a sub-feature of Routes). If it should remain accessible only from the Routes page, document that explicitly. If it should be top-level, add:
  ```diff
  + { href: '/explore', label: 'Explore', icon: 'explore', accent: '#7FB3C2' },
  ```
  between routes and plans. If deliberately omitted, add a comment next to `navItems`.
- **Risk if applied**: Adding it to the nav is a product decision, not a mechanical code change. The implementer should confirm intent before adding.
- **Verification**: N/A — requires product decision.

---

### L4. Dashboard "This Week" stat card uses Sunday-start for the "week" label but the `weeklyMileage` fetch data uses the server's ISO week logic
- **File(s)**: `apps/web/src/routes/dashboard/+page.svelte:192`, `apps/web/src/lib/data.ts` (referenced)
- **Category**: inconsistency
- **Problem**: This is a secondary note to H3. The "This Week" stat card (`thisWeekDistance`) is computed client-side from `filteredRuns` using a Sunday-start cutoff. The mileage chart's "weekly" view uses `weeklyMileage` which is fetched from `fetchWeeklyMileage()` — a server-side SQL aggregation that almost certainly uses ISO weeks (Monday-start). A user sees one total in the stat card and a different bar height for "this week" in the chart. Only fixable once H3 is resolved; note it here so the implementer tests the chart consistency too.
- **Evidence**: Dashboard line 192 vs `fetchWeeklyMileage()` in `data.ts` (SQL-driven, ISO weeks).
- **Proposed change**: After fixing H3, verify the chart's last bar and the stat card value match for the current week on a Monday.
- **Risk if applied**: None — verification only.
- **Verification**: On a Wednesday, check that "This Week" stat == height of the most-recent bar in the Mileage chart.

---

### L5. `/settings/+page.ts` uses `307 Temporary Redirect` — should be `301`
- **File(s)**: `apps/web/src/routes/settings/+page.ts:9`
- **Category**: inconsistency
- **Problem**: The settings index redirects to `/settings/account` with a `307`. With `adapter-static`, this generates a static redirect entry. Since `/settings` will never have its own content, a `301 Permanent Redirect` is more appropriate and better for browser cache/prefetch.
- **Evidence**:
  ```typescript
  throw redirect(307, '/settings/account');
  ```
- **Proposed change**:
  ```diff
  - throw redirect(307, '/settings/account');
  + throw redirect(301, '/settings/account');
  ```
- **Risk if applied**: Browsers that have cached the 307 will re-check on every navigation; browsers that cache the 301 will not. Minimal UX impact.
- **Verification**: After build, the generated redirect serves `301`.

---

## Counts
H: 4  M: 4  L: 5
