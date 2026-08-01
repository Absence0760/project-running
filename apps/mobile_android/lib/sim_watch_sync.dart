import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'watch_settings.dart';

/// Pure Dart mirror of the custom watch's `run_store` blob format
/// (`apps/custom_watch/core/src/run_store.rs`).
///
/// The watch records a run as a self-describing little-endian blob:
///
///   header(16) | record[N](16) | footer(20)
///
/// Each record's byte 15 is a tag — 0 = track point, 1 = a closed lap,
/// 2 = a settled workout step's outcome, 3 = the workout summary — and
/// tagged records interleave with points in recording order.
///
/// Version 3 put the footer's totals under the CRC: the checksum covers
/// every byte of the blob except the four it occupies itself, so a
/// distance / moving / elapsed value cannot rot into a run that verifies
/// with wrong numbers. Versions outside
/// [_minSupportedVersion] .. [_maxSupportedVersion] are rejected
/// outright — a v1/v2 blob's CRC covers a narrower window and re-admitting
/// it would re-open exactly that hole, and an unknown newer record layout
/// decoded as GPS points would corrupt a track (decisions §321). Version 4
/// added the two workout tags without touching v3's CRC window, so both
/// decode here (decisions §356).
///
/// The watch exposes the set of runs over BLE as a manifest (a header +
/// one entry per stored run). The phone pulls each blob in chunks,
/// verifies its CRC, and reshapes it into the canonical watch-run payload
/// that [runFromWatchPayload] (watch_ingest_queue.dart) already consumes
/// — laps land in the registered `metadata.laps` shape
/// (docs/backend/metadata.md § laps).
///
/// This module is deliberately pure — no BLE, no disk, no platform
/// channels — so the whole decode/verify/reshape path is unit-testable
/// against a frozen golden vector without a radio attached.
const int _headerLen = 16;
const int _pointLen = 16;
const int _footerLen = 20;

/// Record tags at byte 15 of every 16-byte record.
const int _recordTagPoint = 0;
const int _recordTagLap = 1;
const int _recordTagStep = 2;
const int _recordTagWorkout = 3;

/// The `run_store` formats this decoder understands. The floor is by
/// design: v3 redefined the CRC window, so v1/v2 blobs are not merely old,
/// they carry a checksum that leaves their totals unprotected. v4 only
/// added record tags on the same window, so both v3 and v4 decode.
const int _minSupportedVersion = 3;
const int _maxSupportedVersion = 4;

/// Bytes of the footer the CRC does not cover — the CRC field itself, which
/// sits last. Everything before it is inside the window.
const int _footerCrcLen = 4;

/// Header `flags` bit (byte 5): the watch stamped this blob at commit, so it
/// is a finished run rather than a mid-run checkpoint snapshot.
///
/// The watch does not advertise the checkpoints of a run it is still
/// recording, so a synced blob normally carries this. It can legitimately be
/// clear: a run interrupted by a reset is recovered from its last checkpoint
/// and advertised then, because the recording ended with the power. Such a
/// blob is a real run whose footer totals are its totals-so-far, so it is
/// ingested rather than refused — refusing it would throw away the only copy
/// of an interrupted run.
const int kRunFlagFinished = 0x01;

/// Sentinel written by the watch when a point has no barometric/GPS
/// elevation fix. Decoded to a null `ele`.
const int _eleNoneSentinel = -32768;

const _uuid = Uuid();

/// CRC-32 (IEEE / reflected, poly 0xEDB88320, init 0xFFFFFFFF, final
/// XOR 0xFFFFFFFF) — the zlib/gzip CRC the firmware writes into the
/// footer over everything but the four bytes the CRC occupies.
int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b & 0xFF;
    for (var i = 0; i < 8; i++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xEDB88320 & mask);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

class TrackHeader {
  final int version;
  final int flags;
  final int runSeq;
  final int startUptimeS;

  const TrackHeader({
    required this.version,
    required this.flags,
    required this.runSeq,
    required this.startUptimeS,
  });

