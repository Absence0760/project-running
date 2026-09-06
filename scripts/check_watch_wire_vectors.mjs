#!/usr/bin/env node
// Guardrail: the watch's phone-facing wire formats are implemented TWICE — a
// `no_std` Rust codec in the firmware (`apps/custom_watch/core/src/*_store.rs`,
// `settings.rs`, `screens.rs`) and a pure-Dart encoder on the phone
// (`apps/mobile_android/lib/watch_*.dart`) — and each rail pins its own
// encoder's output with a frozen golden byte vector in its OWN suite. Nothing
// compared the two. The failure messages said so out loud ("update BOTH this
// vector and the Dart mirror in …"), which is an instruction, not an
// enforcement: a one-sided version bump or layout change fails only the rail
// that moved, its golden gets updated to whatever that rail now emits, and the
// other rail keeps encoding the old shape with a green test.
//
// decisions.md § 641 is the precedent — `turn_cues` diverged in all three of
// its implementations at once precisely because the pair was registered in no
// registry, so nothing was able to notice. This script is that registry, plus
// the comparison it exists to make: it reads the golden vector out of BOTH
// rails' sources and fails when they disagree.
//
// Neither suite can make this check itself. `cargo test` runs from
// apps/custom_watch and cannot see a Dart file; `flutter test` runs from
// apps/mobile_android and cannot see a Rust one; the Swift, Kotlin and Monkey C
// rails below can read neither. A shared fixture both suites loaded would also
// be WEAKER than this: each rail recomputing its vector from its own encoder
// and the two pins then being compared is two independent computations plus an
// equality check, where a fixture is one number both rails read.
//
// Two registries live here, and both are closed:
//   VECTOR_PAIRS  — one golden byte vector per rail, compared byte-for-byte.
//   CONSTANT_ROWS — one value restated on two or more rails (wire versions,
//                   frame caps, the Apple-Watch route budget, the off-route
//                   hysteresis, the Minetti fit).
// Every golden test the firmware declares and every hex constant the phone's
// test tree declares must appear in VECTOR_PAIRS or in the rail-local list that
// says why it has no counterpart, so a new format cannot be added on one rail
// and go unnoticed — which is the § 641 defect itself.
//
// Run: `node scripts/check_watch_wire_vectors.mjs`
// CI:  the `watch-wire-vectors` job in .github/workflows/ci.yml, which is in
//      the `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_watch_wire_vectors.test.mjs`

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { stripComments } from './comment_strip.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at a
// mutated copy of the tree, which is how a guard is shown to fail.
export const ROOT = process.env.WATCH_WIRE_ROOT ?? REPO_ROOT;

const RS_COURSE = 'apps/custom_watch/core/src/course_store.rs';
const RS_WORKOUT = 'apps/custom_watch/core/src/workout_store.rs';
const RS_ROADBOOK = 'apps/custom_watch/core/src/roadbook_store.rs';
const RS_SCREENS = 'apps/custom_watch/core/src/screens.rs';
const RS_SETTINGS = 'apps/custom_watch/core/src/settings.rs';
const RS_RUN = 'apps/custom_watch/core/src/run_store.rs';

const DT_COURSE = 'apps/mobile_android/test/watch_course_test.dart';
const DT_WORKOUT = 'apps/mobile_android/test/watch_workout_test.dart';
const DT_ROADBOOK = 'apps/mobile_android/test/watch_roadbook_test.dart';
const DT_SCREENS = 'apps/mobile_android/test/watch_screens_test.dart';
const DT_SETTINGS = 'apps/mobile_android/test/watch_settings_test.dart';
const DT_RUN = 'apps/mobile_android/test/sim_watch_sync_test.dart';

/**
 * One golden byte vector that exists on both rails and must be identical.
 *
 * `rust.fn` names the `#[test]` whose body spells the vector out; that body
 * must contain EXACTLY ONE vector, so adding a second to a registered test is
 * itself a failure rather than a coin flip over which one gets compared. Where
 * a test carries several (`pre_v3_golden_blobs_are_rejected`), `rust.const`
 * names the one meant.
 *
 * @typedef {{
 *   name: string,
 *   rust: { file: string, fn: string, const?: string },
 *   dart: { file: string, const: string },
 * }} VectorPair
 */

/** @type {readonly VectorPair[]} */
export const VECTOR_PAIRS = [
  {
    name: 'CRS1 course frame',
    rust: { file: RS_COURSE, fn: 'golden_frame_is_stable' },
    dart: { file: DT_COURSE, const: '_goldenHex' },
  },
  {
    name: 'CRS1 course frame with an elevation series',
    rust: { file: RS_COURSE, fn: 'golden_elevation_frame_is_stable' },
    dart: { file: DT_COURSE, const: '_goldenElevHex' },
  },
  {
    name: 'WKT1 workout frame',
    rust: { file: RS_WORKOUT, fn: 'golden_frame_is_stable' },
    dart: { file: DT_WORKOUT, const: '_goldenHex' },
  },
  {
    name: 'RBK1 roadbook frame',
    rust: { file: RS_ROADBOOK, fn: 'golden_frame_is_stable' },
    dart: { file: DT_ROADBOOK, const: '_goldenHex' },
  },
  {
    name: 'SCR1 screens frame',
    rust: { file: RS_SCREENS, fn: 'the_golden_frame_is_stable' },
    dart: { file: DT_SCREENS, const: '_goldenHex' },
  },
  {
    name: 'SET1 settings frame, every field',
    rust: { file: RS_SETTINGS, fn: 'golden_vector' },
    dart: { file: DT_SETTINGS, const: '_goldenHex' },
  },
  {
    name: 'SET1 settings frame, the five v4 fields alone',
    rust: { file: RS_SETTINGS, fn: 'golden_vector_v4_arms_only' },
    dart: { file: DT_SETTINGS, const: '_goldenV4ArmsHex' },
  },
  {
    name: 'SET1 settings frame, resting HR alone',
    rust: { file: RS_SETTINGS, fn: 'golden_vector_resting_hr_only' },
    dart: { file: DT_SETTINGS, const: '_goldenRestingHrHex' },
  },
  {
    name: 'SET1 settings frame, the ICE card alone',
    rust: { file: RS_SETTINGS, fn: 'golden_vector_ice_only' },
    dart: { file: DT_SETTINGS, const: '_goldenIceHex' },
  },
  {
    name: 'SET1 settings frame, the timezone offset alone',
    rust: { file: RS_SETTINGS, fn: 'golden_vector_tz_only' },
    dart: { file: DT_SETTINGS, const: '_goldenTzHex' },
  },
  {
    name: 'SET1 settings frame, the auto-lap rung alone',
    rust: { file: RS_SETTINGS, fn: 'golden_vector_auto_lap_only' },
    dart: { file: DT_SETTINGS, const: '_goldenAutoLapHex' },
  },
  {
    name: 'SET1 settings frame, the storm threshold alone',
    rust: { file: RS_SETTINGS, fn: 'golden_vector_storm_only' },
    dart: { file: DT_SETTINGS, const: '_goldenStormHex' },
  },
  {
    name: 'TRK1 run blob',
    rust: { file: RS_RUN, fn: 'golden_blob_is_stable' },
    dart: { file: DT_RUN, const: '_goldenV5Hex' },
  },
  {
    name: 'TRK1 run blob carrying a lap record',
    rust: { file: RS_RUN, fn: 'golden_blob_with_a_lap_is_stable' },
    dart: { file: DT_RUN, const: '_goldenV5LapHex' },
  },
  {
    name: 'TRK1 run blob carrying the workout records',
    rust: { file: RS_RUN, fn: 'golden_blob_with_workout_records_is_stable' },
    dart: { file: DT_RUN, const: '_goldenV5WorkoutHex' },
  },
  {
    name: 'TRK1 v1 run blob (rejected on both rails)',
    rust: { file: RS_RUN, fn: 'pre_v3_golden_blobs_are_rejected', const: 'V1_HEX' },
    dart: { file: DT_RUN, const: '_v1GoldenHex' },
  },
  {
    name: 'TRK1 v2 run blob (rejected on both rails)',
    rust: { file: RS_RUN, fn: 'pre_v3_golden_blobs_are_rejected', const: 'V2_HEX' },
    dart: { file: DT_RUN, const: '_v2GoldenHex' },
  },
];

