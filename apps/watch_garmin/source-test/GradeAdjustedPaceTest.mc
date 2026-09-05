import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Unit tests for the Minetti grade-adjusted-pace model in
// source/GradeAdjustedPaceView.mc.
//
// Expected numbers are pinned to the canonical TS<->Dart parity oracle
// (apps/web/src/lib/runs/grade_adjusted_pace.ts and its Dart twin
// apps/mobile_android/lib/grade_adjusted_pace.dart), which use the identical
// polynomial C(i)=155.4 i^5 -30.4 i^4 -43.3 i^3 +46.3 i^2 +19.5 i +3.6 and the
// same +/-45% clamp. The factor numbers below were computed from that
// polynomial; the Connect IQ field MUST agree with the web/mobile surfaces on
// the same inputs.
//
// These functions compile only into a unit-test build (the `test` annotation
// is excluded from release via monkey.jungle). The whole file is host-pure: it
// drives the static helpers (costAtGrade / gradeFactor / gapPace / formatPace),
// so no Activity.Info or simulator sensor feed is required.

(:test)
module GradeAdjustedPaceTest {

    // Float comparison tolerance for the factor/cost assertions. The oracle
    // values carry 6 dp; 1e-4 is comfortably tighter than any meaningful drift
    // yet immune to single-precision rounding on the watch.
    const EPS = 0.0001;

    function approx(logger as Test.Logger, label as String, got as Float, want as Float) as Boolean {
        var d = got - want;
        if (d < 0) { d = -d; }
        if (d > EPS) {
            logger.debug(label + ": got " + got.toString() + " want " + want.toString());
            return false;
        }
        return true;
    }

    // ---- C(0) and the flat baseline ------------------------------------

    // On dead-flat ground the cost is exactly C(0)=3.6 and the factor is 1.0,
    // i.e. GAP == raw pace. This is the load-bearing invariant for the road
    // marathoner: the field must not "correct" flat ground.
    (:test)
    function flatFactorIsOne(logger as Test.Logger) as Boolean {
        var ok = approx(logger, "C(0)", GradeAdjustedPaceView.costAtGrade(0.0), 3.6);
        ok = ok && approx(logger, "factor(0)", GradeAdjustedPaceView.gradeFactor(0.0), 1.0);
        return ok;
    }

    // A raw 5:00/km effort on the flat must read 5:00/km GAP (1000 m / 3.3333
    // m/s = 300 s). No phantom adjustment.
    (:test)
    function flatPaceEqualsRawPace(logger as Test.Logger) as Boolean {
        var speed = 1000.0 / 300.0; // 3.3333 m/s == 5:00/km
        var pace = GradeAdjustedPaceView.gapPace(speed, 0.0, 1000.0);
        Test.assertEqualMessage(pace, "5:00", "flat GAP should equal raw 5:00/km, got " + pace);
        return true;
    }

    // Tiny altitude jitter on genuinely flat ground (a few cm of rise over a
    // long-enough segment) is a sub-1% grade -> factor essentially 1.0, so GAP
    // stays pinned to raw pace. This is the marathoner's "jitter must not
    // manufacture grade" guard. 0.05 m rise over 30 m = 0.167% grade.
    (:test)
    function flatJitterDoesNotMoveGap(logger as Test.Logger) as Boolean {
        var grade = 0.05 / 30.0; // 0.00167
        var f = GradeAdjustedPaceView.gradeFactor(grade);
        // factor must be within ~0.4% of 1.0 (19.5*0.00167/3.6 ~= 0.009)
        if (f < 0.99 || f > 1.011) {
            logger.debug("jitter factor drifted: " + f.toString());
            return false;
        }
        var speed = 1000.0 / 300.0;
        var pace = GradeAdjustedPaceView.gapPace(speed, grade, 1000.0);
        // 300 s scaled by ~1/1.009 -> 297.3 s -> rounds to 4:57, still ~5:00
        Test.assertEqualMessage(pace, "4:57", "flat-jitter GAP should stay ~5:00, got " + pace);
        return true;
    }

    // ---- Steep climbs: GAP faster than raw, by the model's factor --------

