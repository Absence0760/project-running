#!/usr/bin/env python3
"""The panic handler's Watch dump has to list every Watch, or it lies by omission.

`state::dump_watches` names its statics one by one — there is no way to iterate
them in `no_std` Rust — so a `Watch` added to `state.rs` and not added to the
macro's list simply never appears in a panic dump. The omission is invisible:
the dump still prints, still looks complete, and the missing one is exactly the
one nobody thought about.

Runs beside the harness tests (`python3 -m unittest discover -s
apps/custom_watch/sim -p 'test_*.py'`), so it needs no CI wiring of its own.
"""

import re
import unittest
from pathlib import Path

STATE_RS = Path(__file__).resolve().parents[1] / "app" / "src" / "state.rs"

# `pub static NAME: Watch<`, allowing the generic list to wrap onto the next
# line as WORKOUT's does.
DECLARED = re.compile(r"^pub static ([A-Z0-9_]+): Watch<", re.MULTILINE)


class WatchDumpCoverageTest(unittest.TestCase):
    def setUp(self):
        self.source = STATE_RS.read_text()

    def dumped(self):
        start = self.source.index("watch_dump!(")
        end = self.source.index(");", start)
        body = self.source[start + len("watch_dump!(") : end]
        return {n.strip() for n in body.split(",") if n.strip()}

    def test_every_watch_is_dumped(self):
        declared = set(DECLARED.findall(self.source))
        # Guard the guard: if the regex stops matching, an empty set would make
        # every assertion below vacuously true.
        self.assertGreater(len(declared), 30, "the Watch declaration regex stopped matching")
        missing = declared - self.dumped()
        self.assertEqual(
            missing,
            set(),
            f"these Watches are declared but absent from watch_dump!: {sorted(missing)}",
        )

    def test_the_dump_lists_nothing_that_does_not_exist(self):
        stale = self.dumped() - set(DECLARED.findall(self.source))
        self.assertEqual(
            stale,
            set(),
            f"watch_dump! names statics that are no longer Watches: {sorted(stale)}",
        )


if __name__ == "__main__":
    unittest.main()
