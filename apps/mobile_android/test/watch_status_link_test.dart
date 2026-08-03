import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/live_broadcaster.dart';
import '../lib/live_watch_forwarder.dart';
import '../lib/sim_watch_link.dart';
import '../lib/watch_status_link.dart';

/// Stands in for the radio. Each [open] hands back a fresh controller the test
/// drives directly: adding bytes is a notification, closing is a BLE drop.
class _FakeSource implements WatchFrameSource {
  final List<StreamController<List<int>>> opened = [];
  int openAttempts = 0;
  int closes = 0;
  int failuresRemaining = 0;

  @override
  Future<Stream<List<int>>> open() async {
    openAttempts++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('no watch in range');
    }
    final controller = StreamController<List<int>>();
    opened.add(controller);
    return controller.stream;
  }

  /// Ends the byte stream, like the real source closing its controller when
  /// the connection goes. A fake that only counted would let a teardown bug
  /// through: cancelling `simWatchFrames` while its input is still live never
  /// completes.
  @override
  Future<void> close() async {
    closes++;
    if (opened.isNotEmpty && !opened.last.isClosed) await opened.last.close();
  }

  StreamController<List<int>> get current => opened.last;
}

class _FakeApi extends ApiClient {
  final List<Map<String, double>> pings = [];

  @override
  Future<void> beginLiveBroadcast({
    required String runId,
    required DateTime startedAt,
    String activityType = 'run',
  }) async {}

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
    pings.add({'lat': lat, 'lng': lng});
  }

  @override
  Future<void> concludeLiveBroadcast(String runId) async {}
}

String _frameJson(int uptimeS, {double lat = 40.015, double lon = -105.2705}) =>
    '{"v":1,"uptime_s":$uptimeS,"fix":{"lat":$lat,"lon":$lon,'
    '"speed_mps":3.20,"course_deg":91.0,"sats":8,"alt_m":1655.0,'
    '"tod_s":43200,"age_s":1},"elev":{"alt_m":1655.0,"gain_m":12.0,'
    '"loss_m":3.0}}\n';

