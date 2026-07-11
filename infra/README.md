# infra/

Terraform stacks for the AWS web hosting plan ([decisions.md § 53](../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages)). One module + per-env stacks for `prod` and `preview`, plus shared `dns` and `github-oidc` stacks. Runtime secrets via sops + AWS KMS.

For the operational walkthrough (cost, rollback, observability, DR), read [`apps/web/deployment.md`](../apps/web/deployment.md) — this file is the **how-to-apply** index.

## Layout

```
infra/
├── bootstrap/           one-time: S3 state bucket
├── modules/
│   └── web-stack/       reusable per-env: S3 + CloudFront + Lambda
│                        + KMS + IAM + alarms
├── dns/                 hosted zone + ACM cert (one stack, both envs share)
├── github-oidc/         OIDC provider + per-env deploy roles
└── envs/
    ├── prod/            calls web-stack with env=prod
    └── preview/         calls web-stack with env=preview
```

Each stack has its own remote state in the bucket created by `bootstrap`. State locking is S3-native via `use_lockfile = true` (Terraform ≥ 1.10) — no DynamoDB table required. The `dns` and `github-oidc` outputs are consumed by per-env stacks via `terraform_remote_state`.

**Region.** Everything sits in `us-east-1`. The ACM cert for CloudFront *has* to live there regardless, and putting the rest of the stack alongside it avoids cross-region complexity. The per-env stacks still expose a `us_east_1` provider alias so a future region move only touches the primary region. To deploy somewhere else, change the default in every `aws_region` variable + every `region` field in the `backend.tf` files + the `AWS_REGION` env in `.github/workflows/release-web.yml`.

**Cost.** Idle monthly: hosted zone $0.50 + 2 KMS keys $2 + S3 / CloudFront / Lambda well under $1 = **~$3/month**. Plus domain registration if you don't already own one (~$15/year for a `.app`).

## First-time deploy

> **Quick path:** [`bin/`](../bin/README.md) wraps the AWS / sops / terraform
> sequences below. The TL;DR is six commands:
>
> ```bash
> bin/aws-preflight.sh                                 # confirm tooling + AWS auth
> bin/deploy-preview.sh                                # apply bootstrap → dns → oidc → preview, idempotent
> bin/sops-init.sh preview                             # wire KMS ARN into ../infra-secrets + seed running/preview.sops.yaml
> bin/secret-set.sh preview ANTHROPIC_API_KEY < ~/key  # write the real Anthropic key (stdin, never argv)
> cd infra/envs/preview && terraform apply             # push the new env var to Lambda
> bin/preview-status.sh preview                        # health check
> ```
>
> The walkthrough below is the full manual recipe. Both produce the same result;
> the scripts add idempotence (`bin/deploy-preview.sh` skips already-applied
> stacks via `terraform plan -detailed-exitcode`), automatic preflight, and
> error-message context. Read the manual recipe at least once so you understand
> what the scripts are doing.

### 0. Phase-0 prereqs (skip what you already have)

Working from zero — no AWS account, no domain, no AWS CLI:

**0.1 — AWS account.** Sign up at https://aws.amazon.com/. Enable MFA on the root account, create an Identity Center user with `AdministratorAccess` (we tighten later), and assign it to the account. Note the **AWS access portal URL** Identity Center gives you (`https://d-xxxxxx.awsapps.com/start`). Account-wide spend alerts are Terraformed in `infra/envs/prod/budgets.tf` (50 % / 100 % ACTUAL + 100 % FORECASTED notifications); set `monthly_budget_limit_usd` and `budget_alert_emails` in `terraform.tfvars` before the prod apply.

