#!/usr/bin/env bash
#
# watch-test.sh — run host-side unit tests for the custom_watch firmware.
# Covers pure-logic crates (NMEA parser, recording state machine, signal
# processing) that don't touch peripherals. No board required.
#
# The workspace's .cargo/config.toml pins the default target to
# thumbv7em-none-eabihf for `cargo build` + `cargo run`. For host tests we
# override --target to the host triple and exclude embedded-only crates
# (`app`, `nrf52840_dk`) so the build doesn't try to link against the
# embedded runtime.
#
# Forwards extra args (e.g. a test-name filter, --nocapture).
# On-target tests (driver bring-up, HAL, BLE) need a board — use
# bin/watch-flash.sh and observe defmt logs instead.
#
# Usage:
#   bin/watch-test.sh                  # all host tests
#   bin/watch-test.sh nmea_parser      # filter by test name
#   bin/watch-test.sh -- --nocapture   # forward args to libtest

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKSPACE="$REPO_ROOT/apps/custom_watch"

if [[ ! -f "$WORKSPACE/Cargo.toml" ]]; then
	fatal "apps/custom_watch/ Cargo workspace not scaffolded yet. See $WORKSPACE/README.md step 2."
fi

need_cmd cargo
need_cmd rustc

HOST_TRIPLE="$(rustc -vV | sed -n 's|host: ||p')"
if [[ -z "$HOST_TRIPLE" ]]; then
	fatal "Could not detect host target triple via 'rustc -vV'."
fi

cd "$WORKSPACE"
exec cargo test \
	--target "$HOST_TRIPLE" \
	--workspace \
	--exclude app \
	--exclude nrf52840_dk \
	"$@"
