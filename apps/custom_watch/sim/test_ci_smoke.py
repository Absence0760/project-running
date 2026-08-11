#!/usr/bin/env python3
"""Host tests for the sim harness's own logic.

Only the parts that need no emulator. The scenario driver is proved by running
it — that IS the sim job — but the wedge detector cannot be: it fires precisely
when the guest has stopped executing, which is the one state CI cannot script
on demand. So it is tested here against a synthetic stream and an injected
clock.

Run: `python3 -m unittest discover -s apps/custom_watch/sim -p 'test_*.py'`
"""

import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ci_smoke import (  # noqa: E402
    GUEST_WEDGED_S,
    LINE_CADENCE_S,
    LogTail,
    SmokeFailure,
)

NEVER = re.compile(r"a pattern no line will ever carry")


class FakeClock:
    """A monotonic clock the test advances by hand, so a 90 s threshold costs
    no wall time to reach."""

    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


class LogTailWedgeTest(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.log = Path(tmp.name) / "sim-output.log"
        self.log.write_text("")
        self.tail = LogTail(self.log, clock=self.clock)

    def emit(self, *lines):
        with self.log.open("a") as fh:
            for line in lines:
                fh.write(line + "\n")

    def test_a_growing_stream_is_never_silent(self):
        self.emit("1.000 DEBUG baro: alt=1600.0m")
        self.tail.poll()
        self.assertEqual(self.tail.silent_s(), 0.0)
        self.clock.advance(1.0)
        self.emit("2.000 DEBUG baro: alt=1600.0m")
        self.tail.poll()
        self.assertEqual(self.tail.silent_s(), 0.0)

    def test_silence_is_measured_from_the_last_line_not_the_last_poll(self):
        self.emit("1.000 DEBUG baro: alt=1600.0m")
        self.tail.poll()
        self.clock.advance(7.0)
        self.tail.poll()
        self.assertEqual(self.tail.silent_s(), 7.0)

    def test_a_wedged_guest_is_named_before_the_deadline(self):
        self.emit("19.000 DEBUG baro: alt=1599.9999m gain=0.0m loss=0.0m")
        self.tail.poll()
        self.clock.advance(GUEST_WEDGED_S)
        with self.assertRaises(SmokeFailure) as caught:
            self.tail.wait(NEVER, 100_000, "the first measured tendency")
        message = str(caught.exception)
        self.assertIn("WEDGED GUEST", message)
        self.assertIn("issue #754", message)
        # The last line is the diagnostic handle: it carries the firmware
        # timestamp the hang has to be read against.
        self.assertIn("19.000", message)
        self.assertNotIn("no decoded log line matched", message)

    def test_a_wait_too_short_to_reach_the_threshold_still_names_the_wedge(self):
        self.emit("19.000 DEBUG baro: alt=1599.9999m")
        self.tail.poll()
        self.clock.advance(LINE_CADENCE_S)
        with self.assertRaises(SmokeFailure) as caught:
            self.tail.wait(NEVER, 0, "the first measured tendency")
        self.assertIn("WEDGED GUEST", str(caught.exception))

    def test_a_live_stream_that_never_matches_is_still_a_real_failure(self):
        """The other half. A running firmware that genuinely fails a claim must
        keep saying so, or this change would hide real regressions."""
        self.emit("19.000 DEBUG baro: alt=1599.9999m")
        self.tail.poll()
        with self.assertRaises(SmokeFailure) as caught:
            self.tail.wait(NEVER, 0, "the first measured tendency")
        message = str(caught.exception)
        self.assertIn("no decoded log line matched", message)
        self.assertIn("genuinely failed", message)
        self.assertNotIn("WEDGED GUEST", message)

    def test_a_matching_line_still_returns_normally(self):
        self.emit("7.000 INFO baro: storm Building qnh=Some(1016.2459)hPa")
        match = self.tail.wait(re.compile(r"baro: storm (\w+)"), 10, "a tendency")
        self.assertEqual(match.group(1), "Building")


if __name__ == "__main__":
    unittest.main()
