#!/usr/bin/env bash
#
# deploy-preview.sh — deploy the PREVIEW env. Thin wrapper around the
# env-generic engine `bin/deploy-env.sh preview`.
#
# Usage:
#   bin/deploy-preview.sh                 # interactive, full chain
#   bin/deploy-preview.sh --plan          # see what would change
#   bin/deploy-preview.sh --auto-approve  # for CI / batch runs
#
# See bin/deploy-env.sh for the stack order + flag reference.

set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/deploy-env.sh" preview "$@"
