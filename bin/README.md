# bin/

Operator scripts. Most wrap an AWS / sops / terraform sequence so the deploy and rotation flows fit on one line and are idempotent.

All scripts source `bin/lib/common.sh` for the color helpers + `need_cmd` / `need_aws_auth` checks.

## First deploy (or rebuild)

The deploy is **two-phase by design** — the env stack creates the KMS key, then
secrets are encrypted against it (in the PRIVATE `../infra-secrets` repo), then
the stack is re-applied so the Lambda gets them. Run the rows top-to-bottom:

| # | When | Run |
|---|---|---|
| 0 | Prod secrets live in the private estate repo — clone it once as a sibling | `git clone git@github.com:Absence0760/infra-secrets.git ../infra-secrets` |
| 1 | Before any `terraform apply` | `bin/aws-preflight.sh` |
| 2 | Stand up the env (S3 + CloudFront + Lambda + KMS) — Lambda comes up *without* the coach key on this first pass (coach → 503, expected) | `bin/deploy-preview.sh` |
| 3 | Wire the new env KMS ARN into `../infra-secrets/.sops.yaml` + seed `running/preview.sops.yaml` | `bin/sops-init.sh preview` |
| 4 | Put the real Anthropic key in (value via **stdin**, never argv — keeps it out of shell history) | `echo -n "sk-ant-…" \| bin/secret-set.sh preview ANTHROPIC_API_KEY` (or `--prompt`) |
| 5 | Commit the encrypted file in the private repo | `(cd ../infra-secrets && git commit -am 'running: preview secrets')` |
| 6 | Re-apply so the Lambda picks up the secret (now coach → 401, not 503) | `bin/deploy-preview.sh` (idempotent — only the Lambda env changes) |
| 7 | Verify the env is healthy | `bin/preview-status.sh preview` |
| — | If the entire AWS stack needs rebuilding | `bin/disaster-recovery.sh` |

**Prod is the same sequence** — swap `preview` → `prod` and run **`bin/deploy-prod.sh`** in place of `deploy-preview.sh`. Both are thin wrappers over `bin/deploy-env.sh <env>`; the shared bootstrap / dns / github-oidc stacks already exist after the preview deploy, so a prod run shows no changes on them and only applies `infra/envs/prod`. The deploy script itself prints the exact phase-2 commands (clone-estate / sops-init / secret-set / re-run / status) for whichever env you're on. Full manual walkthrough: [`infra/README.md` § First-time deploy](../infra/README.md).

## Day-to-day

| When | Run |
|---|---|
| AWS session expired | `bin/aws-login.sh` |
| Debugging a Lambda response | `bin/lambda-logs.sh preview --tail` |
| Dependabot left ghost CI runs | `bin/cancel-stale-runs.sh --apply` |
| Local dev without burning the MapTiler quota | `bin/protomaps-dev.sh start` (then paste the printed env vars into each app's `.env.local`; full recipe at [`docs/ops/protomaps_local_setup.md`](../docs/ops/protomaps_local_setup.md), design at [decisions.md § 68](../docs/architecture/decisions.md#68-tile-rendering-honours-an-env-override-so-local-dev-can-use-self-hosted-protomaps-without-touching-prod-code-paths)) |
| Testing Stripe / RevenueCat payments locally | `bin/payments-dev.sh start` (= `pnpm dev:payments`: boots Supabase + functions serve with `.env.local` + `stripe listen`; `… replay` POSTs a signed RevenueCat event to flip the tier — full recipe at [`docs/testing/local_testing_stubs.md § Stripe`](../docs/testing/local_testing_stubs.md)) |

## Rare events

| When | Run |
|---|---|
| Adding a second human/role to the KMS key policy | `bin/onboard-operator.sh arn:aws:iam::…:role/Admin both` |
| KMS key was destroyed + recreated, encrypted file is stuck on the old key | `bin/key-rotate.sh preview` |

## Custom watch firmware (research-tier, [§ 71](../docs/architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) + [§ 80](../docs/architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance))

Wrappers around `cargo` + `probe-rs` (and Renode, for the simulator) for the Rust + Embassy firmware at [`apps/custom_watch/`](../apps/custom_watch/README.md). The build/flash/test wrappers `cd` into the workspace and forward extra args. Full walkthrough in [`apps/custom_watch/local_testing.md`](../apps/custom_watch/local_testing.md).

| When | Run |
|---|---|
| First-machine setup — verify toolchain + board detection | `bin/watch-doctor.sh` |
| Inner loop — build, flash, stream `defmt` logs over RTT until Ctrl-C | `bin/watch-flash.sh` |
| Host-side unit tests (no board required) | `bin/watch-test.sh` |
| Boot the firmware on an emulated nRF52840 DK + stream decoded `defmt` logs (no board required; `--gui` opens the live watch screen, phone link on TCP 7788) | `bin/watch-sim.sh` |
| Attach an interactive Renode monitor to the running sim, from a second terminal (button macros: `runMacro $btn1`…`$btn4` — start/pause, stop, page, lap) | `bin/watch-monitor.sh` |
| Compile-check / release binary without flashing | `bin/watch-build.sh` |
| Stream logs from an already-running board (no reflash) | `bin/watch-logs.sh` |

## Conventions

- Read-only by default. Gated by a prompt (or `--auto-approve`): `deploy-preview`, `deploy-prod`, `onboard-operator`, `disaster-recovery`. Gated by an explicit flag: `cancel-stale-runs` (`--apply`). Ungated but local-file-only, idempotent, and verified with a decrypt round-trip: `secret-set`, `sops-init`, `key-rotate` (they rewrite the estate repo's `.sops.yaml` / encrypted file — the mutation is the point).
- Idempotent. Re-running on an already-completed step prints "skipping" and exits 0.
- Profile selection: scripts honour `$AWS_PROFILE` (set it once in `~/.bashrc.d/26-aliases-aws.sh`). If unset, `running` (this account's workstation SSO profile) is the default.
- Region: pinned to `us-east-1` everywhere (CloudFront + ACM constraint).
