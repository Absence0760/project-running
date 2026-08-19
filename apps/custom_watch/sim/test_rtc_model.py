#!/usr/bin/env python3
"""The sim RTC must charge the CPU's unreported time before it starts counting.

Renode grants the CPU a quantum and folds the executed slice into the clock
source only when the CPU reports. A timer enabled part-way through that slice
is then credited with the whole of it — so RTC1's COUNTER reads non-zero on the
very first read after `TASKS_CLEAR; TASKS_START`, embassy-nrf's
`RtcDriver::init` spin (`while counter != 0 {}`) misses, and it waits for the
24-bit counter to wrap: 2^24 / 32768 = 512 s, longer than any scenario budget.
The firmware never reaches its first log line. Measured on the CI build that
wedged: TASKS_START at virtual time 0.001000000 s, the COUNTER read one
instruction later at 0.001065330 s (issue #788, decisions.md 663).

`SyncCpuTime()` before each counter-mutating task is what stops it, and dropping
it fails only for the builds whose boot happens to land the wrong side of a
30.5 us tick — which is exactly how it survived a week of green local runs. So
it is pinned here rather than left to a scenario.

Runs beside the harness tests (`python3 -m unittest discover -s
apps/custom_watch/sim -p 'test_*.py'`), so it needs no CI wiring of its own.
"""

import unittest
from pathlib import Path

MODEL = Path(__file__).resolve().parent / "NRF52840_RTC_Overflow.cs"

# Every task that moves the counter or its run state. TRIGOVRFLW is here for
# the same reason as the rest: it sets the counter, and a stale slice landing
# after it moves the wrap it exists to schedule.
COUNTER_TASKS = ("TASKS_START", "TASKS_STOP", "TASKS_CLEAR", "TASKS_TRIGOVRFLW")

# What each task callback does to the timers once the sync has happened.
MUTATIONS = ("UpdateTimersEnable(", "timer.Value =", "overflowTimer.Value =")


class RtcCounterSyncTest(unittest.TestCase):
    def setUp(self):
        self.source = MODEL.read_text()

    def register_body(self, task):
        """The register-map entry that defines `task`, up to the next entry."""
        marker = f'name: "{task}"'
        self.assertIn(marker, self.source, f"{task} is not defined in the model")
        start = self.source.rindex("{(long)Register.", 0, self.source.index(marker))
        nxt = self.source.find("{(long)Register.", start + 1)
        return self.source[start:nxt if nxt != -1 else len(self.source)]

    def test_sync_helper_asks_the_bus_for_the_running_cpu(self):
        self.assertIn("machine.SystemBus.TryGetCurrentCPU(out var cpu)", self.source)
        self.assertIn("cpu.SyncTime();", self.source)

    def test_every_counter_task_syncs_before_it_touches_the_timers(self):
        for task in COUNTER_TASKS:
            with self.subTest(task=task):
                body = self.register_body(task)
                self.assertIn(
                    "SyncCpuTime();",
                    body,
                    f"{task} does not sync the CPU's unreported time",
                )
                sync_at = body.index("SyncCpuTime();")
                for mutation in MUTATIONS:
                    at = body.find(mutation)
                    if at == -1:
                        continue
                    self.assertLess(
                        sync_at,
                        at,
                        f"{task} reaches {mutation.strip()} before SyncCpuTime()",
                    )

    def test_a_counter_task_actually_mutates_something(self):
        # Guards the test above from passing vacuously if a callback is gutted.
        for task in COUNTER_TASKS:
            with self.subTest(task=task):
                body = self.register_body(task)
                self.assertTrue(
                    any(m in body for m in MUTATIONS),
                    f"{task} no longer touches the timers — is this test still right?",
                )


if __name__ == "__main__":
    unittest.main()