    // 10% / 20% / 30% / 45% climb factors, pinned to the oracle. Uphill makes
    // the equivalent flat pace FASTER (factor > 1), so the GAP number is a
    // smaller min:sec.
    (:test)
    function climbFactors(logger as Test.Logger) as Boolean {
        var ok = approx(logger, "factor(0.10)", GradeAdjustedPaceView.gradeFactor(0.10), 1.657837);
        ok = ok && approx(logger, "factor(0.20)", GradeAdjustedPaceView.gradeFactor(0.20), 2.501858);
        ok = ok && approx(logger, "factor(0.30)", GradeAdjustedPaceView.gradeFactor(0.30), 3.494245);
        ok = ok && approx(logger, "factor(0.45)", GradeAdjustedPaceView.gradeFactor(0.45), 5.396115);
        return ok;
    }

    // The factor strictly increases with climb steepness (monotone uphill).
    (:test)
    function climbFactorIsMonotone(logger as Test.Logger) as Boolean {
        var f10 = GradeAdjustedPaceView.gradeFactor(0.10);
        var f20 = GradeAdjustedPaceView.gradeFactor(0.20);
        var f30 = GradeAdjustedPaceView.gradeFactor(0.30);
        var f45 = GradeAdjustedPaceView.gradeFactor(0.45);
        Test.assert(f10 > 1.0);
        Test.assert(f20 > f10);
        Test.assert(f30 > f20);
        Test.assert(f45 > f30);
        return true;
    }

    // Raw 5:00/km up a 10% wall -> GAP 3:01/km (1000 / (3.3333*1.657837) =
    // 180.96 s). The runner is working a 3:01 effort, not the 5:00 the native
    // field shows.
    (:test)
    function climbPaceIsFasterThanRaw(logger as Test.Logger) as Boolean {
        var speed = 1000.0 / 300.0;
        var p10 = GradeAdjustedPaceView.gapPace(speed, 0.10, 1000.0);
        Test.assertEqualMessage(p10, "3:01", "5:00/km up 10% should be 3:01 GAP, got " + p10);
        var p20 = GradeAdjustedPaceView.gapPace(speed, 0.20, 1000.0);
        Test.assertEqualMessage(p20, "2:00", "5:00/km up 20% should be 2:00 GAP, got " + p20);
        var p30 = GradeAdjustedPaceView.gapPace(speed, 0.30, 1000.0);
        Test.assertEqualMessage(p30, "1:26", "5:00/km up 30% should be 1:26 GAP, got " + p30);
        return true;
    }

    // ---- The clamp at +/-45% --------------------------------------------

    // Grades steeper than the Minetti valid range clamp to +/-45%, so a GPS
    // altitude spike can't produce an absurd factor. 50% climb == 45% factor.
    (:test)
    function climbClampsAt45(logger as Test.Logger) as Boolean {
        var f45 = GradeAdjustedPaceView.gradeFactor(0.45);
        var f50 = GradeAdjustedPaceView.gradeFactor(0.50);
        var f200 = GradeAdjustedPaceView.gradeFactor(2.00); // absurd spike
        return approx(logger, "factor(0.50)==factor(0.45)", f50, f45)
            && approx(logger, "factor(2.0)==factor(0.45)", f200, f45)
            && approx(logger, "clamped factor value", f50, 5.396115);
    }

    (:test)
    function descentClampsAtMinus45(logger as Test.Logger) as Boolean {
        var fm45 = GradeAdjustedPaceView.gradeFactor(-0.45);
        var fm50 = GradeAdjustedPaceView.gradeFactor(-0.50);
        var fm200 = GradeAdjustedPaceView.gradeFactor(-2.00);
        return approx(logger, "factor(-0.50)==factor(-0.45)", fm50, fm45)
            && approx(logger, "factor(-2.0)==factor(-0.45)", fm200, fm45)
            && approx(logger, "clamped descent factor value", fm50, 1.120085);
    }

    // ---- Descents: the Minetti sign-change ------------------------------

    // A gentle descent is metabolically CHEAP: factor < 1, so GAP is SLOWER
    // (larger min:sec) than the raw pace -- the screaming-downhill number the
    // native field shows is flattered. -10% -> factor 0.597696.
    (:test)
    function gentleDescentIsCheap(logger as Test.Logger) as Boolean {
        var f = GradeAdjustedPaceView.gradeFactor(-0.10);
        Test.assert(f < 1.0);
        return approx(logger, "factor(-0.10)", f, 0.597696);
    }

