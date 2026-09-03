import 'dart:async';
import 'dart:typed_data';

import 'package:core_models/core_models.dart' show MetadataKeys;
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show WorkoutStep, WorkoutStepKind;

import '../lib/sim_watch_sync.dart';
import '../lib/watch_course.dart';
import '../lib/watch_ingest_queue.dart';
import '../lib/watch_roadbook.dart';
import '../lib/watch_screens.dart';
import '../lib/watch_settings.dart';
import '../lib/watch_workout.dart';

/// The frozen v3 golden vector — one 3-point run blob, as pre-§356 (v3)
/// firmware wrote it. v4 only added record tags on the same CRC window, so
/// this must keep decoding: it is the still-in-a-bench-board's-flash compat
/// vector, and its bytes are frozen even though the firmware's own golden
/// now pins the v4 form ([_goldenV4Hex]).
///
/// Header byte 4 is the format version (`03`) and byte 5 is `01` —
/// [kRunFlagFinished], which the firmware stamps in `RunWriter::finalize`.
/// The trailing CRC covers both, every record, AND the footer's totals
/// (decisions §321); a mid-run checkpoint of the same points would be this
/// blob with byte 5 zero and a different CRC.
const _goldenHex =
    '54524b31030100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c02000039e3c091';

/// The frozen v3 golden vector with a closed lap (index 1, 1 km, 5:00
/// split, 290 s moving) interleaved after point 2 — the pre-§356 form of
/// the firmware's `golden_blob_with_a_lap_is_stable`, kept decodable like
/// [_goldenHex].
const _goldenLapHex =
    '54524b31030100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '0100102700002c010000220100000001'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c0200008d2b643c';

/// The frozen v4 golden — the same 3-point run as pre-§1026 (v4) firmware
/// wrote it, altitudes still in decimetres. Kept decodable for the same
/// reason [_goldenHex] is: a bench board's flash may still hold one. Only the
/// version byte and the CRC differ from [_goldenHex].
const _goldenV4Hex =
    '54524b31040100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c02000001f8ef8c';

/// The frozen v4 lap golden, kept decodable like [_goldenV4Hex].
const _goldenV4LapHex =
    '54524b31040100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '0100102700002c010000220100000001'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c0200001ac2224c';

/// The frozen v4 workout golden, kept decodable like [_goldenV4Hex]: two
/// settled step records interleaved in stream order (step 0 completed —
/// 400 m / 95 s / 238 s/km; step 1 skipped — 51.2 m / 30 s / no pace) and the
/// finalize-time summary (3 planned steps, partial, WKT1 frame CRC
/// 0x0BADF00D).
const _goldenV4WorkoutHex =
    '54524b31040100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    '0000a00f00005f000000ee0000000002'
    'e4cfd9170c0141c101000000723f7a00'
    '0101000200001e000000000000000002'
    '74d1d917000341c10200000000800000'
    '03010df0ad0b00000000000000000003'
    '454e4431d2040000580200006c0200000895c50c';

/// The same 3-point run as today's v5 firmware writes it — byte-identical
/// to the firmware's `golden_blob_is_stable`, so a wire-format drift on
/// either side is caught here. v5 stores each point's altitude in whole
/// METRES rather than decimetres (decisions §1026), so the two elevation
/// bytes read `5806` / `5a06` (1624 m / 1626 m) where [_goldenV4Hex] read
/// `703f` / `723f` (16240 dm / 16242 dm).
const _goldenV5Hex =
    '54524b31050100000700000029000000'
    'b8ced91718ff40c10000000058067800'
    'e4cfd9170c0141c1010000005a067a00'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c0200007b613b01';

/// The v5 lap golden — byte-identical to the firmware's
/// `golden_blob_with_a_lap_is_stable`.
const _goldenV5LapHex =
    '54524b31050100000700000029000000'
    'b8ced91718ff40c10000000058067800'
    'e4cfd9170c0141c1010000005a067a00'
    '0100102700002c010000220100000001'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c020000b95df241';

/// The v5 workout golden — byte-identical to the firmware's
/// `golden_blob_with_workout_records_is_stable`.
const _goldenV5WorkoutHex =
    '54524b31050100000700000029000000'
    'b8ced91718ff40c10000000058067800'
    '0000a00f00005f000000ee0000000002'
    'e4cfd9170c0141c1010000005a067a00'
    '0101000200001e000000000000000002'
    '74d1d917000341c10200000000800000'
    '03010df0ad0b00000000000000000003'
    '454e4431d2040000580200006c02000023450760';

/// The v1 and v2 goldens as prior firmware wrote them. v3 widened the CRC
/// window to take in the footer totals, so their checksums no longer
/// describe the bytes they precede — kept here to pin the compat decision:
/// they are rejected, not decoded.
const _v1GoldenHex =
    '54524b31010000000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c02000077fdfebd';
const _v2GoldenHex =
    '54524b31020100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c020000566db750';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _goldenBlob() => _hex(_goldenHex);
Uint8List _goldenLapBlob() => _hex(_goldenLapHex);

/// The golden as the firmware's `checkpoint_blob` would have written it
/// mid-run: [kRunFlagFinished] clear, and the footer CRC recomputed over the
/// changed prefix so the blob still verifies. This is what boot recovery
/// serves after a reset interrupted the run.
Uint8List _checkpointBlob() {
  final blob = _goldenBlob();
  blob[5] = 0;
  final crc = crc32(blob.sublist(0, blob.length - 4));
  ByteData.sublistView(blob).setUint32(blob.length - 4, crc, Endian.little);
  return blob;
}

/// Hand-build a v4 blob over the golden's three points with a configurable
/// workout trail — two step records (optionally sharing an index) and the
/// summary unless [withSummary] is false. These are the semantically
/// inconsistent shapes the fail-closed section-drop rules pin: a checkpoint
/// recovered without its finalize-time summary, and a re-armed workout's
/// spliced double trail.
Uint8List _buildWorkoutBlob(
    {required bool withSummary, bool duplicateIndex = false}) {
  final golden = _goldenBlob();
  final body = BytesBuilder();
  final header = Uint8List.fromList(golden.sublist(0, 16));
  header[4] = 4;
  body.add(header);
  Uint8List step(int index) {
    final d = ByteData(16);
    d.setUint8(0, index);
    d.setUint32(2, 4000, Endian.little);
    d.setUint32(6, 95, Endian.little);
    d.setUint16(10, 238, Endian.little);
    d.setUint8(15, 2); // step tag
    return d.buffer.asUint8List();
  }

  body.add(golden.sublist(16, 32));
  body.add(step(0));
  body.add(golden.sublist(32, 48));
  body.add(step(duplicateIndex ? 0 : 1));
  body.add(golden.sublist(48, 64));
  if (withSummary) {
    final d = ByteData(16);
    d.setUint8(0, 3);
    d.setUint8(1, 1);
    d.setUint32(2, 0x0BADF00D, Endian.little);
    d.setUint8(15, 3); // summary tag
    body.add(d.buffer.asUint8List());
  }
  final prefix = body.toBytes();
  final footer = Uint8List.fromList(golden.sublist(golden.length - 20));
  final crc = crc32([...prefix, ...footer.sublist(0, 16)]);
  ByteData.sublistView(footer).setUint32(16, crc, Endian.little);
  return Uint8List.fromList([...prefix, ...footer]);
}

