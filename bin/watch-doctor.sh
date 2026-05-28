#!/usr/bin/env bash
#
# watch-doctor.sh — verify the custom_watch firmware toolchain is set up.
#
# Checks rustc + cargo, the thumbv7em-none-eabihf target, probe-rs CLI,
# connected debug probes, and whether the Cargo workspace at
# apps/custom_watch/ has been scaffolded. Run before first flash to surface
# setup gaps early; safe to re-run any time.
#
# Read-only. Exits 0 if everything is ready, non-zero with a fix list otherwise.
#
# Usage:
#   bin/watch-doctor.sh

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

FAILS=0
bump_fail() { FAILS=$((FAILS + 1)); }

step "Rust toolchain"
if command -v rustc >/dev/null; then
	ok "rustc $(rustc --version | awk '{print $2}')"
else
	err "rustc not found"
	dim "Fix: install rustup from https://rustup.rs/ (or 'dnf install rustup && rustup-init')"
	bump_fail
fi

if command -v cargo >/dev/null; then
	ok "cargo $(cargo --version | awk '{print $2}')"
else
	err "cargo not found — comes with rustup"
	bump_fail
fi

step "Embedded build target (thumbv7em-none-eabihf)"
if command -v rustup >/dev/null && rustup target list --installed 2>/dev/null | grep -q '^thumbv7em-none-eabihf$'; then
	ok "thumbv7em-none-eabihf installed"
else
	err "thumbv7em-none-eabihf not installed"
	dim "Fix: rustup target add thumbv7em-none-eabihf"
	bump_fail
fi

step "probe-rs (flash + log streamer)"
if command -v probe-rs >/dev/null; then
	ok "probe-rs $(probe-rs --version 2>/dev/null | awk 'NR==1 {print $2}')"
else
	err "probe-rs not installed"
	dim "Fix: cargo install probe-rs --features cli"
	dim "Or:  https://probe.rs/docs/getting-started/installation/"
	bump_fail
fi

step "Connected debug probes"
if command -v probe-rs >/dev/null; then
	probes_output="$(probe-rs list 2>&1 || true)"
	# Fail-closed: only treat as detected if we recognise a probe identifier
	# in the output. `probe-rs list` can exit 0 while emitting a non-empty
	# error string (e.g. udev-permission failures on Linux print
	# "No access to any debug probe..." but still exit 0); the older
	# negative-match-on-"no probes" logic mis-handled that case by printing
	# the raw error string as if it were a probe list.
	if echo "$probes_output" | grep -qiE 'J-Link|CMSIS-DAP|ST-Link|DAPLink|FTDI|nRF'; then
		echo "$probes_output" | sed 's/^/    /'
	else
		warn "No debug probes detected"
		dim "Plug the nRF52840 DK into a USB port (data cable, not power-only)."
		dim "Linux: if the board is plugged in but not listed, you may be missing udev rules."
		dim "See https://probe.rs/docs/getting-started/probe-setup/#udev-rules for the file."
		if [[ -n "$probes_output" ]]; then
			dim "Raw 'probe-rs list' output (for diagnosis):"
			echo "$probes_output" | head -5 | sed 's/^/      /'
		fi
	fi
fi

step "apps/custom_watch/ workspace"
if [[ -f "$REPO_ROOT/apps/custom_watch/Cargo.toml" ]]; then
	ok "Cargo workspace scaffolded"
else
	warn "Cargo workspace not yet scaffolded"
	dim "See apps/custom_watch/README.md step 2 for the scaffold instructions."
fi

step "Verdict"
if (( FAILS > 0 )); then
	err "$FAILS hard failure(s) — install the missing pieces above before flashing"
	exit 1
fi
ok "Ready to build + flash"