    // The cost curve bottoms out around -18% (cheapest possible running grade)
    // and then RISES again on very steep descents (braking is expensive). This
    // sign-change is the heart of the Minetti model. Verify the minimum sits
    // between -10% and -25%, and that -30% costs MORE than -20%, and -45%
    // costs MORE than -30% (back above flat).
    (:test)
    function descentCurveHasMinimumThenRises(logger as Test.Logger) as Boolean {
        var f10 = GradeAdjustedPaceView.gradeFactor(-0.10);
        var f15 = GradeAdjustedPaceView.gradeFactor(-0.15);
        var f20 = GradeAdjustedPaceView.gradeFactor(-0.20);
        var f25 = GradeAdjustedPaceView.gradeFactor(-0.25);
        var f30 = GradeAdjustedPaceView.gradeFactor(-0.30);
        var f45 = GradeAdjustedPaceView.gradeFactor(-0.45);
        // descending into the trough: -10% cheaper than flat, -15%/-20% cheaper still
        Test.assert(f15 < f10);
        Test.assert(f20 < f15);
        // climbing back out of the trough as the descent steepens
        Test.assert(f25 > f20);
        Test.assert(f30 > f25);
        Test.assert(f45 > f30);
        // and very steep descent is back above flat (braking costs > level)
        Test.assertMessage(f45 > 1.0, "factor(-0.45) should exceed 1.0, got " + f45.toString());
        return true;
    }

    // Pin the descent trough factor: the minimum cost is ~0.4948, near -18%.
    (:test)
    function descentTroughIsAboutMinus18(logger as Test.Logger) as Boolean {
        var fMin = GradeAdjustedPaceView.gradeFactor(-0.18);
        // the true minimum is ~0.49480 at -0.1814; -0.18 is within 1e-4 of it
        if (fMin > 0.4960) {
            logger.debug("trough factor too high: " + fMin.toString());
            return false;
        }
        // and it is genuinely lower than its neighbours either side
        Test.assert(fMin < GradeAdjustedPaceView.gradeFactor(-0.10));
        Test.assert(fMin < GradeAdjustedPaceView.gradeFactor(-0.30));
        return true;
    }

    // Raw 5:00/km on a -10% descent -> GAP 8:22/km (1000 / (3.3333*0.597696)
    // = 501.93 s): the easy downhill is worth far less than its raw pace says.
    (:test)
    function descentPaceIsSlowerThanRaw(logger as Test.Logger) as Boolean {
        var speed = 1000.0 / 300.0;
        var p = GradeAdjustedPaceView.gapPace(speed, -0.10, 1000.0);
        Test.assertEqualMessage(p, "8:22", "5:00/km down 10% should be 8:22 GAP, got " + p);
        // at the trough (-20%, factor ~0.5) it's the slowest equivalent pace: 10:00
        var pTrough = GradeAdjustedPaceView.gapPace(speed, -0.20, 1000.0);
        Test.assertEqualMessage(pTrough, "10:00", "5:00/km down 20% should be ~10:00 GAP, got " + pTrough);
        // very steep -45% descent is expensive again -> faster GAP than the trough
        var pSteep = GradeAdjustedPaceView.gapPace(speed, -0.45, 1000.0);
        Test.assertEqualMessage(pSteep, "4:28", "5:00/km down 45% should be 4:28 GAP, got " + pSteep);
        return true;
    }

    // ---- Statute (min/mi) unit path -------------------------------------

    // The same effort with the mile unit: raw 8:00/mi flat == 8:00/mi GAP,
    // and up a 10% wall reads 4:50/mi (1609.344 / (speed*1.657837) = 289.5 s).
    (:test)
    function statutePaceFlatAndClimb(logger as Test.Logger) as Boolean {
        var speed = 1609.344 / 480.0; // 8:00/mi raw
        var flat = GradeAdjustedPaceView.gapPace(speed, 0.0, 1609.344);
        Test.assertEqualMessage(flat, "8:00", "flat statute GAP should be 8:00/mi, got " + flat);
        var climb = GradeAdjustedPaceView.gapPace(speed, 0.10, 1609.344);
        Test.assertEqualMessage(climb, "4:50", "8:00/mi up 10% should be 4:50 GAP, got " + climb);
        var desc = GradeAdjustedPaceView.gapPace(speed, -0.10, 1609.344);
        Test.assertEqualMessage(desc, "13:23", "8:00/mi down 10% should be 13:23 GAP, got " + desc);
        return true;
    }

