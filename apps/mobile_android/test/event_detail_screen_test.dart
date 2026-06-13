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

/// Renders one upcoming athletic event (so the RSVP row shows) and throws
/// on the RSVP write to drive the swallowed-failure banner.
class _RsvpFailSocial extends SocialService {
  int rsvpCalls = 0;
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => null;
  @override
  Future<EventView?> fetchEventById(String eventId) async => EventView(
        row: EventRow(
          id: 'e1',
          clubId: 'club-1',
          title: 'Saturday Long Run',
          startsAt: DateTime.utc(2026, 6, 20, 8),
          authorId: 'host',
          category: 'run',
          isPublic: true,
        ),
        byday: null,
        attendeeCount: 0,
        viewerRsvp: null,
        nextInstanceStart: DateTime.utc(2026, 6, 20, 8),
      );
  @override
  Future<List<AttendeeView>> fetchAttendees(String eventId, DateTime instance) async => const [];
  @override
  Future<List<EventResultView>> fetchEventResults(String eventId, DateTime instance) async =>
      const [];
  @override
  Future<RaceSessionRow?> fetchRaceSession(String eventId, DateTime instance) async => null;
  @override
  Future<({double lat, double lng})?> fetchEventMeetPoint(String eventId) async => null;
  @override
  Future<void> rsvpEvent(String eventId, String status, DateTime instance) async {
    rsvpCalls++;
    throw Exception('network down');
  }
}

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

  group('EventDetailScreen — RSVP failure', () {
    testWidgets('a failed RSVP surfaces a banner instead of silently reverting',
        (tester) async {
      final social = _RsvpFailSocial();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: social,
            clubSlug: 'club-1',
            eventId: 'e1',
          ),
        ),
      );
      // Let _load resolve (two Future.wait batches).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final going = find.widgetWithText(OutlinedButton, "I'm in");
      expect(going, findsOneWidget);
      await tester.tap(going);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(social.rsvpCalls, 1);
      expect(find.textContaining("Couldn't update your RSVP"), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // drain banner timer
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
