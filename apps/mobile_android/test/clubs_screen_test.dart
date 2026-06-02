import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/clubs_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ClubsScreen(
        social: SocialService(),
        training: TrainingService(),
      ),
    ),
  );
}

void main() {
  group('ClubsScreen — initial render', () {
    testWidgets('renders the Clubs app-bar title', (tester) async {
      await _pump(tester);
      await tester.pump();
      expect(find.text('Clubs'), findsOneWidget);
    });

    testWidgets('renders the Browse / My clubs segmented button',
        (tester) async {
      await _pump(tester);
      await tester.pump();
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      expect(find.text('Browse'), findsOneWidget);
      expect(find.text('My clubs'), findsOneWidget);
    });

    testWidgets('starts on the My clubs tab — search field is hidden',
        (tester) async {
      // Reason: returning users default to "My clubs" so they see the
      // clubs they're already in. Browse-only widgets (the search
      // TextField) must NOT render on first paint.
      await _pump(tester);
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search by name or location'),
          findsNothing);
    });

    testWidgets('renders the New club FAB with an add icon',
        (tester) async {
      await _pump(tester);
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('New club'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('switching to the Browse tab reveals the search field',
        (tester) async {
      await _pump(tester);
      await tester.pump();
      // Tap the "Browse" segment.
      await tester.tap(find.text('Browse'));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search by name or location'),
          findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });
}