    // ---- Walk / low-speed threshold -------------------------------------

    // Below MIN_SPEED_MPS (0.4 m/s) the runner is walking/stopped and pace is
    // noise -> "--:--", regardless of grade. Power-hiking a climb at 0.3 m/s
    // must NOT emit a garbage GAP.
    (:test)
    function belowWalkThresholdIsBlank(logger as Test.Logger) as Boolean {
        Test.assertEqual(GradeAdjustedPaceView.gapPace(0.39, 0.0, 1000.0), "--:--");
        Test.assertEqual(GradeAdjustedPaceView.gapPace(0.30, 0.20, 1000.0), "--:--");
        Test.assertEqual(GradeAdjustedPaceView.gapPace(0.0, 0.0, 1000.0), "--:--");
        return true;
    }

    // Just above the threshold the field computes a (very slow) real pace, not
    // a blank. 0.41 m/s flat -> 1000/0.41 = 2439 s -> 40:39/km.
    (:test)
    function justAboveWalkThresholdComputes(logger as Test.Logger) as Boolean {
        var pace = GradeAdjustedPaceView.gapPace(0.41, 0.0, 1000.0);
        Test.assertEqualMessage(pace, "40:39", "0.41 m/s flat should compute 40:39, got " + pace);
        return true;
    }

    // ---- formatPace guards: ceiling, rounding, divide-by-zero -----------

    // The formatter caps at 99:00 (5940 s): anything slower is rendered as
    // "--:--" rather than a 3-digit-minute string the native cell can't show.
    (:test)
    function formatPaceCeiling(logger as Test.Logger) as Boolean {
        Test.assertEqual(GradeAdjustedPaceView.formatPace(5940.0), "99:00");
        Test.assertEqual(GradeAdjustedPaceView.formatPace(5941.0), "--:--");
        Test.assertEqual(GradeAdjustedPaceView.formatPace(5939.0), "98:59");
        return true;
    }

    // Seconds zero-pad; minutes don't. 65 s -> 1:05, 9 s -> 0:09, 600 s -> 10:00.
    (:test)
    function formatPacePadsSeconds(logger as Test.Logger) as Boolean {
        Test.assertEqual(GradeAdjustedPaceView.formatPace(65.0), "1:05");
        Test.assertEqual(GradeAdjustedPaceView.formatPace(9.0), "0:09");
        Test.assertEqual(GradeAdjustedPaceView.formatPace(600.0), "10:00");
        Test.assertEqual(GradeAdjustedPaceView.formatPace(0.0), "0:00");
        return true;
    }

    // Rounding is to the nearest second (Math.round), so 119.4 -> 1:59 and
    // 119.6 -> 2:00.
    (:test)
    function formatPaceRoundsToNearestSecond(logger as Test.Logger) as Boolean {
        Test.assertEqual(GradeAdjustedPaceView.formatPace(119.4), "1:59");
        Test.assertEqual(GradeAdjustedPaceView.formatPace(119.6), "2:00");
        return true;
    }

    // ---- GradeTracker: the rolling state machine ------------------------

    // The grade only rolls forward once MIN_SEGMENT_M of horizontal travel
    // has been covered. Anything shorter is GPS-altitude jitter, and the
    // whole reason the anchor exists is that a 1 m wobble over a 1 m step
    // reads as a 100% wall.
    (:test)
    function trackerHoldsGradeUntilASegmentIsCovered(logger as Test.Logger) as Boolean {
        // Distances are stated as fractions of the window rather than as
        // literals, so widening it cannot leave a stale sub-gate sample
        // reading as an above-gate one. What the window may BE is a separate
        // question, pinned by theWindowIsLongerThanTheNoiseFloor below.
        var seg = $.MIN_SEGMENT_M;
        var t = new GradeTracker();
        t.onSample(0.0, 100.0);       // seeds the anchor, no grade yet
        Test.assertEqualMessage(t.grade(), 0.0, "seed sample must not set a grade");
        t.onSample(seg * 0.15, 103.0);  // under the gate, ignored
        Test.assertEqualMessage(t.grade(), 0.0, "a sub-window run is jitter, not a wall");
        t.onSample(seg, 100.0 + seg * 0.10);   // one window, +10% grade
        return approx(logger, "grade after a real segment", t.grade(), 0.10);
    }