  /// Whether [kRunFlagFinished] is set — see that constant for why a clear
  /// flag is still a run worth ingesting.
  bool get finished => flags & kRunFlagFinished != 0;
}

class TrackPoint {
  final int latE7;
  final int lonE7;
  final int tOffsetS;

  /// Elevation in decimetres, or null when the watch wrote the
  /// no-fix sentinel.
  final int? eleDm;

  /// Heart rate in BPM, or null when the watch wrote 0 (no sample).
  final int? bpm;

  const TrackPoint({
    required this.latE7,
    required this.lonE7,
    required this.tOffsetS,
    required this.eleDm,
    required this.bpm,
  });
}

class TrackFooter {
  final int distanceM;
  final int movingS;
  final int elapsedS;
  final int crc32;

  const TrackFooter({
    required this.distanceM,
    required this.movingS,
    required this.elapsedS,
    required this.crc32,
  });
}

class ManifestHeader {
  final int version;
  final int runCount;
  final int watchUptimeS;

  const ManifestHeader({
    required this.version,
    required this.runCount,
    required this.watchUptimeS,
  });
}

class ManifestEntry {
  final int runSeq;
  final int size;
  final int startUptimeS;

  const ManifestEntry({
    required this.runSeq,
    required this.size,
    required this.startUptimeS,
  });
}

class Manifest {
  final ManifestHeader header;
  final List<ManifestEntry> entries;

  const Manifest({required this.header, required this.entries});
}

