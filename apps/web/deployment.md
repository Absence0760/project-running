# Web app deployment plan

How `apps/web/` (SvelteKit 2 + Svelte 5) ships to production.

Operational counterpart of [`apps/web/CLAUDE.md`](CLAUDE.md) (stack, conventions, file layout) and [`apps/web/local_testing.md`](local_testing.md) (running it locally). For the cross-service overview see [`docs/deployment.md`](../../docs/deployment.md).

**Status: plan.** Today the web app exists as a working dev server only.

---

## Provider — Vercel (canonical), GitHub Pages (fallback)

The web app has two parts:

1. **Static site** — every route except `/api/coach`. SvelteKit prerenders / SPA-renders these. Either provider serves them fine.
2. **Server-side `/api/coach/+server.ts`** — needs a runtime that can stream Anthropic responses back to the client. GitHub Pages can't do this; Vercel can.

So the two-provider story collapses if we just run Vercel for everything. Recommended path: **Vercel as canonical**, with the Pages deploy kept as a free static mirror that also acts as a fallback if Vercel ever has an outage. The SvelteKit Vercel adapter handles the SSR routes; the static adapter handles everything else.

If we never need the Coach endpoint, GitHub Pages alone is enough — but rolling back from "Vercel only" to "Pages only" forfeits Coach. Easier to set up Vercel once and never look back.

**Region:** Vercel auto-picks edges; the Coach SSR route uses Vercel's edge runtime (Node 20 default; switch to `runtime: 'edge'` if cold-start matters more than max payload size). Anthropic API calls go from Vercel's edge directly to `api.anthropic.com`, no proxy.

---

## Domain and routing

| Hostname | Routed to | TTL |
|---|---|---|
| `runonward.app` | Vercel (apex, A → ALIAS) | 300 |
| `www.runonward.app` | Vercel (CNAME → `runonward.app`) | 300 |

Vercel handles certificate provisioning automatically once the domain is verified. The first deploy after wiring DNS issues a Let's Encrypt cert; renews every 60 days without intervention.

**Apex `A` record gotcha**: Cloudflare Registrar lets you `CNAME @`; most other registrars don't allow CNAMEs at the apex. If you're using one that doesn't, set `A` records to Vercel's documented IPs (`76.76.21.21` is the one they advertise; check the dashboard for the current set when wiring).

---

## One-time setup

```bash
# 1. Sign in to Vercel and import the GitHub repo.
# 2. Set Root Directory to "apps/web" in the Vercel project settings.
# 3. Set Framework Preset to "SvelteKit".
# 4. Add the production env vars (next section).
# 5. Trigger the first deploy (Vercel does it automatically on import).
# 6. Wire DNS for runonward.app to point at the Vercel project.
```

Vercel reads `vercel.json` if present; today there isn't one. Add one only if we need to override defaults (custom headers, redirects, regex rewrites). The SvelteKit Vercel adapter handles the build output without configuration.

### Production env vars (Vercel)

Set these in **Project → Settings → Environment Variables**, scoped to "Production" and "Preview":

| Variable | Source | Notes |
|---|---|---|
| `PUBLIC_SUPABASE_URL` | Supabase project | once custom domain is live, use `https://api.runonward.app` |
| `PUBLIC_SUPABASE_ANON_KEY` | Supabase project | the **publishable** key, not service-role |
| `PUBLIC_MAPTILER_KEY` | MapTiler dashboard | shared with mobile + Wear OS |
| `PUBLIC_REVENUECAT_WEB_API_KEY` | RevenueCat dashboard | client-side web SDK key |
| `ANTHROPIC_API_KEY` | Anthropic console | server-only — `/api/coach` reads it |
| `PUBLIC_SENTRY_DSN` | Sentry frontend project | optional — empty disables client-side capture (`hooks.client.ts`) |
| `SENTRY_DSN` | Sentry frontend project | optional — empty disables server-side capture (`hooks.server.ts`); typically the same DSN as `PUBLIC_SENTRY_DSN` |
| `PUBLIC_APP_RELEASE` / `APP_RELEASE` | CI tag (e.g. `web@1.2.3`) | optional — tags Sentry events with the release; defaults to `dev` when unset |
| `BASE_PATH` | `/` for Vercel; `/<repo-name>` for Pages | empty in Vercel; the Pages workflow sets it |

