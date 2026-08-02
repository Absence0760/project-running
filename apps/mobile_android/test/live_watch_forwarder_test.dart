import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/live_broadcaster.dart';
import '../lib/live_freshness.dart';
import '../lib/live_watch_forwarder.dart';
import '../lib/privacy.dart';
import '../lib/sim_watch_link.dart';

class _FakeApi extends ApiClient {
  int begins = 0;
  int concludes = 0;
  final List<Map<String, dynamic>> pings = [];
  Object? beginError;
  Object? pingError;

  @override
  Future<void> beginLiveBroadcast({
    required String runId,
    required DateTime startedAt,
    String activityType = 'run',
  }) async {
    begins++;
    if (beginError != null) throw beginError!;
  }

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
    if (pingError != null) throw pingError!;
    pings.add({
      'run_id': runId,
      'lat': lat,
      'lng': lng,
      'distance_m': distanceM,
      'elapsed_s': elapsedS,
      'bpm': bpm,
      'ele': ele,
    });
  }

  @override
  Future<void> concludeLiveBroadcast(String runId) async {
    concludes++;
  }
}

SimWatchStatus _frame(
  int uptimeS, {
  double lat = 40.015,
  double lon = -105.2705,
  int ageS = 1,
  double? altM,
  SimWatchElevation? elev,
}) =>
    SimWatchStatus(
      version: 1,
      uptimeS: uptimeS,
      fix: SimWatchFix(
        lat: lat,
        lon: lon,
        speedMps: 3,
        sats: 8,
        ageS: ageS,
        altM: altM,
      ),
      elev: elev,
    );

SimWatchStatus _noFixFrame(int uptimeS) =>
    SimWatchStatus(version: 1, uptimeS: uptimeS);

