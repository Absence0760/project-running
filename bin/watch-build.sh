#!/usr/bin/env bash
#
# watch-build.sh — build the custom_watch firmware in release mode without
# flashing. Useful for verifying compile when no board is connected, for
# inspecting binary size (cargo size --release), or for catching warnings
# without burning a flash cycle.
#
# Thin wrapper around: cd apps/custom_watch && cargo build --release "$@"
#
# Usage:
#   bin/watch-build.sh
#   bin/watch-build.sh --bin sensor_smoke

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"

if [[ ! -f "$WORKSPACE/Cargo.toml" ]]; then
	fatal "apps/custom_watch/ Cargo workspace not scaffolded yet. See $WORKSPACE/README.md step 2."
fi

need_cmd cargo
cd "$WORKSPACE"
exec cargo build --release "$@"
