import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:mobile_android/social_service.dart';
import 'package:mobile_android/widgets/upcoming_event_card.dart';

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
    createdBy: 'user1',
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
}) {
  return tester.pumpWidget(
    MaterialApp(
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

    testWidgets('calls onTap when tapped', (tester) async {
      var taps = 0;
      await _pump(tester, _event(), onTap: () => taps++);
      await tester.tap(find.byType(UpcomingEventCard));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