void main() {
  late _FakeApi api;
  late LiveBroadcaster broadcaster;
  late DateTime clock;
  late WatchLiveForwarder forwarder;
  late StreamController<SimWatchStatus> frames;

  setUp(() {
    api = _FakeApi();
    broadcaster = LiveBroadcaster(api);
    clock = DateTime.utc(2026, 1, 1, 12);
    forwarder = WatchLiveForwarder(
      api: api,
      broadcaster: broadcaster,
      now: () => clock,
    );
    // Broadcast, like the BLE notify it stands in for: a close() on a
    // single-subscription controller nothing listened to never completes,
    // which would hang the tests that deliberately never reach listen().
    frames = StreamController<SimWatchStatus>.broadcast();
    addTearDown(() async {
      if (!frames.isClosed) await frames.close();
    });
  });

  group('WatchLiveForwarder start / stop', () {
    test('start pre-creates the run row and attaches the broadcaster',
        () async {
      final id = await forwarder.start(frames.stream);
      expect(id, isNotNull);
      expect(api.begins, 1);
      expect(broadcaster.isActive, true);
      expect(broadcaster.runId, id);
      expect(forwarder.linkUp, true);
    });

    test('a failed beginLiveBroadcast fails closed — no run, no attach',
        () async {
      api.beginError = StateError('offline');
      final id = await forwarder.start(frames.stream);
      expect(id, isNull);
      expect(forwarder.runId, isNull);
      expect(broadcaster.isActive, false);
    });

    test('frames before start are refused', () async {
      expect(await forwarder.onFrame(_frame(1)), WatchFrameOutcome.notStarted);
      expect(api.pings, isEmpty);
    });

    test('stop concludes the broadcast, detaches, and silences later frames',
        () async {
      await forwarder.start(frames.stream);
      await forwarder.stop();
      expect(api.concludes, 1);
      expect(broadcaster.isActive, false);
      expect(forwarder.runId, isNull);
      expect(forwarder.linkUp, false);
      expect(await forwarder.onFrame(_frame(9)), WatchFrameOutcome.notStarted);
      expect(api.pings, isEmpty);
    });
  });

  group('WatchLiveForwarder admission', () {
    setUp(() async {
      await forwarder.start(frames.stream);
    });

    test('a fresh fix reaches the live pipeline as a ping', () async {
      expect(await forwarder.onFrame(_frame(10)), WatchFrameOutcome.admitted);
      expect(api.pings.single['lat'], 40.015);
      expect(api.pings.single['lng'], -105.2705);
      expect(api.pings.single['run_id'], forwarder.runId);
    });

    test('the status frame carries no odometer, so none is invented', () async {
      await forwarder.onFrame(_frame(10));
      expect(api.pings.single['distance_m'], isNull);
      expect(api.pings.single['elapsed_s'], isNull);
      expect(api.pings.single['bpm'], isNull);
    });

    test('a frame with no fix is not forwarded', () async {
      expect(await forwarder.onFrame(_noFixFrame(10)), WatchFrameOutcome.noFix);
      expect(api.pings, isEmpty);
    });

    test('a fix at the age limit is still current', () async {
      expect(await forwarder.onFrame(_frame(10, ageS: 10)),
          WatchFrameOutcome.admitted);
      expect(api.pings, hasLength(1));
    });

    test('a fix past the age limit is refused, never re-dated as fresh',
        () async {
      expect(await forwarder.onFrame(_frame(10, ageS: 11)),
          WatchFrameOutcome.staleFix);
      expect(api.pings, isEmpty);
      expect(forwarder.linkFreshness(), isNull);
    });

    test('a stale fix does not consume the sequence position', () async {
      expect(await forwarder.onFrame(_frame(10, ageS: 99)),
          WatchFrameOutcome.staleFix);
      expect(await forwarder.onFrame(_frame(10, ageS: 99)),
          WatchFrameOutcome.duplicate,
          reason: 'the frame was still seen, so its re-delivery is a duplicate');
    });
  });

  group('WatchLiveForwarder elevation', () {
    setUp(() async {
      await forwarder.start(frames.stream);
    });

    test('barometric elevation is preferred over the GNSS altitude', () async {
      await forwarder.onFrame(_frame(
        10,
        altM: 1624,
        elev: const SimWatchElevation(altM: 1600.5, gainM: 540, lossM: 120),
      ));
      expect(api.pings.single['ele'], 1600.5);
    });

    test('GNSS altitude is used when the barometer has not streamed yet',
        () async {
      await forwarder.onFrame(_frame(10, altM: 1624));
      expect(api.pings.single['ele'], 1624);
    });

    test('no altitude source leaves ele null', () async {
      await forwarder.onFrame(_frame(10));
      expect(api.pings.single['ele'], isNull);
    });
  });

  group('WatchLiveForwarder sequencing', () {
    setUp(() async {
      await forwarder.start(frames.stream);
    });

    test('a re-delivered frame is dropped as a duplicate', () async {
      expect(await forwarder.onFrame(_frame(10)), WatchFrameOutcome.admitted);
      expect(await forwarder.onFrame(_frame(10)), WatchFrameOutcome.duplicate);
      expect(api.pings, hasLength(1));
    });

    test('an out-of-order frame does not rewind the spectator', () async {
      await forwarder.onFrame(_frame(100));
      expect(await forwarder.onFrame(_frame(99)),
          WatchFrameOutcome.outOfOrder);
      expect(api.pings, hasLength(1));
    });

    test('a forward frame resets the backwards run', () async {
      await forwarder.onFrame(_frame(100));
      expect(await forwarder.onFrame(_frame(99)), WatchFrameOutcome.outOfOrder);
      expect(await forwarder.onFrame(_frame(101)), WatchFrameOutcome.admitted);
      expect(await forwarder.onFrame(_frame(98)), WatchFrameOutcome.outOfOrder,
          reason: 'the earlier backwards frame must not carry over');
    });

    test('a sustained backwards run re-baselines — the watch rebooted',
        () async {
      await forwarder.onFrame(_frame(3600));
      expect(await forwarder.onFrame(_frame(1)), WatchFrameOutcome.outOfOrder);
      expect(await forwarder.onFrame(_frame(2)), WatchFrameOutcome.outOfOrder);
      expect(await forwarder.onFrame(_frame(3)), WatchFrameOutcome.admitted);
      expect(await forwarder.onFrame(_frame(4)), WatchFrameOutcome.admitted);
    });

    test('a reboot early in the watch uptime also recovers', () async {
      await forwarder.onFrame(_frame(20));
      await forwarder.onFrame(_frame(1));
      await forwarder.onFrame(_frame(2));
      expect(await forwarder.onFrame(_frame(3)), WatchFrameOutcome.admitted,
          reason: 'counting backwards frames must not depend on the jump size');
    });
  });

  group('WatchLiveForwarder gaps and reconnects', () {
    test('a dropout pushes nothing and ages into stale on the spectator clock',
        () async {
      await forwarder.start(frames.stream);
      frames.add(_frame(10));
      await pumpEventQueue();
      expect(api.pings, hasLength(1));

      await frames.close();
      await pumpEventQueue();
      expect(forwarder.linkUp, false);

      clock = clock.add(const Duration(seconds: 60));
      expect(api.pings, hasLength(1), reason: 'no keep-alive during the gap');
      expect(forwarder.linkFreshness()!.stale, false);

      clock = clock.add(
        const Duration(milliseconds: liveStaleAfterMs - 60000),
      );
      expect(forwarder.linkFreshness()!.stale, true);
    });

    test('reconnect resumes the same run and drops the replayed frame',
        () async {
      await forwarder.start(frames.stream);
      final id = forwarder.runId;
      expect(await forwarder.onFrame(_frame(10)), WatchFrameOutcome.admitted);

      await frames.close();
      await pumpEventQueue();

      final reconnected = StreamController<SimWatchStatus>.broadcast();
      addTearDown(reconnected.close);
      expect(await forwarder.start(reconnected.stream), id);
      expect(api.begins, 1, reason: 'a reconnect must not start a second run');
      expect(forwarder.linkUp, true);
      expect(await forwarder.onFrame(_frame(10)), WatchFrameOutcome.duplicate);
    });

    test('the first fix after a long gap is refused while it is stale',
        () async {
      await forwarder.start(frames.stream);
      await forwarder.onFrame(_frame(10));
      clock = clock.add(const Duration(seconds: 120));
      expect(await forwarder.onFrame(_frame(130, ageS: 118)),
          WatchFrameOutcome.staleFix);
      expect(api.pings, hasLength(1));
      expect(await forwarder.onFrame(_frame(131, ageS: 2)),
          WatchFrameOutcome.admitted,
          reason: 'a genuinely reacquired fix resumes the feed');
    });

    test('a link error marks the link down without throwing', () async {
      await forwarder.start(frames.stream);
      frames.addError(StateError('ble dropped'));
      await pumpEventQueue();
      expect(forwarder.linkUp, false);
    });
  });

  group('WatchLiveForwarder privacy and resilience', () {
    test('an in-zone fix is dropped by the broadcaster, not re-routed',
        () async {
      final zoned = LiveBroadcaster(
        api,
        privacyZonesProvider: () =>
            const [PrivacyZone(lat: 40.015, lng: -105.2705, radiusM: 300)],
      );
      final f = WatchLiveForwarder(
        api: api,
        broadcaster: zoned,
        now: () => clock,
      );
      await f.start(frames.stream);
      expect(await f.onFrame(_frame(10)), WatchFrameOutcome.admitted);
      expect(api.pings, isEmpty,
          reason: 'privacy-zone clipping is inherited from LiveBroadcaster');
      expect(f.linkFreshness(), isNotNull,
          reason: 'the link is healthy even though the position is withheld');
    });

    test('a backend failure on the ping path never reaches the caller',
        () async {
      api.pingError = StateError('network down');
      await forwarder.start(frames.stream);
      expect(await forwarder.onFrame(_frame(10)), WatchFrameOutcome.admitted);
      expect(api.pings, isEmpty);
    });
  });
}