    // The clamp applies to the measured grade too, not only to the factor:
    // a GPS altitude spike over a short-but-qualifying segment must not
    // store a grade the Minetti fit was never defined for.
    (:test)
    function trackerClampsAMeasuredSpike(logger as Test.Logger) as Boolean {
        // `$.` is the global scope the file-level consts in
        // GradeAdjustedPaceView.mc live in; reading the constant rather than
        // restating 0.45 keeps this test honest if the clamp ever moves.
        var maxG = $.MAX_GRADE;
        var seg = $.MIN_SEGMENT_M;
        var t = new GradeTracker();
        t.onSample(0.0, 100.0);
        // A rise of five windows' worth over one window: a 500% grade.
        t.onSample(seg, 100.0 + seg * 5.0);
        Test.assertEqualMessage(t.grade(), maxG, "a measured spike must clamp to MAX_GRADE");
        var t2 = new GradeTracker();
        t2.onSample(0.0, 100.0);
        t2.onSample(seg, 100.0 - seg * 5.0);
        Test.assertEqualMessage(t2.grade(), 0.0 - maxG, "a downward spike must clamp to -MAX_GRADE");
        return true;
    }

    // The defect this class was extracted for. `elapsedDistance` restarts at
    // 0 when the recorder resets or discards an activity. With the anchor
    // still parked at the old total, every later run measures NEGATIVE, so
    // the `run >= MIN_SEGMENT_M` gate never opens again and the grade of the
    // discarded activity's last hill is applied to the whole of the next
    // run -- silently, as a confident number.
    (:test)
    function trackerRecoversFromADistanceRewind(logger as Test.Logger) as Boolean {
        var seg = $.MIN_SEGMENT_M;
        var t = new GradeTracker();
        t.onSample(0.0, 100.0);
        t.onSample(seg, 100.0 + seg * 0.30);   // 30% climb
        if (!approx(logger, "grade before the reset", t.grade(), 0.30)) { return false; }

        t.onSample(0.0, 106.0);       // the reset: distance rewinds
        Test.assertEqualMessage(
            t.grade(), 0.0,
            "a distance rewind must drop the discarded activity's grade, got " + t.grade().toString());

        // and the tracker must be able to measure again immediately, not
        // after re-covering the whole discarded distance.
        t.onSample(seg, 106.0 - seg * 0.10);   // one window, -10%
        return approx(logger, "grade measured after the rewind", t.grade(), -0.10);
    }

    // `reset()` is what the field's onTimerReset calls. It must clear the
    // anchors as well as the grade: clearing only the grade would leave the
    // anchor at the old total and reproduce the rewind bug exactly.
    (:test)
    function trackerResetClearsAnchorsNotJustTheGrade(logger as Test.Logger) as Boolean {
        var seg = $.MIN_SEGMENT_M;
        var t = new GradeTracker();
        t.onSample(1000.0, 100.0);
        t.onSample(1000.0 + seg, 100.0 + seg * 0.30);  // 30% climb, anchor moves
        Test.assert(t.grade() > 0.2);

        t.reset();
        Test.assertEqualMessage(t.grade(), 0.0, "reset must clear the grade");

        // A fresh activity starts at 0 again. If reset had left the anchor at
        // the old total the first sample below would measure a large negative
        // run and the second would still be under the gate; with the anchors
        // cleared the first seeds and the second measures.
        t.onSample(0.0, 200.0);
        t.onSample(seg, 200.0 + seg * 0.10);
        return approx(logger, "grade after reset then a fresh segment", t.grade(), 0.10);
    }

    // Flat ground with no altitude change stays at exactly 0.0 however many
    // segments go by -- the marathoner's "the field must not invent a grade"
    // guard, at the state-machine level rather than the polynomial's.
    (:test)
    function trackerStaysFlatOnLevelGround(logger as Test.Logger) as Boolean {
        var t = new GradeTracker();
        var d = 0.0;
        // Step a whole window at a time, so the gate opens on every sample and
        // the loop actually exercises twenty accepted segments rather than
        // twenty rejected ones -- a step under the window would pass this test
        // by never measuring anything at all.
        for (var i = 0; i < 20; i += 1) {
            t.onSample(d, 42.0);
            d += $.MIN_SEGMENT_M;
        }
        Test.assertEqualMessage(t.grade(), 0.0, "level ground must measure exactly 0.0");
        return true;
    }

