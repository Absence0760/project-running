import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:ui_kit/ui_kit.dart';
import '../lib/social_service.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/upcoming_event_card.dart';

EventView _event({
  String title = 'Saturday 5k',
  String? meetLabel,
  DateTime? nextInstanceStart,
}) {
  final when = nextInstanceStart ?? DateTime.now().add(const Duration(hours: 5));
  final row = EventRow(
    id: 'e1',
    clubId: 'c1',
    title: title,
    startsAt: when,
    authorId: 'user1',
    category: 'run',
    isPublic: true,
    meetLabel: meetLabel,
  );
  return EventView(
    row: row,
    byday: null,
    attendeeCount: 10,
    viewerRsvp: 'going',
    nextInstanceStart: when,
  );
}

Future<void> _pump(
  WidgetTester tester,
  EventView event, {
  VoidCallback? onTap,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: UpcomingEventCard(event: event, onTap: onTap),
      ),
    ),
  );
}

void main() {
  group('UpcomingEventCard', () {
    testWidgets('renders the event title', (tester) async {
      await _pump(tester, _event(title: 'Parkrun Saturday'));
      expect(find.text('Parkrun Saturday'), findsOneWidget);
    });

    testWidgets('renders the RSVP label', (tester) async {
      await _pump(tester, _event());
      expect(find.textContaining("RSVP'D"), findsOneWidget);
    });

    testWidgets('renders meet location label when provided', (tester) async {
      await _pump(tester, _event(meetLabel: 'Bandstand, Hyde Park'));
      expect(find.text('Bandstand, Hyde Park'), findsOneWidget);
    });

    testWidgets('omits meet location when meetLabel is null', (tester) async {
      await _pump(tester, _event(meetLabel: null));
      expect(find.byIcon(Icons.place), findsNothing);
    });

    testWidgets('date-only schedule row survives a narrow width without '
        'overflowing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: UpcomingEventCard(event: _event(meetLabel: null)),
              ),
            ),
          ),
        ),
      );
      // With no meet label the date is the only schedule-row text; at 200
      // it must ellipsize instead of throwing a RenderFlex overflow (the
      // harness fails the test on one).
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets('long title + meet label survive a narrow width without '
        'overflowing', (tester) async {
      const longTitle =
          'Jahresabschluss-Vereinsmeisterschaft mit anschliessendem '
          'gemeinsamem Fruehstueckslauf am Flussufer';
      const longMeet =
          'Treffpunkt am Haupteingang des Stadtparks neben dem grossen '
          'Brunnen gegenueber der Strassenbahnhaltestelle';
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: UpcomingEventCard(
                  event: _event(title: longTitle, meetLabel: longMeet),
                ),
              ),
            ),
          ),
        ),
      );
      // Title and meet label must ellipsize; a RenderFlex overflow fails
      // the test via the harness.
      expect(find.text(longTitle), findsOneWidget);
      expect(find.text(longMeet), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var taps = 0;
      await _pump(tester, _event(), onTap: () => taps++);
      await tester.tap(find.byType(UpcomingEventCard));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('null onTap does not crash on tap', (tester) async {
      await _pump(tester, _event());
      await tester.tap(find.byType(UpcomingEventCard));
      await tester.pump();
      // No exception — InkWell with a null onTap is inert.
      expect(tester.takeException(), isNull);
    });

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('event icon uses onPrimary over the primary bubble ($name)',
          (tester) async {
        await _pump(tester, _event(), theme: theme);
        final icon = tester.widget<Icon>(find.byIcon(Icons.event));
        expect(icon.color, theme.colorScheme.onPrimary);
      });
    }
  });

  group('UpcomingEventCard — relative-time badge', () {
    testWidgets('an imminent event (<=1 min out) reads "Starting now"',
        (tester) async {
      await _pump(
        tester,
        _event(
          nextInstanceStart: DateTime.now().add(const Duration(seconds: 30)),
        ),
      );
      expect(find.textContaining('Starting now'), findsOneWidget);
    });

    testWidgets('a few-minutes-out event reads "In N min"', (tester) async {
      await _pump(
        tester,
        _event(
          // +30 s buffer so the elapsed-during-test ms can't drop the
          // whole-minute count below 20 (inMinutes truncates).
          nextInstanceStart:
              DateTime.now().add(const Duration(minutes: 20, seconds: 30)),
        ),
      );
      expect(find.textContaining('In 20 min'), findsOneWidget);
    });

    testWidgets('exactly one hour out reads "In 1 hour"', (tester) async {
      await _pump(
        tester,
        _event(
          // A small buffer so the boundary lands cleanly on the 1h bucket.
          nextInstanceStart:
              DateTime.now().add(const Duration(hours: 1, seconds: 30)),
        ),
      );
      expect(find.textContaining('In 1 hour'), findsOneWidget);
    });

    testWidgets('several hours out reads "In N hours"', (tester) async {
      await _pump(
        tester,
        _event(
          nextInstanceStart:
              DateTime.now().add(const Duration(hours: 6, minutes: 1)),
        ),
      );
      expect(find.textContaining('In 6 hours'), findsOneWidget);
    });

    testWidgets('between 24h and 48h reads "Tomorrow"', (tester) async {
      await _pump(
        tester,
        _event(
          nextInstanceStart:
              DateTime.now().add(const Duration(hours: 30)),
        ),
      );
      expect(find.textContaining('Tomorrow'), findsOneWidget);
    });

    testWidgets('more than 48h out reads "In N days"', (tester) async {
      await _pump(
        tester,
        _event(
          nextInstanceStart:
              DateTime.now().add(const Duration(days: 3, hours: 1)),
        ),
      );
      expect(find.textContaining('In 3 days'), findsOneWidget);
    });
  });
}
