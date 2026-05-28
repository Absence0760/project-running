#!/usr/bin/env bash
#
# watch-test.sh — run host-side unit tests for the custom_watch firmware.
# Covers pure-logic crates (NMEA parser, recording state machine, signal
# processing) that don't touch peripherals. No board required.
#
# Thin wrapper around: cd apps/custom_watch && cargo test "$@"
# Forwards extra args (e.g. a test-name filter or --release).
#
# On-target tests (driver bring-up, HAL, BLE) need a board — use
# bin/watch-flash.sh and observe defmt logs instead.
#
# Usage:
#   bin/watch-test.sh                  # all host tests
#   bin/watch-test.sh nmea_parser      # filter by test name

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"

if [[ ! -f "$WORKSPACE/Cargo.toml" ]]; then
	fatal "apps/custom_watch/ Cargo workspace not scaffolded yet. See $WORKSPACE/README.md step 2."
fi

need_cmd cargo
cd "$WORKSPACE"
exec cargo test "$@"