/**
 * Firmware golden tests with no phone counterpart, and why. Each still has to
 * be ABSENT from the phone rail: a "rail-local" vector that turns up in a Dart
 * constant is a pair the registry is lying about, which is the one thing this
 * list must not be able to hide.
 *
 * @type {readonly { file: string, fn: string, why: string }[]}
 */
export const RUST_ONLY = [
  {
    file: RS_SETTINGS,
    fn: 'v7_golden_vector_still_decodes',
    why: 'a decode-compat vector: the phone encoder has only ever stamped the current version, so there is nothing on that rail to mirror it',
  },
  { file: RS_SETTINGS, fn: 'v6_golden_vector_still_decodes', why: 'decode-compat, as v7' },
  { file: RS_SETTINGS, fn: 'v5_golden_vector_still_decodes', why: 'decode-compat, as v7' },
  { file: RS_SETTINGS, fn: 'v4_golden_vector_still_decodes', why: 'decode-compat, as v7' },
  { file: RS_SETTINGS, fn: 'v3_golden_vector_still_decodes', why: 'decode-compat, as v7' },
  {
    file: RS_SETTINGS,
    fn: 'a_v2_golden_vector_is_refused_for_carrying_no_checksum',
    why: 'pins a REFUSAL of bytes no shipped encoder emits; the phone rail has no encoder that could produce them',
  },
  {
    file: RS_SETTINGS,
    fn: 'a_v1_golden_vector_is_refused_for_carrying_no_checksum',
    why: 'pins a refusal, as v2',
  },
];

/**
 * Phone hex constants with no firmware counterpart, and why. Same rule in
 * reverse: each must be absent from the firmware rail.
 *
 * @type {readonly { file: string, const: string, why: string }[]}
 */
export const DART_ONLY = [
  {
    file: DT_RUN,
    const: '_goldenHex',
    why: 'the v3 run blob a pre-§356 board still has in flash — the phone must keep DECODING it, and the firmware no longer writes it, so there is no live Rust encoder to mirror',
  },
  { file: DT_RUN, const: '_goldenLapHex', why: 'the v3 lap blob, as _goldenHex' },
  {
    file: DT_RUN,
    const: '_goldenV4Hex',
    why: 'the v4 run blob a pre-§1026 board still has in flash — its altitudes are decimetres and the phone must keep reading them that way, while the firmware now writes v5 metres, so there is no live Rust encoder to mirror',
  },
  { file: DT_RUN, const: '_goldenV4LapHex', why: 'the v4 lap blob, as _goldenV4Hex' },
  {
    file: DT_RUN,
    const: '_goldenV4WorkoutHex',
    why: 'the v4 workout blob, as _goldenV4Hex',
  },
];

// ---------------------------------------------------------------------------
// Values restated on two or more rails.
// ---------------------------------------------------------------------------

/** Numeric literal, digit separators and a type suffix removed. @param {string} s */
function num(s) {
  const t = s.trim().replace(/_/g, '');
  const v = Number(t);
  if (!Number.isFinite(v)) throw new Error(`not a number: ${s.trim()}`);
  return v;
}

/**
 * The single capture of `re` in `src`. Zero matches and more than one are both
 * errors: a guard that silently took the first of several would report a
 * verdict about whichever copy it happened to reach.
 * @param {string} src @param {RegExp} re @param {string} where
 */
export function only(src, re, where) {
  const flags = re.flags.includes('g') ? re.flags : `${re.flags}g`;
  const hits = [...src.matchAll(new RegExp(re.source, flags))];
  if (hits.length === 0) throw new Error(`no match for /${re.source}/ in ${where}`);
  if (hits.length > 1) {
    throw new Error(`/${re.source}/ matched ${hits.length} times in ${where}; expected one`);
  }
  return hits[0][1];
}

/** `pub const NAME: ty = <expr>;` @param {string} name */
const rustConst = (name) => (/** @type {string} */ src, /** @type {string} */ where) =>
  num(only(src, new RegExp(`\\bconst\\s+${name}\\s*:\\s*[A-Za-z0-9_]+\\s*=\\s*([^;]+);`), where));

/** `const int name = <expr>;` @param {string} name */
const dartConst = (name) => (/** @type {string} */ src, /** @type {string} */ where) =>
  num(only(src, new RegExp(`\\bconst\\s+(?:int|double)\\s+${name}\\s*=\\s*([^;]+);`), where));

/** `static let name = <expr>` @param {string} name */
const swiftLet = (name) => (/** @type {string} */ src, /** @type {string} */ where) =>
  num(only(src, new RegExp(`\\blet\\s+${name}\\s*(?::\\s*[A-Za-z0-9_<>]+\\s*)?=\\s*([^\\n]+)`), where));

/** `export const NAME = <expr>;` @param {string} name */
const tsConst = (name) => (/** @type {string} */ src, /** @type {string} */ where) =>
  num(only(src, new RegExp(`\\bconst\\s+${name}(?:\\s*:\\s*[A-Za-z0-9_]+)?\\s*=\\s*([^;]+);`), where));

/** Monkey C `const NAME = <expr>;` @param {string} name */
const mcConst = (name) => (/** @type {string} */ src, /** @type {string} */ where) =>
  num(only(src, new RegExp(`\\bconst\\s+${name}\\s*=\\s*([^;]+);`), where));

