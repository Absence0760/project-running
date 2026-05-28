#!/usr/bin/env bash
#
# watch-flash.sh — build the custom_watch firmware, flash it to a connected
# Nordic nRF52840 DK, and stream defmt logs over RTT until Ctrl-C.
#
# Thin wrapper around: cd apps/custom_watch && cargo run --release "$@"
# Forwards extra args to cargo (e.g. --bin sensor_smoke, or --features=foo).
#
# Requires: thumbv7em-none-eabihf target, probe-rs, nRF52840 DK plugged in.
# Run bin/watch-doctor.sh first if anything fails.
#
# Usage:
#   bin/watch-flash.sh                       # flash the default binary
#   bin/watch-flash.sh --bin sensor_smoke    # flash a specific test binary

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"

if [[ ! -f "$WORKSPACE/Cargo.toml" ]]; then
	fatal "apps/custom_watch/ Cargo workspace not scaffolded yet. See $WORKSPACE/README.md step 2."
fi

need_cmd cargo
cd "$WORKSPACE"
exec cargo run --release "$@"