    // A run of exactly MIN_SEGMENT_M qualifies (the gate is `>=`), and the
    // anchor advances with it -- so the next segment is measured from the
    // new point, not from the original one.
    (:test)
    function trackerAnchorAdvancesOnEachAcceptedSegment(logger as Test.Logger) as Boolean {
        var seg = $.MIN_SEGMENT_M;
        var t = new GradeTracker();
        t.onSample(0.0, 0.0);
        t.onSample(seg, seg * 0.20);  // exactly at the gate -> 20%
        if (!approx(logger, "grade at exactly MIN_SEGMENT_M", t.grade(), 0.20)) { return false; }
        // Use an asymmetric second leg so the two answers differ: from the
        // advanced anchor at (seg, seg*0.2) a sample at (2*seg, seg*0.2) is a
        // flat 0%, while from a stuck anchor at (0, 0) it would read 10%.
        t.onSample(seg * 2.0, seg * 0.20);
        return approx(logger, "grade from the advanced anchor", t.grade(), 0.0);
    }

    // The finding this window's value exists to answer, stated as the
    // relationship rather than as the number. The other three rails gate
    // elevation GAIN at 3 m -- a smaller change is not treated as climb at all
    // -- so the largest altitude change the app throws away as noise, taken
    // over the shortest run a grade is measured across, must not read as a
    // wall.
    //
    // At the 5 m this field shipped with, 3 m of noise was a 0.60 grade -- past
    // MAX_GRADE, so it clamped, and the factor was 5.396: a pace 5.4x faster
    // than raw off a rise nothing else is willing to call climb. That is worst
    // on a Forerunner with no barometric altimeter, where Activity.Info's
    // altitude is GPS altitude and the noise is metres. Nothing gates the rise
    // and nothing can -- a threshold big enough to suppress that noise
    // suppresses every real grade below threshold/window with it.
    //
    // The 3.0 here is a literal because Monkey C has no route_simplify to read
    // it from; the value it mirrors is registered across the other three rails
    // in scripts/check_watch_wire_vectors.mjs as the elevation-gain noise gate,
    // and MIN_SEGMENT_M itself is held equal across all four by the same file.
    (:test)
    function theWindowIsLongerThanTheNoiseFloor(logger as Test.Logger) as Boolean {
        var noiseFloorM = 3.0;
        var noiseFloorGrade = noiseFloorM / $.MIN_SEGMENT_M;
        Test.assertMessage(
            noiseFloorGrade < $.MAX_GRADE,
            "a window of " + $.MIN_SEGMENT_M.toString() + " m makes the " +
                noiseFloorM.toString() + " m noise floor a " +
                noiseFloorGrade.toString() +
                " grade, past the steepest the Minetti fit is defined at");
        var f = GradeAdjustedPaceView.gradeFactor(noiseFloorGrade);
        Test.assertMessage(
            f < 2.1,
            "the noise floor alone must not more than double the reported " +
                "effort; it multiplies it by " + f.toString());
        return true;
    }

    // ---- Sanity: factor sign relative to flat across the whole range -----

    // Uphill is always >= flat cost; the gentle-descent band is always < flat;
    // a no-information call (factor exactly 1) only happens at grade 0. This
    // codifies the qualitative shape the personas rely on.
    (:test)
    function factorSignsAcrossRange(logger as Test.Logger) as Boolean {
        // every climb sampled is harder than flat
        var climbs = [0.02, 0.05, 0.10, 0.20, 0.30, 0.45];
        for (var i = 0; i < climbs.size(); i += 1) {
            var f = GradeAdjustedPaceView.gradeFactor(climbs[i]);
            Test.assertMessage(f > 1.0, "climb " + climbs[i].toString() + " factor " + f.toString() + " should exceed 1");
        }
        // the gentle-descent band (-5%..-30%) is cheaper than flat
        var descents = [-0.05, -0.10, -0.15, -0.20, -0.25, -0.30];
        for (var j = 0; j < descents.size(); j += 1) {
            var fd = GradeAdjustedPaceView.gradeFactor(descents[j]);
            Test.assertMessage(fd < 1.0, "descent " + descents[j].toString() + " factor " + fd.toString() + " should be below 1");
        }
        return true;
    }