/**
 * Resolve a `<name> / 2` expression against the value `name` holds in the same
 * file. Anything else throws: a re-arm spelled as a fresh literal is a rail
 * that has stopped deriving, and reading it as if it still did would report
 * agreement it no longer has.
 * @param {string} expr @param {string} name @param {number} base
 */
export function halfOf(expr, name, base) {
  const ok = new RegExp(`^(?:Self\\.)?${name}\\s*/\\s*2(?:\\.0)?$`).test(expr.trim());
  if (!ok) {
    throw new Error(
      `expected the re-arm to be derived as "${name} / 2", got "${expr.trim()}" — a rail that ` +
        `has stopped deriving it is one this row can no longer speak for`,
    );
  }
  return base / 2;
}

/**
 * The Minetti 2002 fifth-order fit, as the one line that names both `i5` and
 * `i2`. Compared as normalised source rather than as six numbers: the four
 * rails spell the polynomial identically, so an equality on the text also
 * catches a reordered term or a flipped sign.
 * @param {string} src @param {string} where
 */
export function minettiFit(src, where) {
  const lines = src
    .split('\n')
    .filter((l) => /\bi5\b/.test(l) && /\bi2\b/.test(l))
    .map((l) => l.trim().replace(/^return\s+/, '').replace(/;\s*$/, '').replace(/\s+/g, ' '));
  if (lines.length !== 1) {
    throw new Error(`expected one Minetti fit line in ${where}, found ${lines.length}`);
  }
  return lines[0];
}

/**
 * The whole GAP reference fixture — the synthetic switchback three suites grade
 * themselves against, plus the pace they must grade it to — as one comparable
 * string. Joined rather than split into eight rows because a fixture is one
 * artefact: a golden pace is only a claim about a rail's algorithm while the
 * track under it is the same track, so a period that moved on one rail turns
 * the other two rails' goldens into answers to a different question. The
 * failure message then prints both specs side by side and the drifted field is
 * the one that differs.
 * @param {(name: string) => (src: string, where: string) => number | string} constOf
 * @param {readonly string[]} names
 */
const gapReferenceSpec =
  (constOf, names) => (/** @type {string} */ src, /** @type {string} */ where) =>
    names.map((n, i) => `${GAP_REFERENCE_FIELDS[i]}=${constOf(n)(src, where)}`).join(' ');

const GAP_REFERENCE_FIELDS = /** @type {const} */ ([
  'points',
  'stepM',
  'stepS',
  'baseGrade',
  'amplitudeM',
  'periodM',
  'sPerKm',
  'maxCost',
]);
const GAP_REFERENCE_UPPER = /** @type {const} */ ([
  'GAP_REFERENCE_POINTS',
  'GAP_REFERENCE_STEP_M',
  'GAP_REFERENCE_STEP_S',
  'GAP_REFERENCE_BASE_GRADE',
  'GAP_REFERENCE_AMPLITUDE_M',
  'GAP_REFERENCE_PERIOD_M',
  'GAP_REFERENCE_S_PER_KM',
  'GAP_REFERENCE_MAX_COST',
]);
const GAP_REFERENCE_DART = /** @type {const} */ ([
  'kGapReferencePoints',
  'kGapReferenceStepM',
  'kGapReferenceStepS',
  'kGapReferenceBaseGrade',
  'kGapReferenceAmplitudeM',
  'kGapReferencePeriodM',
  'kGapReferenceSPerKm',
  'kGapReferenceMaxCost',
]);

const RS_COURSE_GEOM = 'apps/custom_watch/core/src/course.rs';
const RS_ALERTS = 'apps/custom_watch/core/src/alerts.rs';
const RS_GAP = 'apps/custom_watch/core/src/grade_adjusted_pace.rs';
const RS_WORKOUT_CORE = 'apps/custom_watch/core/src/workout.rs';
const RS_RECORD = 'apps/custom_watch/core/src/record.rs';
const RS_ROUTE_SIMPLIFY = 'apps/custom_watch/core/src/route_simplify.rs';
const RS_TRACK_PROJECTION = 'apps/custom_watch/core/src/track_projection.rs';
const DL_COURSE = 'apps/mobile_android/lib/watch_course.dart';
const DL_WORKOUT = 'apps/mobile_android/lib/watch_workout.dart';
const DL_ROADBOOK = 'apps/mobile_android/lib/watch_roadbook.dart';
const DL_SCREENS = 'apps/mobile_android/lib/watch_screens.dart';
const DL_SETTINGS = 'apps/mobile_android/lib/watch_settings.dart';
const DL_GAP = 'apps/mobile_android/lib/grade_adjusted_pace.dart';
const DL_RUN_SYNC = 'apps/mobile_android/lib/sim_watch_sync.dart';
const DL_RUN_SCREEN = 'apps/mobile_android/lib/screens/run_screen.dart';
const DL_APPLE_ROUTE = 'apps/mobile_android/lib/apple_watch_route_bridge.dart';
const SW_ARMED_ROUTE = 'apps/watch_ios/WatchApp/ArmedRoute.swift';
const SW_ROUTE_NAV = 'apps/watch_ios/WatchApp/RouteNavigator.swift';
const SW_INGEST = 'apps/mobile_ios/ios/Runner/WatchIngestBridge.swift';
const KT_RUN_APP =
  'apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt';
const TS_GAP = 'apps/web/src/lib/runs/grade_adjusted_pace.ts';
const TS_GAP_TEST = 'apps/web/src/lib/runs/grade_adjusted_pace.test.ts';
const DT_GAP_ANDROID = 'apps/mobile_android/test/grade_adjusted_pace_test.dart';
const DT_GAP_IOS = 'apps/mobile_ios/test/grade_adjusted_pace_test.dart';
const MC_GAP = 'apps/watch_garmin/source/GradeAdjustedPaceView.mc';
const MC_GAP_TEST = 'apps/watch_garmin/source-test/GradeAdjustedPaceTest.mc';

/**
 * A file that does NOT restate a row's value but TAKES it from the rail that
 * declares it. The sharing is a decision, and prose is the wrong place to
 * record it in both directions at once: a reader who gives the consumer its own
 * copy has no note saying the sharing was deliberate, and a reader who retunes
 * the value has no note saying the consumer moves with it. `takes` must match
 * the consumer's source exactly once — it is the import, not a use, so a file
 * that keeps the identifier while declaring its own no longer matches.
 *
 * @typedef {{ label: string, file: string, lang: 'rust' | 'dart' | 'other',
 *             takes: RegExp }} Consumer
 * @typedef {{ label: string, file: string, lang: 'rust' | 'dart' | 'other',
 *             read: (src: string, where: string) => number | string }} Rail
 * @typedef {{ name: string, why: string, rails: readonly Rail[],
 *             consumers?: { why: string, rails: readonly Consumer[] } }} ConstantRow
 */