ByteData _view(List<int> bytes) =>
    ByteData.sublistView(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

bool _magicMatches(List<int> bytes, int offset, String ascii) {
  if (offset + ascii.length > bytes.length) return false;
  for (var i = 0; i < ascii.length; i++) {
    if (bytes[offset + i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

TrackHeader decodeHeader(List<int> blob) {
  if (blob.length < _headerLen) {
    throw const FormatException('blob shorter than header');
  }
  if (!_magicMatches(blob, 0, 'TRK1')) {
    throw const FormatException('bad header magic (expected TRK1)');
  }
  final d = _view(blob);
  return TrackHeader(
    version: blob[4],
    flags: blob[5],
    runSeq: d.getUint32(8, Endian.little),
    startUptimeS: d.getUint32(12, Endian.little),
  );
}

/// Decode the point that starts at byte [offset].
TrackPoint decodePoint(List<int> blob, int offset) {
  if (offset + _pointLen > blob.length) {
    throw const FormatException('point out of range');
  }
  final d = _view(blob);
  final ele = d.getInt16(offset + 12, Endian.little);
  final bpm = blob[offset + 14];
  return TrackPoint(
    latE7: d.getInt32(offset, Endian.little),
    lonE7: d.getInt32(offset + 4, Endian.little),
    tOffsetS: d.getUint32(offset + 8, Endian.little),
    eleDm: ele == _eleNoneSentinel ? null : ele,
    bpm: bpm == 0 ? null : bpm,
  );
}

/// One closed lap persisted in the record stream (tag 1 at byte 15):
/// 1-based index, the lap's own distance in decimetres, and the lap's
/// elapsed + moving seconds.
class LapRecord {
  final int index;
  final int lapDistanceDm;
  final int splitS;
  final int movingS;

  const LapRecord({
    required this.index,
    required this.lapDistanceDm,
    required this.splitS,
    required this.movingS,
  });
}

/// Decode the lap record that starts at byte [offset].
LapRecord decodeLap(List<int> blob, int offset) {
  if (offset + _pointLen > blob.length) {
    throw const FormatException('lap record out of range');
  }
  final d = _view(blob);
  return LapRecord(
    index: d.getUint16(offset, Endian.little),
    lapDistanceDm: d.getUint32(offset + 2, Endian.little),
    splitS: d.getUint32(offset + 6, Endian.little),
    movingS: d.getUint32(offset + 10, Endian.little),
  );
}

/// One settled workout step's outcome persisted in the record stream
/// (tag 2 at byte 15, run-store v4): the 0-based expanded-step index,
/// whether it was skipped rather than completed, and what it banked —
/// distance in decimetres, whole seconds on the workout clock, and the
/// whole-step average pace (0 on the wire = none).
class WorkoutStepRecord {
  final int stepIndex;
  final bool skipped;
  final int distanceDm;
  final int durationS;
  final int? paceSecPerKm;

  const WorkoutStepRecord({
    required this.stepIndex,
    required this.skipped,
    required this.distanceDm,
    required this.durationS,
    required this.paceSecPerKm,
  });
}

/// Decode the step record that starts at byte [offset]. A status byte
/// outside the two known values is a malformed record inside a version this
/// decoder claims to support — thrown, like an unknown tag, never read as
/// "completed".
WorkoutStepRecord decodeWorkoutStep(List<int> blob, int offset) {
  if (offset + _pointLen > blob.length) {
    throw const FormatException('workout step record out of range');
  }
  final status = blob[offset + 1];
  if (status > 1) {
    throw FormatException('unknown workout step status $status');
  }
  final d = _view(blob);
  final pace = d.getUint16(offset + 10, Endian.little);
  return WorkoutStepRecord(
    stepIndex: blob[offset],
    skipped: status == 1,
    distanceDm: d.getUint32(offset + 2, Endian.little),
    durationS: d.getUint32(offset + 6, Endian.little),
    paceSecPerKm: pace == 0 ? null : pace,
  );
}

/// The armed workout's finalize-time summary (tag 3 at byte 15, run-store
/// v4): planned step count, the watch's >=80% roll-up, and the CRC32 of the
/// canonical `WKT1` frame for the armed step list — the attribution handle
/// that says WHICH pushed workout these step records ran.
class WorkoutSummaryRecord {
  final int stepTotal;
  final bool partial;
  final int frameCrc;

  const WorkoutSummaryRecord({
    required this.stepTotal,
    required this.partial,
    required this.frameCrc,
  });
}

/// Decode the workout summary record that starts at byte [offset].
WorkoutSummaryRecord decodeWorkoutSummary(List<int> blob, int offset) {
  if (offset + _pointLen > blob.length) {
    throw const FormatException('workout summary record out of range');
  }
  final rollup = blob[offset + 1];
  if (rollup > 1) {
    throw FormatException('unknown workout rollup $rollup');
  }
  final d = _view(blob);
  return WorkoutSummaryRecord(
    stepTotal: blob[offset],
    partial: rollup == 1,
    frameCrc: d.getUint32(offset + 2, Endian.little),
  );
}

TrackFooter decodeFooter(List<int> blob) {
  if (blob.length < _footerLen) {
    throw const FormatException('blob shorter than footer');
  }
  final base = blob.length - _footerLen;
  if (!_magicMatches(blob, base, 'END1')) {
    throw const FormatException('bad footer magic (expected END1)');
  }
  final d = _view(blob);
  return TrackFooter(
    distanceM: d.getUint32(base + 4, Endian.little),
    movingS: d.getUint32(base + 8, Endian.little),
    elapsedS: d.getUint32(base + 12, Endian.little),
    crc32: d.getUint32(base + 16, Endian.little),
  );
}

/// Number of track points a well-formed blob of [length] bytes carries,
/// or -1 if the length can't be a header+points+footer blob.
int _pointCount(int length) {
  final body = length - _headerLen - _footerLen;
  if (body < 0 || body % _pointLen != 0) return -1;
  return body ~/ _pointLen;
}

/// True iff [blob] is a structurally valid `run_store` blob whose footer
/// CRC matches a fresh CRC-32 over every byte the CRC covers — header,
/// records, and the footer's magic + totals. Any structural defect (short
/// blob, bad magic, misaligned length, CRC mismatch) returns false rather
/// than throwing, so a corrupt BLE transfer is dropped, never adopted as
/// a run.
///
/// The totals being inside the window is what makes this all-or-nothing:
/// a blob is trusted whole or refused whole, never trusted for its track
/// while its summary is quietly wrong.
bool verifyBlob(List<int> blob) {
  final n = _pointCount(blob.length);
  if (n < 0) return false;
  if (!_magicMatches(blob, 0, 'TRK1')) return false;
  final footerBase = blob.length - _footerLen;
  if (!_magicMatches(blob, footerBase, 'END1')) return false;
  final expected =
      _view(blob).getUint32(blob.length - _footerCrcLen, Endian.little);
  final actual = crc32(blob.sublist(0, blob.length - _footerCrcLen));
  return expected == actual;
}

Manifest decodeManifest(List<int> bytes) {
  const manHeaderLen = 12;
  const manEntryLen = 12;
  if (bytes.length < manHeaderLen) {
    throw const FormatException('manifest shorter than header');
  }
  if (!_magicMatches(bytes, 0, 'MAN1')) {
    throw const FormatException('bad manifest magic (expected MAN1)');
  }
  final d = _view(bytes);
  final header = ManifestHeader(
    version: bytes[4],
    runCount: bytes[5],
    watchUptimeS: d.getUint32(8, Endian.little),
  );
  final entries = <ManifestEntry>[];
  for (var i = 0; i < header.runCount; i++) {
    final base = manHeaderLen + i * manEntryLen;
    if (base + manEntryLen > bytes.length) {
      throw const FormatException('manifest truncated before all entries');
    }
    entries.add(ManifestEntry(
      runSeq: d.getUint32(base, Endian.little),
      size: d.getUint32(base + 4, Endian.little),
      startUptimeS: d.getUint32(base + 8, Endian.little),
    ));
  }
  return Manifest(header: header, entries: entries);
}

/// Encode a 10-byte ChunkRequest the phone writes to the watch to pull
/// `len` bytes of run `runSeq` starting at `offset`.
Uint8List encodeChunkRequest(int runSeq, int offset, int len) {
  final out = ByteData(10);
  out.setUint32(0, runSeq, Endian.little);
  out.setUint32(4, offset, Endian.little);
  out.setUint16(8, len, Endian.little);
  return out.buffer.asUint8List();
}

/// Reshape a verified run blob into the canonical watch-run payload
/// (`runFromWatchPayload`-shaped map).
///
/// The watch has no wall clock — it timestamps points as offsets from its
/// own monotonic uptime. We reconstruct the absolute start time on the
/// phone: at the moment the manifest is read, the watch reports its
/// current uptime (`manifestHeader.watchUptimeS`) and the run's start
/// uptime (`entry.startUptimeS`), so the run began roughly
/// `(watchUptimeS - startUptimeS)` seconds before [phoneNow]. This
/// approximation ignores BLE transfer latency and any watch/phone clock
/// drift accumulated during the run — acceptable for the tier-1 bench
/// prototype (see decisions.md; documented as the started_at
/// approximation).
///
/// A run recovered from a PRIOR power cycle has its `startUptimeS`
/// clamped by the watch to the current uptime (`flash_store.rs`
/// `manifest_at`), so the uptime offset under-ages it. The tell is an
/// offset shorter than the footer's `elapsedS` — a run cannot have
/// started less than its own elapsed time before its end — and in that
/// case we date the run as ending now-ish: `startedAt = phoneNow -
/// elapsedS`.
Map<String, dynamic> payloadFromBlob(
  List<int> blob,
  ManifestEntry entry,
  ManifestHeader manifestHeader,
  DateTime phoneNow,
) {
  final header = decodeHeader(blob);
  if (header.version < _minSupportedVersion ||
      header.version > _maxSupportedVersion) {
    // Fail closed at both ends: an unknown record layout decoded as points
    // would corrupt a track, and a pre-v3 blob's CRC never covered its
    // totals, so its summary is unverified even where its track checks out.
    throw FormatException(
        'unsupported run_store blob version ${header.version}');
  }
  final footer = decodeFooter(blob);
  final n = _pointCount(blob.length);
  if (n < 0) {
    throw const FormatException('blob is not a valid run_store blob');
  }
  final uptimeOffsetS = manifestHeader.watchUptimeS - entry.startUptimeS;
  final startedAt = phoneNow.toUtc().subtract(Duration(
        seconds:
            uptimeOffsetS < footer.elapsedS ? footer.elapsedS : uptimeOffsetS,
      ));

  final track = <Map<String, dynamic>>[];
  final laps = <Map<String, dynamic>>[];
  final stepResults = <Map<String, dynamic>>[];
  WorkoutSummaryRecord? workoutSummary;
  // Cumulative duration up to the start of the next lap — the registered
  // `start_offset_s` (metadata.md § laps: per-lap deltas on the wire, the
  // offset reconstructed by summing prior splits).
  var lapStartOffsetS = 0;
  for (var i = 0; i < n; i++) {
    final at = _headerLen + i * _pointLen;
    switch (blob[at + 15]) {
      case _recordTagPoint:
        final p = decodePoint(blob, at);
        track.add(<String, dynamic>{
          'lat': p.latE7 / 1e7,
          'lng': p.lonE7 / 1e7,
          'ele': p.eleDm == null ? null : p.eleDm! / 10.0,
          'ts': startedAt.add(Duration(seconds: p.tOffsetS)).toIso8601String(),
          'bpm': p.bpm,
        });
      case _recordTagLap:
        final lap = decodeLap(blob, at);
        laps.add(<String, dynamic>{
          'index': lap.index,
          'start_offset_s': lapStartOffsetS,
          'distance_m': lap.lapDistanceDm / 10.0,
          'duration_s': lap.splitS,
        });
        lapStartOffsetS += lap.splitS;
      case _recordTagStep:
        final step = decodeWorkoutStep(blob, at);
        stepResults.add(<String, dynamic>{
          'step_index': step.stepIndex,
          'status': step.skipped ? 'skipped' : 'completed',
          'actual_distance_m': step.distanceDm / 10.0,
          'duration_s': step.durationS,
          'actual_pace_sec_per_km': step.paceSecPerKm,
        });
      case _recordTagWorkout:
        workoutSummary = decodeWorkoutSummary(blob, at);
      default:
        // The CRC passed, so this is a record kind this decoder does not
        // know within a version it claims to support — a bug, not noise.
        throw FormatException('unknown record tag ${blob[at + 15]} at $at');
    }
  }

  // The workout trail is auxiliary to the run: semantic inconsistency drops
  // the SECTION, never the verified run. No summary means no attribution —
  // a run recovered from a mid-run checkpoint (the summary lands only at
  // finalize) or a firmware bug — and duplicate step indices mean the
  // workout was re-armed mid-run, splicing two trails this shape can't
  // represent. Both are discarded whole rather than attributed by guess.
  final indices = stepResults.map((r) => r['step_index']).toSet();
  final workoutConsistent =
      workoutSummary != null && indices.length == stepResults.length;

  return <String, dynamic>{
    'id': _uuid.v4(),
    'started_at': startedAt.toIso8601String(),
    'duration_s': footer.elapsedS,
    'distance_m': footer.distanceM.toDouble(),
    'source': 'watch',
    'track': track,
    'activity_type': 'run',
    'finished': header.finished,
    if (laps.isNotEmpty) 'laps': laps,
    if (workoutConsistent)
      'workout': <String, dynamic>{
        'step_total': workoutSummary.stepTotal,
        'adherence': workoutSummary.partial ? 'partial' : 'completed',
        'workout_crc': workoutSummary.frameCrc,
        'step_results': stepResults,
      },
  };
}

/// Transport seam over the BLE radio. The production implementation
/// (`ReactiveBleWatchTransport`) drives flutter_reactive_ble; tests
/// drive a fake that replays a canned blob. [WatchSyncClient] never
/// touches the radio directly — it only speaks to this interface — so
/// the full pull/decode/verify/reshape orchestration is testable with
/// no device attached.
abstract class WatchBleTransport {
  /// Scan for the watch's advertised service and connect. Completes when
  /// the manifest + chunk characteristics are ready to use.
  Future<void> scan();

  /// Read the raw manifest bytes (MAN1 header + entries).
  Future<List<int>> readManifest();

  /// Write a [encodeChunkRequest] payload asking the watch to stream a
  /// slice of a run.
  Future<void> writeChunkRequest(List<int> request);

  /// Write a [WatchSettings.encode] frame to the watch's settings
  /// characteristic — the phone → watch config push.
  Future<void> writeSettings(List<int> frame);

  /// Write one `offset(2 LE) | payload` chunk of a WKT1 workout frame
  /// (`chunkWorkout` in watch_workout.dart) to the watch's workout
  /// characteristic. Chunks must arrive in order, offset 0 first — the
  /// firmware's `WorkoutAssembler` resets on offset 0 and rejects gaps.
  Future<void> writeWorkout(List<int> chunk);

  /// Write one `offset(2 LE) | payload` chunk of a CRS1 course frame
  /// (`chunkCourse` in watch_course.dart) to the watch's course
  /// characteristic — the same in-order, offset-0-first contract the
  /// firmware's `CourseAssembler` enforces.
  Future<void> writeCourse(List<int> chunk);

  /// Write a whole `SCR1` composed-screen frame (`encodeWatchScreens` in
  /// watch_screens.dart) to the watch's screens characteristic. Unchunked:
  /// the set caps at 28 bytes, so one ATT write carries it and the frame
  /// the watch decodes is the complete answer to what screens it has.
  Future<void> writeScreens(List<int> frame);

  /// Write one `offset(2 LE) | payload` chunk of an RBK1 roadbook frame
  /// (`chunkRoadbook` in watch_roadbook.dart) to the watch's roadbook
  /// characteristic — the same in-order, offset-0-first contract the
  /// firmware's `RoadbookAssembler` enforces. Chunked rather than single-
  /// write like [writeScreens] because a full 16+16 schedule is 364 bytes,
  /// past one ATT write.
  Future<void> writeRoadbook(List<int> chunk);

  /// Notifications carrying run-blob chunks, in request order.
  Stream<List<int>> get chunkStream;

  /// Tear down the connection. Safe to call more than once.
  Future<void> disconnect();
}

class WatchSyncResult {
  final int synced;
  final int failed;
  final int total;

  const WatchSyncResult({
    required this.synced,
    required this.failed,
    required this.total,
  });
}

/// Delivers one decoded watch-run payload — `api.saveRun` when signed in,
/// otherwise `WatchIngestQueue.enqueue` (wired by the caller).
typedef WatchRunSink = Future<void> Function(Map<String, dynamic> payload);

/// Orchestrates a full watch → phone sync over an injected
/// [WatchBleTransport]: connect, read the manifest, pull each run in
/// chunks, verify its CRC, reshape it, and hand it to [onRun].
class WatchSyncClient {
  final WatchBleTransport transport;
  final WatchRunSink onRun;
  final int chunkSize;
  final Duration chunkTimeout;

  WatchSyncClient({
    required this.transport,
    required this.onRun,
    this.chunkSize = 180,
    this.chunkTimeout = const Duration(seconds: 15),
  });

  Future<WatchSyncResult> sync({
    void Function(int done, int total)? onProgress,
    DateTime Function()? now,
  }) async {
    final clock = now ?? DateTime.now;
    await transport.scan();
    try {
      final manifest = decodeManifest(await transport.readManifest());
      final total = manifest.entries.length;
      var synced = 0;
      var failed = 0;
      for (var i = 0; i < total; i++) {
        final entry = manifest.entries[i];
        try {
          final blob = await _pullRun(entry);
          if (blob.length != entry.size || !verifyBlob(blob)) {
            failed++;
          } else {
            await onRun(payloadFromBlob(blob, entry, manifest.header, clock()));
            synced++;
          }
        } catch (_) {
          failed++;
        }
        onProgress?.call(i + 1, total);
      }
      return WatchSyncResult(synced: synced, failed: failed, total: total);
    } finally {
      await transport.disconnect();
    }
  }

  /// Encode [settings] and push the single frame to the watch over the same
  /// injected [WatchBleTransport] the run-sync path uses: connect, write the
  /// settings characteristic, disconnect.
  Future<void> pushSettings(WatchSettings settings) async {
    await transport.scan();
    try {
      await transport.writeSettings(settings.encode());
    } finally {
      await transport.disconnect();
    }
  }

  /// Push a chunked WKT1 workout frame (`chunkWorkout` over
  /// `encodeWorkoutSteps`, watch_workout.dart — the chunking stays with the
  /// wire module, this client only carries bytes): connect, write every
  /// chunk in order, disconnect. The firmware arms the workout only once the
  /// last chunk completes the frame and its CRC checks out; a broken-off
  /// push leaves whatever was armed before, and the next offset-0 write
  /// starts clean.
  Future<void> pushWorkout(Iterable<List<int>> chunks) async {
    await transport.scan();
    try {
      for (final chunk in chunks) {
        await transport.writeWorkout(chunk);
      }
    } finally {
      await transport.disconnect();
    }
  }

  /// Push a chunked CRS1 course frame (`chunkCourse` over `encodeCourse`,
  /// watch_course.dart) — [pushWorkout]'s contract on the course
  /// characteristic: the firmware loads the course only once the last chunk
  /// completes the frame and its CRC checks out, a broken-off push leaves
  /// whatever was loaded before, and the next offset-0 write starts clean.
  Future<void> pushCourse(Iterable<List<int>> chunks) async {
    await transport.scan();
    try {
      for (final chunk in chunks) {
        await transport.writeCourse(chunk);
      }
    } finally {
      await transport.disconnect();
    }
  }

  /// Push a whole `SCR1` composed-screen frame (`encodeWatchScreens` in
  /// watch_screens.dart — the encoding stays with the wire module, this
  /// client only carries bytes). Unchunked, so [pushSettings]'s shape
  /// rather than [pushCourse]'s: one write is the complete set.
  ///
  /// A frame carrying a count of 0 is a legitimate push — it is how a
  /// runner clears the screens already on the watch.
  Future<void> pushScreens(List<int> frame) async {
    await transport.scan();
    try {
      await transport.writeScreens(frame);
    } finally {
      await transport.disconnect();
    }
  }

  /// Push a chunked RBK1 roadbook frame (`chunkRoadbook` over
  /// `encodeRoadbook`, watch_roadbook.dart) — [pushCourse]'s contract on the
  /// roadbook characteristic: the firmware loads the schedule only once the
  /// last chunk completes the frame and its CRC checks out, a broken-off push
  /// leaves whatever was loaded before, and the next offset-0 write starts
  /// clean.
  ///
  /// A frame carrying zero checkpoints and zero cut-offs is a legitimate push —
  /// it is how a runner clears the schedule already on the watch.
  Future<void> pushRoadbook(Iterable<List<int>> chunks) async {
    await transport.scan();
    try {
      for (final chunk in chunks) {
        await transport.writeRoadbook(chunk);
      }
    } finally {
      await transport.disconnect();
    }
  }

  Future<List<int>> _pullRun(ManifestEntry entry) async {
    final received = <int>[];
    final pending = <List<int>>[];
    Completer<List<int>>? waiting;

    final sub = transport.chunkStream.listen((chunk) {
      final w = waiting;
      if (w != null && !w.isCompleted) {
        waiting = null;
        w.complete(chunk);
      } else {
        pending.add(chunk);
      }
    });

    try {
      var offset = 0;
      while (received.length < entry.size) {
        final remaining = entry.size - received.length;
        final len = remaining < chunkSize ? remaining : chunkSize;
        await transport.writeChunkRequest(
          encodeChunkRequest(entry.runSeq, offset, len),
        );
        final List<int> chunk;
        if (pending.isNotEmpty) {
          chunk = pending.removeAt(0);
        } else {
          final c = Completer<List<int>>();
          waiting = c;
          chunk = await c.future.timeout(chunkTimeout);
        }
        if (chunk.isEmpty) break;
        received.addAll(chunk);
        offset += chunk.length;
      }
    } finally {
      await sub.cancel();
    }
    return received;
  }
}