    // ---- The GAP reference track: the fourth rail of the window bracket ---

    // A clean, noise-free 6% climb switchbacking +/-8 m every 150 m, walked at
    // 5 m every 3 s for 3 km -- the 30-minute power-hike-paced staircase
    // decisions § 992 measured the window's cost on, and the profile that
    // binds its UPPER end. The other end is theWindowIsLongerThanTheNoiseFloor
    // above, which is a floor and only a floor: it admits nothing under
    // 19.40 m and would pass at 200 m, a window long enough to average real
    // terrain flat. Points sit on a line of constant latitude, where the
    // haversine collapses exactly to R * dLambda, so the per-pair horizontal
    // step below is a closed form rather than a distance function this rail
    // does not have.
    //
    // The eight constants are frozen identically on the three rails that own a
    // batch grader -- grade_adjusted_pace.test.ts, grade_adjusted_pace_test.dart
    // and the firmware's grade_adjusted_pace.rs -- and compared between them by
    // scripts/check_watch_wire_vectors.mjs, which reads all eight out of each.
    // A fixture that drifts on one rail makes its golden meaningless rather
    // than wrong, which is the failure nothing would otherwise report
    // (decisions § 641).
    //
    // This rail is the fourth, and it joins on different terms. The field is a
    // STREAMING estimator: it reports an instantaneous pace once a second and
    // has no batch entry point to grade a track through, so the reduction below
    // lives in the test rather than in source/. What it still buys is what the
    // bracket is for -- the SAME track, driven through THIS rail's own
    // GradeTracker window and its own Minetti factor, must reduce to the same
    // 311 s/km, so a window, a clamp or a polynomial coefficient that moved
    // here fails against a golden the other three share. What it does NOT pin
    // is the per-second value the cell renders; the tracker tests above are
    // what cover that.
    const GAP_REFERENCE_POINTS = 601;
    const GAP_REFERENCE_STEP_M = 5.0;
    const GAP_REFERENCE_STEP_S = 3;
    const GAP_REFERENCE_BASE_GRADE = 0.06;
    const GAP_REFERENCE_AMPLITUDE_M = 8.0;
    const GAP_REFERENCE_PERIOD_M = 150.0;
    const GAP_REFERENCE_S_PER_KM = 311;
    const GAP_REFERENCE_MAX_COST = 0.03;

    // R * dLambda at the equator for one nominal 5 m step: 4.994382 m, not
    // 5 -- which is why the window's measured upper edge is 24.97 m rather
    // than 25. The walk closes a segment on the first pair that CLEARS the
    // window, so what is really bounded is the effective segment.
    function gapReferenceHorizStepM() as Numeric {
        return (6371000.0 * ((GAP_REFERENCE_STEP_M / 111320.0) * Math.PI)) / 180.0;
    }

    // The profile is parameterised on the NOMINAL x = i * 5 m, exactly as the
    // three sibling fixtures are; the horizontal step above is what the walk
    // measures across. Keeping both is what makes the four goldens comparable.
    function gapReferenceElevation(i as Number, amplitudeM as Numeric, baseGrade as Numeric) as Numeric {
        var x = i * GAP_REFERENCE_STEP_M;
        return 100.0 + baseGrade * x
            + amplitudeM * Math.sin((2.0 * Math.PI * x) / GAP_REFERENCE_PERIOD_M);
    }

    // Feed the fixture to a real GradeTracker one sample at a time -- which is
    // how the recorder feeds the field -- and credit each closed window its
    // horizontal length times the factor the tracker's own grade earns it.
    // The walk re-anchors on the same condition the tracker does, so the grade
    // read back is always the window that just closed.
    function gapReferenceReportedSPerKm(amplitudeM as Numeric, baseGrade as Numeric) as Number {
        var step = gapReferenceHorizStepM();
        var t = new GradeTracker();
        var anchor = 0;
        var adjDistM = 0.0;
        var timeS = 0.0;
        t.onSample(0.0, gapReferenceElevation(0, amplitudeM, baseGrade));
        for (var i = 1; i < GAP_REFERENCE_POINTS; i += 1) {
            t.onSample(i * step, gapReferenceElevation(i, amplitudeM, baseGrade));
            var segHoriz = (i - anchor) * step;
            if (segHoriz >= $.MIN_SEGMENT_M) {
                adjDistM += segHoriz * GradeAdjustedPaceView.gradeFactor(t.grade());
                timeS += (i - anchor) * GAP_REFERENCE_STEP_S;
                anchor = i;
            }
        }
        return Math.round(timeS / (adjDistM / 1000.0)).toNumber();
    }

