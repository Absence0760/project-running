#!/usr/bin/env python3
"""Host tests for the `dropout` scenario's frozen-distance anchor.

decisions.md § 731. The anchor raced the last real fix's own credit: it passed
locally, where the credited snapshot landed first, and failed on CI where a
`paused` snapshot carrying the pre-fix distance arrived 1 ms after the fix. That
was verified by replaying the two recorded logs through the old and new logic
and nothing was committed, so a regression to the anchor is caught today only by
a live Renode run that may or may not lose the same coin flip.

The reason it has to be pinned here rather than left to the sim job is in the
ADR: with the anchor sampled one fix low, the void's own settled value already
clears `DROPOUT_RESUME_M`, so the re-anchor assertion below it would pass for a
firmware that never re-anchored. A racy anchor produces a false GREEN one
assertion later, and a false green is exactly what an emulator cannot be asked
to reproduce on demand.

Run: `python3 -m unittest discover -s apps/custom_watch/sim -p 'test_*.py'`
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ci_smoke import (  # noqa: E402
    DROPOUT_FIX_CREDIT_SETTLE_S,
    DROPOUT_RESUME_M,
    SmokeFailure,
    void_freeze,
)

# The two recorded timelines § 731 was decided on, as `(t, odometer_m)`
# snapshots strictly inside a void opening at t=86.9s. The last real fix is
# stamped at void_start; its credit takes the odometer from 104.4 m to 110.4 m.
VOID_START = 86.9
VOID_SPAN = 40.0
PRE_FIX_M = 104.4
SETTLED_M = 110.4


def _void_tail(start_t, distance, count=48, step=0.8):
    """The rest of a void: one snapshot per second, odometer unmoving."""
    return [(start_t + i * step, distance) for i in range(1, count + 1)]


# Local: the credit lands in the same millisecond as the fix line.
LOCAL = [(VOID_START + 0.001, SETTLED_M)] + _void_tail(VOID_START + 0.001, SETTLED_M)
# CI (run 32870450327): a `paused` snapshot carrying the pre-fix distance slips
# between the fix line and the credit, 1 ms after the fix.
CI = [(VOID_START + 0.001, PRE_FIX_M), (VOID_START + 0.002, SETTLED_M)] + _void_tail(
    VOID_START + 0.002, SETTLED_M
)


class VoidFreezeTest(unittest.TestCase):
    def test_the_local_timeline_anchors_on_the_settled_distance(self):
        frozen, settled = void_freeze(LOCAL, VOID_START, VOID_SPAN)
        self.assertEqual(frozen, SETTLED_M)
        self.assertGreater(len(settled), 40)

    def test_the_ci_timeline_anchors_on_the_same_distance_as_the_local_one(self):
        """Both runs agreed on the settled distance to the millimetre — which is
        the tell that this was the harness and not the firmware."""
        frozen, settled = void_freeze(CI, VOID_START, VOID_SPAN)
        self.assertEqual(frozen, SETTLED_M)
        self.assertEqual(frozen, void_freeze(LOCAL, VOID_START, VOID_SPAN)[0])

    def test_the_pre_fix_snapshot_is_outside_the_settled_set(self):
        _, settled = void_freeze(CI, VOID_START, VOID_SPAN)
        self.assertTrue(all(t > VOID_START + DROPOUT_FIX_CREDIT_SETTLE_S for t, _ in settled))
        self.assertNotIn(PRE_FIX_M, [d for _, d in settled])

    def test_the_mis_anchor_would_have_been_a_false_green_not_only_a_false_red(self):
        """The anchor is also the baseline the re-anchor check measures
        `DROPOUT_RESUME_M` from. Sampled one fix low, the void's OWN settled
        value clears that threshold before the reacquire happens at all."""
        mis_anchored = CI[0][1]
        self.assertGreaterEqual(SETTLED_M - mis_anchored, DROPOUT_RESUME_M)
        frozen, _ = void_freeze(CI, VOID_START, VOID_SPAN)
        self.assertLess(SETTLED_M - frozen, DROPOUT_RESUME_M)

    def test_creeping_credit_inside_the_void_still_fails(self):
        creeping = CI[:2] + [
            (VOID_START + 2.0 + i, SETTLED_M + 0.1 * i) for i in range(1, 30)
        ]
        with self.assertRaises(SmokeFailure) as caught:
            void_freeze(creeping, VOID_START, VOID_SPAN)
        self.assertIn("inside a void with no fixes in it", str(caught.exception))

    def test_a_far_edge_lump_still_fails(self):
        """A recorder that credited the whole void in one lump at its far edge
        is what the every-snapshot walk exists to catch."""
        lump = CI + [(VOID_START + VOID_SPAN - 0.5, SETTLED_M + 122.0)]
        with self.assertRaises(SmokeFailure) as caught:
            void_freeze(lump, VOID_START, VOID_SPAN)
        self.assertIn("232.4 m", str(caught.exception))

    def test_an_early_lump_inside_the_settle_window_still_fails(self):
        """The settle window is for the last fix's credit arriving, never for a
        lump of the void's own displacement credited early."""
        early = [
            (VOID_START + 0.001, PRE_FIX_M),
            (VOID_START + 0.5, SETTLED_M + 40.0),
            (VOID_START + 1.0, SETTLED_M),
        ] + _void_tail(VOID_START + 1.0, SETTLED_M)
        with self.assertRaises(SmokeFailure) as caught:
            void_freeze(early, VOID_START, VOID_SPAN)
        self.assertIn("above the", str(caught.exception))
        self.assertIn("fix-credit settle window", str(caught.exception))

    def test_a_void_wholly_inside_the_settle_window_claims_nothing(self):
        """Nothing past the window means the frozen distance was never
        observable; reporting it as frozen would vouch for a measurement that
        was not taken."""
        short = [(VOID_START + 0.5, SETTLED_M), (VOID_START + 1.5, SETTLED_M)]
        with self.assertRaises(SmokeFailure) as caught:
            void_freeze(short, VOID_START, VOID_SPAN)
        self.assertIn("never observable", str(caught.exception))

    def test_the_settle_window_is_a_strict_comparison(self):
        """A snapshot landing exactly on the deadline is inside the window, not
        past it — the same strictness `fix_stale` uses one assertion below."""
        boundary = VOID_START + DROPOUT_FIX_CREDIT_SETTLE_S
        with self.assertRaises(SmokeFailure):
            void_freeze([(boundary, SETTLED_M)], VOID_START, VOID_SPAN)
        frozen, settled = void_freeze(
            [(boundary, SETTLED_M), (boundary + 0.001, SETTLED_M)], VOID_START, VOID_SPAN
        )
        self.assertEqual(frozen, SETTLED_M)
        self.assertEqual(len(settled), 1)

    def test_a_drop_inside_the_void_fails_too(self):
        """`moved` is an inequality, not a growth test: an odometer that goes
        DOWN inside a void is no more explicable than one that goes up."""
        dropping = CI[:2] + _void_tail(VOID_START + 0.002, SETTLED_M, count=3) + [
            (VOID_START + 20.0, SETTLED_M - 5.0)
        ]
        with self.assertRaises(SmokeFailure) as caught:
            void_freeze(dropping, VOID_START, VOID_SPAN)
        self.assertIn("105.4 m", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
