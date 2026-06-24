#!/usr/bin/env bash
#
# deploy-prod.sh — deploy the PROD env. Thin wrapper around the
# env-generic engine `bin/deploy-env.sh prod`.
#
# The three shared stacks (bootstrap / dns / github-oidc) are applied once
# per account and shared with preview, so on a normal prod deploy they show
# no changes and are skipped — only infra/envs/prod actually applies.
#
# Usage:
#   bin/deploy-prod.sh                 # interactive, full chain
#   bin/deploy-prod.sh --plan          # see what would change
#   bin/deploy-prod.sh --auto-approve  # for CI / batch runs
#
# See bin/deploy-env.sh for the stack order + flag reference.

set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/deploy-env.sh" prod "$@"
