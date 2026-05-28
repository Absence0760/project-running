#!/usr/bin/env bash
#
# watch-logs.sh — attach to a running nRF52840 DK and stream defmt logs over
# RTT. Does NOT reflash the firmware — use bin/watch-flash.sh for that.
#
# Useful for tailing logs after a flash session has exited, watching a
# long-running test, or attaching from a second terminal while
# bin/watch-flash.sh is doing the build cycle.
#
# Thin wrapper around: probe-rs attach --chip nRF52840_xxAA "$@"
#
# Usage:
#   bin/watch-logs.sh

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

need_cmd probe-rs
exec probe-rs attach --chip nRF52840_xxAA "$@"