/// MAN1 manifest describing exactly the golden run: watch uptime 700 s,
/// one entry run_seq=7 size=84 start_uptime=41 — a same-boot run whose
/// uptime offset (659 s) covers the footer's 620 s elapsed.
Uint8List _goldenManifest({int watchUptimeS = 700, int startUptimeS = 41}) {
  final d = ByteData(12 + 12);
  d.setUint8(0, 'M'.codeUnitAt(0));
  d.setUint8(1, 'A'.codeUnitAt(0));
  d.setUint8(2, 'N'.codeUnitAt(0));
  d.setUint8(3, '1'.codeUnitAt(0));
  d.setUint8(4, 3); // version
  d.setUint8(5, 1); // run_count
  d.setUint32(8, watchUptimeS, Endian.little); // watch_uptime_s
  d.setUint32(12, 7, Endian.little); // run_seq
  d.setUint32(16, 84, Endian.little); // size
  d.setUint32(20, startUptimeS, Endian.little); // start_uptime_s
  return d.buffer.asUint8List();
}

/// Fake transport that replays [blob] slice-by-slice in answer to each
/// chunk request, and hands back [manifest] on read.
class FakeWatchTransport implements WatchBleTransport {
  final List<int> blob;
  final List<int> manifest;
  final _chunks = StreamController<List<int>>.broadcast();
  int scanCount = 0;
  int disconnectCount = 0;
  final requests = <List<int>>[];
  final settingsWrites = <List<int>>[];
  final workoutWrites = <List<int>>[];
  final courseWrites = <List<int>>[];
  final screensWrites = <List<int>>[];
  final roadbookWrites = <List<int>>[];

  FakeWatchTransport({required this.blob, required this.manifest});

  @override
  Stream<List<int>> get chunkStream => _chunks.stream;

  @override
  Future<void> scan() async {
    scanCount++;
  }

  @override
  Future<List<int>> readManifest() async => manifest;

  /// The verdict the watch answers `push_status` reads with, newest first.
  /// Empty means the firmware has none to give — an unconfirmed push.
  List<List<int>> pushStatusReads = const [];
  int pushStatusReadCount = 0;

  @override
  Future<List<int>> readPushStatus() async {
    final at = pushStatusReadCount++;
    if (at >= pushStatusReads.length) {
      return pushStatusReads.isEmpty ? const [] : pushStatusReads.last;
    }
    return pushStatusReads[at];
  }

  @override
  Future<void> writeChunkRequest(List<int> request) async {
    requests.add(request);
    final d = ByteData.sublistView(Uint8List.fromList(request));
    final offset = d.getUint32(4, Endian.little);
    final len = d.getUint16(8, Endian.little);
    final end = (offset + len) > blob.length ? blob.length : (offset + len);
    final chunk = blob.sublist(offset, end);
    scheduleMicrotask(() => _chunks.add(chunk));
  }

  @override
  Future<void> writeSettings(List<int> frame) async {
    settingsWrites.add(frame);
  }

  @override
  Future<void> writeWorkout(List<int> chunk) async {
    workoutWrites.add(chunk);
  }

  @override
  Future<void> writeCourse(List<int> chunk) async {
    courseWrites.add(chunk);
  }

  @override
  Future<void> writeScreens(List<int> frame) async {
    screensWrites.add(frame);
  }

  @override
  Future<void> writeRoadbook(List<int> chunk) async {
    roadbookWrites.add(chunk);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    await _chunks.close();
  }
}

