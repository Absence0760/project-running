# infra/

Terraform stacks for the AWS web hosting plan ([decisions.md § 53](../docs/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages)). One module + per-env stacks for `prod` and `preview`, plus shared `dns` and `github-oidc` stacks. Runtime secrets via sops + AWS KMS.

For the operational walkthrough (cost, rollback, observability, DR), read [`apps/web/deployment.md`](../apps/web/deployment.md) — this file is the **how-to-apply** index.

## Layout

```
infra/
├── bootstrap/           one-time: state bucket + DDB lock table
├── modules/
│   └── web-stack/       reusable per-env: S3 + CloudFront + Lambda
│                        + KMS + IAM + alarms
├── dns/                 hosted zone + ACM cert (one stack, both envs share)
├── github-oidc/         OIDC provider + per-env deploy roles
└── envs/
    ├── prod/            calls web-stack with env=prod
    └── preview/         calls web-stack with env=preview
```

Each stack has its own remote state in the bucket created by `bootstrap`. The `dns` and `github-oidc` outputs are consumed by per-env stacks via `terraform_remote_state`.

## First-time deploy

Prereqs on the workstation:

- Terraform ≥ 1.13 (`dnf install terraform`)
- sops + `~/.aws/config` SSO profile that resolves via `aws sts get-caller-identity`
- AWS CLI v2 with the SSO session active (`aws sso login --profile <name>`)

### 1. Bootstrap (one-time)

```bash
cd infra/bootstrap
terraform init
terraform apply -var "state_bucket_name=runonward-tfstate"
```

Creates the S3 bucket + DynamoDB lock table that every other stack uses. **Local state only** — never migrate this stack into the bucket it creates.

### 2. DNS

```bash
cd ../dns
terraform init
terraform apply -var "apex_domain=runonward.app"
```

Outputs the four NS records — paste those at the registrar that owns `runonward.app`. Wait for propagation (typically <5 min, occasionally an hour) before continuing — ACM cert validation requires the NS delegation to be live.

### 3. GitHub OIDC

```bash
cd ../github-oidc
terraform init
terraform apply -var "github_repo=<owner>/<repo>"
```

Outputs the two role ARNs:

```bash
terraform output deploy_role_arn_prod
terraform output deploy_role_arn_preview
```

Add both to **GitHub Settings → Secrets and variables → Actions** as `AWS_DEPLOY_ROLE_ARN_PROD` and `AWS_DEPLOY_ROLE_ARN_PREVIEW`.

### 4. Preview env (apply first to flush out config issues against a non-prod blast radius)

```bash
cd ../envs/preview
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars                          # fill in supabase URL + anon key
terraform init
terraform apply
```

The first apply creates the KMS key, S3 bucket, CloudFront distribution, and Lambda **with a placeholder zip and no `ANTHROPIC_API_KEY`** (because the secrets file doesn't exist yet). The coach endpoint will return 503 — that's expected. Static site already works.

Now encrypt the secrets file against the env's KMS key:

```bash
ARN=$(terraform output -raw kms_key_arn)
sed -i "s|REPLACE_PREVIEW_KMS_ARN|$ARN|" ../../.sops.yaml
echo 'ANTHROPIC_API_KEY: sk-ant-...' > /tmp/coach.yaml
echo 'SENTRY_DSN: ...' >> /tmp/coach.yaml      # optional
sops --encrypt /tmp/coach.yaml > secrets.enc.yaml
shred -u /tmp/coach.yaml
```

Re-apply to wire the secrets into the Lambda:

```bash
terraform apply
```

### 5. Prod env

Same flow, in `envs/prod/`:

```bash
cd ../prod
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
terraform init
terraform apply
ARN=$(terraform output -raw kms_key_arn)
sed -i "s|REPLACE_PROD_KMS_ARN|$ARN|" ../../.sops.yaml
echo 'ANTHROPIC_API_KEY: sk-ant-...' > /tmp/coach.yaml
sops --encrypt /tmp/coach.yaml > secrets.enc.yaml
shred -u /tmp/coach.yaml
terraform apply
```

### 6. First code deploy

Now push a `web@*` tag (or push to `main` for preview) — `.github/workflows/release-web.yml` builds the Lambda zip + the SvelteKit static build, OIDC-assumes the deploy role, and uploads everything.

## Rotation

Edit a secret in place:

```bash
cd infra/envs/prod
sops secrets.enc.yaml                            # opens $EDITOR with decrypted YAML
terraform apply                                  # pushes new value to Lambda
```

The Lambda's environment variables update in-place; in-flight requests finish on the old config, new requests pick up the new value within ~10 s.

## State

Remote state in `s3://runonward-tfstate/` — locked via DynamoDB. The `bootstrap` stack itself uses local state (chicken-and-egg).

## Disaster recovery

If the AWS account itself is gone, see [`apps/web/deployment.md` § Disaster recovery](../apps/web/deployment.md#disaster-recovery) for the rebuild procedure. Important nuance: KMS keys can't be cross-account-recovered, so the existing `secrets.enc.yaml` files are unrecoverable in that scenario — re-issue the secrets fresh and re-encrypt against the new env's KMS key.

## What's NOT in here

- The CI deploy step itself (`.github/workflows/release-web.yml`) — that's a code-not-infra concern.
- The Lambda handler source — `apps/web/lambda/coach/`.
- Backend infra (Supabase, Fly.io worker + OSRM) — those have their own deploy plans under each `apps/<service>/deployment.md`.
