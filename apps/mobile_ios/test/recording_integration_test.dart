import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart';

import '../lib/local_run_store.dart';
import '../lib/sync_service.dart';

/// Integration test for the GPS → record → save → sync golden path.
///
/// Drives the four components end-to-end:
///   1. A fake [GeolocatorPlatform] feeds synthetic positions.
///   2. [RunRecorder] consumes them through the real prepare → begin →
///      filter chain.
///   3. The recorded track is persisted to [LocalRunStore] (real
///      filesystem, scoped to a tempDir).
///   4. [SyncService.debugTrySync] drains the unsynced run through a
///      fake [ApiClient] that captures the batch.
///
/// Stops short of the full RunScreen UI (which would need additional
/// mocks for Pedometer / WakelockPlus / flutter_tts / flutter_local_notifications
/// — out of scope for this integration check). Covers the data
/// pipeline: that's where regressions would be silent and dangerous.

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permissionState = LocationPermission.always;
  StreamController<Position>? _positions;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permissionState;

  @override
  Future<LocationPermission> requestPermission() async => permissionState;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    _positions ??= StreamController<Position>.broadcast();
    return _positions!.stream;
  }

  void emit(Position p) {
    _positions ??= StreamController<Position>.broadcast();
    _positions!.add(p);
  }

  void emitError(Object error) {
    _positions?.addError(error);
  }

  Future<void> dispose() async {
    await _positions?.close();
    _positions = null;
  }
}

class _CapturingApiClient extends ApiClient {
  String? fakeUserId = 'integration-test-user';

  final List<List<String>> savedBatchIds = [];
  int saveBatchCallCount = 0;

  @override
  String? get userId => fakeUserId;

  @override
  Future<void> saveRunsBatch(
    List<cm.Run> runs, {
    int uploadConcurrency = 8,
    int rowChunkSize = 100,
    void Function(int saved)? onProgress,
  }) async {
    saveBatchCallCount++;
    savedBatchIds.add(runs.map((r) => r.id).toList());
  }
}

