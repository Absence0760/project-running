#!/usr/bin/env bash
# Source-level claims about `apps/watch_garmin` that no compiler in this repo
# can make. Runs WITHOUT the Connect IQ SDK — pure text parse — so a Linux
# runner (or this workstation, where `monkeyc` is not installed) can hold the
# Monkey C to its contracts before a watch ever runs it.
#
# The Garmin tier is the least verified thing in the monorepo. No CI job builds
# it, no CI job runs its `(:test)` suite, and until this file existed nothing
# read a line of it except `scripts/check_watch_wire_vectors.mjs`, which pins
# four numbers (the Minetti polynomial, the +/-45% clamp, C(0), and the 5 m
# segment gate) and nothing else. Everything BETWEEN those numbers — the state
# machine that decides which grade they are applied to, the annotations that
# keep test code off the watch, the permissions the runtime enforces and the
# build does not — was unread.
#
# Four claims, each covering a failure that produces no error anywhere:
#
#   1. The grade tracker recovers from a distance rewind, in both of the two
#      ways it can. `Activity.Info.elapsedDistance` restarts at 0 when the
#      recorder resets or discards an activity. With the anchor left at the
#      old total every later run measures NEGATIVE, the `run >= MIN_SEGMENT_M`
#      gate never opens again, and the grade of the discarded activity's last
#      hill is applied to the whole of the next run. Nothing throws, nothing
#      blanks: the cell shows a confident, wrong pace. So `GradeTracker`
#      must re-anchor on a negative run AND `GradeAdjustedPaceView` must
#      override `onTimerReset` to clear it.
#
#   2. Every file under `source-test/` is annotated `(:test)`, and
#      `monkey.jungle` still excludes that annotation. `base.sourcePath`
#      compiles `source-test` into EVERY build; only `base.excludeAnnotations`
#      keeps it off a watch. Drop either and the test code and its fixtures
#      ship — against a per-device memory ceiling in the tens of KB, which is
#      the binding constraint on a Connect IQ app — with a clean build and no
#      warning.
#
#   3. Every Toybox module the source uses that the runtime gates on a
#      permission is declared in the manifest, and every declared permission is
#      used. Calling a gated API without its `<iq:uses-permission>` throws at
#      RUNTIME, on the watch, mid-activity — never at build time. This app
#      deliberately holds no permissions today; `CLAUDE.md` says the sync path
#      will need `Communications`, which is exactly when this claim earns its
#      keep.
#
#   4. The values other rails read out of this file are NAMED, not literals.
#      `scripts/check_watch_wire_vectors.mjs` reads this file by regex, so a
#      constant spelled inline is a rail that cannot be compared however loudly
#      a comment on the far side claims a relationship. That is how the 99:00
#      live-pace ceiling sat at the head of a four-rail chain — firmware GAP,
#      firmware alerts, the phone's WKT1 encoder — with every link enforced
#      except the one it starts at.
#
#   5. Every `Rez.Strings.X` the source loads, and every `@Strings.X` the
#      manifest names, has an entry in `resources/strings/strings.xml` — and
#      every entry is claimed by one of them. A missing entry is a build error
#      the SDK would catch; an ORPHANED entry is not, and it makes the string
#      table a lie about the app's surface.
#
#   6. The unit this field renders its PACE in comes from the runner's pace
#      preference, not their distance one. `DeviceSettings` exposes the two
#      separately and a watch can hold different answers for them, so reading
#      `distanceUnits` shows min/mi to a runner whose watch is set to min/km
#      everywhere else. Both members exist and are the same type, so the wrong
#      one compiles, runs, and is wrong only for the runners who set them apart.
#
#   7. The GAP reference golden is graded through the SHIPPED window. The
#      four-rail fixture bracket (decisions § 1160) freezes eight numbers on
#      each rail and joins them as one spec, so a golden pace is a claim about
#      an algorithm rather than about an arbitrary track. On this rail the
#      reduction that turns the fixture into a pace lives in the (:test) suite
#      rather than in source/, because the field is a streaming estimator with
#      no batch entry point. That is the whole exposure: a reduction that
#      stopped driving a real `GradeTracker`, or that spelled the window as a
#      literal instead of reading `MIN_SEGMENT_M`, would go on reporting 311
#      against a window nothing on this rail uses -- agreeing with the other
#      three about a number while saying nothing about the code.
#
# WHAT THIS DOES NOT PROVE. It parses text. It does not compile Monkey C, does
# not run it, and is not evidence that the app builds or that the GAP numbers
# are right — `source-test/GradeAdjustedPaceTest.mc` makes that claim and has
# never been executed, because the SDK is not installed here. See
# docs/custom_watch/quality_standards.md for the rungs this sits at.
#
# Run: bash apps/watch_garmin/scripts/check_garmin_source.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$DIR" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
failures = []