/** @type {(f: string, r: (s: string, w: string) => number | string) => Rail} */
const rustRail = (file, read) => ({ label: file, file, lang: 'rust', read });
/** @type {(f: string, r: (s: string, w: string) => number | string) => Rail} */
const dartRail = (file, read) => ({ label: file, file, lang: 'dart', read });
/** @type {(f: string, r: (s: string, w: string) => number | string) => Rail} */
const otherRail = (file, read) => ({ label: file, file, lang: 'other', read });
/** @type {(f: string, t: RegExp) => Consumer} */
const rustConsumer = (file, takes) => ({ label: file, file, lang: 'rust', takes });
/** @type {(f: string, t: RegExp) => Consumer} */
const dartConsumer = (file, takes) => ({ label: file, file, lang: 'dart', takes });
/** @type {(f: string, t: RegExp) => Consumer} */
const otherConsumer = (file, takes) => ({ label: file, file, lang: 'other', takes });

/** @type {readonly ConstantRow[]} */
export const CONSTANT_ROWS = [
  {
    name: 'CRS1 format version',
    why: 'the version byte the phone stamps and the watch branches its layout on; a one-sided bump is exactly the drift the goldens alone could not see',
    rails: [
      rustRail(RS_COURSE, rustConst('COURSE_FORMAT_VERSION')),
      dartRail(DL_COURSE, dartConst('_courseVersion')),
    ],
  },
  {
    name: 'WKT1 format version',
    why: 'as CRS1',
    rails: [
      rustRail(RS_WORKOUT, rustConst('WORKOUT_FORMAT_VERSION')),
      dartRail(DL_WORKOUT, dartConst('_workoutVersion')),
    ],
  },
  {
    name: 'RBK1 format version',
    why: 'as CRS1',
    rails: [
      rustRail(RS_ROADBOOK, rustConst('ROADBOOK_FORMAT_VERSION')),
      dartRail(DL_ROADBOOK, dartConst('_roadbookVersion')),
    ],
  },
  {
    name: 'RBK1 checkpoint length (bytes)',
    why: "the stride both rails walk the checkpoint series with, at the version the phone emits. A one-sided change reads every field after the first checkpoint from the wrong offset — the CRC still matches, the counts still agree, and the schedule decodes as a plausible different race. Only the CURRENT version's stride is a pair: the firmware also knows v1's, but the phone has no decoder and never emits v1, so restating it there would be a constant nothing reads",
    rails: [
      rustRail(RS_ROADBOOK, rustConst('ROADBOOK_CHECKPOINT_LEN')),
      dartRail(DL_ROADBOOK, dartConst('kRoadbookCheckpointLen')),
    ],
  },
  {
    name: 'SCR1 format version',
    why: 'as CRS1',
    rails: [
      rustRail(RS_SCREENS, rustConst('SCR1_VERSION')),
      dartRail(DL_SCREENS, dartConst('_screensVersion')),
    ],
  },
  {
    name: 'SET1 format version',
    why: 'as CRS1, and the one that moves most often — decode accepts v3..v8, but the phone encoder must stamp what the firmware calls current',
    rails: [
      rustRail(RS_SETTINGS, rustConst('SETTINGS_VERSION')),
      dartRail(DL_SETTINGS, dartConst('_settingsVersion')),
    ],
  },
  {
    name: 'TRK1 current format version',
    why: "the version the watch STAMPS against the newest the phone will read. Unlike the four push formats this one flows watch->phone, so the two halves are not encoder-and-decoder but writer-and-ceiling: a firmware-only bump ships a watch whose runs the phone refuses outright, which is a runner losing a race to a version byte, and nothing in either suite could see it — the firmware's golden pins what it emits, the phone's pins what it reads, and neither knows the other's bound",
    rails: [
      rustRail(RS_RUN, rustConst('FORMAT_VERSION')),
      dartRail(DL_RUN_SYNC, dartConst('_maxSupportedVersion')),
    ],
  },
  {
    name: 'TRK1 oldest readable format version',
    why: 'the compat floor, the other end of the same window. A phone floor ABOVE the firmware\'s would refuse a blob the firmware still considers current; one below would decode a pre-v3 blob whose CRC never covered its totals',
    rails: [
      rustRail(RS_RUN, rustConst('MIN_FORMAT_VERSION')),
      dartRail(DL_RUN_SYNC, dartConst('_minSupportedVersion')),
    ],
  },
  {
    name: 'TRK1 first whole-metre altitude version',
    why: 'the version at which a track point\'s altitude stopped meaning decimetres and started meaning metres. A rail holding a different switch point reports every altitude in one whole format version ten times too high or too low — silently, since the bytes verify and the CRC matches',
    rails: [
      rustRail(RS_RUN, rustConst('ELE_METRES_VERSION')),
      dartRail(DL_RUN_SYNC, dartConst('kEleMetresVersion')),
    ],
  },
  {
    name: 'CRS1 course point cap',
    why: 'the phone thins a route to this budget and the watch refuses a frame claiming more; if the phone cap grew first, every long course would be refused whole',
    rails: [
      rustRail(RS_COURSE_GEOM, rustConst('MAX_COURSE_POINTS')),
      dartRail(DL_COURSE, dartConst('kMaxCoursePoints')),
    ],
  },
  {
    name: 'WKT1 workout step cap',
    why: 'as the course cap: the phone truncates to it, the watch refuses past it',
    rails: [
      rustRail(RS_WORKOUT_CORE, rustConst('MAX_WORKOUT_STEPS')),
      dartRail(DL_WORKOUT, dartConst('kMaxWorkoutSteps')),
    ],
  },
  {
    name: 'SCR1 screen cap',
    why: 'as the course cap',
    rails: [
      rustRail(RS_SCREENS, rustConst('MAX_SCREENS')),
      dartRail(DL_SCREENS, dartConst('kMaxWatchScreens')),
    ],
  },
  {
    name: 'SCR1 slots per screen',
    why: 'a LAYOUT width, not only a cap — a disagreement shifts every entry after the first',
    rails: [
      rustRail(RS_SCREENS, rustConst('SCREEN_SLOTS')),
      dartRail(DL_SCREENS, dartConst('kWatchScreenSlots')),
    ],
  },
  {
    name: 'RBK1 checkpoint cap',
    why: 'as the course cap',
    rails: [
      rustRail(RS_RECORD, rustConst('MAX_PUSHED_LEGS')),
      dartRail(DL_ROADBOOK, dartConst('kMaxRoadbookCheckpoints')),
    ],
  },
  {
    name: 'RBK1 cutoff-leg cap',
    why: 'as the course cap',
    rails: [
      rustRail(RS_RECORD, rustConst('MAX_CUTOFF_LEGS')),
      dartRail(DL_ROADBOOK, dartConst('kMaxRoadbookCutoffs')),
    ],
  },
  {
    name: 'pace-band floor (s/km)',
    why: 'the phone refuses a band outside this range before pushing and the watch refuses it again on arrival; a phone floor below the watch’s pushes a band the watch silently drops',
    rails: [
      rustRail(RS_ALERTS, rustConst('PACE_BAND_MIN_S_PER_KM')),
      dartRail(DL_WORKOUT, dartConst('kWorkoutPaceMinSecPerKm')),
    ],
  },
  {
    name: 'pace-band ceiling (s/km)',
    why: 'as the floor',
    rails: [
      rustRail(RS_ALERTS, rustConst('PACE_BAND_MAX_S_PER_KM')),
      dartRail(DL_WORKOUT, dartConst('kWorkoutPaceMaxSecPerKm')),
    ],
  },
  {
    name: 'Apple-Watch route push budget (points)',
    why: 'three prose "must match" cross-references and no test. The phone thins to it, the watch app refuses a payload past it, and the iOS host bridge refuses it again — so a phone budget above either receiver drops the whole route rather than truncating it, and the runner arms a route the watch never got',
    rails: [
      dartRail(DL_APPLE_ROUTE, dartConst('kMaxAppleWatchRoutePoints')),
      otherRail(SW_ARMED_ROUTE, swiftLet('maxPoints')),
      otherRail(SW_INGEST, swiftLet('maxRoutePoints')),
    ],
  },
  {
    name: 'off-route alert threshold (m)',
    why: 'one hysteresis on four rails — the custom watch, the phone run screen, the Apple Watch and Wear OS all decide "off route" at the same distance, and a runner told they are off course on one wrist and on course on the other has no way to tell which is right',
    rails: [
      rustRail(RS_COURSE_GEOM, rustConst('OFF_COURSE_THRESHOLD_M')),
      dartRail(DL_RUN_SCREEN, dartConst('_offRouteThresholdMetres')),
      otherRail(SW_ROUTE_NAV, swiftLet('thresholdMetres')),
      otherRail(KT_RUN_APP, (src, where) =>
        num(only(src, /offRouteDistanceM\s*>\s*([0-9.]+)/, where)),
      ),
    ],
  },
  {
    name: 'off-route re-arm distance (m)',
    why: 'the other half of the same hysteresis. Three rails DERIVE it as half the threshold and Wear OS writes the number out, so this row is what stops the derived and the literal parting company',
    rails: [
      rustRail(RS_COURSE_GEOM, (src, where) =>
        halfOf(
          only(src, /\bconst\s+OFF_COURSE_REARM_M\s*:\s*f64\s*=\s*([^;]+);/, where),
          'OFF_COURSE_THRESHOLD_M',
          rustConst('OFF_COURSE_THRESHOLD_M')(src, where),
        ),
      ),
      dartRail(DL_RUN_SCREEN, (src, where) =>
        halfOf(
          only(src, /off\s*<\s*(_offRouteThresholdMetres\s*\/\s*2)\b/, where),
          '_offRouteThresholdMetres',
          dartConst('_offRouteThresholdMetres')(src, where),
        ),
      ),
      otherRail(SW_ROUTE_NAV, (src, where) =>
        halfOf(
          only(src, /\blet\s+rearmMetres\s*=\s*([^\n]+)/, where),
          'thresholdMetres',
          swiftLet('thresholdMetres')(src, where),
        ),
      ),
      otherRail(KT_RUN_APP, (src, where) =>
        num(only(src, /offRouteDistanceM\s*<\s*([0-9.]+)/, where)),
      ),
    ],
  },
  {
    name: 'Minetti 2002 fifth-order fit',
    why: 'the grade-adjusted-pace polynomial, copied verbatim onto four rails — firmware, web, phone and the Garmin data field. A coefficient that moved on one of them would still produce a plausible pace, which is why nothing would ever report it',
    rails: [
      rustRail(RS_GAP, minettiFit),
      dartRail(DL_GAP, minettiFit),
      otherRail(TS_GAP, minettiFit),
      otherRail(MC_GAP, minettiFit),
    ],
  },
  {
    name: 'Minetti valid-range clamp (fractional grade)',
    why: 'the fit is only defined to about +/-45%; a rail clamping wider extrapolates the polynomial into nonsense on a wall',
    rails: [
      rustRail(RS_GAP, rustConst('MAX_GRADE')),
      dartRail(DL_GAP, dartConst('maxGrade')),
      otherRail(TS_GAP, tsConst('MAX_GRADE')),
      otherRail(MC_GAP, mcConst('MAX_GRADE')),
    ],
  },
  {
    name: 'Minetti flat-ground cost C(0)',
    why: 'the divisor that makes the factor exactly 1.0 on the flat; a rail holding a different one reports a grade adjustment on level ground',
    rails: [
      rustRail(RS_GAP, rustConst('MINETTI_FLAT_COST')),
      dartRail(DL_GAP, dartConst('minettiFlatCost')),
      otherRail(TS_GAP, tsConst('MINETTI_FLAT_COST')),
      otherRail(MC_GAP, mcConst('FLAT_COST')),
    ],
  },
  {
    name: 'elevation-gain noise gate (m)',
    why: 'the threshold a climb must clear before it counts as gain. A rail without it — which is what the firmware shipped with until this round — reads a plus/minus 1 m barometric sawtooth as metres of phantom vert per minute, on the device whose headline metric is cumulative climb. It is a THRESHOLD rather than a wire field, so no format version moves when it drifts and no decode fails; the three rails simply answer different numbers for the same track',
    rails: [
      rustRail(RS_ROUTE_SIMPLIFY, rustConst('ELEVATION_GAIN_MIN_DELTA_M')),
      dartRail('apps/mobile_android/lib/route_simplify.dart', dartConst('kElevationGainMinDeltaM')),
      otherRail('apps/web/src/lib/routes/route_simplify.ts', tsConst('ELEVATION_GAIN_MIN_DELTA_M')),
    ],
  },
  {
    name: 'live-pace ceiling (s/km)',
    why: 'the head of a four-rail chain, and the one link nothing could read. Past 99:00 a live pace is a runaway from a near-zero adjusted speed rather than a pace, and both rails render `--:--` instead. The other two links are already enforced elsewhere and are deliberately not restated here: the firmware\'s own `alerts::the_pace_band_ceiling_is_the_apps_own_live_pace_ceiling` pins `alerts::PACE_BAND_MAX_S_PER_KM` equal to this value, and the `pace-band ceiling (s/km)` row above pins THAT against the phone',
    rails: [
      rustRail(RS_GAP, rustConst('MAX_PACE_S_PER_KM')),
      otherRail(MC_GAP, mcConst('MAX_PACE_S')),
    ],
  },
  {
    name: 'live-pace walk gate (m/s)',
    why: 'below this the runner is walking or stopped and an instantaneous pace is noise, so both streaming rails blank the cell. A rail with a lower gate reports a pace on a power-hike the other calls unreadable, and the two wrists then disagree about whether there is a number at all. Streaming-only: the web and Dart GAP helpers are batch, take no per-sample speed, and have no analogue to hold',
    rails: [
      rustRail(RS_GAP, rustConst('MIN_SPEED_MPS')),
      otherRail(MC_GAP, mcConst('MIN_SPEED_MPS')),
    ],
  },
  {
    name: 'renderable-track span gate (m)',
    why: "the bounding-box diagonal below which a track is jitter rather than a run, and is drawn as nothing rather than as a dot on one pixel. A THRESHOLD, not a wire field, so no version moves when it drifts and no decode fails — the three rails simply disagree about whether a run has a picture. It was a bare literal on the phone and the web until this round, which is why it could not be registered: this guard reads a rail by the NAME of its constant",
    rails: [
      rustRail(RS_TRACK_PROJECTION, rustConst('MIN_RENDERABLE_SPAN_M')),
      dartRail(
        'apps/mobile_android/lib/widgets/track_preview.dart',
        dartConst('kMinRenderableSpanM'),
      ),
      otherRail(
        'apps/web/src/lib/routes/track_projection.ts',
        tsConst('MIN_RENDERABLE_SPAN_M'),
      ),
    ],
  },
  {
    name: 'minimum segment before a grade sample is trusted (m)',
    why: 'the anchored window every rail measures grade over; a shorter one on one rail reads GPS-altitude jitter as a wall',
    rails: [
      rustRail(RS_GAP, rustConst('MIN_SEGMENT_M')),
      dartRail(DL_GAP, dartConst('minSegmentM')),
      otherRail(TS_GAP, tsConst('MIN_SEGMENT_M')),
      otherRail(MC_GAP, mcConst('MIN_SEGMENT_M')),
    ],
    consumers: {
      why: "the roadbook allocates a goal time by grade-adjusted EFFORT, and it walks the course with the same anchored window for the same reason: a leg graded over less than this reads altitude jitter as a wall and hands the crew a schedule that front-loads the climbs that are not there. § 992 raised the window and the roadbook's three rails moved with it, correctly and silently — their suites passed unchanged, so nothing would have reported a rail that did not. Giving the roadbook a window of its own is a decision someone may take, but it must be taken deliberately: two windows means the pace a runner is shown mid-race and the arrival time their crew is holding a drop bag against were computed over different terrain",
      rails: [
        rustConsumer(
          'apps/custom_watch/core/src/roadbook.rs',
          /\buse\s+crate::grade_adjusted_pace::\{[^}]*\bMIN_SEGMENT_M\b[^}]*\}/,
        ),
        dartConsumer(
          'apps/mobile_android/lib/roadbook.dart',
          /\bimport\s+'grade_adjusted_pace\.dart'\s+show\b[^;]*\bminSegmentM\b/,
        ),
        dartConsumer(
          'apps/mobile_ios/lib/roadbook.dart',
          /\bimport\s+'grade_adjusted_pace\.dart'\s+show\b[^;]*\bminSegmentM\b/,
        ),
        otherConsumer(
          'apps/web/src/lib/routes/roadbook.ts',
          /\bimport\s+\{[^}]*\bMIN_SEGMENT_M\b[^}]*\}\s+from\s+'[^']*grade_adjusted_pace'/,
        ),
      ],
    },
  },
  {
    name: 'GAP reference track (fixture and the pace it must grade to)',
    why: "the window above is a number, and until this round nothing on any rail pinned it: every suite passed at 5, 20, 30 and 50 m. Each rail now grades one frozen synthetic switchback and must report the same integer, which brackets the window from ABOVE the way the noise-floor test brackets it from below — the noise-floor relationship would pass at 200 m, a window that averages real terrain flat. The eight fields are one artefact, not eight constants: a golden pace says nothing about a rail's algorithm unless the track under it is the same track",
    rails: [
      rustRail(RS_GAP, gapReferenceSpec(rustConst, GAP_REFERENCE_UPPER)),
      dartRail(DT_GAP_ANDROID, gapReferenceSpec(dartConst, GAP_REFERENCE_DART)),
      dartRail(DT_GAP_IOS, gapReferenceSpec(dartConst, GAP_REFERENCE_DART)),
      otherRail(TS_GAP_TEST, gapReferenceSpec(tsConst, GAP_REFERENCE_UPPER)),
      otherRail(MC_GAP_TEST, gapReferenceSpec(mcConst, GAP_REFERENCE_UPPER)),
    ],
  },
];

