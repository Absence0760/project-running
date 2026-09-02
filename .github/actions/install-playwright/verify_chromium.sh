#!/usr/bin/env bash
#
# Make Chromium's system libraries present, and prove it by launching the
# browser rather than by trusting apt's exit code.
#
# This lived inline in action.yml, where nothing could execute it: a composite
# action's shell is in no job's test suite, and the branch that matters — the
# apt fallback — runs only when a launch has already failed, which the incident
# history below says is rare. So it was the whole of the repair path, unrun.
# Extracted for the same reason and in the same shape as start-supabase's
# wait_for_sidecars.sh; verify_chromium.test.mjs drives it with stub node /
# pnpm / sudo on PATH.
#
# Why the apt half is conditional rather than unconditional: `playwright
# install-deps` exists to make Chromium's system libraries present, and on a
# GitHub-hosted image they already ARE, so the command only ever verifies — and
# it verifies by talking to a third party. That turned an Ubuntu-mirror outage
# into a red test shard five times across two pushes on 2026-08-18 (round 4:
# shards 1, 7, 13; round 5: shards 6, 7), each identical: three 120s attempts
# all timing out, then a hard fail, no test ever run, and a re-run clean every
# time. Two earlier outages took main red the same way (runs 32069680540 and
# 32090988359).
#
# So verify the libraries directly instead, and let apt run only when the
# verification says something is genuinely missing. The verification is a real
# Chromium launch — the exact thing the shards go on to do, and strictly
# stronger than inspecting `ldd` output, which cannot see what Chromium
# dlopens. Playwright names the missing library itself when a launch fails on a
# dependency, so the failure path stays loud and specific.
#
# What this deliberately does NOT do: pass when it cannot tell. A launch that
# fails for any reason falls through to apt, and the FINAL verdict is another
# launch — install-deps can succeed and still leave the browser broken, and it
# can fail on a mirror having already installed what was missing.
#
# Run from apps/web: `node -e` resolves require() from the cwd, which is why
# this is a script invoked with the caller's working directory rather than one
# written to a temp dir.

# `node -e` resolves require() from the cwd, which is why this runs
# from apps/web rather than from a script written to a temp dir.
# chromium.launch() with no options is the headless shell — the same
# binary devices['Desktop Chrome'] drives in the shards' config.
launch_check() {
  timeout -k 10 120 node -e '
    const { chromium } = require("@playwright/test");
    chromium
      .launch()
      .then((browser) => browser.close())
      .then(() => process.exit(0))
      .catch((error) => {
        console.error(String((error && error.message) || error));
        process.exit(1);
      });
  ' 2>&1
}

if launched=$(launch_check); then
  echo "Chromium launched — its system libraries are present, apt not needed"
  exit 0
fi

echo "::warning::Chromium would not launch, so a system library is genuinely missing — falling through to apt"
printf '%s\n' "${launched}"

# Bound apt so a dead mirror fails fast instead of hanging. Both
# halves are needed: the conf caps each index fetch so the usual case
# exits non-zero on its own within seconds, and the outer `timeout`
# still bounds the pathological case the per-fetch cap cannot (~20
# index files x a retried timeout each is minutes, not seconds).
sudo tee /etc/apt/apt.conf.d/99-ci-timeouts >/dev/null <<'CONF'
Acquire::http::Timeout "15";
Acquire::https::Timeout "15";
Acquire::Retries "2";
CONF

# `timeout` kills the node process, but the apt-get it spawned
# through sudo can outlive it still holding the apt/dpkg locks —
# which would fail the NEXT attempt on "Could not get lock"
# rather than on the mirror, hiding the real cause behind our own
# leftovers. Reap the tree, then repair any half-configured
# package the kill interrupted.
reap_apt() {
  sudo pkill -9 -x apt-get 2>/dev/null || true
  sudo pkill -9 -x dpkg 2>/dev/null || true
  sudo rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
  sudo dpkg --configure -a 2>/dev/null || true
}

for attempt in 1 2 3; do
  # -k: SIGKILL 10s after the SIGTERM, because apt ignores TERM
  # while it is inside a socket read on an unresponsive mirror.
  if timeout -k 10 120 pnpm exec playwright install-deps chromium; then
    break
  fi
  echo "::warning::playwright install-deps attempt ${attempt} failed or exceeded 120s"
  reap_apt
done

# The verdict is the browser, not apt's exit code: install-deps can
# succeed and still leave the launch broken, and it can fail on a
# mirror having already installed what was missing.
if launched=$(launch_check); then
  echo "Chromium launched after installing its system libraries"
  exit 0
fi

echo "::error::Chromium still will not launch after the system-library install — its own error is below, and a library named there is one the runner's apt mirrors could not resolve"
printf '%s\n' "${launched}"
grep -hoE 'https?://[^ /]+' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null | sort -u || true
exit 1
