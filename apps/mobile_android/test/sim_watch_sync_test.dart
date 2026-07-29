import 'dart:async';
import 'dart:typed_data';

import 'package:core_models/core_models.dart' show MetadataKeys;
import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart';
import '../lib/watch_ingest_queue.dart';
import '../lib/watch_settings.dart';

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

/// The same 3-point run as today's v4 firmware writes it — byte-identical
/// to the firmware's `golden_blob_is_stable`, so a wire-format drift on
/// either side is caught here. Only the version byte and the CRC differ
/// from [_goldenHex].
const _goldenV4Hex =
    '54524b31040100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c02000001f8ef8c';

/// The v4 lap golden — byte-identical to the firmware's
/// `golden_blob_with_a_lap_is_stable`.
const _goldenV4LapHex =
    '54524b31040100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '0100102700002c010000220100000001'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c0200001ac2224c';

/// The v4 workout golden — byte-identical to the firmware's
/// `golden_blob_with_workout_records_is_stable`: two settled step records
/// interleaved in stream order (step 0 completed — 400 m / 95 s / 238 s/km;
/// step 1 skipped — 51.2 m / 30 s / no pace) and the finalize-time summary
/// (3 planned steps, partial, WKT1 frame CRC 0x0BADF00D).
const _goldenWorkoutHex =
    '54524b31040100000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    '0000a00f00005f000000ee0000000002'
    'e4cfd9170c0141c101000000723f7a00'
    '0101000200001e000000000000000002'
    '74d1d917000341c10200000000800000'
    '03010df0ad0b00000000000000000003'
    '454e4431d2040000580200006c0200000895c50c';

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

  FakeWatchTransport({required this.blob, required this.manifest});

  @override
  Stream<List<int>> get chunkStream => _chunks.stream;

  @override
  Future<void> scan() async {
    scanCount++;
  }

  @override
  Future<List<int>> readManifest() async => manifest;

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
      final p0 = decodePoint(blob, 16);
      expect(p0.latE7, 400150200);
      expect(p0.lonE7, -1052705000);
      expect(p0.tOffsetS, 0);
      expect(p0.eleDm, 16240);
      expect(p0.bpm, 120);

      final p1 = decodePoint(blob, 32);
      expect(p1.latE7, 400150500);
      expect(p1.lonE7, -1052704500);
      expect(p1.tOffsetS, 1);
      expect(p1.eleDm, 16242);
      expect(p1.bpm, 122);

      final p2 = decodePoint(blob, 48);
      expect(p2.latE7, 400150900);
      expect(p2.lonE7, -1052704000);
      expect(p2.tOffsetS, 2);
      expect(p2.eleDm, isNull); // -32768 sentinel
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
      blob[4] = 5; // future version
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

    test('the workout golden yields the attributable workout section', () {
      final blob = _hex(_goldenWorkoutHex);
      expect(verifyBlob(blob), isTrue, reason: 'workout golden must verify');
      final m = decodeManifest(_goldenManifest());
      final payload = payloadFromBlob(
          blob, m.entries.single, m.header, DateTime.utc(2026, 7, 8, 12));

      // Points decode exactly as before — the workout records are not points.
      expect((payload['track'] as List), hasLength(3));

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
      final blob = Uint8List.fromList(_hex(_goldenWorkoutHex));
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
        _hex('53455431050f00be00d3a40000403800000024f44800504349036caa74de'),
      );
    });
  });
}
