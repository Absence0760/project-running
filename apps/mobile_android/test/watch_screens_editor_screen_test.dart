import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/watch_screens_editor_screen.dart';
import '../lib/sim_watch_sync.dart';
import '../lib/watch_screens.dart';

class _FakeTransport implements WatchBleTransport {
  final _chunks = StreamController<List<int>>.broadcast();
  final screensWrites = <List<int>>[];
  final Object? writeError;
  int scanCount = 0;
  int disconnectCount = 0;

  _FakeTransport({this.writeError});

  @override
  Stream<List<int>> get chunkStream => _chunks.stream;
  @override
  Future<void> scan() async {
    scanCount++;
  }

  @override
  Future<List<int>> readManifest() async => const [];
  @override
  Future<List<int>> readPushStatus() async => const [];
  @override
  Future<void> writeChunkRequest(List<int> request) async {}
  @override
  Future<void> writeSettings(List<int> frame) async {}
  @override
  Future<void> writeWorkout(List<int> chunk) async {}
  @override
  Future<void> writeCourse(List<int> chunk) async {}
  @override
  Future<void> writeRoadbook(List<int> chunk) async {}
  @override
  Future<void> writeScreens(List<int> frame) async {
    if (writeError != null) throw writeError!;
    screensWrites.add(frame);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
  }
}

