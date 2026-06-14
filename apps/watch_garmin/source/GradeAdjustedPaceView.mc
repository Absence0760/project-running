import Toybox.Activity;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Grade-adjusted pace (GAP): the pace you would be running on flat ground
// for the same metabolic effort you're spending on the current grade.
// Garmin's native fields show raw pace, which lies on hills -- a 5:00/km
// effort up a 10% wall reads slow and a screaming descent reads fast. This
// field corrects for that, which is the single most-requested thing ultra
// and trail runners want that Garmin's first-party UI doesn't surface well.
//
// Energy-cost model: Minetti et al. 2002, "Energy cost of walking and
// running at extreme uphill and downhill slopes" (J Appl Physiol 93:1039).
// C(i) is the metabolic cost of running at gradient i (rise/run, fractional);
// the GAP factor is C(i)/C(0), i.e. how much harder this grade is than flat.

// Flat-ground running cost, C(0), from the polynomial below. Module-level so
// the static pure helpers (testable without an Activity.Info) can read it.
const FLAT_COST = 3.6;

// Minetti's model is only fit between roughly -45% and +45% grade; clamp to
// that so a momentary GPS altitude spike can't produce an absurd factor.
const MAX_GRADE = 0.45;

// Below this speed the runner is walking / stopped and pace is noise.
const MIN_SPEED_MPS = 0.4;

// Need at least this much horizontal travel before trusting a new grade
// sample -- GPS altitude is jittery, so we measure grade over a segment,
// not point-to-point.
const MIN_SEGMENT_M = 5.0;

class GradeAdjustedPaceView extends WatchUi.SimpleDataField {

    private var mLastAltitude as Float or Null = null;
    private var mLastDistance as Float or Null = null;
    private var mGrade as Float = 0.0;
    private var mMetric as Boolean = true;

    function initialize() {
        SimpleDataField.initialize();
        label = WatchUi.loadResource(Rez.Strings.FieldLabel) as String;
        mMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
    }

    // Called once per second by the activity recorder.
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        var speed = info.currentSpeed;
        if (speed == null || speed < MIN_SPEED_MPS) {
            return "--:--";
        }

        updateGrade(info);

        var unitMeters = mMetric ? 1000.0 : 1609.344;
        return gapPace(speed, mGrade, unitMeters);
    }

    // The whole speed -> grade-adjusted-pace pipeline as one pure function so
    // it can be unit-tested without an Activity.Info (which only the simulator
    // can construct). compute() is now just "read sensors, then call this".
    // Returns the formatted pace string, or "--:--" when the input is unusable.
    static function gapPace(speed as Float, grade as Float, unitMeters as Float) as String {
        if (speed < MIN_SPEED_MPS) {
            return "--:--";
        }
        var gapSpeed = speed * gradeFactor(grade); // equivalent flat-ground speed, m/s
        if (gapSpeed <= 0.0) {
            return "--:--";
        }
        return formatPace(unitMeters / gapSpeed);
    }

    // Cost multiplier relative to flat ground, with the grade clamped to
    // Minetti's valid range first (a momentary GPS-altitude spike can't
    // manufacture an absurd factor). 1.0 on the flat, > 1 uphill, < 1 on
    // gentle descents, rising back above 1 on very steep descents.
    static function gradeFactor(grade as Float) as Float {
        var g = grade;
        if (g > MAX_GRADE) { g = MAX_GRADE; }
        if (g < -MAX_GRADE) { g = -MAX_GRADE; }
        return costAtGrade(g) / FLAT_COST;
    }

    // Roll the grade estimate forward only when we've covered a real segment.
    private function updateGrade(info as Activity.Info) as Void {
        var dist = info.elapsedDistance;
        var alt = info.altitude;
        if (dist == null || alt == null) {
            return;
        }
        if (mLastDistance == null || mLastAltitude == null) {
            mLastDistance = dist;
            mLastAltitude = alt;
            return;
        }
        var run = dist - mLastDistance;
        if (run >= MIN_SEGMENT_M) {
            var rise = alt - mLastAltitude;
            var g = rise / run;
            if (g > MAX_GRADE) { g = MAX_GRADE; }
            if (g < -MAX_GRADE) { g = -MAX_GRADE; }
            mGrade = g;
            mLastDistance = dist;
            mLastAltitude = alt;
        }
    }

    // Minetti 2002 5th-order fit: C(i) in J/kg/m, i fractional gradient.
    static function costAtGrade(i as Float) as Float {
        var i2 = i * i;
        var i3 = i2 * i;
        var i4 = i3 * i;
        var i5 = i4 * i;
        return 155.4 * i5 - 30.4 * i4 - 43.3 * i3 + 46.3 * i2 + 19.5 * i + 3.6;
    }

    static function formatPace(totalSeconds as Float) as String {
        // Guard against a runaway value (e.g. near-zero gapSpeed) blowing
        // past a sane pace ceiling the native field could render.
        if (totalSeconds > 5940.0) { // 99:00 per unit
            return "--:--";
        }
        var total = Math.round(totalSeconds).toNumber();
        var minutes = total / 60;
        var seconds = total % 60;
        return minutes.format("%d") + ":" + seconds.format("%02d");
    }
}