def fail(msg):
    failures.append(msg)


def read(rel):
    p = root / rel
    if not p.is_file():
        fail("missing file: %s" % rel)
        return ""
    return p.read_text(encoding="utf-8")


def strip_comments(src):
    """Blank out // line comments and /* */ blocks, keeping offsets stable.

    A claim below is about what the code DOES; a sentence in a comment naming
    `onTimerReset` must not satisfy it. Offsets are preserved so a brace scan
    over the result still lines up with the original.
    """
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        if src[i] == '"':
            i += 1
            while i < n and src[i] != '"':
                i += 2 if src[i] == "\\" else 1
            i += 1
            continue
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def body_of(src, signature):
    """The brace-balanced body of the first declaration matching `signature`.

    Brace counting rather than a lazy regex: these bodies contain braces of
    their own and `.*?\\}` stops at the first one.

    The name must END where the signature does. A plain substring search reads
    `function onTimerResetX` as `function onTimerReset` and reports the override
    present when the recorder would call nothing -- which is the same silent
    failure the claim exists to catch, one level up.
    """
    m = re.search(re.escape(signature) + r"(?![A-Za-z0-9_])", src)
    if m is None:
        return None
    at = m.start()
    open_at = src.find("{", at)
    if open_at < 0:
        return None
    depth = 0
    for i in range(open_at, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[open_at + 1:i]
    return None


# --------------------------------------------------------------------------
# 1. The grade tracker recovers from a distance rewind.
# --------------------------------------------------------------------------
gap_raw = read("source/GradeAdjustedPaceView.mc")
gap = strip_comments(gap_raw)

# Vacuity guard: everything below reads this file, so a rename that made the
# reads return nothing would pass silently.
if "class GradeAdjustedPaceView" not in gap:
    fail(
        "source/GradeAdjustedPaceView.mc no longer declares "
        "`class GradeAdjustedPaceView` — every claim below reads it and would "
        "pass on an empty file"
    )

tracker = body_of(gap, "class GradeTracker")
if tracker is None:
    fail(
        "no `class GradeTracker` in source/GradeAdjustedPaceView.mc. The "
        "rolling grade state lives there so it can be reset and unit-tested; "
        "folding it back into the view's private fields removes the only "
        "handle `onTimerReset` has on it."
    )
else:
    on_sample = body_of(tracker, "function onSample")
    if on_sample is None:
        fail("GradeTracker declares no `onSample` — nothing feeds the grade")
    elif not re.search(r"\brun\s*<\s*0(?:\.0)?\b", on_sample):
        fail(
            "GradeTracker.onSample has no negative-run branch. "
            "`Activity.Info.elapsedDistance` rewinds to 0 on an activity reset "
            "or discard; without re-anchoring on it the `run >= MIN_SEGMENT_M` "
            "gate never opens again and the field applies the discarded "
            "activity's last measured grade to the whole of the next run, as a "
            "confident number, with nothing reporting it."
        )
    else:
        # Re-anchoring means BOTH anchors move. Moving one leaves the pair
        # describing two different points and the next measured grade is
        # nonsense rather than merely stale.
        rewind = on_sample[re.search(r"\brun\s*<\s*0(?:\.0)?\b", on_sample).start():]
        rewind = rewind[: rewind.find("}") + 1] if "}" in rewind else rewind
        for field in ("mLastDistance", "mLastAltitude"):
            if not re.search(r"\b%s\s*=" % field, rewind):
                fail(
                    "GradeTracker.onSample's negative-run branch does not "
                    "re-anchor `%s`. Both anchors must move together or the "
                    "next segment is measured between two unrelated points." % field
                )

    reset_body = body_of(tracker, "function reset")
    if reset_body is None:
        fail("GradeTracker declares no `reset()` — `onTimerReset` has nothing to call")
    else:
        for field in ("mLastDistance", "mLastAltitude", "mGrade"):
            if not re.search(r"\b%s\s*=" % field, reset_body):
                fail(
                    "GradeTracker.reset() does not clear `%s`. Clearing the "
                    "grade alone leaves the anchor parked at the discarded "
                    "activity's distance total, which reproduces exactly the "
                    "freeze this reset exists to prevent." % field
                )

view = body_of(gap, "class GradeAdjustedPaceView")
if view is not None:
    timer_reset = body_of(view, "function onTimerReset")
    if timer_reset is None:
        fail(
            "GradeAdjustedPaceView does not override `onTimerReset`. The "
            "recorder calls it when the runner resets or discards an activity; "
            "without it the field carries the discarded run's grade into the "
            "next one."
        )
    elif not re.search(r"\.reset\s*\(", timer_reset):
        fail(
            "GradeAdjustedPaceView.onTimerReset does not call the tracker's "
            "`reset()`, so the override is inert."
        )

# --------------------------------------------------------------------------
# 2. Test sources are annotated, and the build still excludes the annotation.
# --------------------------------------------------------------------------
jungle = read("monkey.jungle")
if not re.search(r"^\s*base\.excludeAnnotations\s*=\s*(.*)$", jungle, re.M):
    fail(
        "monkey.jungle declares no `base.excludeAnnotations`. `base.sourcePath` "
        "compiles source-test into EVERY build; the annotation exclusion is the "
        "only thing keeping the test code and its fixtures off a watch whose "
        "memory ceiling is tens of KB."
    )
else:
    excluded = {
        a.strip()
        for a in re.search(r"^\s*base\.excludeAnnotations\s*=\s*(.*)$", jungle, re.M)
        .group(1)
        .split(";")
    }
    if "test" not in excluded:
        fail(
            "monkey.jungle's base.excludeAnnotations does not exclude `test` "
            "(%s) — the (:test) suite would ship to the watch" % sorted(excluded)
        )

source_path = re.search(r"^\s*base\.sourcePath\s*=\s*(.*)$", jungle, re.M)
paths = {p.strip() for p in source_path.group(1).split(";")} if source_path else set()
test_dir = root / "source-test"
test_files = sorted(test_dir.glob("*.mc")) if test_dir.is_dir() else []
if test_files and "source-test" not in paths:
    fail(
        "source-test/ holds %d Monkey C file(s) but monkey.jungle's "
        "base.sourcePath does not list it, so `monkeyc --unit-test` compiles "
        "none of them and the suite reports zero tests rather than failing"
        % len(test_files)
    )
for f in test_files:
    if "(:test)" not in f.read_text(encoding="utf-8"):
        fail(
            "source-test/%s carries no `(:test)` annotation, so "
            "base.excludeAnnotations cannot keep it out of a release build and "
            "it ships to the watch" % f.name
        )

# --------------------------------------------------------------------------
# 3. Permission-gated Toybox modules are declared, and declarations are used.
# --------------------------------------------------------------------------
# Toybox modules whose APIs the Connect IQ runtime refuses without the named
# manifest permission. Deliberately partial: a module absent from this map is
# simply not required to be declared, which is a false negative and never a
# false alarm.
GATED = {
    "Communications": "Communications",
    "Position": "Positions",
    "Sensor": "Sensor",
    "SensorHistory": "SensorHistory",
    "ActivityRecording": "FitContributor",
    "UserProfile": "UserProfile",
    "PersistedContent": "PersistedContent",
    "Background": "Background",
    "Complications": "Complications",
    "Notifications": "Notifications",
}

# XML comments are stripped for the same reason the Monkey C ones are: this
# manifest's own comment spells out the `<iq:uses-permission id="Communications"/>`
# line the sync path will one day need, and a guard that read it would report a
# permission the app does not hold.
manifest = re.sub(r"<!--.*?-->", " ", read("manifest.xml"), flags=re.S)
declared = set(re.findall(r'<iq:uses-permission\s+id="([^"]+)"', manifest))

used = set()
for mc in sorted((root / "source").glob("*.mc")):
    body = strip_comments(mc.read_text(encoding="utf-8"))
    for module, perm in GATED.items():
        if re.search(r"\bimport\s+Toybox\.%s\b" % module, body) or re.search(
            r"\b%s\.[A-Za-z_]" % module, body
        ):
            used.add((module, perm, mc.name))

for module, perm, where in sorted(used):
    if perm not in declared:
        fail(
            "source/%s uses Toybox.%s but manifest.xml declares no "
            '<iq:uses-permission id="%s"/>. The runtime refuses the call on the '
            "watch, mid-activity; the build says nothing." % (where, module, perm)
        )

for perm in sorted(declared - {p for _, p, _ in used}):
    fail(
        'manifest.xml declares <iq:uses-permission id="%s"/> and no source file '
        "uses the module it gates. An unused permission is an install-prompt "
        "line the runner is asked to accept for nothing." % perm
    )

# --------------------------------------------------------------------------
# 4. The cross-rail constants are named, and used by name.
# --------------------------------------------------------------------------
# name -> the magic number it must not be spelled as inline, anywhere in the
# file other than its own declaration.
#
# FLAT_COST is deliberately absent: 3.6 is also the constant term of the
# Minetti polynomial in `costAtGrade`, because C(0) IS that term — the two
# copies are one identity, not a duplication, and every rail spells it twice
# for the same reason. Both halves are independently registered across the
# four rails by `scripts/check_watch_wire_vectors.mjs` (the fit, and C(0)),
# and `flatFactorIsOne` in the (:test) suite pins them equal.
NAMED_CONSTANTS = {
    "MIN_SEGMENT_M": "5.0",
    "MAX_GRADE": "0.45",
    "MIN_SPEED_MPS": "0.4",
    "MAX_PACE_S": "5940.0",
}
for name, literal in sorted(NAMED_CONSTANTS.items()):
    decl = re.search(r"\bconst\s+%s\s*=\s*([^;]+);" % name, gap)
    if decl is None:
        fail(
            "source/GradeAdjustedPaceView.mc declares no `const %s`. Another "
            "rail reads this value by name; spelled inline it cannot be "
            "compared, and a comment on the far side claiming it mirrors this "
            "one is then an instruction rather than an enforcement." % name
        )
        continue
    rest = gap[: decl.start()] + gap[decl.end():]
    if re.search(r"(?<![\w.])%s(?![\d])" % re.escape(literal), rest):
        fail(
            "source/GradeAdjustedPaceView.mc spells `%s` inline somewhere "
            "other than the `const %s` declaration. Use the name: a second "
            "copy is what drifts." % (literal, name)
        )

# --------------------------------------------------------------------------
# 5. String resources: referenced <-> defined, both directions.
# --------------------------------------------------------------------------
strings_xml = read("resources/strings/strings.xml")
defined = set(re.findall(r'<string\s+id="([^"]+)"', strings_xml))
if not defined:
    fail("resources/strings/strings.xml defines no <string> — claim 4 would pass vacuously")

referenced = set(re.findall(r"@Strings\.([A-Za-z_][A-Za-z_0-9]*)", manifest))
for mc in sorted((root / "source").glob("*.mc")):
    body = strip_comments(mc.read_text(encoding="utf-8"))
    referenced |= set(re.findall(r"Rez\.Strings\.([A-Za-z_][A-Za-z_0-9]*)", body))

for name in sorted(referenced - defined):
    fail(
        "`%s` is loaded from the string table but resources/strings/strings.xml "
        "defines no entry for it" % name
    )
for name in sorted(defined - referenced):
    fail(
        "resources/strings/strings.xml defines `%s` and nothing references it — "
        "a string the app cannot show" % name
    )

# --------------------------------------------------------------------------
# 6. The pace unit follows the runner's PACE preference.
# --------------------------------------------------------------------------
# `System.DeviceSettings` carries `paceUnits` and `distanceUnits` as separate
# `UnitsSystem` members (both since API 1.0.0; this app's minApiLevel is 3.1.0,
# so every targeted device has them). They are the same type, so reading the
# wrong one compiles and runs — it is wrong only on a watch where the two
# disagree, which is a real configuration and not one the developer's own watch
# is likely to be in.
if view is not None:
    init = body_of(view, "function initialize")
    if init is None:
        fail(
            "GradeAdjustedPaceView declares no `initialize` — the unit is "
            "resolved once at construction, so there is nowhere else for this "
            "claim to read"
        )
    elif not re.search(r"getDeviceSettings\(\)\s*\.\s*paceUnits", init):
        fail(
            "GradeAdjustedPaceView.initialize does not read "
            "`System.getDeviceSettings().paceUnits`. This cell renders a PACE, "
            "and Garmin exposes the pace and distance unit preferences "
            "separately; a runner who logs distance in miles and reads pace in "
            "min/km gets the wrong unit, with the right-looking number in it."
        )
    if re.search(r"\bdistanceUnits\b", gap):
        fail(
            "source/GradeAdjustedPaceView.mc reads `distanceUnits`. Nothing in "
            "this field is a distance; the label and the divisor are both about "
            "pace, so the pace preference is the one to follow."
        )

# --------------------------------------------------------------------------
# 7. The GAP reference golden is graded through the shipped window.
# --------------------------------------------------------------------------
GAP_REFERENCE_CONSTANTS = (
    "GAP_REFERENCE_POINTS",
    "GAP_REFERENCE_STEP_M",
    "GAP_REFERENCE_STEP_S",
    "GAP_REFERENCE_BASE_GRADE",
    "GAP_REFERENCE_AMPLITUDE_M",
    "GAP_REFERENCE_PERIOD_M",
    "GAP_REFERENCE_S_PER_KM",
    "GAP_REFERENCE_MAX_COST",
)
gap_test = strip_comments(read("source-test/GradeAdjustedPaceTest.mc"))
if re.search(r"\bmodule\s+GradeAdjustedPaceTest\b", gap_test) is None:
    fail(
        "source-test/GradeAdjustedPaceTest.mc no longer declares "
        "`module GradeAdjustedPaceTest` — the claims below read it and would "
        "pass on an empty file"
    )
for name in GAP_REFERENCE_CONSTANTS:
    hits = len(re.findall(r"\bconst\s+%s\s*=\s*[^;]+;" % name, gap_test))
    if hits != 1:
        fail(
            "source-test/GradeAdjustedPaceTest.mc declares `const %s` %d times, "
            "expected once. scripts/check_watch_wire_vectors.mjs joins all eight "
            "GAP_REFERENCE_* values into one spec per rail and compares the "
            "specs; a name it cannot read exactly once takes this rail out of "
            "the comparison rather than failing it." % (name, hits)
        )

walk = body_of(gap_test, "function gapReferenceReportedSPerKm")
if walk is None:
    fail(
        "source-test/GradeAdjustedPaceTest.mc declares no "
        "`gapReferenceReportedSPerKm` — the golden has nothing to grade the "
        "reference track through"
    )
else:
    if not re.search(r"\bnew\s+GradeTracker\s*\(", walk):
        fail(
            "gapReferenceReportedSPerKm does not drive a `GradeTracker`. The "
            "golden's only value is that the fixture is graded through THIS "
            "rail's rolling window; a private copy of the walk would report 311 "
            "whatever the shipped tracker did."
        )
    if not re.search(r"\$\.MIN_SEGMENT_M\b", walk):
        fail(
            "gapReferenceReportedSPerKm does not read `$.MIN_SEGMENT_M`. The "
            "window is the value this golden brackets; spelled as a literal it "
            "would keep reporting 311 after the window moved."
        )

if failures:
    for f in failures:
        print("FAIL: %s" % f, file=sys.stderr)
    sys.exit(1)
print("apps/watch_garmin: source-level checks pass (not compiled — no Connect IQ SDK)")
PY