void main() {
  group('crc32', () {
    test('matches the zlib check value for "123456789"', () {
      expect(crc32('123456789'.codeUnits), 0xCBF43926);
    });
  });

  group('golden vector decode', () {
    final blob = _goldenBlob();

    test('blob is 84 bytes', () {
      expect(blob.length, 84);
    });

    test('header', () {
      final h = decodeHeader(blob);
      expect(h.version, 3);
      expect(h.flags, kRunFlagFinished);
      expect(h.finished, isTrue);
      expect(h.runSeq, 7);
      expect(h.startUptimeS, 41);
    });

    test('three points decode exactly', () {
      final p0 = decodePoint(blob, 16, 3);
      expect(p0.latE7, 400150200);
      expect(p0.lonE7, -1052705000);
      expect(p0.tOffsetS, 0);
      expect(p0.eleMetres, closeTo(1624.0, 1e-9));
      expect(p0.bpm, 120);

      final p1 = decodePoint(blob, 32, 3);
      expect(p1.latE7, 400150500);
      expect(p1.lonE7, -1052704500);
      expect(p1.tOffsetS, 1);
      expect(p1.eleMetres, closeTo(1624.2, 1e-9));
      expect(p1.bpm, 122);

      final p2 = decodePoint(blob, 48, 3);
      expect(p2.latE7, 400150900);
      expect(p2.lonE7, -1052704000);
      expect(p2.tOffsetS, 2);
      expect(p2.eleMetres, isNull); // -32768 sentinel
      expect(p2.bpm, isNull); // 0 sentinel
    });

    test('footer', () {
      final f = decodeFooter(blob);
      expect(f.distanceM, 1234);
      expect(f.movingS, 600);
      expect(f.elapsedS, 620);
      expect(f.crc32, 0x91c0e339);
    });

    test('verifyBlob is true for the untouched golden vector', () {
      expect(verifyBlob(blob), isTrue);
    });

    // v3's whole point: the CRC covers every byte but the four it occupies,
    // so no position in the blob is unprotected. Through v2 the 12 summary
    // bytes at offsets 68..80 sat outside the window and a flip there was
    // undetectable — a run that verified with wrong distance / moving /
    // elapsed. This is exhaustive precisely so that hole cannot reappear.
    test('flipping ANY byte of the blob fails verification', () {
      for (var i = 0; i < blob.length; i++) {
        final mutated = Uint8List.fromList(blob);
        mutated[i] ^= 0x01;
        expect(verifyBlob(mutated), isFalse,
            reason: 'byte $i flip should fail verification');
      }
    });

    test('the footer summary bytes are inside the CRC window', () {
      // Named separately from the exhaustive sweep above so the regression
      // this closes is stated, not inferred.
      for (var i = 84 - 20 + 4; i < 84 - 4; i++) {
        final mutated = Uint8List.fromList(blob);
        mutated[i] ^= 0x01;
        expect(verifyBlob(mutated), isFalse,
            reason: 'byte $i is distance/moving/elapsed and must be covered');
      }
    });

    test('a pre-v3 blob is rejected, never decoded', () {
      // The compat decision (decisions §321): v1/v2 checksums cover a
      // narrower window, so re-admitting them would re-open the unprotected
      // totals hole. There are no deployed devices to migrate.
      final m = decodeManifest(_goldenManifest());
      for (final hex in [_v1GoldenHex, _v2GoldenHex]) {
        final old = _hex(hex);
        expect(verifyBlob(old), isFalse);
        expect(
          () => payloadFromBlob(
              old, m.entries.single, m.header, DateTime.utc(2026, 7, 8)),
          throwsFormatException,
        );
      }
    });
  });

  group('manifest + chunk request', () {
    test('decodeManifest', () {
      final m = decodeManifest(_goldenManifest());
      expect(m.header.version, 3);
      expect(m.header.runCount, 1);
      expect(m.header.watchUptimeS, 700);
      expect(m.entries, hasLength(1));
      expect(m.entries.single.runSeq, 7);
      expect(m.entries.single.size, 84);
      expect(m.entries.single.startUptimeS, 41);
    });

    test('encodeChunkRequest round-trips through the LE layout', () {
      final req = encodeChunkRequest(7, 40, 20);
      expect(req, hasLength(10));
      final d = ByteData.sublistView(req);
      expect(d.getUint32(0, Endian.little), 7);
      expect(d.getUint32(4, Endian.little), 40);
      expect(d.getUint16(8, Endian.little), 20);
    });
  });

  group('payloadFromBlob', () {
    test('reshapes the golden run with the started_at approximation', () {
      final m = decodeManifest(_goldenManifest());
      final phoneNow = DateTime.utc(2026, 7, 8, 12, 0, 0);
      final payload = payloadFromBlob(
        _goldenBlob(),
        m.entries.single,
        m.header,
        phoneNow,
      );

      // started_at = phoneNow - (watch_uptime 700 - start_uptime 41) = -659 s.
      expect(payload['started_at'], DateTime.utc(2026, 7, 8, 11, 49, 1).toIso8601String());
      expect(payload['duration_s'], 620); // elapsed_s
      expect(payload['distance_m'], 1234.0);
      expect(payload['source'], 'watch');
      expect(payload['activity_type'], 'run');
      expect((payload['id'] as String), isNotEmpty);

      final track = (payload['track'] as List).cast<Map<String, dynamic>>();
      expect(track, hasLength(3));
      expect(track[0]['lat'], closeTo(40.0150200, 1e-9));
      expect(track[0]['lng'], closeTo(-105.2705000, 1e-9));
      expect(track[0]['ele'], closeTo(1624.0, 1e-9));
      expect(track[0]['bpm'], 120);
      expect(track[0]['ts'], DateTime.utc(2026, 7, 8, 11, 49, 1).toIso8601String());
      expect(track[2]['ts'], DateTime.utc(2026, 7, 8, 11, 49, 3).toIso8601String());
      expect(track[2]['ele'], isNull);
      expect(track[2]['bpm'], isNull);
    });

    test('the lap golden carries the finished flag the firmware stamps', () {
      // The one byte separating a committed run from a mid-run checkpoint of the
      // same points. It sits inside the CRC-covered prefix, so clearing it
      // without recomputing the CRC must fail verification — a checkpoint can
      // never be promoted to "finished" by bit-rot in transit.
      final blob = _goldenLapBlob();
      final h = decodeHeader(blob);
      expect(h.flags, kRunFlagFinished);
      expect(h.finished, isTrue);

      final tampered = Uint8List.fromList(blob);
      tampered[5] = 0;
      expect(verifyBlob(tampered), isFalse);
    });

    test('a finished blob ingests with no recovered_unfinished key', () {
      final m = decodeManifest(_goldenManifest());
      final payload = payloadFromBlob(
        _goldenBlob(),
        m.entries.single,
        m.header,
        DateTime.utc(2026, 7, 8, 12),
      );
      expect(payload['finished'], isTrue);

      final run = runFromWatchPayload(payload);
      expect(run.metadata?.containsKey(MetadataKeys.recoveredUnfinished),
          isNot(isTrue),
          reason: 'a normal finished run must not carry the key at all');
    });

    test('a boot-recovered checkpoint ingests flagged recovered_unfinished',
        () {
      final blob = _checkpointBlob();
      expect(verifyBlob(blob), isTrue,
          reason: 'the recomputed CRC must still verify');
      expect(decodeHeader(blob).finished, isFalse);

      final m = decodeManifest(_goldenManifest());
      final payload = payloadFromBlob(
        blob,
        m.entries.single,
        m.header,
        DateTime.utc(2026, 7, 8, 12),
      );
      expect(payload['finished'], isFalse);

      // The totals are the checkpoint's totals-so-far, and the run says so.
      final run = runFromWatchPayload(payload);
      expect(run.metadata?[MetadataKeys.recoveredUnfinished], isTrue);
      expect(run.duration, const Duration(seconds: 620));
    });

    test('a blob with a lap yields the registered metadata.laps shape', () {
      final blob = _goldenLapBlob();
      expect(verifyBlob(blob), isTrue, reason: 'lap golden must verify');
      // The manifest advertises the blob's real size (4 records = 100 B).
      final m = decodeManifest(_goldenManifest());
      final phoneNow = DateTime.utc(2026, 7, 8, 12, 0, 0);
      final payload = payloadFromBlob(blob, m.entries.single, m.header, phoneNow);

      // Points decode exactly as in v1 — the lap record is not a point.
      final track = (payload['track'] as List).cast<Map<String, dynamic>>();
      expect(track, hasLength(3));
      expect(track[0]['lat'], closeTo(40.0150200, 1e-9));
      expect(track[2]['ele'], isNull);

      // The lap lands in the registered shape (metadata.md § laps):
      // per-lap deltas + a reconstructed start_offset_s.
      final laps = (payload['laps'] as List).cast<Map<String, dynamic>>();
      expect(laps, hasLength(1));
      expect(laps[0]['index'], 1);
      expect(laps[0]['start_offset_s'], 0);
      expect(laps[0]['distance_m'], closeTo(1000.0, 1e-9));
      expect(laps[0]['duration_s'], 300);

      // And runFromWatchPayload forwards them into Run.metadata.
      final run = runFromWatchPayload(payload);
      final metaLaps = (run.metadata?['laps'] as List?)?.cast<Map>();
      expect(metaLaps, isNotNull);
      expect(metaLaps, hasLength(1));
      expect(metaLaps![0]['duration_s'], 300);
    });

    test('consecutive laps accumulate start_offset_s from prior splits', () {
      // Hand-build a blob: two laps back to back (no points needed for
      // the offset math).
      final body = BytesBuilder();
      final header = ByteData(16);
      header.setUint8(0, 0x54); // T
      header.setUint8(1, 0x52); // R
      header.setUint8(2, 0x4b); // K
      header.setUint8(3, 0x31); // 1
      header.setUint8(4, 3); // current format version
      header.setUint32(8, 9, Endian.little);
      header.setUint32(12, 0, Endian.little);
      body.add(header.buffer.asUint8List());
      for (final (i, split) in [(1, 300), (2, 420)]) {
        final lap = ByteData(16);
        lap.setUint16(0, i, Endian.little);
        lap.setUint32(2, 10000, Endian.little);
        lap.setUint32(6, split, Endian.little);
        lap.setUint32(10, split - 10, Endian.little);
        lap.setUint8(15, 1); // lap tag
        body.add(lap.buffer.asUint8List());
      }
      final prefix = body.toBytes();
      final footer = ByteData(20);
      footer.setUint8(0, 0x45); // E
      footer.setUint8(1, 0x4e); // N
      footer.setUint8(2, 0x44); // D
      footer.setUint8(3, 0x31); // 1
      footer.setUint32(4, 2000, Endian.little);
      footer.setUint32(8, 700, Endian.little);
      footer.setUint32(12, 720, Endian.little);
      // The CRC covers the prefix AND the footer's magic + totals — every
      // byte but the four it lands in.
      final footerBytes = footer.buffer.asUint8List();
      footer.setUint32(
          16, crc32([...prefix, ...footerBytes.sublist(0, 16)]), Endian.little);
      final blob = Uint8List.fromList([...prefix, ...footerBytes]);
      expect(verifyBlob(blob), isTrue);

      final m = decodeManifest(_goldenManifest(watchUptimeS: 800, startUptimeS: 0));
      final payload = payloadFromBlob(
          blob, m.entries.single, m.header, DateTime.utc(2026, 7, 8));
      final laps = (payload['laps'] as List).cast<Map<String, dynamic>>();
      expect(laps[0]['start_offset_s'], 0);
      expect(laps[1]['start_offset_s'], 300, reason: 'sum of prior splits');
      expect(laps[1]['duration_s'], 420);
    });

    test('a blob newer than the supported format is rejected, never misread',
        () {
      final blob = Uint8List.fromList(_goldenLapBlob());
      // One past the ceiling. `_maxSupportedVersion` is held equal to the
      // firmware's own `FORMAT_VERSION` by
      // scripts/check_watch_wire_vectors.mjs, so this stays one past whatever
      // the watch currently writes.
      blob[4] = 6;
      // Re-stamp the CRC so ONLY the version gate can reject it.
      final d = ByteData.sublistView(blob);
      d.setUint32(blob.length - 4, crc32(blob.sublist(0, blob.length - 4)),
          Endian.little);
      expect(verifyBlob(blob), isTrue, reason: 'structurally valid');
      final m = decodeManifest(_goldenManifest());
      expect(
        () => payloadFromBlob(
            blob, m.entries.single, m.header, DateTime.utc(2026, 7, 8)),
        throwsFormatException,
      );
    });

    test('the v4 goldens decode identically to their v3 forms', () {
      // v4 changed nothing about points, laps, or the CRC window — the
      // version exists so a v3-only reader rejects a blob that may carry
      // workout tags instead of throwing mid-walk.
      final m = decodeManifest(_goldenManifest());
      final phoneNow = DateTime.utc(2026, 7, 8, 12, 0, 0);
      for (final (v3, v4) in [
        (_goldenHex, _goldenV4Hex),
        (_goldenLapHex, _goldenV4LapHex),
      ]) {
        expect(verifyBlob(_hex(v4)), isTrue);
        final a = payloadFromBlob(_hex(v3), m.entries.single, m.header, phoneNow);
        final b = payloadFromBlob(_hex(v4), m.entries.single, m.header, phoneNow);
        for (final key in ['duration_s', 'distance_m', 'finished']) {
          expect(b[key], a[key]);
        }
        expect(b['track'], a['track']);
        expect(b['laps'], a['laps']);
        expect(b.containsKey('workout'), isFalse,
            reason: 'no workout records, no workout section');
      }
    });

    test('the v5 goldens decode with their altitudes in metres', () {
      // The bytes are the firmware's current output, so this is the pair the
      // wire guard compares. Everything but the altitude is identical to the
      // v4 golden's payload: the version moved one field's UNIT, not the
      // layout, so the run is the same run.
      final m = decodeManifest(_goldenManifest());
      final phoneNow = DateTime.utc(2026, 7, 8, 12, 0, 0);
      for (final (v4, v5) in [
        (_goldenV4Hex, _goldenV5Hex),
        (_goldenV4LapHex, _goldenV5LapHex),
      ]) {
        expect(verifyBlob(_hex(v5)), isTrue);
        final a =
            payloadFromBlob(_hex(v4), m.entries.single, m.header, phoneNow);
        final b =
            payloadFromBlob(_hex(v5), m.entries.single, m.header, phoneNow);
        for (final key in ['duration_s', 'distance_m', 'finished']) {
          expect(b[key], a[key]);
        }
        expect(b['laps'], a['laps']);
        final track = b['track'] as List<dynamic>;
        final was = a['track'] as List<dynamic>;
        expect(track.length, was.length);
        for (var i = 0; i < track.length; i++) {
          final p = track[i] as Map<String, dynamic>;
          final q = was[i] as Map<String, dynamic>;
          for (final key in ['lat', 'lng', 'ts', 'bpm']) {
            expect(p[key], q[key], reason: 'point $i $key');
          }
        }
        expect((track[0] as Map)['ele'], closeTo(1624.0, 1e-9));
        expect((track[1] as Map)['ele'], closeTo(1626.0, 1e-9));
        expect((track[2] as Map)['ele'], isNull);
      }
    });

    test('the same altitude bytes mean ten times more under v5', () {
      // The whole reason the unit resolves against the header version rather
      // than being assumed. Nothing about these bytes is wrong — the CRC
      // matches, every field decodes — so reading a v3/v4 blob as metres, or a
      // v5 one as decimetres, is a silent tenfold error in the one metric this
      // watch exists for.
      final m = decodeManifest(_goldenManifest());
      final phoneNow = DateTime.utc(2026, 7, 8, 12, 0, 0);
      final relabelled = _hex(_goldenV4Hex);
      relabelled[4] = 5;
      final crc = crc32(relabelled.sublist(0, relabelled.length - 4));
      ByteData.sublistView(relabelled)
          .setUint32(relabelled.length - 4, crc, Endian.little);
      expect(verifyBlob(relabelled), isTrue);
      final payload =
          payloadFromBlob(relabelled, m.entries.single, m.header, phoneNow);
      final track = payload['track'] as List<dynamic>;
      expect((track[0] as Map)['ele'], closeTo(16240.0, 1e-9));
      expect(eleMetresFromStored(16240, kEleMetresVersion - 1),
          closeTo(1624.0, 1e-9));
      expect(eleMetresFromStored(16240, kEleMetresVersion), 16240.0);
      // The sentinel is unit-independent — no version ever meant it as a
      // height, so it must not resolve to a depth on either side.
      expect(eleMetresFromStored(-32768, 3), isNull);
      expect(eleMetresFromStored(-32768, kEleMetresVersion), isNull);
    });

    test('the workout golden yields the attributable workout section', () {
      final blob = _hex(_goldenV5WorkoutHex);
      expect(verifyBlob(blob), isTrue, reason: 'workout golden must verify');
      final m = decodeManifest(_goldenManifest());
      final payload = payloadFromBlob(
          blob, m.entries.single, m.header, DateTime.utc(2026, 7, 8, 12));

      // Points decode exactly as before — the workout records are not points.
      expect((payload['track'] as List), hasLength(3));

      // The v4 form of the same run still decodes to the same workout
      // section: v5 moved the altitude unit, which the workout tags do not
      // carry, so a board still holding a v4 blob loses nothing here.
      final v4 = payloadFromBlob(_hex(_goldenV4WorkoutHex), m.entries.single,
          m.header, DateTime.utc(2026, 7, 8, 12));
      expect(v4['workout'], payload['workout']);

      final workout = payload['workout'] as Map<String, dynamic>;
      expect(workout['step_total'], 3);
      expect(workout['adherence'], 'partial');
      expect(workout['workout_crc'], 0x0BADF00D);
      final steps =
          (workout['step_results'] as List).cast<Map<String, dynamic>>();
      expect(steps, hasLength(2));
      expect(steps[0]['step_index'], 0);
      expect(steps[0]['status'], 'completed');
      expect(steps[0]['actual_distance_m'], closeTo(400.0, 1e-9));
      expect(steps[0]['duration_s'], 95);
      expect(steps[0]['actual_pace_sec_per_km'], 238);
      expect(steps[1]['step_index'], 1);
      expect(steps[1]['status'], 'skipped');
      expect(steps[1]['actual_distance_m'], closeTo(51.2, 1e-9));
      expect(steps[1]['duration_s'], 30);
      expect(steps[1]['actual_pace_sec_per_km'], isNull);

      // And runFromWatchPayload forwards the section whole into
      // metadata.watch_workout (registered in docs/backend/metadata.md).
      final run = runFromWatchPayload(payload);
      final meta = run.metadata?[MetadataKeys.watchWorkout] as Map?;
      expect(meta, isNotNull);
      expect(meta!['workout_crc'], 0x0BADF00D);
      expect((meta['step_results'] as List), hasLength(2));
    });

    test('step records without a summary are dropped, keeping the run', () {
      // A run recovered from a mid-run checkpoint carries settled steps but
      // no summary (the summary lands only at finalize): no attribution, so
      // the auxiliary section is discarded whole — never attributed by
      // guessing which workout the phone pushed last.
      final blob = _buildWorkoutBlob(withSummary: false);
      expect(verifyBlob(blob), isTrue);
      final m = decodeManifest(_goldenManifest());
      final payload = payloadFromBlob(
          blob, m.entries.single, m.header, DateTime.utc(2026, 7, 8));
      expect(payload.containsKey('workout'), isFalse);
      expect((payload['track'] as List), hasLength(3),
          reason: 'the verified run itself is kept');
    });

    test('duplicate step indices drop the workout section, keeping the run',
        () {
      // A workout re-armed mid-run splices two trails into one blob; the
      // flat shape cannot represent that honestly, so it is discarded whole.
      final blob = _buildWorkoutBlob(withSummary: true, duplicateIndex: true);
      expect(verifyBlob(blob), isTrue);
      final m = decodeManifest(_goldenManifest());
      final payload = payloadFromBlob(
          blob, m.entries.single, m.header, DateTime.utc(2026, 7, 8));
      expect(payload.containsKey('workout'), isFalse);
      expect((payload['track'] as List), hasLength(3));
    });

    test('an unknown step status byte throws like an unknown tag', () {
      final blob = Uint8List.fromList(_hex(_goldenV4WorkoutHex));
      // Byte 1 of the first step record (the second 16-byte cell).
      blob[16 + 16 + 1] = 2;
      final d = ByteData.sublistView(blob);
      d.setUint32(blob.length - 4, crc32(blob.sublist(0, blob.length - 4)),
          Endian.little);
      expect(verifyBlob(blob), isTrue, reason: 'only the status is wrong');
      final m = decodeManifest(_goldenManifest());
      expect(
        () => payloadFromBlob(
            blob, m.entries.single, m.header, DateTime.utc(2026, 7, 8)),
        throwsFormatException,
      );
    });

    test('a recovered prior-boot run dates from the footer elapsed fallback',
        () {
      // The watch clamps a prior-boot start_uptime_s to the current uptime
      // (flash_store.rs manifest_at), so the manifest reads uptime 100 /
      // start 100: offset 0 < elapsed 620 → the run must predate this boot.
      final m = decodeManifest(_goldenManifest(
        watchUptimeS: 100,
        startUptimeS: 100,
      ));
      final phoneNow = DateTime.utc(2026, 7, 8, 12, 0, 0);
      final payload = payloadFromBlob(
        _goldenBlob(),
        m.entries.single,
        m.header,
        phoneNow,
      );

      // started_at = phoneNow - elapsed_s 620, not phoneNow - offset 0.
      expect(payload['started_at'],
          DateTime.utc(2026, 7, 8, 11, 49, 40).toIso8601String());
      final track = (payload['track'] as List).cast<Map<String, dynamic>>();
      expect(track[0]['ts'],
          DateTime.utc(2026, 7, 8, 11, 49, 40).toIso8601String());
      expect(track[2]['ts'],
          DateTime.utc(2026, 7, 8, 11, 49, 42).toIso8601String());
    });

    test('a partially clamped offset (offset < elapsed) also falls back', () {
      // uptime 100 - start 41 = 59 s < elapsed 620 s: impossible for a
      // same-boot run, so it dates as ending now-ish.
      final m = decodeManifest(_goldenManifest(
        watchUptimeS: 100,
        startUptimeS: 41,
      ));
      final payload = payloadFromBlob(
        _goldenBlob(),
        m.entries.single,
        m.header,
        DateTime.utc(2026, 7, 8, 12, 0, 0),
      );
      expect(payload['started_at'],
          DateTime.utc(2026, 7, 8, 11, 49, 40).toIso8601String());
    });

    test('an offset just past elapsed keeps the uptime dating', () {
      // uptime 662 - start 41 = 621 s >= elapsed 620 s: consistent, so the
      // uptime offset wins (fallback would say 11:49:40).
      final m = decodeManifest(_goldenManifest(
        watchUptimeS: 662,
        startUptimeS: 41,
      ));
      final payload = payloadFromBlob(
        _goldenBlob(),
        m.entries.single,
        m.header,
        DateTime.utc(2026, 7, 8, 12, 0, 0),
      );
      expect(payload['started_at'],
          DateTime.utc(2026, 7, 8, 11, 49, 39).toIso8601String());
    });

    test('the reshaped payload feeds runFromWatchPayload cleanly', () {
      final m = decodeManifest(_goldenManifest());
      final payload = payloadFromBlob(
        _goldenBlob(),
        m.entries.single,
        m.header,
        DateTime.utc(2026, 7, 8, 12, 0, 0),
      );
      final run = runFromWatchPayload(payload);
      expect(run.source.name, 'watch');
      expect(run.distanceMetres, 1234.0);
      expect(run.duration.inSeconds, 620);
      expect(run.track, hasLength(3));
      expect(run.track.first.bpm, 120);
      expect(run.track.first.elevationMetres, closeTo(1624.0, 1e-9));
      expect(run.track.last.bpm, isNull);
      expect(run.metadata?['activity_type'], 'run');
    });
  });

  group('WatchSyncClient orchestration (fake transport)', () {
    test('pulls, verifies, reshapes and delivers the golden run in chunks',
        () async {
      final transport = FakeWatchTransport(
        blob: _goldenBlob(),
        manifest: _goldenManifest(),
      );
      final delivered = <Map<String, dynamic>>[];
      final progress = <int>[];

      final client = WatchSyncClient(
        transport: transport,
        onRun: (p) async => delivered.add(p),
        chunkSize: 20, // 84 bytes → 20,20,20,20,4
      );

      final result = await client.sync(
        onProgress: (done, total) => progress.add(done),
        now: () => DateTime.utc(2026, 7, 8, 12, 0, 0),
      );

      expect(result.total, 1);
      expect(result.synced, 1);
      expect(result.failed, 0);
      expect(transport.scanCount, 1);
      expect(transport.disconnectCount, 1);
      expect(transport.requests, hasLength(5)); // 20*4 + 4
      expect(progress, [1]);

      expect(delivered, hasLength(1));
      final run = runFromWatchPayload(delivered.single);
      expect(run.distanceMetres, 1234.0);
      expect(run.track, hasLength(3));
    });

    test('a CRC-corrupt blob is counted failed, never delivered', () async {
      final corrupt = _goldenBlob();
      corrupt[20] ^= 0xFF; // mangle a point byte inside the CRC window
      final transport = FakeWatchTransport(
        blob: corrupt,
        manifest: _goldenManifest(),
      );
      final delivered = <Map<String, dynamic>>[];

      final client = WatchSyncClient(
        transport: transport,
        onRun: (p) async => delivered.add(p),
        chunkSize: 32,
      );
      final result = await client.sync();

      expect(result.synced, 0);
      expect(result.failed, 1);
      expect(delivered, isEmpty);
      expect(transport.disconnectCount, 1);
    });
  });

  group('WatchSyncClient.pushSettings (fake transport)', () {
    test('connects, writes the encoded frame, disconnects', () async {
      final transport = FakeWatchTransport(
        blob: _goldenBlob(),
        manifest: _goldenManifest(),
      );
      final client = WatchSyncClient(
        transport: transport,
        onRun: (_) async {},
      );

      await client.pushSettings(const WatchSettings(
        maxHr: 190,
        pacer: (distanceM: 42195, timeS: 14400),
        gear: (baselineM: 500000.0, targetM: 800000.0),
        zoneCeiling: 3,
      ));

      expect(transport.scanCount, 1);
      expect(transport.disconnectCount, 1);
      expect(transport.settingsWrites, hasLength(1));
      expect(transport.requests, isEmpty);
      final frame = Uint8List.fromList(transport.settingsWrites.single);
      expect(
        frame,
        _hex('53455431080f0000be00d3a40000403800000024f4480050434903f8e6c33f'),
      );
    });
  });

  group('WatchSyncClient.pushWorkout (fake transport)', () {
    List<WorkoutStep> steps() => [
          const WorkoutStep(
            kind: WorkoutStepKind.warmup,
            targetDistanceMetres: 800,
            targetPaceSecPerKm: 360,
            toleranceSecPerKm: 10,
            label: 'w',
          ),
          const WorkoutStep(
            kind: WorkoutStepKind.rep,
            repIndex: 1,
            repTotal: 1,
            targetDistanceMetres: 400,
            targetPaceSecPerKm: 240,
            toleranceSecPerKm: 10,
            label: 'r',
          ),
        ];

    test('connects, writes every chunk in order, disconnects', () async {
      final transport = FakeWatchTransport(
        blob: _goldenBlob(),
        manifest: _goldenManifest(),
      );
      final client = WatchSyncClient(
        transport: transport,
        onRun: (_) async {},
      );

      final frame = encodeWorkoutSteps(steps());
      // A payload cap far below the frame length forces several chunks, so
      // this pins the in-order offset walk, not just a single write.
      final chunks = chunkWorkout(frame, payloadMax: 10);
      expect(chunks.length, greaterThan(2));
      await client.pushWorkout(chunks);

      expect(transport.scanCount, 1);
      expect(transport.disconnectCount, 1);
      expect(transport.requests, isEmpty);
      expect(transport.workoutWrites, hasLength(chunks.length));
      // Offsets lead each chunk, ascending from 0, and the payloads
      // reassemble the exact sealed frame.
      final reassembled = <int>[];
      var expectedOffset = 0;
      for (final chunk in transport.workoutWrites) {
        final d = ByteData.sublistView(Uint8List.fromList(chunk));
        expect(d.getUint16(0, Endian.little), expectedOffset);
        reassembled.addAll(chunk.sublist(2));
        expectedOffset = reassembled.length;
      }
      expect(reassembled, frame);
    });

    test('a failed chunk write still disconnects', () async {
      final transport = _WorkoutWriteFailsTransport();
      final client = WatchSyncClient(
        transport: transport,
        onRun: (_) async {},
      );
      await expectLater(
        client.pushWorkout(chunkWorkout(encodeWorkoutSteps(steps()))),
        throwsStateError,
      );
      expect(transport.disconnectCount, 1,
          reason: 'the finally must release the radio');
    });
  });

  group('WatchSyncClient.pushCourse (fake transport)', () {
    List<CoursePoint> points() => const [
          CoursePoint(40.0158083, -105.2705),
          CoursePoint(40.015, -105.2705),
          CoursePoint(40.015, -105.269445),
        ];

    test('connects, writes every chunk in order, disconnects', () async {
      final transport = FakeWatchTransport(
        blob: _goldenBlob(),
        manifest: _goldenManifest(),
      );
      final client = WatchSyncClient(
        transport: transport,
        onRun: (_) async {},
      );

      final frame = encodeCourse(points(), elevationM: const [1650, 1655, 1640]);
      // A payload cap below the frame length forces several chunks, so this
      // pins the in-order offset walk on the course characteristic too.
      final chunks = chunkCourse(frame, payloadMax: 12);
      expect(chunks.length, greaterThan(2));
      await client.pushCourse(chunks);

      expect(transport.scanCount, 1);
      expect(transport.disconnectCount, 1);
      expect(transport.workoutWrites, isEmpty,
          reason: 'a course push must not touch the workout characteristic');
      expect(transport.courseWrites, hasLength(chunks.length));
      final reassembled = <int>[];
      var expectedOffset = 0;
      for (final chunk in transport.courseWrites) {
        final d = ByteData.sublistView(Uint8List.fromList(chunk));
        expect(d.getUint16(0, Endian.little), expectedOffset);
        reassembled.addAll(chunk.sublist(2));
        expectedOffset = reassembled.length;
      }
      expect(reassembled, frame);
    });

    test('a failed chunk write still disconnects', () async {
      final transport = _CourseWriteFailsTransport();
      final client = WatchSyncClient(
        transport: transport,
        onRun: (_) async {},
      );
      await expectLater(
        client.pushCourse(chunkCourse(encodeCourse(points()))),
        throwsStateError,
      );
      expect(transport.disconnectCount, 1,
          reason: 'the finally must release the radio');
    });
  });

  group('WatchSyncClient.pushRoadbook (fake transport)', () {
    WatchRoadbookCheckpoint cp(int i) => WatchRoadbookCheckpoint(
          cumDistanceM: i * 5000.0,
          legDistanceM: 5000,
          projectedElapsedSec: i * 1800,
          cutoff: WatchCutoffStatus.safe,
          isRefill: i.isEven,
        );

    /// The worst case at the caps: 16 checkpoints + 16 cut-offs = 444 B, which
    /// is past the 242-byte chunk payload, so a full schedule takes exactly two
    /// writes. This is the boundary the firmware's assembler exists for.
    test('a full-cap schedule takes two writes at the real payload cap',
        () async {
      final transport = FakeWatchTransport(
        blob: _goldenBlob(),
        manifest: _goldenManifest(),
      );
      final client = WatchSyncClient(transport: transport, onRun: (_) async {});

      final frame = encodeRoadbook(
        [for (var i = 1; i <= kMaxRoadbookCheckpoints; i++) cp(i)],
        [
          for (var i = 1; i <= kMaxRoadbookCutoffs; i++)
            WatchCutoffLeg(cumDistanceM: i * 5000.0, limitElapsedSec: i * 2400),
        ],
      );
      expect(frame.length, 444);
      final chunks = chunkRoadbook(frame);
      expect(chunks, hasLength(2));

      await client.pushRoadbook(chunks);

      expect(transport.scanCount, 1);
      expect(transport.disconnectCount, 1);
      expect(transport.courseWrites, isEmpty,
          reason: 'a roadbook push must not touch the course characteristic');
      expect(transport.roadbookWrites, hasLength(2));

      final reassembled = <int>[];
      var expectedOffset = 0;
      for (final chunk in transport.roadbookWrites) {
        final d = ByteData.sublistView(Uint8List.fromList(chunk));
        expect(d.getUint16(0, Endian.little), expectedOffset);
        reassembled.addAll(chunk.sublist(2));
        expectedOffset = reassembled.length;
      }
      expect(reassembled, frame);
    });

    test('a short schedule rides one write', () async {
      final transport = FakeWatchTransport(
        blob: _goldenBlob(),
        manifest: _goldenManifest(),
      );
      final client = WatchSyncClient(transport: transport, onRun: (_) async {});

      final frame = encodeRoadbook(
        [cp(1), cp(2)],
        const [WatchCutoffLeg(cumDistanceM: 10000, limitElapsedSec: 5400)],
      );
      expect(frame.length, lessThanOrEqualTo(kRoadbookChunkPayloadMax));
      await client.pushRoadbook(chunkRoadbook(frame));

      expect(transport.roadbookWrites, hasLength(1));
      expect(transport.roadbookWrites.single.sublist(2), frame);
    });

    test('an empty schedule still pushes — it is how a runner clears one',
        () async {
      final transport = FakeWatchTransport(
        blob: _goldenBlob(),
        manifest: _goldenManifest(),
      );
      final client = WatchSyncClient(transport: transport, onRun: (_) async {});

      await client.pushRoadbook(chunkRoadbook(encodeRoadbook(const [], const [])));

      expect(transport.roadbookWrites, hasLength(1));
      expect(transport.disconnectCount, 1);
    });

    test('an over-cap series is refused before the radio is opened', () async {
      final transport = FakeWatchTransport(
        blob: _goldenBlob(),
        manifest: _goldenManifest(),
      );
      final client = WatchSyncClient(transport: transport, onRun: (_) async {});

      // The encoder refuses rather than trimming (matching the firmware), so a
      // caller that chunks-then-pushes throws before pushRoadbook is reached —
      // no scan, no partial schedule left on the watch.
      expect(
        () => client.pushRoadbook(chunkRoadbook(encodeRoadbook(
          [for (var i = 0; i <= kMaxRoadbookCheckpoints; i++) cp(i)],
          const [],
        ))),
        throwsArgumentError,
      );
      expect(transport.roadbookWrites, isEmpty);
      expect(transport.scanCount, 0,
          reason: 'a refused schedule must not even open the radio');
    });

    test('a failed chunk write still disconnects', () async {
      final transport = _RoadbookWriteFailsTransport();
      final client = WatchSyncClient(transport: transport, onRun: (_) async {});
      await expectLater(
        client.pushRoadbook(
          chunkRoadbook(encodeRoadbook([cp(1)], const [])),
        ),
        throwsStateError,
      );
      expect(transport.disconnectCount, 1,
          reason: 'the finally must release the radio');
    });
  });

  group('push verdicts (push_status)', () {
    List<int> psh1(int seq, WatchPushKind kind, {required bool accepted}) => [
          ...'PSH1'.codeUnits,
          seq,
          WatchPushKind.values.indexOf(kind),
          accepted ? 1 : 0,
        ];

    List<CoursePoint> points() => const [
          CoursePoint(40.0158083, -105.2705),
          CoursePoint(40.015, -105.2705),
        ];
    List<WorkoutStep> steps() => const [
          WorkoutStep(
            kind: WorkoutStepKind.warmup,
            targetDistanceMetres: 800,
            targetPaceSecPerKm: 360,
            toleranceSecPerKm: 10,
            label: 'w',
          ),
        ];
    WatchRoadbookCheckpoint cp() => const WatchRoadbookCheckpoint(
          cumDistanceM: 5000.0,
          legDistanceM: 5000,
          projectedElapsedSec: 1800,
          cutoff: WatchCutoffStatus.safe,
          isRefill: false,
        );

    /// Every push, with the call that drives it — so a new push characteristic
    /// cannot be added without a verdict path.
    final everyPush = <WatchPushKind, Future<void> Function(WatchSyncClient)>{
      WatchPushKind.settings: (c) => c.pushSettings(const WatchSettings(
            maxHr: 190,
            pacer: (distanceM: 42195, timeS: 14400),
            gear: (baselineM: 500000.0, targetM: 800000.0),
            zoneCeiling: 3,
          )),
      WatchPushKind.course: (c) =>
          c.pushCourse(chunkCourse(encodeCourse(points()))),
      WatchPushKind.workout: (c) =>
          c.pushWorkout(chunkWorkout(encodeWorkoutSteps(steps()))),
      WatchPushKind.screens: (c) => c.pushScreens(encodeWatchScreens(const [])),
      WatchPushKind.roadbook: (c) =>
          c.pushRoadbook(chunkRoadbook(encodeRoadbook([cp()], const []))),
    };

    WatchSyncClient clientFor(FakeWatchTransport t) => WatchSyncClient(
          transport: t,
          onRun: (_) async {},
          pushConfirmInterval: Duration.zero,
        );

    test('a refused push throws instead of reporting sent', () async {
      // The defect: an ATT write-with-response is the SoftDevice's answer,
      // not the firmware's, so all five of these completed as successes while
      // the watch kept the OLD value.
      for (final entry in everyPush.entries) {
        final transport = FakeWatchTransport(blob: const [], manifest: const [])
          ..pushStatusReads = [
            psh1(4, entry.key, accepted: true),
            psh1(5, entry.key, accepted: false),
          ];
        await expectLater(
          entry.value(clientFor(transport)),
          throwsA(isA<WatchPushRejected>()
              .having((e) => e.kind, 'kind', entry.key)),
          reason: '${entry.key.name} reported success on a refusal',
        );
        expect(transport.disconnectCount, 1,
            reason: 'the finally must still release the radio');
      }
    });

    test('an accepted push completes', () async {
      for (final entry in everyPush.entries) {
        final transport = FakeWatchTransport(blob: const [], manifest: const [])
          ..pushStatusReads = [
            psh1(4, entry.key, accepted: false),
            psh1(5, entry.key, accepted: true),
          ];
        await entry.value(clientFor(transport));
        expect(transport.disconnectCount, 1);
      }
    });

    test('a watch with no verdict to give leaves the push unconfirmed',
        () async {
      // Firmware predating the characteristic, or a read that failed: the
      // push must complete as it always did. This path has never run on
      // hardware, so it must not be able to turn a working push into a
      // reported failure.
      final transport = FakeWatchTransport(blob: const [], manifest: const []);
      await clientFor(transport).pushCourse(chunkCourse(encodeCourse(points())));
      expect(transport.courseWrites, isNotEmpty);
    });

    test('an unmoved sequence never invents a rejection', () async {
      // The watch's LAST verdict may well be a refusal from an earlier push.
      // Only a MOVED sequence is this push's answer; a stale one that read as
      // a rejection would send the runner to re-push what is already loaded.
      final transport = FakeWatchTransport(blob: const [], manifest: const [])
        ..pushStatusReads = [psh1(9, WatchPushKind.course, accepted: false)];
      await clientFor(transport).pushCourse(chunkCourse(encodeCourse(points())));
      expect(transport.courseWrites, isNotEmpty);
    });

    test("another push's refusal is not this push's verdict", () async {
      final transport = FakeWatchTransport(blob: const [], manifest: const [])
        ..pushStatusReads = [
          psh1(1, WatchPushKind.course, accepted: true),
          psh1(2, WatchPushKind.settings, accepted: false),
        ];
      await clientFor(transport).pushCourse(chunkCourse(encodeCourse(points())));
      expect(transport.courseWrites, isNotEmpty);
    });

    test('the first read after a write may still be the previous verdict',
        () async {
      // A read is a separate ATT transaction and the SoftDevice can answer it
      // before the firmware's handler has run, so confirmation polls.
      final transport = FakeWatchTransport(blob: const [], manifest: const [])
        ..pushStatusReads = [
          psh1(7, WatchPushKind.course, accepted: true),
          psh1(7, WatchPushKind.course, accepted: true),
          psh1(7, WatchPushKind.course, accepted: true),
          psh1(8, WatchPushKind.course, accepted: false),
        ];
      await expectLater(
        clientFor(transport).pushCourse(chunkCourse(encodeCourse(points()))),
        throwsA(isA<WatchPushRejected>()),
      );
    });

    test('decodePushStatus fails closed on anything that is not a verdict', () {
      final good = psh1(3, WatchPushKind.roadbook, accepted: true);
      expect(decodePushStatus(good)?.seq, 3);
      expect(decodePushStatus(good)?.kind, WatchPushKind.roadbook);
      expect(decodePushStatus(good)?.accepted, isTrue);

      expect(decodePushStatus(const []), isNull);
      expect(decodePushStatus(good.sublist(0, good.length - 1)), isNull,
          reason: 'a short read is not a verdict');
      expect(decodePushStatus([...'CRS1'.codeUnits, ...good.sublist(4)]), isNull,
          reason: 'a foreign magic is not a verdict');
      final unknownKind = [...good]..[5] = WatchPushKind.values.length;
      expect(decodePushStatus(unknownKind), isNull);
      final badVerdict = [...good]..[6] = 2;
      expect(decodePushStatus(badVerdict), isNull);
    });

    test('the kind indices are the firmware wire discriminants', () {
      // watch_core::ble_sync::PushKind — append only, never reorder. A shift
      // here relabels every banner and every verdict, invisibly (§ 410).
      expect(WatchPushKind.values.map((k) => k.index).toList(),
          [0, 1, 2, 3, 4]);
      expect(WatchPushKind.settings.index, 0);
      expect(WatchPushKind.course.index, 1);
      expect(WatchPushKind.workout.index, 2);
      expect(WatchPushKind.screens.index, 3);
      expect(WatchPushKind.roadbook.index, 4);
    });
  });
}

class _RoadbookWriteFailsTransport extends FakeWatchTransport {
  _RoadbookWriteFailsTransport() : super(blob: const [], manifest: const []);

  @override
  Future<void> writeRoadbook(List<int> chunk) async {
    throw StateError('radio dropped');
  }
}

class _CourseWriteFailsTransport extends FakeWatchTransport {
  _CourseWriteFailsTransport() : super(blob: const [], manifest: const []);

  @override
  Future<void> writeCourse(List<int> chunk) async {
    throw StateError('radio dropped');
  }
}

class _WorkoutWriteFailsTransport extends FakeWatchTransport {
  _WorkoutWriteFailsTransport() : super(blob: const [], manifest: const []);

  @override
  Future<void> writeWorkout(List<int> chunk) async {
    throw StateError('radio dropped');
  }
}
