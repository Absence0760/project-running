import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/event_category.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/social_service.dart';

ClubView _club(String? viewerRole) => ClubView(
      row: ClubRow(
        id: 'club-1',
        slug: 'club-1',
        name: 'Club',
        description: null,
        locationLabel: null,
        isPublic: true,
        joinPolicy: 'open',
        ownerId: 'owner-1',
        createdAt: DateTime(2026, 1, 1),
        memberCount: 1,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 1,
      viewerRole: viewerRole,
      viewerStatus: viewerRole == null ? null : 'active',
      joinPolicy: 'open',
    );

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

  group('M6 attendance — host-gating predicate', () {
    test('an organiser of a class event may mark attendance', () {
      expect(canMarkEventAttendance(_club('owner'), 'class'), isTrue);
      expect(canMarkEventAttendance(_club('admin'), 'class'), isTrue);
      expect(canMarkEventAttendance(_club('event_organiser'), 'class'), isTrue);
    });

    test('a non-organiser viewer may NOT mark attendance', () {
      expect(canMarkEventAttendance(_club('member'), 'class'), isFalse);
      expect(canMarkEventAttendance(_club(null), 'class'), isFalse);
      expect(canMarkEventAttendance(null, 'class'), isFalse);
    });

    test('attendance marking is class-only — never on run/cycle/social', () {
      expect(canMarkEventAttendance(_club('owner'), 'run'), isFalse);
      expect(canMarkEventAttendance(_club('owner'), 'cycle'), isFalse);
      expect(canMarkEventAttendance(_club('owner'), 'social'), isFalse);
    });
  });
}