Position _pos({
  required double metresEast,
  required int secondsFromStart,
  double accuracy = 5,
}) {
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;
  return Position(
    longitude: lngBase + metresEast / metrePerDegLng,
    latitude: lat,
    timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
    accuracy: accuracy,
    altitude: 400,
    altitudeAccuracy: 2,
    heading: 90,
    headingAccuracy: 5,
    speed: 2.5,
    speedAccuracy: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGeolocatorPlatform fake;
  late Directory tempDir;
  late LocalRunStore runStore;

  setUp(() async {
    fake = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = fake;

    tempDir = Directory.systemTemp.createTempSync('recording_integration_');
    runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tempDir);
  });

  tearDown(() async {
    await fake.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('full pipeline — GPS feed → recorder → LocalRunStore → SyncService → API',
      () async {
    // ── 1. Recorder consumes the synthetic GPS feed ──
    final recorder = RunRecorder();
    await recorder.prepare();
    // Drain async setup so the listen() callback is wired before we
    // start emitting. Without this the first position gets silently
    // dropped.
    await Future<void>.delayed(Duration.zero);

    recorder.begin();

    // 6 fixes, 10 m apart, one per second → ~50 m of accumulated track.
    for (var i = 0; i < 6; i++) {
      fake.emit(_pos(metresEast: (i * 10).toDouble(), secondsFromStart: i));
      await Future<void>.delayed(Duration.zero);
    }

    final track = recorder.debugTrack;
    expect(track.length, greaterThanOrEqualTo(2),
        reason: 'recorder should have captured the synthetic feed');
    final distance = recorder.debugDistanceMetres;
    expect(distance, greaterThan(20),
        reason: 'recorder should have accumulated distance from real movement');

    // ── 2. "Finish" — build a Run and persist to LocalRunStore ──
    final waypoints = track
        .map((w) => cm.Waypoint(
              lat: w.lat,
              lng: w.lng,
              elevationMetres: w.elevationMetres,
              timestamp: w.timestamp,
              bpm: w.bpm,
            ))
        .toList();
    final run = cm.Run(
      id: 'integration-test-run-1',
      startedAt: DateTime(2026, 4, 10, 10, 0, 0),
      duration: recorder.debugElapsed,
      distanceMetres: distance,
      track: waypoints,
      source: cm.RunSource.app,
    );
    await runStore.save(run);

    expect(runStore.runs.length, 1);
    expect(runStore.runs.first.id, 'integration-test-run-1');
    expect(runStore.unsyncedCount, 1,
        reason: 'fresh save should be marked unsynced');

    // ── 3. SyncService drains the unsynced run via the fake API ──
    final api = _CapturingApiClient();
    final sync = SyncService(apiClient: api, runStore: runStore);
    await sync.debugTrySync('integration');

    expect(api.saveBatchCallCount, 1,
        reason: 'SyncService should have pushed the unsynced run in one batch');
    expect(api.savedBatchIds, [
      ['integration-test-run-1'],
    ]);
    expect(runStore.unsyncedCount, 0,
        reason: 'SyncService should have flipped the run to synced');

    recorder.dispose();
  });

  test('pipeline survives a stream error mid-recording (recorder + store still consistent)',
      () async {
    final recorder = RunRecorder();
    await recorder.prepare();
    await Future<void>.delayed(Duration.zero);

    recorder.begin();

    fake.emit(_pos(metresEast: 0, secondsFromStart: 0));
    fake.emit(_pos(metresEast: 10, secondsFromStart: 1));
    await Future<void>.delayed(Duration.zero);

    // Simulate the OS tearing down the GPS stream mid-run. The
    // recorder cancels its subscription on error (cancelOnError: true);
    // the underlying broadcast controller stays open in the fake but
    // the recorder isn't listening anymore.
    fake.emitError(Exception('OS torn down'));
    await Future<void>.delayed(Duration.zero);

    // Try to save what we have — the partial track should be preserved.
    final track = recorder.debugTrack;
    expect(track.isNotEmpty, isTrue,
        reason: 'pre-error positions should be preserved in the track');

    final waypoints = track
        .map((w) => cm.Waypoint(
              lat: w.lat,
              lng: w.lng,
              elevationMetres: w.elevationMetres,
              timestamp: w.timestamp,
              bpm: w.bpm,
            ))
        .toList();
    final run = cm.Run(
      id: 'partial-run-after-error',
      startedAt: DateTime(2026, 4, 10, 10, 0, 0),
      duration: recorder.debugElapsed,
      distanceMetres: recorder.debugDistanceMetres,
      track: waypoints,
      source: cm.RunSource.app,
    );
    await runStore.save(run);

    expect(runStore.runs.length, 1);
    expect(runStore.unsyncedCount, 1);

    recorder.dispose();
  });

  test('pipeline preserves the run when SyncService runs offline (api null)',
      () async {
    final recorder = RunRecorder();
    await recorder.prepare();
    await Future<void>.delayed(Duration.zero);

    recorder.begin();
    fake.emit(_pos(metresEast: 0, secondsFromStart: 0));
    fake.emit(_pos(metresEast: 30, secondsFromStart: 3));
    await Future<void>.delayed(Duration.zero);

    final track = recorder.debugTrack;
    final waypoints = track
        .map((w) => cm.Waypoint(
              lat: w.lat,
              lng: w.lng,
              timestamp: w.timestamp,
            ))
        .toList();
    final run = cm.Run(
      id: 'offline-run',
      startedAt: DateTime(2026, 4, 10, 10, 0, 0),
      duration: recorder.debugElapsed,
      distanceMetres: recorder.debugDistanceMetres,
      track: waypoints,
      source: cm.RunSource.app,
    );
    await runStore.save(run);

    // Offline: api is null, the sync attempt is a no-op.
    final sync = SyncService(apiClient: null, runStore: runStore);
    await sync.debugTrySync('offline');

    expect(runStore.unsyncedCount, 1,
        reason: 'offline run should stay unsynced for a later attempt');

    recorder.dispose();
  });
}
