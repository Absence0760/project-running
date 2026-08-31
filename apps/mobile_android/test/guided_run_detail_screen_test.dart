import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show TextLane;

import '../lib/audio_cues.dart';
import '../lib/guided_runs.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/main.dart' show pendingArmGuidedRun;
import '../lib/screens/guided_runs_screen.dart';

final AppLocalizations _l10n = AppLocalizationsEn();

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

/// FakeAudioCues — records every speakGuidedCue call so the test can
/// assert the Preview button on the detail screen wires through. Does
/// not extend AudioCues because that class instantiates FlutterTts in
/// its constructor (platform channel binding); a separate fake keeps
/// the test off the platform.
class FakeAudioCues implements AudioCues {
  final List<String> spoken = [];

  @override
  Future<void> speakGuidedCue(String text) async {
    spoken.add(text);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Other AudioCues methods aren't exercised by GuidedRunDetailScreen.
    // Default to no-op futures.
    return Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GuidedRunDetailScreen renders the title + subtitle + description',
      (tester) async {
    final run = guidedRunLibrary(_l10n).first;
    await tester.pumpWidget(
      _app(GuidedRunDetailScreen(run: run, audioCues: FakeAudioCues())),
    );
    expect(find.text(run.title), findsWidgets);
    expect(find.text(run.subtitle), findsOneWidget);
    expect(find.text(run.description), findsOneWidget);
  });

  testWidgets('GuidedRunDetailScreen renders one ListTile per cue', (tester) async {
    // Use a small fixture so every cue fits in the viewport — the
    // library's first run has 8 cues which overflows the test surface.
    const fixture = GuidedRun(
      id: 'fixture',
      title: 'Fixture',
      subtitle: 'subtitle',
      durationSec: 180,
      description: 'desc',
      cues: [
        GuidedCue(atSec: 0, text: 'First'),
        GuidedCue(atSec: 60, text: 'Second'),
        GuidedCue(atSec: 180, text: 'Third'),
      ],
    );
    await tester.pumpWidget(
      _app(GuidedRunDetailScreen(run: fixture, audioCues: FakeAudioCues())),
    );
    for (final cue in fixture.cues) {
      expect(find.text(cue.text), findsOneWidget, reason: 'cue "${cue.text}" missing');
    }
  });

  testWidgets('GuidedRunDetailScreen shows the formatted at_sec on each row',
      (tester) async {
    // Use a run with known cue times so we can pin the formatter.
    const fixture = GuidedRun(
      id: 'fixture',
      title: 'Fixture',
      subtitle: 'subtitle',
      durationSec: 600,
      description: 'desc',
      cues: [
        GuidedCue(atSec: 0, text: 'Cue at zero'),
        GuidedCue(atSec: 65, text: 'Cue at one minute five'),
        GuidedCue(atSec: 600, text: 'Cue at ten'),
      ],
    );
    await tester.pumpWidget(
      _app(GuidedRunDetailScreen(run: fixture, audioCues: FakeAudioCues())),
    );
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
  });

  testWidgets('Preview icon tap routes through audioCues.speakGuidedCue',
      (tester) async {
    final fake = FakeAudioCues();
    const fixture = GuidedRun(
      id: 'fixture',
      title: 'Fixture',
      subtitle: 'subtitle',
      durationSec: 120,
      description: 'desc',
      cues: [
        GuidedCue(atSec: 0, text: 'First cue spoken'),
        GuidedCue(atSec: 60, text: 'Second cue spoken'),
        GuidedCue(atSec: 120, text: 'Third cue spoken'),
      ],
    );
    await tester.pumpWidget(
      _app(GuidedRunDetailScreen(run: fixture, audioCues: fake)),
    );

    // Tap the first volume_up icon — should speak the first cue's text.
    await tester.tap(find.byIcon(Icons.volume_up).first);
    await tester.pump();

    expect(fake.spoken, ['First cue spoken']);
  });

  testWidgets('Preview icons appear on every cue row', (tester) async {
    const fixture = GuidedRun(
      id: 'fixture',
      title: 'Fixture',
      subtitle: 'subtitle',
      durationSec: 120,
      description: 'desc',
      cues: [
        GuidedCue(atSec: 0, text: 'a'),
        GuidedCue(atSec: 60, text: 'b'),
        GuidedCue(atSec: 120, text: 'c'),
      ],
    );
    await tester.pumpWidget(
      _app(GuidedRunDetailScreen(run: fixture, audioCues: FakeAudioCues())),
    );
    expect(find.byIcon(Icons.volume_up), findsNWidgets(3));
  });

  group('GuidedRunDetailScreen — Use this run', () {
    tearDown(() => pendingArmGuidedRun.value = null);

    testWidgets('parks the library id and clears the pushed screens',
        (tester) async {
      final run = guidedRunLibrary(_l10n).first;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GuidedRunDetailScreen(
                    run: run,
                    audioCues: FakeAudioCues(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(GuidedRunDetailScreen), findsOneWidget);

      await tester.tap(find.text('Use this run'));
      await tester.pumpAndSettle();

      expect(pendingArmGuidedRun.value, run.id,
          reason: 'the recorder is handed the library id, never a title');
      expect(find.byType(GuidedRunDetailScreen), findsNothing,
          reason: 'the Run tab lives under the shell, so the pushed screens '
              'have to come off the stack for the switch to be visible');
    });
  });

  group('GuidedRunDetailScreen — the cue timestamp lane', () {
    // The cue timestamp sat in a 56px box. "120:00" needs 64.0px in real
    // Roboto at titleSmall once the OS text scale reaches 1.5x and 85.4 at
    // 2x, and a mm:ss stamp carries no break opportunity, so it painted over
    // the cue text beside it.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so a lane whose floor tracks
    // the scale here tracks it on a device too.
    const fixture = GuidedRun(
      id: 'fixture',
      title: 'Fixture',
      subtitle: 'subtitle',
      durationSec: 7200,
      description: 'desc',
      cues: [GuidedCue(atSec: 7200, text: 'Two hours in')],
    );

    Future<void> pumpCue(WidgetTester tester, {double scale = 1.0}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: GuidedRunDetailScreen(run: fixture, audioCues: FakeAudioCues()),
        ),
      );
      await tester.pump();
    }

    testWidgets('the lane widens to the stamp instead of overpainting',
        (tester) async {
      await pumpCue(tester);
      final lane = find.ancestor(
        of: find.text('120:00'),
        matching: find.byType(TextLane),
      );
      expect(lane, findsOneWidget);
      final stamp = tester.renderObject<RenderParagraph>(find.text('120:00'));
      expect(
        tester.getSize(lane).width,
        greaterThanOrEqualTo(stamp.getMaxIntrinsicWidth(double.infinity)),
      );
    });

    testWidgets('the lane floor grows with the OS text scale', (tester) async {
      await pumpCue(tester, scale: 2.0);
      final lane = find.byType(TextLane).first;
      expect(tester.getSize(lane).width,
          greaterThanOrEqualTo(tester.widget<TextLane>(lane).width * 2));
    });
  });
}
