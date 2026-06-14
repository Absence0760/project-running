import Toybox.Lang;
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
}
