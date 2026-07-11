import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'watch_settings.dart';

/// Pure Dart mirror of the custom watch's `run_store` blob format
/// (`apps/custom_watch/core/src/run_store.rs`).
///
/// The watch records a run as a self-describing little-endian blob:
///
///   header(16) | point[N](16) | footer(20)
///
/// and exposes the set of runs over BLE as a manifest (a header + one
/// entry per stored run). The phone pulls each blob in chunks, verifies
/// its CRC, and reshapes it into the canonical watch-run payload that
/// [runFromWatchPayload] (watch_ingest_queue.dart) already consumes.
///
/// This module is deliberately pure — no BLE, no disk, no platform
/// channels — so the whole decode/verify/reshape path is unit-testable
/// against a frozen golden vector without a radio attached.
const int _headerLen = 16;
const int _pointLen = 16;
const int _footerLen = 20;

/// Sentinel written by the watch when a point has no barometric/GPS
/// elevation fix. Decoded to a null `ele`.
const int _eleNoneSentinel = -32768;

const _uuid = Uuid();

/// CRC-32 (IEEE / reflected, poly 0xEDB88320, init 0xFFFFFFFF, final
/// XOR 0xFFFFFFFF) — the zlib/gzip CRC the firmware writes into the
/// footer over `header + points`.
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
/// CRC matches a fresh CRC-32 over its `header + points`. Any structural
/// defect (short blob, bad magic, misaligned length, CRC mismatch)
/// returns false rather than throwing, so a corrupt BLE transfer is
/// dropped, never adopted as a run.
bool verifyBlob(List<int> blob) {
  final n = _pointCount(blob.length);
  if (n < 0) return false;
  if (!_magicMatches(blob, 0, 'TRK1')) return false;
  final footerBase = blob.length - _footerLen;
  if (!_magicMatches(blob, footerBase, 'END1')) return false;
  final expected = _view(blob).getUint32(footerBase + 16, Endian.little);
  final actual = crc32(blob.sublist(0, _headerLen + n * _pointLen));
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
Map<String, dynamic> payloadFromBlob(
  List<int> blob,
  ManifestEntry entry,
  ManifestHeader manifestHeader,
  DateTime phoneNow,
) {
  final footer = decodeFooter(blob);
  final n = _pointCount(blob.length);
  if (n < 0) {
    throw const FormatException('blob is not a valid run_store blob');
  }
  final startedAt = phoneNow
      .toUtc()
      .subtract(Duration(
        seconds: manifestHeader.watchUptimeS - entry.startUptimeS,
      ));

  final track = <Map<String, dynamic>>[];
  for (var i = 0; i < n; i++) {
    final p = decodePoint(blob, _headerLen + i * _pointLen);
    track.add(<String, dynamic>{
      'lat': p.latE7 / 1e7,
      'lng': p.lonE7 / 1e7,
      'ele': p.eleDm == null ? null : p.eleDm! / 10.0,
      'ts': startedAt.add(Duration(seconds: p.tOffsetS)).toIso8601String(),
      'bpm': p.bpm,
    });
  }

  return <String, dynamic>{
    'id': _uuid.v4(),
    'started_at': startedAt.toIso8601String(),
    'duration_s': footer.elapsedS,
    'distance_m': footer.distanceM.toDouble(),
    'source': 'watch',
    'track': track,
    'activity_type': 'run',
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
