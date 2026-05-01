import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/live_broadcaster.dart';

class _FakeApiClient extends ApiClient {
  int callCount = 0;
  final List<Map<String, dynamic>> calls = [];
  Object? errorToThrow;

  @override
  Future<void> insertLivePing({
    required String runId,
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
    double? ele,
  }) async {
    callCount++;
    calls.add({
      'run_id': runId,
      'lat': lat,
      'lng': lng,
      'distance_m': distanceM,
      'elapsed_s': elapsedS,
      'bpm': bpm,
      'ele': ele,
    });
    if (errorToThrow != null) throw errorToThrow!;
  }
}

void main() {
  group('LiveBroadcaster', () {
    test('starts inactive', () {
      final lb = LiveBroadcaster(_FakeApiClient());
      expect(lb.isActive, false);
      expect(lb.runId, isNull);
    });

    test('pushPing is a no-op when inactive', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      await lb.pushPing(lat: 1, lng: 2);
      expect(api.callCount, 0);
    });

    test('attach flips isActive and exposes the run id', () {
      final lb = LiveBroadcaster(_FakeApiClient());
      lb.attach('run-1');
      expect(lb.isActive, true);
      expect(lb.runId, 'run-1');
    });

    test('first ping after attach goes through', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      await lb.pushPing(lat: 1, lng: 2, distanceM: 10, elapsedS: 5, bpm: 130, ele: 12);
      expect(api.callCount, 1);
      expect(api.calls.single, {
        'run_id': 'run-1',
        'lat': 1,
        'lng': 2,
        'distance_m': 10,
        'elapsed_s': 5,
        'bpm': 130,
        'ele': 12,
      });
    });

    test('throttles back-to-back pings within the 5s window', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      await lb.pushPing(lat: 1, lng: 2);
      await lb.pushPing(lat: 1, lng: 2); // immediate — throttled
      await lb.pushPing(lat: 1, lng: 2); // immediate — throttled
      expect(api.callCount, 1, reason: 'throttle window must drop the 2nd and 3rd same-tick calls');
    });

    test('detach silences future pings', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      lb.detach();
      expect(lb.isActive, false);
      expect(lb.runId, isNull);
      await lb.pushPing(lat: 1, lng: 2);
      expect(api.callCount, 0);
    });

    test('swallows api errors so the recorder stays untouched', () async {
      final api = _FakeApiClient()..errorToThrow = StateError('network down');
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      // Must not throw — L4 per docs/conventions.md § Layered resilience.
      await lb.pushPing(lat: 1, lng: 2);
      expect(api.callCount, 1);
    });

    test('re-attach resets the throttle timer so the next ping fires immediately', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      await lb.pushPing(lat: 1, lng: 2);
      lb.detach();
      lb.attach('run-2');
      await lb.pushPing(lat: 3, lng: 4);
      expect(api.callCount, 2);
      expect(api.calls.last['run_id'], 'run-2');
    });
  });
}