/// Pump the editor and let the SharedPreferences read settle — the store
/// read is a real platform-channel round trip, so it needs `runAsync`.
Future<void> _pumpEditor(WidgetTester tester, {_FakeTransport? transport}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WatchScreensEditorScreen(
        transportFactory: () => transport ?? _FakeTransport(),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

/// Drain the fire-and-forget SharedPreferences write a mutation kicks off.
Future<void> _settleStore(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

String _draftJson(List<Map<String, Object>> screens) => jsonEncode(screens);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('draft codec', () {
    test('a set round-trips through its stored form', () {
      final screens = [
        WatchScreen(WatchLayout.duo,
            const [WatchMetric.distance, WatchMetric.avgPace]),
        WatchScreen(WatchLayout.single, const [WatchMetric.climbGain]),
      ];
      final back = decodeWatchScreenDraft(encodeWatchScreenDraft(screens))!;
      expect(back, hasLength(2));
      expect(back.first.layout, WatchLayout.duo);
      expect(back.first.metrics,
          const [WatchMetric.distance, WatchMetric.avgPace]);
      expect(back.last.layout, WatchLayout.single);
      expect(back.last.metrics, const [WatchMetric.climbGain]);
    });

    test('the stored form names layouts and metrics by their wire name', () {
      final raw = encodeWatchScreenDraft([
        WatchScreen(WatchLayout.trio, const [
          WatchMetric.elapsed,
          WatchMetric.heartRate,
          WatchMetric.altitude,
        ]),
      ]);
      expect(
        jsonDecode(raw),
        [
          {
            'layout': 'trio',
            'metrics': ['elapsed', 'heart_rate', 'altitude'],
          }
        ],
      );
    });

    test('an arity mismatch rejects the whole set, not just the screen', () {
      final raw = _draftJson([
        {
          'layout': 'duo',
          'metrics': ['distance'],
        },
        {
          'layout': 'single',
          'metrics': ['elapsed'],
        },
      ]);
      expect(decodeWatchScreenDraft(raw), isNull);
    });

    test('an unknown layout or metric name rejects the set', () {
      expect(
        decodeWatchScreenDraft(_draftJson([
          {
            'layout': 'quad',
            'metrics': ['elapsed'],
          }
        ])),
        isNull,
      );
      expect(
        decodeWatchScreenDraft(_draftJson([
          {
            'layout': 'single',
            'metrics': ['moon_phase'],
          }
        ])),
        isNull,
      );
    });

    test('a set past the cap rejects rather than truncating', () {
      final raw = _draftJson([
        for (var i = 0; i < kMaxWatchScreens + 1; i++)
          {
            'layout': 'single',
            'metrics': ['elapsed'],
          }
      ]);
      expect(decodeWatchScreenDraft(raw), isNull);
    });

    test('malformed json is null, not a throw', () {
      expect(decodeWatchScreenDraft('{'), isNull);
      expect(decodeWatchScreenDraft('"not a list"'), isNull);
    });
  });

  group('editor', () {
    testWidgets('the loading phase stands screen-card blocks, not a bare '
        'spinner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WatchScreensEditorScreen(
            transportFactory: _FakeTransport.new,
          ),
        ),
      );
      // No runAsync yet: the store read is still in flight.
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(find.byType(ListSkeleton), findsNothing);
    });

    testWidgets('an empty store lands on the empty state, not a blank list',
        (tester) async {
      await _pumpEditor(tester);
      expect(find.text('No screens composed'), findsOneWidget);
      expect(find.text('0 of 4 screens'), findsOneWidget);
      expect(find.text('Screen 1'), findsNothing);
    });

    testWidgets('adding a screen seeds a single-slot draft', (tester) async {
      await _pumpEditor(tester);
      await tester.tap(find.text('Add screen'));
      await _settleStore(tester);

      expect(find.text('Screen 1'), findsOneWidget);
      expect(find.text('1 of 4 screens'), findsOneWidget);
      expect(find.text('Slot 1'), findsOneWidget);
      expect(find.text('Slot 2'), findsNothing);
    });

    testWidgets('the add affordance stops at the cap rather than throwing',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          for (var i = 0; i < kMaxWatchScreens; i++)
            {
              'layout': 'single',
              'metrics': ['elapsed'],
            }
        ]),
      });
      await _pumpEditor(tester);

      expect(find.text('4 of 4 screens'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Add screen'), 300);
      await tester.pump();
      expect(find.text('A watch holds at most 4 screens.'), findsOneWidget);
      final add = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Add screen'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(add.onPressed, isNull);
    });

    testWidgets('widening the layout fills the new slots with distinct metrics',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          {
            'layout': 'single',
            'metrics': ['elapsed'],
          }
        ]),
      });
      await _pumpEditor(tester);

      await tester.tap(find.text('Trio'));
      await _settleStore(tester);

      expect(find.text('Slot 1'), findsOneWidget);
      expect(find.text('Slot 2'), findsOneWidget);
      expect(find.text('Slot 3'), findsOneWidget);
      final stored = decodeWatchScreenDraft(
        (await SharedPreferences.getInstance())
            .getString(kWatchScreensPrefsKey)!,
      )!;
      expect(stored.single.layout, WatchLayout.trio);
      expect(stored.single.metrics,
          const [WatchMetric.elapsed, WatchMetric.distance,
              WatchMetric.avgPace]);
    });

    testWidgets('narrowing the layout names the metrics it would drop',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          {
            'layout': 'trio',
            'metrics': ['elapsed', 'heart_rate', 'altitude'],
          }
        ]),
      });
      await _pumpEditor(tester);

      await tester.tap(find.text('Single'));
      await tester.pumpAndSettle();

      expect(find.text('Drop 2 metric(s)?'), findsOneWidget);
      expect(find.textContaining('Heart rate, Altitude'), findsOneWidget);
    });

    testWidgets('cancelling the narrow keeps every metric', (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          {
            'layout': 'trio',
            'metrics': ['elapsed', 'heart_rate', 'altitude'],
          }
        ]),
      });
      await _pumpEditor(tester);

      await tester.tap(find.text('Single'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Slot 3'), findsOneWidget);
    });

    testWidgets('confirming the narrow truncates to the layout arity',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          {
            'layout': 'trio',
            'metrics': ['elapsed', 'heart_rate', 'altitude'],
          }
        ]),
      });
      await _pumpEditor(tester);

      await tester.tap(find.text('Single'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Change layout'),
      ));
      await tester.pumpAndSettle();
      await _settleStore(tester);

      expect(find.text('Slot 2'), findsNothing);
      final stored = decodeWatchScreenDraft(
        (await SharedPreferences.getInstance())
            .getString(kWatchScreensPrefsKey)!,
      )!;
      expect(stored.single.layout, WatchLayout.single);
      expect(stored.single.metrics, const [WatchMetric.elapsed]);
    });

    testWidgets('moving a slot down reorders the frame, because order is meaning',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          {
            'layout': 'duo',
            'metrics': ['distance', 'avg_pace'],
          }
        ]),
      });
      await _pumpEditor(tester);

      await tester.tap(find.byTooltip('Move down').first);
      await _settleStore(tester);

      final stored = decodeWatchScreenDraft(
        (await SharedPreferences.getInstance())
            .getString(kWatchScreensPrefsKey)!,
      )!;
      expect(stored.single.metrics,
          const [WatchMetric.avgPace, WatchMetric.distance]);
    });

    testWidgets('removing a screen asks first and keeps it on cancel',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          {
            'layout': 'duo',
            'metrics': ['distance', 'avg_pace'],
          }
        ]),
      });
      await _pumpEditor(tester);

      await tester.tap(find.byTooltip('Remove screen'));
      await tester.pumpAndSettle();
      expect(find.text('Remove screen 1?'), findsOneWidget);
      expect(find.text('Its 2 metric(s) go with it.'), findsOneWidget);

      // Routed through confirmDestructive: cancel first and unstyled, the
      // confirm carrying the error colour.
      final actions = tester
          .widgetList<TextButton>(find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          ))
          .toList();
      expect(actions, hasLength(2));
      expect((actions.first.child! as Text).data, 'Cancel');
      expect(actions.first.style?.foregroundColor, isNull);
      expect(
        actions.last.style?.foregroundColor?.resolve({}),
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.error,
      );

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Screen 1'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove screen'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Remove'),
      ));
      await tester.pumpAndSettle();
      await _settleStore(tester);
      expect(find.text('No screens composed'), findsOneWidget);
    });

    testWidgets('an unreadable saved set offers a start-over, not a wrong set',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          {
            'layout': 'duo',
            'metrics': ['distance'],
          }
        ]),
      });
      await _pumpEditor(tester);

      expect(find.text("The saved screens couldn't be read."), findsOneWidget);
      expect(find.text('Add screen'), findsNothing);

      await tester.tap(find.text('Start over'));
      await _settleStore(tester);
      expect(find.text('No screens composed'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance())
            .getString(kWatchScreensPrefsKey),
        isNull,
      );
    });
  });

  group('push', () {
    testWidgets('the push writes the SCR1 frame the encoder produced',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kWatchScreensPrefsKey: _draftJson([
          {
            'layout': 'duo',
            'metrics': ['distance', 'avg_pace'],
          }
        ]),
      });
      final transport = _FakeTransport();
      await _pumpEditor(tester, transport: transport);

      await tester.tap(find.byIcon(Icons.upload));
      await _settleStore(tester);

      expect(transport.screensWrites, hasLength(1));
      // The frozen golden frame both codecs pin (watch_screens_test.dart /
      // watch_core::screens::the_golden_frame_is_stable) — one Duo of
      // distance + average pace.
      expect(
        transport.screensWrites.single,
        [
          0x53, 0x43, 0x52, 0x31, 0x01, 0x01, 0x00, 0x00, //
          0x01, 0x02, 0x03, 0x00, //
          0x7b, 0x58, 0xf9, 0x01,
        ],
      );
      expect(transport.disconnectCount, 1);
      expect(find.text('Pushed 1 screen(s) to the watch'), findsOneWidget);
    });

    testWidgets('pushing an empty set clears the watch, and says so',
        (tester) async {
      final transport = _FakeTransport();
      await _pumpEditor(tester, transport: transport);

      await tester.tap(find.byIcon(Icons.upload));
      await _settleStore(tester);

      expect(transport.screensWrites.single.sublist(0, 6),
          [0x53, 0x43, 0x52, 0x31, 0x01, 0x00]);
      expect(
        find.text('Cleared the composed screens on the watch'),
        findsOneWidget,
      );
    });

    testWidgets('a failed push surfaces the error rather than reading as sent',
        (tester) async {
      final transport = _FakeTransport(writeError: StateError('no radio'));
      await _pumpEditor(tester, transport: transport);

      await tester.tap(find.byIcon(Icons.upload));
      await _settleStore(tester);

      expect(find.textContaining('Screens push failed'), findsOneWidget);
      expect(find.textContaining('no radio'), findsOneWidget);
      expect(transport.disconnectCount, 1);
    });
  });
}