// ---------------------------------------------------------------------------
// Extraction.
// ---------------------------------------------------------------------------

const HEX_ONLY = /^[0-9a-f]+$/;

/**
 * Every byte vector spelled out in a chunk of Rust — a hex string literal
 * (backslash line continuations folded away) or a `[0x.., …]` array.
 * @param {string} src comment-stripped Rust
 */
export function rustVectors(src) {
  /** @type {string[]} */
  const out = [];
  // Whitespace is only ever allowed straight after a `\` line continuation.
  // Without that, a prose assert message made of nothing but hex letters and
  // spaces — "deadbeef cafe decade" — reads as a byte vector, which in a test
  // whose vector is spelled some other way is a wrong answer rather than a
  // loud one. Caught by this file's own unit tests on the first draft.
  // One character per alternation branch, not a run inside a second quantifier:
  // `(?:[0-9a-fA-F]+|\\\s*)+` is two nested quantifiers over overlapping input, so
  // a long unterminated hex run backtracks exponentially and hangs the guard on a
  // file it cannot even parse. The branches here are disjoint on their first
  // character, so the match is linear and the language is unchanged.
  for (const m of src.matchAll(/"((?:[0-9a-fA-F]|\\\s*)*)"/g)) {
    const hex = m[1].replace(/\\\s*/g, '').toLowerCase();
    if (hex.length >= 16 && hex.length % 2 === 0 && HEX_ONLY.test(hex)) out.push(hex);
  }
  for (const m of src.matchAll(/\[\s*(?:0x[0-9a-fA-F]{2}\s*,\s*)+0x[0-9a-fA-F]{2}\s*,?\s*\]/g)) {
    const hex = [...m[0].matchAll(/0x([0-9a-fA-F]{2})/g)].map((b) => b[1].toLowerCase()).join('');
    if (hex.length >= 16) out.push(hex);
  }
  return out;
}

