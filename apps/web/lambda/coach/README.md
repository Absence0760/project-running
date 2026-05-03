# Coach Lambda

Production handler for `/api/coach/*`. Reaches the same `$lib/coach/handler` core that the SvelteKit dev route uses (see [`apps/web/CLAUDE.md`](../../CLAUDE.md) and [decisions.md § 53](../../../../docs/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages)).

## Layout

```
src/index.ts      Lambda Function URL handler (response-streaming).
                  Adapts API Gateway events to the shared core.
build.mjs         esbuild bundler — produces dist/index.mjs + coach.zip.
dist/             generated (gitignored)
```

## Build locally

```bash
cd apps/web
node lambda/coach/build.mjs
# → apps/web/lambda/coach/dist/coach.zip
```

The CI workflow (`.github/workflows/release-web.yml`) runs the same script.

## Runtime env (set by Terraform)

- `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` — non-secret, written by Terraform from variables.
- `ANTHROPIC_API_KEY` — sops-encrypted in `infra/envs/<env>/secrets.enc.yaml`, decrypted by Terraform at apply time.
- `SENTRY_DSN`, `APP_RELEASE`, `COACH_PROVIDER`, `OPENAI_*` — optional.

`BYPASS_PAYWALL` is intentionally ignored in this handler — it's a dev-only escape hatch.

## Updating the deployed Lambda

The CDK / Terraform stack creates the Lambda with a placeholder zip and a `live` alias. CI replaces the code on every `web@*` tag via `aws lambda update-function-code` and retargets the alias. Rollback is `aws lambda update-alias --function-name web-coach-prod --name live --function-version <previous>` — see [`apps/web/deployment.md` § Rollback](../../deployment.md#rollback).
