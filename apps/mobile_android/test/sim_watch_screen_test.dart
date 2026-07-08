import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_screen.dart';
import '../lib/screens/sim_watch_screen.dart';
import '../lib/sim_watch_link.dart';
import '../lib/sim_watch_sync.dart';

/// The golden run blob from `watch_core::run_store` (pinned identically in
/// `sim_watch_sync_test.dart`), served in chunks so the screen's Sync action
/// can be exercised without a BLE radio.
final _goldenBlob = _hex(
  '54524b31010000000700000029000000b8ced91718ff40c100000000703f7800'
  'e4cfd9170c0141c101000000723f7a0074d1d917000341c10200000000800000'
  '454e4431d2040000580200006c02000077fdfebd',
);

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
    ];

class _FakeSyncTransport implements WatchBleTransport {
  final _chunks = StreamController<List<int>>.broadcast();
  @override
  Future<void> scan() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<List<int>> get chunkStream => _chunks.stream;
  @override
  Future<List<int>> readManifest() async => [
        0x4d, 0x41, 0x4e, 0x31, 0x01, 0x01, 0x00, 0x00, // MAN1 v1 count=1
        0x81, 0x02, 0x00, 0x00, // watch_uptime = 641
        0x07, 0x00, 0x00, 0x00, // run_seq 7
        0x54, 0x00, 0x00, 0x00, // size 84
        0x29, 0x00, 0x00, 0x00, // start_uptime 41
      ];
  @override
  Future<void> writeChunkRequest(List<int> request) async {
    final offset = request[4] | request[5] << 8 | request[6] << 16 | request[7] << 24;
    final len = request[8] | request[9] << 8;
    final end = (offset + len).clamp(0, _goldenBlob.length);
    _chunks.add(_goldenBlob.sublist(offset, end));
  }
}

class _FakeLink extends SimWatchLink {
  final StreamController<SimWatchStatus> controller;
  final Object? connectError;
  bool closed = false;

  _FakeLink(this.controller, {this.connectError})
      : super(host: 'test', port: 1);

  @override
  Future<Stream<SimWatchStatus>> connect() async {
    final error = connectError;
    if (error != null) throw error;
    return controller.stream;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

Future<void> _pumpScreen(WidgetTester tester, SimWatchLink link) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SimWatchScreen(linkFactory: (_, __) => link),
    ),
  );
}

const _fix = SimWatchFix(
  lat: 40.015,
  lon: -105.2705,
  speedMps: 3.0,
  sats: 8,
  ageS: 1,
  altM: 1624.0,
);

const _elev = SimWatchElevation(altM: 1600.0, gainM: 540.0, lossM: 120.0);

void main() {
  testWidgets('connect renders live frames as they arrive', (tester) async {
    final controller = StreamController<SimWatchStatus>();
    final link = _FakeLink(controller);
    await _pumpScreen(tester, link);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Connected — waiting for frames…'), findsOneWidget);

    controller.add(const SimWatchStatus(version: 1, uptimeS: 42, fix: null));
    await tester.pump();
    expect(find.text('00:00:42'), findsOneWidget);
    expect(find.text('No GPS fix yet'), findsOneWidget);

    controller
        .add(const SimWatchStatus(version: 1, uptimeS: 43, fix: _fix));
    await tester.pump();
    expect(find.text('40.01500, -105.27050'), findsOneWidget);
    expect(find.text('3.0 m/s'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('1624 m'), findsOneWidget);

    await controller.close();
    await tester.pump();
  });

  testWidgets('renders the barometric elevation block when present',
      (tester) async {
    final controller = StreamController<SimWatchStatus>();
    final link = _FakeLink(controller);
    await _pumpScreen(tester, link);

    await tester.tap(find.text('Connect'));
    await tester.pump();

    // Baro streams without a GPS fix — the elev tiles still render.
    controller.add(
      const SimWatchStatus(version: 1, uptimeS: 50, fix: null, elev: _elev),
    );
    await tester.pump();
    expect(find.text('Barometric altitude'), findsOneWidget);
    expect(find.text('1600 m'), findsOneWidget);
    expect(find.text('Ascent'), findsOneWidget);
    expect(find.text('+540 m'), findsOneWidget);
    expect(find.text('Descent'), findsOneWidget);
    expect(find.text('-120 m'), findsOneWidget);

    // A later frame without elev drops the block (no stale carry-over).
    controller.add(const SimWatchStatus(version: 1, uptimeS: 51, fix: null));
    await tester.pump();
    expect(find.text('Barometric altitude'), findsNothing);

    await controller.close();
    await tester.pump();
  });

  testWidgets('failed connection surfaces the error, not a silent idle',
      (tester) async {
    final controller = StreamController<SimWatchStatus>();
    final link = _FakeLink(controller, connectError: 'refused');
    await _pumpScreen(tester, link);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.textContaining('Connection failed'), findsOneWidget);
    expect(find.textContaining('refused'), findsOneWidget);
    // Not awaited: close() only completes once a listener has consumed the
    // done event, and this stream never got a listener.
    unawaited(controller.close());
  });

  testWidgets('disconnect closes the link', (tester) async {
    final controller = StreamController<SimWatchStatus>();
    final link = _FakeLink(controller);
    await _pumpScreen(tester, link);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.tap(find.text('Disconnect'));
    await tester.pump();
    expect(link.closed, isTrue);
    expect(find.text('Connect'), findsOneWidget);
    // Not awaited: the subscription was cancelled on disconnect, so the
    // done event has no listener left to be delivered to.
    unawaited(controller.close());
  });

  group('settings gate', () {
    late Directory tempDir;

    Future<void> pumpSettings(WidgetTester tester, String? url) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(
            preferences: prefs,
            heartRate: BleHeartRate(),
            treadmill: BleTreadmill(),
            devBackendUrl: url,
          ),
        ),
      );
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sim_watch_gate_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('sim watch tile shows only for a loopback backend',
        (tester) async {
      await pumpSettings(tester, 'http://127.0.0.1:54321');
      await tester.dragUntilVisible(
        find.text('Sim watch link'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.text('Sim watch link'), findsOneWidget);
    });

    testWidgets('sim watch tile hidden against a real backend',
        (tester) async {
      await pumpSettings(tester, 'https://abc.supabase.co');
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      expect(find.text('Sim watch link'), findsNothing);
    });
  });

  group('run sync', () {
    testWidgets('Sync action pulls the golden run and delivers it',
        (tester) async {
      final delivered = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SimWatchScreen(
            transportFactory: _FakeSyncTransport.new,
            runSink: (p) async => delivered.add(p),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pump();
      // The pull is real-async (broadcast stream + completers); let the event
      // loop drain it (pumpAndSettle would hang on the sync spinner).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(delivered, hasLength(1));
      expect(delivered.first['source'], 'watch');
      expect((delivered.first['track'] as List), hasLength(3));
      expect(find.textContaining('Synced 1 of 1'), findsOneWidget);
    });
  });
}