/**
 * The brace-matched body of `fn <name>(`, skipping string and char literals so
 * a `"{…}"` format string cannot unbalance the walk.
 * @param {string} src comment-stripped Rust @param {string} name
 */
export function rustFnBody(src, name) {
  const at = src.search(new RegExp(`\\bfn\\s+${name}\\s*\\(`));
  if (at < 0) return null;
  let i = src.indexOf('{', at);
  if (i < 0) return null;
  const start = i;
  let depth = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === '"') {
      i++;
      while (i < src.length && src[i] !== '"') i += src[i] === '\\' ? 2 : 1;
      i++;
      continue;
    }
    if (c === "'") {
      const m = src.slice(i).match(/^'(?:\\(?:u\{[0-9a-fA-F]{1,6}\}|x[0-9a-fA-F]{2}|.)|[^\\'])'/);
      if (m) {
        i += m[0].length;
        continue;
      }
    }
    if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth === 0) return src.slice(start + 1, i);
    }
    i++;
  }
  return null;
}

/**
 * A `const NAME: &str = "…";` inside a chunk of Rust.
 * @param {string} src @param {string} name
 */
export function rustConstHex(src, name) {
  const m = src.match(
    new RegExp(`\\bconst\\s+${name}\\s*:\\s*&(?:'static\\s+)?str\\s*=\\s*"([^"]*)"`),
  );
  if (!m) return null;
  const hex = m[1].replace(/\\/g, '').replace(/\s+/g, '').toLowerCase();
  return HEX_ONLY.test(hex) && hex.length > 0 && hex.length % 2 === 0 ? hex : null;
}

