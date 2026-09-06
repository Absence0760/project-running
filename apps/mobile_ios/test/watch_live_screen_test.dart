import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/watch_live_screen.dart';
import '../lib/sim_watch_sync.dart';
import '../lib/watch_status_link.dart';

/// Stands in for the radio: [open] hands back a controller the test drives,
/// [close] ends it — the same fake shape `watch_status_link_test.dart` uses,
/// because a fake that only counted would hide the teardown-order bug §456
/// records.
class _FakeSource implements WatchFrameSource {
  final List<StreamController<List<int>>> opened = [];
  int closes = 0;
  bool alwaysFail = false;

  @override
  Future<Stream<List<int>>> open() async {
    if (alwaysFail) throw StateError('no watch in range');
    final controller = StreamController<List<int>>();
    opened.add(controller);
    return controller.stream;
  }

  @override
  Future<void> close() async {
    closes++;
    if (opened.isNotEmpty && !opened.last.isClosed) await opened.last.close();
  }

  StreamController<List<int>> get current => opened.last;
}

class _FakeApi extends ApiClient {
  _FakeApi({this.uid = 'u1'});

  final String? uid;
  final List<String> begun = [];
  final List<String> concluded = [];
  final List<Map<String, double>> pings = [];
  bool beginThrows = false;

  @override
  String? get userId => uid;

  @override
  Future<void> beginLiveBroadcast({
    required String runId,
    required DateTime startedAt,
    String activityType = 'run',
  }) async {
    if (beginThrows) throw StateError('backend down');
    begun.add(runId);
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
    pings.add({'lat': lat, 'lng': lng});
  }

  @override
  Future<void> concludeLiveBroadcast(String runId) async {
    concluded.add(runId);
  }
}

/// Empty MAN1 manifest — run_count 0, so a sync completes having pulled
/// nothing. These tests are about the link being taken down around the sync;
/// the decode is `sim_watch_sync_test.dart`'s.
Uint8List _emptyManifest() {
  final d = ByteData(12);
  d.setUint8(0, 'M'.codeUnitAt(0));
  d.setUint8(1, 'A'.codeUnitAt(0));
  d.setUint8(2, 'N'.codeUnitAt(0));
  d.setUint8(3, '1'.codeUnitAt(0));
  d.setUint8(4, 3);
  d.setUint8(5, 0);
  return d.buffer.asUint8List();
}

class _FakeTransport implements WatchBleTransport {
  final _chunks = StreamController<List<int>>.broadcast();
  int scans = 0;

  @override
  Stream<List<int>> get chunkStream => _chunks.stream;

  @override
  Future<void> scan() async {
    scans++;
  }

  @override
  Future<List<int>> readManifest() async => _emptyManifest();

  @override
  Future<void> writeChunkRequest(List<int> request) async {}

  @override
  Future<void> writeSettings(List<int> frame) async {}

  @override
  Future<void> writeWorkout(List<int> chunk) async {}

  @override
  Future<void> writeCourse(List<int> chunk) async {}

  @override
  Future<void> writeScreens(List<int> frame) async {}

  @override
  Future<void> writeRoadbook(List<int> chunk) async {}

  @override
  Future<List<int>> readPushStatus() async => const [];

  @override
  Future<void> disconnect() async {}
}

class _Clock {
  DateTime value = DateTime.utc(2026, 8, 2, 12);
  DateTime call() => value;
}

List<int> _frame(int uptimeS) => utf8.encode(
      '{"v":1,"uptime_s":$uptimeS,"fix":{"lat":40.015,"lon":-105.2705,'
      '"speed_mps":3.2,"sats":8,"alt_m":1655.0,"age_s":1}}\n',
    );

Future<void> _pump(
  WidgetTester tester, {
  required ApiClient? api,
  required WatchStatusLink Function() linkFactory,
  WatchBleTransport Function()? transportFactory,
  DateTime Function()? now,
}) {
  return tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: WatchLiveScreen(
      apiClient: api,
      linkFactory: linkFactory,
      transportFactory: transportFactory ?? _FakeTransport.new,
      runSink: (_) async {},
      now: now ?? DateTime.now,
    ),
  ));
}

/// Never `pumpAndSettle`: an armed relay holds a 1 Hz freshness ticker, which
/// would spin that forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

/// Run an interaction in the REAL async zone.
///
/// Tearing the link down cancels a subscription to the `simWatchFrames`
/// `async*` generator, and that cancel never completes under the widget
/// tester's fake-async clock — so every path that stops the link (Stop, the
/// pre-sync pause, dispose) has to run here or it hangs mid-teardown.
Future<void> _real(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.text('Start relay'));
  await _settle(tester);
}

