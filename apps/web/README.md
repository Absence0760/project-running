# apps/web

The web app — **canonical feature surface for the whole product** ([decisions.md § 24](../../docs/architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)). Every user-facing feature lives here unless it is physically impossible in a browser (live GPS recording, device sensors, haptics, OS share sheets).

Stack: SvelteKit 2 + Svelte 5 (runes), TypeScript, `@sveltejs/adapter-static`, normalize.css + `src/app.css`. The `/api/coach` route doubles as the body of a hand-rolled Node 24 Lambda handler under [`lambda/coach/`](lambda/coach/).

Deployed to AWS — S3 (static build) + CloudFront + Route 53 for the bulk, with the coach Lambda routed via a separate CloudFront behaviour. Terraform-provisioned, sops + AWS KMS for runtime secrets, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the rationale and [deployment.md](deployment.md) for the full plan.

## Run locally

```bash
# From the repo root (matches CI):
npm install                              # workspace bootstrap
npm run dev --workspace=apps/web         # dev server on :7777
npm run build --workspace=apps/web       # production build
npm run preview --workspace=apps/web     # preview build on :8888
npm run check --workspace=apps/web       # type-check
```

`pnpm i / pnpm dev` from inside `apps/web/` also works locally because of the historical `pnpm-lock.yaml`, but CI runs the npm path.

## See also

- [CLAUDE.md](CLAUDE.md) — full session notes: folder structure, create-flow modal pattern, conventions, PR guidelines
- [local_testing.md](local_testing.md) — every feature, how to verify locally
- [deployment.md](deployment.md) — prod plan, cost, observability, rollback
- [`lambda/coach/`](lambda/coach/) — the coach endpoint's Lambda wrapper
- [`../../docs/features/web_app_auth.md`](../../docs/features/web_app_auth.md) — auth flow
- [`../../docs/product/parity.md`](../../docs/product/parity.md) — feature × platform matrix; rows with `✗` or `Partial` for this app are the backlog