/**
 * A top-level Dart `const <name> = '…' '…';` whose value is only hex.
 * @param {string} src comment-stripped Dart @param {string} name
 */
export function dartConstHex(src, name) {
  const m = src.match(new RegExp(`(?:^|\\n)\\s*const\\s+(?:String\\s+)?${name}\\s*=([^;]*);`));
  if (!m) return null;
  const parts = [...m[1].matchAll(/'([^']*)'/g)].map((p) => p[1]);
  if (parts.length === 0) return null;
  const hex = parts.join('').replace(/\s+/g, '').toLowerCase();
  return HEX_ONLY.test(hex) && hex.length >= 16 && hex.length % 2 === 0 ? hex : null;
}

/**
 * Every top-level Dart declaration whose value is only hex, as name → hex.
 * `const` and `final` both count: `sim_watch_screen_test.dart` holds its copy
 * of the run blob as `final _goldenBlob = _hex('…')`, and a copy nothing
 * compares is the whole defect this file exists for.
 *
 * A collection is a collection of values, never one vector, so a `[` or `{`
 * outside the literals disqualifies the declaration. Without that,
 * `status_color_literal_guard_test.dart`'s 21 banned six-digit colour literals
 * join into one 63-byte "vector" the registry has never heard of. The test is
 * on the bracket rather than on the comma between the elements: the registered
 * `sim_watch_screen_test.dart::_goldenBlob` is `_hex('…' '…' '…',)`, a trailing
 * comma in a call, and its own guard test catches a rule that drops it.
 * @param {string} src comment-stripped Dart
 */
