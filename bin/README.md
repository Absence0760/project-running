# bin/

Operator scripts. Most wrap an AWS / sops / terraform sequence so the deploy and rotation flows fit on one line and are idempotent.

All scripts source `bin/lib/common.sh` for the color helpers + `need_cmd` / `need_aws_auth` checks.

## First deploy (or rebuild)

| When | Run |
|---|---|
| Before any `terraform apply` | `bin/aws-preflight.sh` |
| Standing up the preview env from zero | `bin/deploy-preview.sh` |
| After Phase 2d to wire sops to the new KMS keys | `bin/sops-init.sh preview` |
| To put a real Anthropic key into Lambda | `bin/secret-set.sh preview ANTHROPIC_API_KEY sk-ant-…` then `cd infra/envs/preview && terraform apply` |
| To verify preview is healthy after deploy | `bin/preview-status.sh preview` |
| If the entire AWS stack needs rebuilding | `bin/disaster-recovery.sh` |

## Day-to-day

| When | Run |
|---|---|
| AWS session expired | `bin/aws-login.sh` |
| Debugging a Lambda response | `bin/lambda-logs.sh preview --tail` |
| Dependabot left ghost CI runs | `bin/cancel-stale-runs.sh --apply` |
| Local dev without burning the MapTiler quota | `bin/protomaps-dev.sh start` (then paste the printed env vars into each app's `.env.local`; full recipe at [`docs/protomaps_local_setup.md`](../docs/protomaps_local_setup.md), design at [decisions.md § 68](../docs/decisions.md#68-tile-rendering-honours-an-env-override-so-local-dev-can-use-self-hosted-protomaps-without-touching-prod-code-paths)) |

## Rare events

| When | Run |
|---|---|
| Adding a second human/role to the KMS key policy | `bin/onboard-operator.sh arn:aws:iam::…:role/Admin both` |
| KMS key was destroyed + recreated, encrypted file is stuck on the old key | `bin/key-rotate.sh preview` |

## Conventions

- Read-only by default. The four scripts that mutate state (`deploy-preview`, `secret-set`, `onboard-operator`, `key-rotate`) prompt before applying, or accept `--auto-approve`.
- Idempotent. Re-running on an already-completed step prints "skipping" and exits 0.
- Profile selection: scripts honour `$AWS_PROFILE` (set it once in `~/.bashrc.d/26-aliases-aws.sh`). If unset, `runonward` is the default.
- Region: pinned to `us-east-1` everywhere (CloudFront + ACM constraint).