/// Deliver one frame, let the decoder hand it on, then advance the ticker —
/// the screen repaints on the 1 Hz tick, not on the frame.
Future<void> _deliver(
    WidgetTester tester, _FakeSource source, int uptimeS) async {
  source.current.add(_frame(uptimeS));
  await _settle(tester);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('reads as not connected before the relay is started',
      (tester) async {
    final source = _FakeSource();
    await _pump(
      tester,
      api: _FakeApi(),
      linkFactory: () => WatchStatusLink(source),
    );

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Nothing is being sent.'), findsOneWidget);
    expect(find.text('Start relay'), findsOneWidget);
    expect(find.text('Share live link'), findsNothing);
    expect(source.opened, isEmpty);
  });

  testWidgets('an open link with no frames yet reads as connecting',
      (tester) async {
    final source = _FakeSource();
    final api = _FakeApi();
    await _pump(tester, api: api, linkFactory: () => WatchStatusLink(source));

    await _start(tester);

    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text("Connected — waiting for the watch's first position."),
        findsOneWidget);
    expect(find.text('Live'), findsNothing);
    expect(api.begun, hasLength(1));
    expect(api.pings, isEmpty);

    await _real(tester, () => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('a decoded frame flips it live and pushes a ping',
      (tester) async {
    final source = _FakeSource();
    final api = _FakeApi();
    final clock = _Clock();
    await _pump(
      tester,
      api: api,
      linkFactory: () => WatchStatusLink(source),
      now: clock.call,
    );

    await _start(tester);
    await _deliver(tester, source, 10);

    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);
    expect(find.text('Share live link'), findsOneWidget);
    expect(api.pings, hasLength(1));
    expect(api.pings.single['lat'], closeTo(40.015, 1e-9));

    await _real(tester, () => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('ageing past the stale window reads as a gap, not live',
      (tester) async {
    final source = _FakeSource();
    final clock = _Clock();
    await _pump(
      tester,
      api: _FakeApi(),
      linkFactory: () => WatchStatusLink(source),
      now: clock.call,
    );

    await _start(tester);
    await _deliver(tester, source, 10);
    expect(find.text('Live'), findsOneWidget);

    // The watch goes quiet. Nothing is torn down — §447's rule is that a gap
    // is reported by freshness, not by dropping the link.
    clock.value = clock.value.add(const Duration(seconds: 91));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Gap'), findsOneWidget);
    expect(find.text('Live'), findsNothing);
    expect(
      find.textContaining(
          'spectators see the last position as delayed, not current'),
      findsOneWidget,
    );
    expect(source.closes, 0);

    await _real(tester, () => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('an exhausted reconnect ladder reads as gave up',
      (tester) async {
    final source = _FakeSource()..alwaysFail = true;
    await _pump(
      tester,
      api: _FakeApi(),
      linkFactory: () => WatchStatusLink(
        source,
        maxReconnectAttempts: 1,
        backoff: (_) => Duration.zero,
      ),
    );

    await _start(tester);
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Looking for your watch…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Gave up'), findsOneWidget);
    expect(
      find.text(
          'Your watch is off or out of range. Nothing new is being sent.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Stop relay'), findsOneWidget);

    await _real(tester, () => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('stop concludes the broadcast and returns to not connected',
      (tester) async {
    final source = _FakeSource();
    final api = _FakeApi();
    await _pump(tester, api: api, linkFactory: () => WatchStatusLink(source));

    await _start(tester);
    await _deliver(tester, source, 10);
    expect(find.text('Share live link'), findsOneWidget);

    await _real(tester, () => tester.tap(find.text('Stop relay')));

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Share live link'), findsNothing);
    expect(source.closes, greaterThan(0));
    expect(api.concluded, equals(api.begun));
  });

  testWidgets('disposing the surface closes the radio and ends the broadcast',
      (tester) async {
    final source = _FakeSource();
    final api = _FakeApi();
    await _pump(tester, api: api, linkFactory: () => WatchStatusLink(source));

    await _start(tester);
    await _deliver(tester, source, 10);
    expect(source.closes, 0);
    expect(api.concluded, isEmpty);

    await _real(tester, () => tester.pumpWidget(const SizedBox()));

    expect(source.closes, greaterThan(0));
    expect(api.concluded, equals(api.begun));
  });

  testWidgets('a sync takes the status link down first and re-arms it after',
      (tester) async {
    final sources = <_FakeSource>[];
    final transport = _FakeTransport();
    final api = _FakeApi();
    await _pump(
      tester,
      api: api,
      linkFactory: () {
        final s = _FakeSource();
        sources.add(s);
        return WatchStatusLink(s);
      },
      transportFactory: () => transport,
    );

    await _start(tester);
    await _deliver(tester, sources.single, 10);
    expect(sources, hasLength(1));

    await _real(tester, () => tester.tap(find.text('Sync runs from watch')));

    // §456: the first link is stopped before the sync opens its own
    // connection, then a FRESH link is armed — a spent one is never restarted.
    expect(sources.first.closes, greaterThan(0));
    expect(sources, hasLength(2));
    expect(transport.scans, 1);
    expect(find.text('No runs on the watch to sync'), findsOneWidget);
    // One broadcast across the sync: the spectator follows the same run
    // rather than being handed a second link.
    expect(api.begun, hasLength(1));
    expect(api.concluded, isEmpty);

    await _real(tester, () => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('a backend that refuses the broadcast leaves the relay off',
      (tester) async {
    final source = _FakeSource();
    final api = _FakeApi()..beginThrows = true;
    await _pump(tester, api: api, linkFactory: () => WatchStatusLink(source));

    await _real(tester, () => tester.tap(find.text('Start relay')));

    expect(find.text('Not connected'), findsOneWidget);
    expect(
      find.text("Couldn't start the live broadcast — nothing is being shared."),
      findsOneWidget,
    );
    expect(source.closes, greaterThan(0));
  });

  testWidgets('a signed-out session cannot arm the relay', (tester) async {
    final source = _FakeSource();
    await _pump(
      tester,
      api: _FakeApi(uid: null),
      linkFactory: () => WatchStatusLink(source),
    );

    await _start(tester);

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Sign in to share a live tracking link.'), findsOneWidget);
    expect(source.opened, isEmpty);
  });
}