`PUBLIC_*` vars are inlined at build time and shipped to the browser. Anything that should stay server-side (the Anthropic key) must NOT have the `PUBLIC_` prefix.

`COACH_PROVIDER` and `OPENAI_BASE_URL` are optional — set them if pointing the Coach endpoint at a self-hosted Ollama / OpenAI-compatible service instead of Anthropic. Default behaviour without them is Claude.

---

## CI deploy path

Triggered by tagging `web@*`. The workflow at `.github/workflows/release-web.yml`:

1. Checks out the tag.
2. `npm ci` at the workspace root.
3. `npm run check --workspace=apps/web`.
4. `npm run build --workspace=apps/web`.
5. (Pages mirror, if kept) Pushes the build to the `gh-pages` branch.
6. (Vercel) The Vercel GitHub integration auto-deploys on every push to `main`; the tag itself is a "pin this build" marker rather than the trigger.

Vercel's deployment model is automatic: every push to the configured production branch (`main`) triggers a build + deploy. Tagging `web@*` doesn't *trigger* the Vercel deploy; it labels the GitHub Release with whatever Vercel built off the same commit. To deploy a non-`main` build (hotfix, rollback), use Vercel's "Promote" UI on a previous deployment.

If we'd rather have tags drive Vercel deploys explicitly: set up a `release-web.yml` step that calls `npx vercel deploy --prod --token=$VERCEL_TOKEN`. Adds CI control at the cost of duplicating Vercel's built-in trigger.

---

## Coach `/api/coach` specifics

The only SSR route in the app, and the only one that costs money to run.

**Cost model:** Each chat turn is a streaming call to `claude-haiku-4-5` (or Opus per request). At ~3k input tokens + 1k output per turn × ~5k turns/month at launch ≈ $15. The hard ceiling lives in `check_rate_limit_tiered` (default 4/hour for free, 16/hour for pro per [paywall.md](../../docs/paywall.md)) — adjust the limits if Anthropic costs spike.

**Latency.** First-token latency is ~600 ms from Vercel edge → Anthropic. The Vercel function runtime is set to `nodejs20.x` (default) rather than `edge` because the Anthropic SDK's streaming uses Node-only APIs. Switching to `edge` would shave ~150 ms but breaks the SDK.

**Rate limit response.** When the EF returns 429, `apps/web/src/routes/coach/+page.svelte` surfaces a "Daily limit reached, upgrade to Pro for higher limits" toast. Verify this on every deploy that touches the coach surface.

**Self-hosted alternative.** Set `COACH_PROVIDER=openai` + `OPENAI_BASE_URL=http://...` in the Vercel env to point at an Ollama instance. We don't run one in production today, but local dev uses this path against a workstation Ollama for fast iteration.

---

## Push notifications service worker

`apps/web/static/sw.js` registers as the push-notification service worker (decisions §38). Two prerequisites for it to work in production:

1. **HTTPS only.** Vercel handles this.
2. **VAPID keys.** Generated once with `npx web-push generate-vapid-keys`. The public key is checked into `apps/web/src/lib/push.ts`; the private key lives in Supabase EF env (`VAPID_PRIVATE_KEY`) so the EF can sign push messages. Update both halves together if rotated.

The `Notifications` row in the database carries the user's subscription endpoint (in `user_device_settings.prefs.push_subscription`); EF triggers (`notify_run_kudos` etc.) issue HTTP POSTs to those endpoints.

---

## Observability

| Surface | Tool | What |
|---|---|---|
| Request logs | Vercel dashboard → Project → Logs | every request, response code, runtime |
| Build logs | Vercel dashboard → Project → Deployments → <id> | full build output, useful when SvelteKit pre-render trips |
| Web Vitals | Vercel Analytics | LCP, CLS, INP, page views |
| Client errors | Sentry (frontend project) | bundled via `@sentry/sveltekit`, source-mapped |
| Coach usage | Anthropic console | per-key spend, request rate, model mix |

**Alerts to wire:**

