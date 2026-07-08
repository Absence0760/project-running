import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart';
import '../lib/watch_ingest_queue.dart';

/// The frozen golden vector — one 3-point run blob. Kept byte-identical to
/// the firmware's `run_store` test vector so a wire-format drift on either
/// side is caught here.
const _goldenHex =
    '54524b31010000000700000029000000'
    'b8ced91718ff40c100000000703f7800'
    'e4cfd9170c0141c101000000723f7a00'
    '74d1d917000341c10200000000800000'
    '454e4431d2040000580200006c02000077fdfebd';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _goldenBlob() => _hex(_goldenHex);

/// MAN1 manifest describing exactly the golden run: watch uptime 100 s,
/// one entry run_seq=7 size=84 start_uptime=41.
Uint8List _goldenManifest() {
  final d = ByteData(12 + 12);
  d.setUint8(0, 'M'.codeUnitAt(0));
  d.setUint8(1, 'A'.codeUnitAt(0));
  d.setUint8(2, 'N'.codeUnitAt(0));
  d.setUint8(3, '1'.codeUnitAt(0));
  d.setUint8(4, 1); // version
  d.setUint8(5, 1); // run_count
  d.setUint32(8, 100, Endian.little); // watch_uptime_s
  d.setUint32(12, 7, Endian.little); // run_seq
  d.setUint32(16, 84, Endian.little); // size
  d.setUint32(20, 41, Endian.little); // start_uptime_s
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
      expect(h.version, 1);
      expect(h.flags, 0);
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
      expect(f.crc32, 0xbdfefd77);
    });

    test('verifyBlob is true for the untouched golden vector', () {
      expect(verifyBlob(blob), isTrue);
    });

    // The footer CRC is defined over header+points only (bytes 0..64), plus
    // this verifier also revalidates the TRK1/END1 magics and the crc field
    // itself. The 12 footer summary bytes distance/moving/elapsed
    // (offsets 68..80) are, by the frozen wire spec, NOT inside the CRC
    // window, so a flip there is genuinely undetectable — pinned explicitly
    // below so a future "tighten verifyBlob" change can't silently regress
    // the wire contract.
    const uncoveredStart = 84 - 20 + 4; // 68: first byte after END1 magic
    const uncoveredEnd = 84 - 4; // 80: first byte of the crc field
    test('flipping any CRC-covered / magic / crc-field byte fails verify', () {
      for (var i = 0; i < blob.length; i++) {
        if (i >= uncoveredStart && i < uncoveredEnd) continue;
        final mutated = Uint8List.fromList(blob);
        mutated[i] ^= 0x01;
        expect(verifyBlob(mutated), isFalse,
            reason: 'byte $i flip should fail verification');
      }
    });

    test('footer summary bytes are outside the CRC window (frozen spec)', () {
      for (var i = uncoveredStart; i < uncoveredEnd; i++) {
        final mutated = Uint8List.fromList(blob);
        mutated[i] ^= 0x01;
        expect(verifyBlob(mutated), isTrue,
            reason: 'byte $i is distance/moving/elapsed, not CRC-protected');
      }
    });
  });

  group('manifest + chunk request', () {
    test('decodeManifest', () {
      final m = decodeManifest(_goldenManifest());
      expect(m.header.version, 1);
      expect(m.header.runCount, 1);
      expect(m.header.watchUptimeS, 100);
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

      // started_at = phoneNow - (watch_uptime 100 - start_uptime 41) = -59 s.
      expect(payload['started_at'], DateTime.utc(2026, 7, 8, 11, 59, 1).toIso8601String());
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
      expect(track[0]['ts'], DateTime.utc(2026, 7, 8, 11, 59, 1).toIso8601String());
      expect(track[2]['ts'], DateTime.utc(2026, 7, 8, 11, 59, 3).toIso8601String());
      expect(track[2]['ele'], isNull);
      expect(track[2]['bpm'], isNull);
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
}
