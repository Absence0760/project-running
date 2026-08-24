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
    PANEL_NO_BANNER,
    RENODE_HOST_SIDE_NOISE,
    UI_BANNER,
    WEDGE_ISSUE,
    LogTail,
    SmokeFailure,
    last_firmware_stamp,
    monitor_value,
    panel_banner,
    renode_cpu_tail,
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
        self.assertIn(f"issue #{WEDGE_ISSUE}", message)
        # The last line is the diagnostic handle: it carries the firmware
        # timestamp the hang has to be read against.
        self.assertIn("19.000", message)
        self.assertNotIn("no decoded log line matched", message)

    def test_the_message_names_no_closed_issue(self):
        """#754 is CLOSED and describes a different wedge (storm, mid-run at
        t=19.0s). Naming it made every reader dismiss a live boot-time wedge."""
        self.emit("19.000 DEBUG baro: alt=1599.9999m")
        self.tail.poll()
        self.clock.advance(GUEST_WEDGED_S)
        with self.assertRaises(SmokeFailure) as caught:
            self.tail.wait(NEVER, 100_000, "the first measured tendency")
        self.assertNotIn("#754", str(caught.exception))

    def test_the_wedge_reports_the_last_stamped_firmware_clock(self):
        """The observed CI wedge ends on an UNSTAMPED continuation line of
        embassy-nrf's multi-line UICR warning, so quoting only the last line
        drops the one number that says the guest died at boot."""
        self.emit(
            "0.000000 WARN  You have requested enabling chip reset functionality",
            "However, UICR is already programmed to some other setting.",
            "To fix this, erase UICR manually.",
        )
        self.tail.poll()
        self.clock.advance(GUEST_WEDGED_S)
        with self.assertRaises(SmokeFailure) as caught:
            self.tail.wait(NEVER, 100_000, "the first accepted fix")
        message = str(caught.exception)
        self.assertIn("firmware clock last read 0.000000s", message)
        self.assertIn("erase UICR manually", message)

    def test_the_machine_probe_is_folded_into_the_wedge(self):
        self.tail.forensics = lambda: "cpu pc=0x19a08; 0 instructions retired"
        self.emit("19.000 DEBUG baro: alt=1599.9999m")
        self.tail.poll()
        self.clock.advance(GUEST_WEDGED_S)
        with self.assertRaises(SmokeFailure) as caught:
            self.tail.wait(NEVER, 100_000, "the first measured tendency")
        self.assertIn("cpu pc=0x19a08", str(caught.exception))

    def test_a_failing_probe_cannot_swallow_the_wedge(self):
        """The diagnosis must never replace the thing it is diagnosing."""

        def broken():
            raise RuntimeError("monitor socket gone")

        self.tail.forensics = broken
        self.emit("19.000 DEBUG baro: alt=1599.9999m")
        self.tail.poll()
        self.clock.advance(GUEST_WEDGED_S)
        with self.assertRaises(SmokeFailure) as caught:
            self.tail.wait(NEVER, 100_000, "the first measured tendency")
        message = str(caught.exception)
        self.assertIn("WEDGED GUEST", message)
        self.assertIn("the wedge probe itself failed", message)
        self.assertIn("monitor socket gone", message)

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


class MonitorValueTest(unittest.TestCase):
    """The monitor frames nothing, so a command's answer has to be picked out
    of its own echo, the coloured prompt, and the CR/LF the telnet side adds."""

    def test_a_property_read_is_picked_out_of_the_echo_and_prompt(self):
        raw = "sysbus.cpu PC\n\r0x19a08\r\r\n\x1b[33;1m(watch) \x1b[0m"
        self.assertEqual(monitor_value("sysbus.cpu PC", raw), "0x19a08")

    def test_a_command_that_printed_nothing_reads_as_no_answer(self):
        raw = "sysbus.cpu PC\n\r\x1b[33;1m(watch) \x1b[0m"
        self.assertIsNone(monitor_value("sysbus.cpu PC", raw))


class FirmwareStampTest(unittest.TestCase):
    def test_the_newest_stamped_line_wins_over_a_later_continuation(self):
        lines = ["0.000000 WARN  reset pin", "However, UICR is programmed."]
        self.assertEqual(last_firmware_stamp(lines), "0.000000")

    def test_a_stream_with_no_stamp_at_all_claims_none(self):
        self.assertIsNone(last_firmware_stamp(["==> Starting Renode (headless)"]))


class RenodeTailTest(unittest.TestCase):
    def test_the_host_side_uart_noise_is_dropped(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        run_dir = Path(tmp.name)
        (run_dir / "renode.log").write_text(
            "\n".join(
                ["[WARNING] gpio1: Unhandled write to offset 0x20. Tags: LATCH."]
                + [f"[WARNING] uart0: {RENODE_HOST_SIDE_NOISE}. ({n})" for n in range(50)]
            )
        )
        tail = renode_cpu_tail(run_dir)
        self.assertEqual(len(tail), 1)
        self.assertIn("LATCH", tail[0])

    def test_a_session_with_no_run_dir_yet_reports_nothing(self):
        self.assertEqual(renode_cpu_tail(None), [])


class PanelBannerTest(unittest.TestCase):
    """The panel-state read every dump is synchronised on (decisions § 716).

    Hosted here rather than left to a sim run for the same reason the wedge
    detector is: the cases that matter are a stream that has said nothing yet
    and a stream that has moved on since a cursor was taken, and neither is a
    state an emulator can be asked to hold.
    """

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.log = Path(tmp.name) / "sim-output.log"
        self.log.write_text("")
        self.tail = LogTail(self.log)

    def emit(self, *lines):
        with self.log.open("a") as fh:
            fh.write("".join(f"{line}\n" for line in lines))

    def test_a_stream_that_has_never_said_claims_nothing(self):
        self.emit("1.000000 DEBUG ui: page Dashboard")
        self.assertIsNone(panel_banner(self.tail))

    def test_the_newest_line_wins_not_the_first(self):
        self.emit(
            "1.000000 DEBUG ui: banner none",
            "9.000000 DEBUG ui: banner Drink",
            "17.000000 DEBUG ui: banner none",
        )
        self.assertEqual(panel_banner(self.tail), PANEL_NO_BANNER)

    def test_a_cursor_reads_the_state_as_of_that_point(self):
        self.emit("1.000000 DEBUG ui: banner none", "9.000000 DEBUG ui: banner Drink")
        cursor = self.tail.mark()
        self.emit("17.000000 DEBUG ui: banner none")
        self.tail.poll()
        # What the dump was vouched for against, not what has happened since:
        # the difference between the two is the repaint that collided with it.
        self.assertEqual(panel_banner(self.tail, cursor), "Drink")
        self.assertEqual(panel_banner(self.tail), PANEL_NO_BANNER)

    def test_a_repaint_after_the_cursor_is_visible_to_the_caller(self):
        self.emit("9.000000 DEBUG ui: banner Drink")
        cursor = self.tail.mark()
        self.assertIsNone(self.tail.search(UI_BANNER, start=cursor))
        self.emit("17.000000 DEBUG ui: banner none")
        self.tail.poll()
        moved = self.tail.search(UI_BANNER, start=cursor)
        self.assertIsNotNone(moved)
        self.assertEqual(moved.group(1), PANEL_NO_BANNER)


if __name__ == "__main__":
    unittest.main()