- Vercel "Deployment Failed" → email
- Sentry: any new error class with >10 events in 5 min
- Better Stack probe of `https://runonward.app/` returning non-200 for >2 min
- Anthropic cost above $X/day (Console → Usage → Alerts)

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| Vercel | Hobby (free) covers static + 100 GB bandwidth + 100 GB-hours compute | $0 |
| Vercel Pro | needed if we exceed the Hobby limits or want password protection on previews | $20 |
| Anthropic API | Coach usage at launch | ~$15 |
| Sentry | Free tier (50k errors/month) | $0 |
| Vercel Analytics | included on Pro; $10/mo on Hobby for the web-vitals add-on | $0 → $10 |
| **Subtotal — launch** | | **$15–35** |

Bandwidth is the variable that tips us off Hobby. 1k users × 5 sessions/month × ~300 KB each ≈ 1.5 GB — far below. Once we're past 100 GB/month (≈ 50k–100k sessions depending on cache hit rate), Pro becomes mandatory.

---

## Rollback

Vercel's UI: Project → Deployments → pick a previous green deployment → "Promote to Production". Takes <30 s.

Equivalent CLI:

```bash
npx vercel ls --token=$VERCEL_TOKEN
npx vercel promote <deployment-url> --token=$VERCEL_TOKEN
```

The Vercel rollback doesn't revert the GitHub commit. To make `main` reflect the rollback (so the next push doesn't re-deploy the broken version), tag a revert commit and let Vercel pick it up.

**Database-coupled rollback.** If a web release relied on a backend migration, rolling back the web deploy without rolling back the schema is fine (newer schema is read-compatible). The reverse — rolling back the schema while leaving the new web deploy serving — is what causes 500s. Always roll forward on the backend, even if the symptom looks like a backend issue.

---

## GitHub Pages mirror (optional)

Today's `release-web.yml` deploys to Pages. Keeping that flow gives:

- Zero-cost static hosting at `<github-org>.github.io/<repo>/`
- A second URL to point at if Vercel is having a bad day

Cost of keeping it: a `BASE_PATH` env var threaded through every `<a>`, `<img>`, and `import.meta.env.BASE_URL` consumer (already done in the existing build). The Pages build can't run `/api/coach`, so a Pages-only deploy hides the coach UI by feature-flagging it off.

If the maintenance is cheaper than the optionality, retire it. The decision can be made post-launch — neither path closes the other off.

---

## Disaster recovery

Vercel is stateless from our side — the build is reproducible from any tagged commit, and the deployment artifact is downloadable from the dashboard for ~30 days. There's nothing to back up that isn't in git.

The dependent services that *do* hold state (Supabase, RevenueCat, Anthropic) have their own DR stories. The web app simply needs:

1. The repo at the desired tag.
2. The production env vars in Vercel (or replicated to a fresh Vercel project on the same domain).
3. DNS pointing at Vercel.

If the Vercel account itself is lost, recovery is roughly:

- Spin up a new Vercel account or migrate to Cloudflare Pages / Netlify (both serve SvelteKit-static fine; Coach SSR migrates to Cloudflare Workers with the `@sveltejs/adapter-cloudflare`).
- Reimport the repo, set env vars from 1Password, redeploy.
- Update DNS.

RTO: ~1 hour from a cold-start of a new account if the domain is at a registrar we control. RPO: 0 — there's no data on Vercel.

---

## Production readiness checklist

- [ ] Vercel project imported, root dir `apps/web`, framework SvelteKit
- [ ] Production env vars set (Supabase URL + anon, MapTiler, RevenueCat, Anthropic, optional Coach overrides)
- [ ] `runonward.app` and `www.runonward.app` verified in Vercel
- [ ] DNS records resolve worldwide (use `dig +short runonward.app @1.1.1.1` from a few networks)
- [ ] HTTPS cert issued (visible in Vercel project → Domains)
- [ ] First deploy green; smoke test sign-in + dashboard + run detail
- [ ] Coach endpoint responds (try a free user → expect a successful streamed reply)
- [ ] Push notification flow verified end-to-end (subscribe in Settings, trigger via a kudos on another account)
- [ ] Sentry frontend project receiving events
- [ ] Vercel Analytics live
- [ ] Better Stack probe configured
- [ ] Anthropic cost alert set
- [ ] Rollback drill: roll back to a previous deployment, confirm the site behaves, roll forward
