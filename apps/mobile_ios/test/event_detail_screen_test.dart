import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/event_category.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/social_service.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EventDetailScreen(
        social: SocialService(),
        clubSlug: 'fake-slug',
        eventId: 'fake-event-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('EventDetailScreen — initial render', () {
    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold with just a centered spinner.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('initial Scaffold has no AppBar yet', (tester) async {
      await _pump(tester);
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('EventDisciplineLabel — slice E class display', () {
    Future<void> pumpLabel(WidgetTester tester, String discipline) {
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EventDisciplineLabel(discipline: discipline),
          ),
        ),
      );
    }

    testWidgets('shows the CLASS eyebrow and the free-text discipline',
        (tester) async {
      await pumpLabel(tester, 'Vinyasa Yoga');
      expect(find.text('CLASS'), findsOneWidget);
      expect(find.text('Vinyasa Yoga'), findsOneWidget);
    });

    testWidgets('renders no athletic affordances', (tester) async {
      await pumpLabel(tester, 'Pilates');
      // A class label is attendance-only: no distance / target-pace metric,
      // no results leaderboard, no Submit-my-time button.
      expect(find.text('Target pace'), findsNothing);
      expect(find.text('Submit my time'), findsNothing);
      expect(find.byType(EventResultsSection), findsNothing);
    });
  });

  group('slice E gating predicate', () {
    test('class / social hide the athletic surface; run / cycle show it', () {
      expect(isAthleticEventCategory('class'), isFalse);
      expect(isAthleticEventCategory('social'), isFalse);
      expect(isAthleticEventCategory('run'), isTrue);
      expect(isAthleticEventCategory('cycle'), isTrue);
    });
  });
}
