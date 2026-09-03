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
import '../lib/watch_roadbook.dart';
import '../lib/sim_watch_sync.dart';
import 'pump_until.dart';

/// The golden run blob from `watch_core::run_store` (pinned identically in
/// `sim_watch_sync_test.dart`), served in chunks so the screen's Sync action
/// can be exercised without a BLE radio.
final _goldenBlob = _hex(
  '54524b31030100000700000029000000b8ced91718ff40c100000000703f7800'
  'e4cfd9170c0141c101000000723f7a0074d1d917000341c10200000000800000'
  '454e4431d2040000580200006c02000039e3c091',
);

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
    ];

class _FakeSyncTransport implements WatchBleTransport {
  final _chunks = StreamController<List<int>>.broadcast();
  final settingsWrites = <List<int>>[];
  final workoutWrites = <List<int>>[];
  final courseWrites = <List<int>>[];
  final screensWrites = <List<int>>[];
  final roadbookWrites = <List<int>>[];
  @override
  Future<void> scan() async {}
  @override
  Future<List<int>> readPushStatus() async => const [];
  @override
  Future<void> disconnect() async {}
  @override
  Stream<List<int>> get chunkStream => _chunks.stream;
  @override
  Future<List<int>> readManifest() async => [
        0x4d, 0x41, 0x4e, 0x31, 0x03, 0x01, 0x00, 0x00, // MAN1 v3 count=1
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

/// Taps the toolbar action carrying [icon]. The Sim Watch toolbar keeps two
/// actions visible and folds the rest into an overflow menu (issue #666 C4),
/// so an action that is not on the toolbar is reached through it.
Future<void> _tapAction(WidgetTester tester, IconData icon) async {
  if (tester.any(find.byIcon(icon))) {
    await tester.tap(find.byIcon(icon));
    return;
  }
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(icon));
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
      await _tapAction(tester, Icons.sync);
      await tester.pump();
      // The pull is real-async (broadcast stream + completers), so it needs the
      // real event loop; pumpAndSettle would hang on the sync spinner.
      await pumpUntil(tester, () => delivered.isNotEmpty,
          describe: 'the pulled run to reach the sink');

      expect(delivered, hasLength(1));
      expect(delivered.first['source'], 'watch');
      expect((delivered.first['track'] as List), hasLength(3));
      expect(find.textContaining('Synced 1 of 1'), findsOneWidget);
    });
  });

  group('settings push', () {
    testWidgets('Push-settings action writes the encoded frame',
        (tester) async {
      final transport = _FakeSyncTransport();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SimWatchScreen(
            transportFactory: () => transport,
            runSink: (_) async {},
            tzOffset: () => const Duration(hours: 5, minutes: 45),
          ),
        ),
      );
      await _tapAction(tester, Icons.tune);
      await tester.pump();
      await pumpUntil(tester, () => transport.settingsWrites.isNotEmpty,
          describe: 'the settings frame to be written to the transport');

      expect(transport.settingsWrites, hasLength(1));
      expect(transport.settingsWrites.single, hasLength(38));
      expect(transport.settingsWrites.single.sublist(0, 8),
          [0x53, 0x45, 0x54, 0x31, 0x08, 0x0f, 0x41, 0x03]);
      // The injected +5:45 phone zone rides as i16 LE 345, then the demo
      // resting HR (the v5 TRIMP half), the v7 auto-lap rung and the v8 storm
      // threshold in tenths of a hPa, ahead of the crc32 trailer.
      expect(
        transport.settingsWrites.single.sublist(27, 29),
        [0x59, 0x01],
      );
      expect(
        transport.settingsWrites.single.sublist(29, 31),
        [0x32, 0x00],
      );
      expect(transport.settingsWrites.single[31], 0x02);
      expect(
        transport.settingsWrites.single.sublist(32, 34),
        [0x28, 0x00],
      );
      final frame = transport.settingsWrites.single;
      final trailer = frame[34] |
          (frame[35] << 8) |
          (frame[36] << 16) |
          (frame[37] << 24);
      expect(trailer, crc32(frame.sublist(0, 34)));
      expect(find.text('Settings pushed to the watch'), findsOneWidget);
    });
  });

  group('workout push', () {
    testWidgets('Push-workout action writes the chunked WKT1 frame',
        (tester) async {
      final transport = _FakeSyncTransport();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SimWatchScreen(
            transportFactory: () => transport,
            runSink: (_) async {},
          ),
        ),
      );
      await _tapAction(tester, Icons.checklist);
      await tester.pump();
      await pumpUntil(tester, () => transport.workoutWrites.isNotEmpty,
          describe: 'the workout frame to be written to the transport');

      // The six-step demo frame (7 + 6*12 + 4 = 83 B) fits one chunk:
      // offset(2 LE) | payload. The frame bytes themselves are pinned
      // byte-exact against the Rust golden in watch_workout_test.dart, so
      // this pins the plumbing: offset 0 leads, the payload is the sealed
      // WKT1 frame the encoder produced.
      expect(transport.workoutWrites, hasLength(1));
      final chunk = transport.workoutWrites.single;
      expect(chunk.sublist(0, 2), [0x00, 0x00]);
      final frame = chunk.sublist(2);
      expect(frame, hasLength(83));
      expect(frame.sublist(0, 4), [0x57, 0x4b, 0x54, 0x31]); // WKT1
      expect(frame[5], 6, reason: 'six demo steps');
      final trailer = frame[79] |
          (frame[80] << 8) |
          (frame[81] << 16) |
          (frame[82] << 24);
      expect(trailer, crc32(frame.sublist(0, 79)));
      expect(
        find.text('Workout pushed to the watch (6 steps)'),
        findsOneWidget,
      );
    });
  });

  group('composed screens', () {
    testWidgets('the compose action opens the screen editor', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SimWatchScreen(
            transportFactory: _FakeSyncTransport.new,
            runSink: (_) async {},
          ),
        ),
      );
      await _tapAction(tester, Icons.dashboard_customize);
      await tester.pumpAndSettle();
      await pumpUntil(tester, () => tester.any(find.text('No screens composed')),
          describe: "the editor's stored-screens read to resolve to empty");

      expect(find.text('Watch screens'), findsOneWidget);
      expect(find.text('No screens composed'), findsOneWidget);
    });
  });

  group('course push', () {
    testWidgets('Push-course action writes the chunked CRS1 frame',
        (tester) async {
      final transport = _FakeSyncTransport();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SimWatchScreen(
            transportFactory: () => transport,
            runSink: (_) async {},
          ),
        ),
      );
      await _tapAction(tester, Icons.route);
      await tester.pump();
      await pumpUntil(tester, () => transport.courseWrites.isNotEmpty,
          describe: 'the course frame to be written to the transport');

      // The three-point demo course with elevation (8 + 3*8 + 3*2 + 4 =
      // 42 B) fits one chunk: offset(2 LE) | payload. The frame bytes are
      // the CRS1 golden fixture watch_course_test.dart pins byte-exact
      // against the Rust vectors; this pins the plumbing.
      expect(transport.courseWrites, hasLength(1));
      final chunk = transport.courseWrites.single;
      expect(chunk.sublist(0, 2), [0x00, 0x00]);
      final frame = chunk.sublist(2);
      expect(frame, hasLength(42));
      expect(frame.sublist(0, 4), [0x43, 0x52, 0x53, 0x31]); // CRS1
      expect(frame[5] | (frame[6] << 8), 3, reason: 'three demo points');
      expect(frame[7], 1, reason: 'the elevation flag rides the push');
      final trailer = frame[38] |
          (frame[39] << 8) |
          (frame[40] << 16) |
          (frame[41] << 24);
      expect(trailer, crc32(frame.sublist(0, 38)));
      expect(
        find.text('Course pushed to the watch (3 points)'),
        findsOneWidget,
      );
    });
  });

  group('roadbook push', () {
    testWidgets('Push-roadbook action writes the chunked RBK1 frame',
        (tester) async {
      final transport = _FakeSyncTransport();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SimWatchScreen(
            transportFactory: () => transport,
            runSink: (_) async {},
          ),
        ),
      );
      await _tapAction(tester, Icons.table_chart_outlined);
      await tester.pump();
      await pumpUntil(tester, () => transport.roadbookWrites.isNotEmpty,
          describe: 'the roadbook frame to be written to the transport');

      // The canned three-checkpoint / two-cut-off sim schedule fits one chunk.
      // Sized from the encoder's own layout rather than restated, or a wire
      // revision moves the frame and this reads a stale number as a pass.
      // The frame bytes are the RBK1 golden fixture watch_roadbook_test.dart
      // pins byte-exact against the Rust vectors; this pins the plumbing.
      const expectedFrameLen = kRoadbookHeaderLen +
          3 * kRoadbookCheckpointLen +
          2 * kRoadbookCutoffLen +
          kRoadbookCrcLen;
      expect(transport.roadbookWrites, hasLength(1));
      final chunk = transport.roadbookWrites.single;
      expect(chunk.sublist(0, 2), [0x00, 0x00]);
      final frame = chunk.sublist(2);
      expect(frame, hasLength(expectedFrameLen));
      expect(frame.sublist(0, 4), [0x52, 0x42, 0x4b, 0x31]); // RBK1
      expect(frame[5], 3, reason: 'three demo checkpoints');
      expect(frame[6], 2, reason: 'two demo cut-offs');
      const bodyLen = expectedFrameLen - kRoadbookCrcLen;
      final trailer = frame[bodyLen] |
          (frame[bodyLen + 1] << 8) |
          (frame[bodyLen + 2] << 16) |
          (frame[bodyLen + 3] << 24);
      expect(trailer, crc32(frame.sublist(0, bodyLen)));
      expect(
        find.text('Roadbook pushed to the watch (3 checkpoints, 2 cut-offs)'),
        findsOneWidget,
      );
      expect(transport.courseWrites, isEmpty,
          reason: 'the roadbook action must not touch the course handle');
    });
  });
}
