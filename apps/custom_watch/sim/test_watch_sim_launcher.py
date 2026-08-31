#!/usr/bin/env python3
"""Host tests for `bin/watch-sim.sh`, the launcher `ci_smoke.py` drives.

decisions.md § 716. Two of that entry's three fixes live in the launcher and
neither was pinned by anything: the EXIT trap ended `exit 0` unconditionally, so
every `fatal` reported SUCCESS to whatever launched the sim (`ci_smoke.py` could
only detect a failed launch by an effect that never appeared), and the trap ran
under the script's own `set -e`, where the first best-effort teardown step to
return non-zero abandoned the rest.

Two of the cases below EXECUTE the script, because both of its early refusals
happen before it builds anything or starts an emulator. The rest are source
assertions, for the same reason `ci_smoke.py`'s wedge detector is tested against
a synthetic stream: the states that matter — a teardown reached with a non-zero
status, a `pkill` finding nothing left to sweep, a second sim racing for the
phone port — are precisely the ones a launch cannot be asked to hold.

Run: `python3 -m unittest discover -s apps/custom_watch/sim -p 'test_*.py'`
"""

import re
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
LAUNCHER = REPO_ROOT / "bin" / "watch-sim.sh"


def launch(*args):
    return subprocess.run(
        ["bash", str(LAUNCHER), *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=120,
    )


class LauncherExitStatusTest(unittest.TestCase):
    """A launcher reports its own failure as an exit status, because a
    downstream absence is a symptom and not a diagnosis."""

    def test_an_unknown_argument_exits_non_zero(self):
        res = launch("--definitely-not-a-flag")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("unknown argument", res.stdout + res.stderr)

    def test_a_missing_nmea_fixture_exits_non_zero_before_building_anything(self):
        res = launch("--nmea", "/nonexistent/does-not-exist.nmea")
        self.assertNotEqual(res.returncode, 0)
        combined = res.stdout + res.stderr
        self.assertIn("NMEA fixture not found", combined)
        # The fixture check sits ahead of the cargo build, so this refusal costs
        # no compile — which is what makes it a test rather than a sim run.
        self.assertNotIn("Building firmware", combined)


class CleanupTrapTest(unittest.TestCase):
    def setUp(self):
        self.src = LAUNCHER.read_text()

    def test_the_launcher_is_syntactically_valid_bash(self):
        res = subprocess.run(["bash", "-n", str(LAUNCHER)], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr)

    def test_cleanup_exits_with_the_status_that_is_ending_the_script(self):
        body = self._cleanup_body()
        self.assertIn('exit "$status"', body)
        self.assertNotRegex(body, r"^\s*exit 0\s*$")

    def test_the_status_is_read_before_anything_can_overwrite_it(self):
        body = self._cleanup_body()
        self.assertRegex(body, r'local status="\$\{1:-\$\?\}"')
        # `$?` is clobbered by the first command the teardown runs, so reading
        # it anywhere but the first line reports that command's status instead.
        statements = [
            l.strip()
            for l in body.splitlines()[1:]
            if l.strip() and not l.strip().startswith("#")
        ]
        self.assertTrue(statements[0].startswith("local status="), statements[0])

    def test_teardown_runs_with_errexit_off(self):
        body = self._cleanup_body()
        self.assertIn("set +e", body)
        # `pkill -P $$` returns 1 whenever nothing is left to sweep, which is
        # the common case; under `set -e` it abandoned the rest of the teardown.
        self.assertLess(body.index("set +e"), body.index("pkill -P $$"))

    def test_sigint_is_the_one_signal_that_keeps_its_own_status(self):
        # Ctrl-C is how an interactive stream ends, not how it fails.
        self.assertIn("trap 'cleanup 0' INT", self.src)
        self.assertIn("trap cleanup TERM HUP EXIT", self.src)

    def test_further_signals_are_ignored_rather_than_reset_to_default(self):
        # Resetting would let pnpm's forwarded SIGINT kill the script on that
        # very line, before the Renode kill, orphaning the emulator on the port.
        self.assertIn("trap '' INT TERM HUP", self._cleanup_body())

    def _cleanup_body(self):
        at = self.src.index("cleanup() {")
        end = self.src.index("\n}\n", at)
        return self.src[at:end]


class PortClaimTest(unittest.TestCase):
    """`ss` can only report who held a port a moment ago, and watch.resc binds
    several seconds into the include — so both ports are CLAIMED, not checked."""

    def setUp(self):
        self.src = LAUNCHER.read_text()

    def test_both_ports_take_an_advisory_lock(self):
        self.assertIn("exec 8>", self.src)
        self.assertIn("exec 9>", self.src)
        self.assertRegex(self.src, r"flock -n 8")
        self.assertRegex(self.src, r"flock -n 9")

    def test_the_phone_port_waits_for_a_real_release(self):
        self.assertRegex(self.src, r'flock -w "\$PORT_LOCK_WAIT_S" 8')

    def test_a_host_without_flock_says_the_guarantee_is_weaker(self):
        # macOS ships no flock(1); leaving the weaker guarantee looking like the
        # strong one is the failure this warning exists to prevent.
        self.assertIn("HAVE_FLOCK", self.src)
        self.assertRegex(self.src, r"warn .*flock is not on PATH")

    def test_the_ss_check_stays_after_the_claim(self):
        # For the holder no lock can coordinate with: an orphaned Renode, or an
        # unrelated program on the port.
        self.assertLess(self.src.index("flock -n 8"), self.src.index("PHONE_PORT_HOLDER="))

    def test_a_taken_monitor_port_is_answered_by_drawing_again(self):
        self.assertRegex(self.src, r"flock -n 9 \|\| continue")
        self.assertRegex(self.src, r"could not claim a free Renode monitor port")


class BootDeadlineTest(unittest.TestCase):
    """The boot deadline is a failure bound, not a synchronisation mechanism:
    expiry means something is actually wrong, and the message names the last
    stage the include reached rather than speculating about a stale sim."""

    def setUp(self):
        self.src = LAUNCHER.read_text()
        self.resc = (Path(__file__).resolve().parent / "watch.resc").read_text()

    def test_the_deadline_is_a_bound_a_healthy_boot_cannot_reach(self):
        m = re.search(r'BOOT_TIMEOUT_S="\$\{WATCH_SIM_BOOT_TIMEOUT_S:-(\d+)\}"', self.src)
        self.assertIsNotNone(m, "the boot deadline must stay overridable and named")
        self.assertGreaterEqual(int(m.group(1)), 120)

    def test_a_failed_boot_names_the_last_stage_the_include_reached(self):
        self.assertIn("watch.resc stage: ", self.resc)
        self.assertIn(r"sed -n 's/.*watch\.resc stage: //p'", self.src)


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