**0.2 — Domain.** Either register one fresh (Porkbun, Namecheap, Cloudflare Registrar — all fine; you don't need Route 53 to register, only to host DNS) or pick an apex you already own. The default examples use `threkir.com` — search the repo for it and swap if you're using something else. The places that hardcode it are:
- `infra/dns/` — set `apex_domain` in the committed `infra/dns/terraform.tfvars` (which also carries `email_auth_records`, the Resend DKIM/SPF/MX/DMARC set — public DNS data, Terraformed so a DR rebuild restores mail deliverability instead of dropping it)
- `infra/envs/{preview,prod}/terraform.tfvars` — set `apex_domain` there (canonical copies live in the private estate repo as `../infra-secrets/running/{preview,prod}.tfvars`, symlinked into place — see § 4/5)
- `infra/envs/preview/variables.tf` + `infra/envs/prod/variables.tf` — `default = "threkir.com"` if you want a fallback

**0.3 — Workstation tooling.**

- Terraform ≥ 1.13 (`dnf install terraform`)
- AWS CLI v2 (already installed per workstation conventions)
- sops (already installed; uses age locally + AWS KMS for shared)
- The PRIVATE estate secrets repo cloned as a sibling of this repo: `git clone git@github.com:Absence0760/infra-secrets.git ../infra-secrets`. Production sops ciphertext lives there (under `running/`), never in this public repo. Set `INFRA_SECRETS_DIR` / `TF_VAR_secrets_file` if your clone lives elsewhere.

**0.4 — AWS CLI SSO.**

```bash
aws configure sso
# SSO start URL: <your access portal URL from 0.1>
# SSO Region: us-east-1
# default region: us-east-1
# default output: json
# profile name: running     (or whatever you want)

aws sso login --profile running
aws sts get-caller-identity --profile running   # proves it works

# Persist the profile choice for future shells:
echo 'export AWS_PROFILE=running' > ~/.bashrc.d/26-aliases-aws.sh
```

### 1. Bootstrap (one-time — S3 state bucket)

```bash
cd infra/bootstrap
terraform init
terraform apply -var "state_bucket_name=threkir-tfstate"
```

Creates the S3 bucket every other stack uses for remote state. **Local state only** — never migrate this stack into the bucket it creates.

### 2. DNS

```bash
cd ../dns
terraform init
terraform apply -var "apex_domain=threkir.com"
```

Outputs the four NS records — paste those at the registrar that owns `threkir.com`. Wait for propagation (typically <5 min, occasionally an hour) before continuing — ACM cert validation requires the NS delegation to be live.

### 3. GitHub OIDC

```bash
cd ../github-oidc
terraform init
terraform apply    # github_repo comes from the committed terraform.tfvars (public info)
```

Outputs the two role ARNs:

```bash
terraform output deploy_role_arn_prod
terraform output deploy_role_arn_preview
```

Add both to **GitHub Settings → Secrets and variables → Actions** as `AWS_DEPLOY_ROLE_ARN_PROD` and `AWS_DEPLOY_ROLE_ARN_PREVIEW`.

While you're in the GitHub Secrets UI, add the **build-input** secrets too. These are different from the role ARNs — they're inlined into the static SvelteKit build at compile time (Vite reads them from `apps/web/.env`, written by the workflow before `npm run build`):

| Secret name | Source | Required? |
|---|---|---|
| `PUBLIC_SUPABASE_URL` | Supabase project settings → API → URL | yes |
| `PUBLIC_SUPABASE_ANON_KEY` | Supabase project settings → API → `anon` `publishable` key (NOT `service_role`) | yes |
| `PUBLIC_MAPTILER_KEY` | maptiler.com → Account → Keys | yes (maps don't render without it) |
| `PUBLIC_REVENUECAT_WEB_CHECKOUT_URL` | RevenueCat dashboard → Web Paywall Link (`https://pay.rev.cat/<token>`) | only when Pro is sellable — `PUBLIC_COACH_ENABLED` or `PUBLIC_ROUTE_GEN_ENABLED` truthy (the build guard enforces it then; with both flags unset — the rock-bottom tier — leave it unset too) |
| `PUBLIC_COACH_ENABLED` / `PUBLIC_ROUTE_GEN_ENABLED` | set `true` when the coach / route engines go live (decisions §204) | no — leave unset at rock-bottom; unset = Pro not sold, coach UI hidden |
| `PUBLIC_REVENUECAT_WEB_PORTAL_URL` | RevenueCat dashboard → customer portal link | optional (manage-subscription button degrades to a hint) |
| `PUBLIC_SENTRY_DSN` | Sentry → Settings → Projects → Client Keys (DSN) | optional |

If a secret is unset, the workflow writes an empty string into `.env` and `svelte-check` errors with `Module '$env/static/public' has no exported member 'PUBLIC_X'`. Set the required three before the first deploy.

### 4. Preview env (apply first to flush out config issues against a non-prod blast radius)

```bash
cd ../envs/preview
# The canonical tfvars lives in the PRIVATE estate repo (plaintext — the values
# are non-secret: publishable key, public URLs, alert emails; the private repo
# keeps them off public GitHub and makes any workstation deploy-ready). Symlink
# it in; fall back to cp-from-example only if you're not using the estate repo.
ln -s ../../../../infra-secrets/running/preview.tfvars terraform.tfvars
$EDITOR terraform.tfvars                          # fill in supabase URL + anon key
terraform init
terraform apply
```

The first apply creates the KMS key, S3 bucket, CloudFront distribution, and Lambda **with a placeholder zip and no `ANTHROPIC_API_KEY`** (because the secrets file doesn't exist yet). The coach endpoint will return 503 — that's expected. Static site already works.

> **Secrets live in the PRIVATE estate repo, NOT here.** This repo is PUBLIC.
> Production sops ciphertext is committed to `Absence0760/infra-secrets` (cloned
> as a sibling at `../infra-secrets`), under `running/<env>.sops.yaml` — never
> under `infra/` (a sops file in public history leaks KMS-ARN metadata + secret
> key names; `infra/.gitignore` blocks it as a fail-safe). The Terraform
> `sops_file` data source reads the external path via the `secrets_file` var
> (default `../infra-secrets/running/<env>.sops.yaml`); set `TF_VAR_secrets_file`
> if your estate clone lives elsewhere. See [decisions.md §53](../docs/architecture/decisions.md) and `infra/.sops.yaml`.

The scripted path does the rest (`bin/sops-init.sh` wires the env's KMS ARN into the estate `.sops.yaml` and seeds the encrypted file; `bin/secret-set.sh` writes a key). The equivalent manual steps for preview:

```bash
ARN=$(terraform output -raw kms_key_arn)                       # from infra/envs/preview
cd ../../../../infra-secrets                                   # the private estate repo
sed -i "s|KMS_RUNNING_PREVIEW_ARN_PLACEHOLDER|$ARN|" .sops.yaml
grep -q 'KMS_RUNNING_PREVIEW_ARN_PLACEHOLDER' .sops.yaml && { echo 'ERROR: estate .sops.yaml still has the preview placeholder'; exit 1; }
mkdir -p running
echo 'ANTHROPIC_API_KEY: sk-ant-...' > /tmp/coach.yaml
echo 'SUPABASE_SERVICE_ROLE_KEY: eyJ...' >> /tmp/coach.yaml   # coach assistant-message persistence (XSS audit H1); without it the coach streams but doesn't save replies
echo 'SENTRY_DSN: ...' >> /tmp/coach.yaml      # optional
sops --encrypt /tmp/coach.yaml > running/preview.sops.yaml
shred -u /tmp/coach.yaml
git add running/preview.sops.yaml .sops.yaml && git commit -m 'running: preview secrets'   # commit in the PRIVATE repo
```

Re-apply (back in `infra/envs/preview`) to wire the secrets into the Lambda:

```bash
cd -    # back to infra/envs/preview
terraform apply
```

### 5. Prod env

> **Scripted path:** `bin/deploy-prod.sh` runs the same orchestrated chain as
> `deploy-preview.sh` (idempotent — the shared bootstrap / dns / github-oidc
> stacks no-op, only `infra/envs/prod` applies) and prints the exact phase-2
> secret-wiring commands. The manual steps below are the equivalent.

Same flow, in `envs/prod/` (ciphertext → `../infra-secrets/running/prod.sops.yaml`):

```bash
cd ../prod
ln -s ../../../../infra-secrets/running/prod.tfvars terraform.tfvars   # canonical copy in the estate repo (see § 4)
$EDITOR terraform.tfvars
terraform init
terraform apply
ARN=$(terraform output -raw kms_key_arn)
( cd ../../../../infra-secrets
  sed -i "s|KMS_RUNNING_PROD_ARN_PLACEHOLDER|$ARN|" .sops.yaml
  grep -q 'KMS_RUNNING_PROD_ARN_PLACEHOLDER' .sops.yaml && { echo 'ERROR: estate .sops.yaml still has the prod placeholder'; exit 1; }
  mkdir -p running
  echo 'ANTHROPIC_API_KEY: sk-ant-...' > /tmp/coach.yaml
  echo 'SUPABASE_SERVICE_ROLE_KEY: eyJ...' >> /tmp/coach.yaml   # coach assistant-message persistence (XSS audit H1)
  sops --encrypt /tmp/coach.yaml > running/prod.sops.yaml
  shred -u /tmp/coach.yaml
  git add running/prod.sops.yaml .sops.yaml && git commit -m 'running: prod secrets' )
terraform apply
```

### 6. First code deploy

Push a no-op commit to `main` (or push a `web@*` tag for prod) — `.github/workflows/release-web.yml` builds the Lambda zip + the SvelteKit static build, OIDC-assumes the deploy role, and uploads everything. Watch the run at https://github.com/<owner>/<repo>/actions.

If the workflow fails with `Could not load credentials from any providers` on the `aws-actions/configure-aws-credentials` step, the GitHub secret for that env's role ARN is missing — re-check step 3.

If it fails on `npm run check` with `Module '$env/static/public' has no exported member 'PUBLIC_X'`, the corresponding `PUBLIC_*` GitHub secret from step 3 is missing.

Once green: visit `preview.<your-apex>` (or `<your-apex>` for prod) and confirm the SvelteKit static site renders.

## Rotation

Edit a secret in place (the encrypted file lives in the PRIVATE estate repo):

```bash
sops ../infra-secrets/running/prod.sops.yaml      # opens $EDITOR with decrypted YAML
( cd ../infra-secrets && git commit -am 'running: rotate prod secret' )   # commit in the private repo
cd infra/envs/prod && terraform apply             # pushes new value to Lambda
```

Or non-interactively for one specific key (no shell history leak — value comes via stdin / `--from-file`; `bin/secret-set.sh` writes to `../infra-secrets/running/<env>.sops.yaml`):

```bash
echo -n "$NEW_VALUE" | bin/secret-set.sh prod ANTHROPIC_API_KEY
( cd ../infra-secrets && git commit -am 'running: rotate ANTHROPIC_API_KEY' )
cd infra/envs/prod && terraform apply
```

If you ever change the *KMS key itself* (destroyed + recreated, or moved in the estate `.sops.yaml`), the existing encrypted file still decrypts under the OLD key in its metadata. Re-encrypt under the new key with [`bin/key-rotate.sh`](../bin/README.md). For *AWS-native key material* rotation (`aws kms enable-key-rotation`) no re-encrypt is needed — sops sees the same key alias.

The Lambda's environment variables update in-place; in-flight requests finish on the old config, new requests pick up the new value within ~10 s.

## State

Remote state in `s3://threkir-tfstate/`. Locking is S3-native via `use_lockfile = true` — Terraform writes a `.tflock` file alongside each state file, using S3's conditional-write `If-None-Match` semantics. No DynamoDB table to manage. The `bootstrap` stack itself uses local state (chicken-and-egg).

## Disaster recovery

If the AWS account itself is gone, see [`apps/web/deployment.md` § Disaster recovery](../apps/web/deployment.md#disaster-recovery) for the rebuild procedure. Important nuance: KMS keys can't be cross-account-recovered, so the existing `../infra-secrets/running/*.sops.yaml` ciphertext is unrecoverable in that scenario (the plaintext is gone with the key) — re-issue the secrets fresh and re-encrypt against the new env's KMS key. The private estate repo is the backup of record for the *encrypted* blobs, but it cannot rescue you from a lost KMS key.

For an interactive rebuild walkthrough that probes which phases are already done and resumes mid-flow, run [`bin/disaster-recovery.sh`](../bin/README.md) (or `bin/disaster-recovery.sh --status` for a read-only state check).

## What's NOT in here

- The CI deploy step itself (`.github/workflows/release-web.yml`) — that's a code-not-infra concern.
- The Lambda handler source — `apps/web/lambda/coach/`.
- Backend infra (Supabase, Fly.io worker + OSRM) — those have their own deploy plans under each `apps/<service>/deployment.md`.