export function dartHexConsts(src) {
  /** @type {Map<string, string>} */
  const out = new Map();
  for (const m of src.matchAll(/(?:^|\n)\s*(?:const|final)\s+(?:String\s+)?(\w+)\s*=([^;]*);/g)) {
    if (/[[{]/.test(m[2].replace(/'[^']*'/g, ''))) continue;
    const parts = [...m[2].matchAll(/'([^']*)'/g)].map((p) => p[1]);
    if (parts.length === 0) continue;
    const hex = parts.join('').replace(/\s+/g, '').toLowerCase();
    if (hex.length >= 16 && hex.length % 2 === 0 && HEX_ONLY.test(hex)) out.set(m[1], hex);
  }
  return out;
}

/**
 * Every `fn` whose name mentions "golden", as declared in a Rust file.
 * @param {string} src comment-stripped Rust
 */
export function rustGoldenFns(src) {
  return [...src.matchAll(/\bfn\s+([A-Za-z0-9_]*golden[A-Za-z0-9_]*)\s*\(/g)].map((m) => m[1]);
}

// ---------------------------------------------------------------------------
// Run.
// ---------------------------------------------------------------------------

/** @param {string} dir @param {string} ext @returns {string[]} */
function walk(dir, ext) {
  /** @type {string[]} */
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p, ext));
    else if (e.name.endsWith(ext)) out.push(p);
  }
  return out;
}

/** @type {Map<string, string>} */
const cache = new Map();
/** @param {string} rel @param {'rust' | 'dart' | 'other'} lang */
function read(rel, lang) {
  const key = `${rel} ${lang}`;
  const hit = cache.get(key);
  if (hit !== undefined) return hit;
  const raw = readFileSync(join(ROOT, rel), 'utf8');
  const src = lang === 'other' ? raw : stripComments(raw, lang);
  cache.set(key, src);
  return src;
}

/**
 * @param {VectorPair} pair
 * @returns {{ hex: string, error?: undefined } | { error: string, hex?: undefined }}
 */
function rustVectorOf(pair) {
  const src = read(pair.rust.file, 'rust');
  const body = rustFnBody(src, pair.rust.fn);
  if (body === null) return { error: `${pair.rust.file}: no fn ${pair.rust.fn}` };
  if (pair.rust.const) {
    const hex = rustConstHex(body, pair.rust.const);
    return hex
      ? { hex }
      : { error: `${pair.rust.file}::${pair.rust.fn}: no hex const ${pair.rust.const}` };
  }
  const found = rustVectors(body);
  if (found.length !== 1) {
    return {
      error: `${pair.rust.file}::${pair.rust.fn}: expected exactly one byte vector, found ${found.length}`,
    };
  }
  return { hex: found[0] };
}

export function main() {
  /** @type {string[]} */
  const errors = [];
  /** @type {string[]} */
  const ok = [];

  // 1. Every registered pair agrees byte for byte.
  /** @type {Map<string, string>} */
  const registeredRustHex = new Map();
  /** @type {Map<string, string>} */
  const registeredDartHex = new Map();
  for (const pair of VECTOR_PAIRS) {
    const r = rustVectorOf(pair);
    const dartHex = dartConstHex(read(pair.dart.file, 'dart'), pair.dart.const);
    if (r.error !== undefined) {
      errors.push(`${pair.name}: ${r.error}`);
      continue;
    }
    if (dartHex === null) {
      errors.push(`${pair.name}: ${pair.dart.file}: no all-hex const ${pair.dart.const}`);
      continue;
    }
    registeredRustHex.set(`${pair.rust.file}::${pair.rust.fn}`, r.hex);
    registeredDartHex.set(`${pair.dart.file}::${pair.dart.const}`, dartHex);
    if (r.hex === dartHex) {
      ok.push(`${pair.name} (${r.hex.length / 2} B)`);
      continue;
    }
    let at = 0;
    while (at < r.hex.length && at < dartHex.length && r.hex[at] === dartHex[at]) at++;
    errors.push(
      `${pair.name}: the two rails no longer encode the same bytes\n` +
        `    firmware ${pair.rust.file}::${pair.rust.fn} -> ${r.hex.length / 2} B ${r.hex}\n` +
        `    phone    ${pair.dart.file}::${pair.dart.const} -> ${dartHex.length / 2} B ${dartHex}\n` +
        `    first difference at byte ${Math.floor(at / 2)}`,
    );
  }

  // 2. The phone's whole hex inventory, for the rail-local absence rule below.
  //    EVERY Dart file on the phone rail is read. This used to be narrowed to
  //    the test files carrying one of the firmware's own wire magics, because
  //    the shared lexer could not blank a file whose strings interpolated
  //    (decisions § 793); it can now (§ 816), so the narrowing is gone and with
  //    it the chance that a golden spelled without a magic byte in it — a
  //    payload-only vector, a magic written as `[0x43, 0x52, …]` — sat outside
  //    the sweep. A file that cannot be lexed is a hard error, never a skip:
  //    a guard must not report a verdict about source it cannot read.
  /** @type {Map<string, Map<string, string>>} */
  const dartConstsByFile = new Map();
  /** @type {Set<string>} */
  const allDartHex = new Set();
  for (const root of ['apps/mobile_android/lib', 'apps/mobile_android/test']) {
    for (const abs of walk(join(ROOT, root), '.dart')) {
      const rel = relative(ROOT, abs);
      /** @type {Map<string, string>} */
      let consts;
      try {
        consts = dartHexConsts(read(rel, 'dart'));
      } catch (e) {
        errors.push(`${rel} cannot be lexed: ${e instanceof Error ? e.message : String(e)}`);
        continue;
      }
      if (consts.size > 0) dartConstsByFile.set(rel, consts);
      for (const hex of consts.values()) allDartHex.add(hex);
    }
  }
  if (allDartHex.size === 0) {
    errors.push('no hex vectors found on the phone rail — the sweep is blind');
  }

  // 3. Every golden the firmware declares is registered, or declared rail-local
  //    AND actually absent from the phone rail.
  const rustOnly = new Map(RUST_ONLY.map((r) => [`${r.file}::${r.fn}`, r]));
  for (const abs of walk(join(ROOT, 'apps/custom_watch'), '.rs')) {
    const rel = relative(ROOT, abs);
    const src = read(rel, 'rust');
    for (const fn of rustGoldenFns(src)) {
      const key = `${rel}::${fn}`;
      if (registeredRustHex.has(key)) continue;
      const local = rustOnly.get(key);
      if (!local) {
        errors.push(
          `${key} is a golden vector the registry does not know about. Add it to VECTOR_PAIRS ` +
            `with the phone constant it mirrors, or to RUST_ONLY with why the phone has no ` +
            `counterpart. An unregistered vector is one nothing compares (decisions § 641).`,
        );
        continue;
      }
      rustOnly.delete(key);
      const body = rustFnBody(src, fn);
      for (const hex of body === null ? [] : rustVectors(body)) {
        if (allDartHex.has(hex)) {
          errors.push(
            `${key} is listed in RUST_ONLY ("${local.why}") but the phone rail pins the same ` +
              `${hex.length / 2}-byte vector. It is a pair — register it in VECTOR_PAIRS.`,
          );
        }
      }
    }
  }
  for (const key of rustOnly.keys()) {
    errors.push(`RUST_ONLY names ${key}, which no longer exists. Drop the entry.`);
  }

  // 4. The same, in reverse, for the phone's hex vectors. A vector that is not
  //    itself registered passes only by being byte-identical to one that is —
  //    which is how the third copy of the run blob in `sim_watch_screen_test`
  //    is held to the registered one without a registry row of its own, and how
  //    it fails the day either copy moves alone.
  const dartOnly = new Map(DART_ONLY.map((d) => [`${d.file}::${d.const}`, d]));
  const allRustHex = new Set(registeredRustHex.values());
  const knownDartHex = new Set(registeredDartHex.values());
  for (const d of DART_ONLY) {
    const hex = dartConstsByFile.get(d.file)?.get(d.const);
    if (hex !== undefined) knownDartHex.add(hex);
  }
  for (const [file, consts] of dartConstsByFile) {
    for (const [name, hex] of consts) {
      const key = `${file}::${name}`;
      if (registeredDartHex.has(key)) continue;
      const local = dartOnly.get(key);
      if (!local) {
        if (knownDartHex.has(hex)) {
          ok.push(`${key} (${hex.length / 2} B) is a verbatim copy of a registered vector`);
          continue;
        }
        errors.push(
          `${key} is a hex vector the registry does not know about, and it is not a copy of one ` +
            `it does. Add it to VECTOR_PAIRS with the firmware test it mirrors, or to DART_ONLY ` +
            `with why the firmware has no counterpart.`,
        );
        continue;
      }
      dartOnly.delete(key);
      if (allRustHex.has(hex)) {
        errors.push(
          `${key} is listed in DART_ONLY ("${local.why}") but the firmware pins the same bytes.`,
        );
      }
    }
  }
  for (const key of dartOnly.keys()) {
    errors.push(`DART_ONLY names ${key}, which no longer exists. Drop the entry.`);
  }

  // 5. Values restated on more than one rail.
  for (const row of CONSTANT_ROWS) {
    /** @type {{ label: string, value: number | string }[]} */
    const seen = [];
    let broke = false;
    for (const rail of row.rails) {
      try {
        seen.push({ label: rail.label, value: rail.read(read(rail.file, rail.lang), rail.file) });
      } catch (e) {
        errors.push(`${row.name}: ${rail.label}: ${e instanceof Error ? e.message : String(e)}`);
        broke = true;
      }
    }
    if (broke) continue;
    const first = seen[0];
    if (seen.every((s) => s.value === first.value)) {
      ok.push(`${row.name} = ${first.value} on ${seen.length} rails`);
    } else {
      errors.push(
        `${row.name}: the rails disagree — ${row.why}\n` +
          seen.map((s) => `    ${s.label} -> ${s.value}`).join('\n'),
      );
    }

    // 5b. Files that TAKE the value rather than restate it. Nothing above can
    //     see these: a consumer holds no constant to compare, so the day one
    //     stops sharing, every rail above still agrees and the guard still
    //     passes while two windows are in use.
    for (const c of row.consumers?.rails ?? []) {
      /** @type {string} */
      let src;
      try {
        src = read(c.file, c.lang);
      } catch (e) {
        errors.push(`${row.name}: ${c.label}: ${e instanceof Error ? e.message : String(e)}`);
        continue;
      }
      const hits = src.match(new RegExp(c.takes.source, `${c.takes.flags.replace('g', '')}g`));
      if (hits?.length === 1) {
        ok.push(`${row.name} is taken from the declaring rail by ${c.label}`);
        continue;
      }
      errors.push(
        `${row.name}: ${c.label} ${hits ? `names it ${hits.length} times` : 'no longer takes it'} ` +
          `from the rail that declares it, and it must — ${row.consumers?.why}`,
      );
    }
  }

  for (const line of ok) console.log(`[OK] ${line}`);
  for (const line of errors) console.error(`[FAIL] ${line}`);
  if (errors.length > 0) {
    console.error(
      `\n${errors.length} watch-rail disagreement(s). Every value above is READ from the file ` +
        `named beside it — fix the source, not this script.`,
    );
  }
  return errors.length;
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  process.exit(main() === 0 ? 0 : 1);
}