List<int> _notification(String payload) => utf8.encode(payload);

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeSource source;
  late List<SimWatchStatus> got;
  late List<Object> errors;

  WatchStatusLink linkWith({
    int maxReconnectAttempts = kWatchLinkMaxReconnectAttempts,
    Duration Function(int attempt)? backoff,
    List<int>? attempts,
  }) {
    final link = WatchStatusLink(
      source,
      maxReconnectAttempts: maxReconnectAttempts,
      backoff: backoff ??
          (attempt) {
            attempts?.add(attempt);
            return Duration.zero;
          },
    );
    link.frames.listen(got.add, onError: errors.add);
    addTearDown(link.stop);
    return link;
  }

  setUp(() {
    source = _FakeSource();
    got = [];
    errors = [];
  });

  group('WatchStatusLink decode', () {
    test('one notification carrying one frame decodes to a status', () async {
      final link = linkWith();
      await link.start();
      source.current.add(_notification(_frameJson(42)));
      await _settle();

      expect(got, hasLength(1));
      expect(got.single.version, 1);
      expect(got.single.uptimeS, 42);
      expect(got.single.fix!.lat, closeTo(40.015, 1e-9));
      expect(got.single.fix!.sats, 8);
      expect(got.single.elev!.gainM, closeTo(12, 1e-9));
      expect(link.state, WatchLinkState.connected);
    });

    test('two frames in one notification both decode', () async {
      final link = linkWith();
      await link.start();
      source.current.add(_notification(_frameJson(10) + _frameJson(11)));
      await _settle();

      expect(got.map((s) => s.uptimeS), [10, 11]);
    });

    test('a frame split across notifications decodes once, whole', () async {
      final link = linkWith();
      await link.start();
      final whole = _frameJson(7);
      final cut = whole.length ~/ 2;
      source.current.add(_notification(whole.substring(0, cut)));
      await _settle();
      expect(got, isEmpty, reason: 'half a frame is not a frame');

      source.current.add(_notification(whole.substring(cut)));
      await _settle();
      expect(got.single.uptimeS, 7);
    });

    test('a truncated frame is skipped and the next one still lands', () async {
      final link = linkWith();
      await link.start();
      source.current.add(_notification('{"v":1,"uptime_s":9,"fi\n'));
      source.current.add(_notification(_frameJson(10)));
      await _settle();

      expect(got.map((s) => s.uptimeS), [10]);
      expect(errors, isEmpty);
    });
  });

  group('WatchStatusLink lifecycle', () {
    test('a drop reconnects and resumes forwarding', () async {
      final link = linkWith();
      await link.start();
      source.current.add(_notification(_frameJson(10)));
      await _settle();

      await source.current.close();
      await _settle();

      expect(source.openAttempts, 2);
      expect(link.state, WatchLinkState.connected);
      source.current.add(_notification(_frameJson(11)));
      await _settle();
      expect(got.map((s) => s.uptimeS), [10, 11]);
    });

    test('a byte-stream error reconnects without reaching the frame stream',
        () async {
      final link = linkWith();
      await link.start();
      source.current.addError(StateError('gatt 133'));
      await _settle();

      expect(errors, isEmpty, reason: 'L4: the frame stream never errors');
      expect(source.openAttempts, 2);
      source.current.add(_notification(_frameJson(3)));
      await _settle();
      expect(got.single.uptimeS, 3);
    });

    test('a failed open retries rather than throwing', () async {
      final link = linkWith();
      source.failuresRemaining = 2;
      await link.start();
      await _settle();

      expect(source.openAttempts, 3);
      expect(link.state, WatchLinkState.connected);
      expect(errors, isEmpty);
    });

    test('the backoff index climbs while failing and resets on a frame',
        () async {
      final attempts = <int>[];
      final link = linkWith(attempts: attempts);
      source.failuresRemaining = 3;
      await link.start();
      await _settle();
      expect(attempts, [0, 1, 2]);

      source.current.add(_notification(_frameJson(1)));
      await _settle();
      await source.current.close();
      await _settle();

      expect(attempts, [0, 1, 2, 0],
          reason: 'a link that delivered a frame starts the ladder over');
    });

    test('a link that connects but never speaks keeps climbing the ladder',
        () async {
      final attempts = <int>[];
      final link = linkWith(attempts: attempts);
      await link.start();
      for (var i = 0; i < 3; i++) {
        await source.current.close();
        await _settle();
      }

      expect(
        attempts,
        [0, 1, 2],
        reason: 'flapping must not reset at the bottom of the ladder',
      );
    });

    test('it gives up after the cap and closes the stream', () async {
      var done = false;
      final link = WatchStatusLink(
        source,
        maxReconnectAttempts: 3,
        backoff: (_) => Duration.zero,
      );
      link.frames.listen(got.add, onError: errors.add, onDone: () => done = true);
      addTearDown(link.stop);
      source.failuresRemaining = 99;
      await link.start();
      await _settle();

      expect(source.openAttempts, 4, reason: 'the first try plus three retries');
      expect(link.state, WatchLinkState.lost);
      expect(done, true, reason: 'a watch that is gone must reach the forwarder');
    });

    test('the default backoff does not spin hot on a watch that is off',
        () async {
      final link = WatchStatusLink(source);
      addTearDown(link.stop);
      source.failuresRemaining = 99;
      await link.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(source.openAttempts, 1,
          reason: 'the shared ladder waits seconds, not milliseconds');
    });

    test('start is idempotent', () async {
      final link = linkWith();
      await link.start();
      await link.start();
      expect(source.openAttempts, 1);
    });

    test('stop closes the source and cancels a pending reconnect', () async {
      final link = linkWith();
      source.failuresRemaining = 1;
      await link.start();
      await link.stop();
      await _settle();

      expect(source.openAttempts, 1);
      expect(source.closes, greaterThan(0));
      expect(link.state, WatchLinkState.idle);
    });

    test('a drop after stop does not reconnect', () async {
      final link = linkWith();
      await link.start();
      final controller = source.current;
      await link.stop();
      // Not awaited: stop() already cancelled the only subscription, and a
      // single-subscription controller's close() future never completes once
      // its listener is gone.
      unawaited(controller.close());
      await _settle();

      expect(source.openAttempts, 1);
    });
  });

  group('WatchStatusLink feeding WatchLiveForwarder', () {
    test('a raw notification becomes a live spectator ping', () async {
      final api = _FakeApi();
      final forwarder = WatchLiveForwarder(
        api: api,
        broadcaster: LiveBroadcaster(api),
      );
      final link = WatchStatusLink(source, backoff: (_) => Duration.zero);
      addTearDown(link.stop);
      addTearDown(forwarder.stop);

      await link.start();
      final runId = await forwarder.start(link.frames);
      expect(runId, isNotNull);

      source.current.add(_notification(_frameJson(30)));
      await _settle();

      expect(api.pings, hasLength(1));
      expect(api.pings.single['lat'], closeTo(40.015, 1e-9));
    });
  });
}