    // The same walk with no window at all: every point pair graded on its own
    // rise over its own run. This is what the runner actually spent, and what
    // a window can only approximate -- a window wider than the terrain averages
    // the climbs and the drops together and hands back a flatter course than
    // the one underfoot.
    function gapReferenceTruthSPerKm() as Numeric {
        var step = gapReferenceHorizStepM();
        var adjDistM = 0.0;
        for (var i = 1; i < GAP_REFERENCE_POINTS; i += 1) {
            var rise = gapReferenceElevation(i, GAP_REFERENCE_AMPLITUDE_M, GAP_REFERENCE_BASE_GRADE)
                - gapReferenceElevation(i - 1, GAP_REFERENCE_AMPLITUDE_M, GAP_REFERENCE_BASE_GRADE);
            adjDistM += step * GradeAdjustedPaceView.gradeFactor(rise / step);
        }
        return ((GAP_REFERENCE_POINTS - 1) * GAP_REFERENCE_STEP_S) / (adjDistM / 1000.0);
    }

    // Ties the closed form to the reduction: with no oscillation and no base
    // grade every factor is exactly 1, so the walk must report the raw pace
    // that step implies (601 s/km). Without this the truth below would be
    // graded against a distance nothing had checked. The web twin ties the
    // same closed form to its own haversine; this rail has none to tie it to,
    // because Garmin hands the field `Activity.Info.elapsedDistance` rather
    // than coordinates -- so what is pinned here is the reduction, not a
    // distance function.
    (:test)
    function gapReferenceGeometryIsRawPaceWhenFlat(logger as Test.Logger) as Boolean {
        var step = gapReferenceHorizStepM();
        var timeS = (GAP_REFERENCE_POINTS - 1) * GAP_REFERENCE_STEP_S;
        var horizM = step * (GAP_REFERENCE_POINTS - 1);
        var want = Math.round(timeS / (horizM / 1000.0)).toNumber();
        var got = gapReferenceReportedSPerKm(0.0, 0.0);
        Test.assertEqualMessage(
            got, want,
            "a level reference walk must report the raw pace the step implies: got "
                + got.toString() + ", want " + want.toString());
        return true;
    }

    // Measured on this fixture, reported against truth 302.611 s/km:
    //   5 m -> 304 (-0.46%)   15 m -> 308 (-1.78%)   20 m -> 311 (-2.77%)
    //   25 m -> 316 (-4.42%)  30 m -> 322 (-6.41%)   200 m -> 426 (-40.78%)
    // so this test and theWindowIsLongerThanTheNoiseFloor together admit only
    // [19.40 m, 24.97 m] on this rail, the same bracket the other three carry.
    (:test)
    function gapReferenceTrackGradesToTheFrozenPace(logger as Test.Logger) as Boolean {
        var truth = gapReferenceTruthSPerKm();
        var reported = gapReferenceReportedSPerKm(
            GAP_REFERENCE_AMPLITUDE_M, GAP_REFERENCE_BASE_GRADE);
        var cost = (reported - truth) / truth;
        if (cost < 0) { cost = -cost; }
        Test.assertMessage(
            cost < GAP_REFERENCE_MAX_COST,
            "a " + $.MIN_SEGMENT_M.toString() + " m window reports " + reported.toString()
                + " s/km against a true " + truth.toString()
                + " s/km on the reference switchback -- too much of the climb averaged away");
        Test.assertEqualMessage(
            reported, GAP_REFERENCE_S_PER_KM,
            "the reference track no longer grades to its frozen value: the window, "
                + "the fixture or the Minetti fit moved on this rail. Re-measure the "
                + "cost against truth before updating this number, and update the web, "
                + "Dart and firmware rails with it. Got " + reported.toString());
        return true;
    }
}
