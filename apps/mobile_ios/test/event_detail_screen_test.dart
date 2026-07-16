import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/event_category.dart';
import '../lib/event_gym_template.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/session_steps.dart';
import '../lib/social_service.dart';

ClubView _club(String? viewerRole) => ClubView(
      row: ClubRow(shadowHidden: false, 
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

/// Configurable fake that drives the happy paths: a club (role configurable),
/// an athletic event, a canned attendee list, and a recording RSVP write.
class _EventSocial extends SocialService {
  _EventSocial({
    this.club,
    this.category = 'run',
    this.attendees = const [],
  });
  ClubView? club;
  String category;
  List<AttendeeView> attendees;
  int rsvpCalls = 0;
  int clearCalls = 0;
  String? lastRsvpStatus;

  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => club;
  @override
  Future<EventView?> fetchEventById(String eventId) async => EventView(
        row: EventRow(
          id: 'e1',
          clubId: 'club-1',
          title: 'Saturday Long Run',
          startsAt: DateTime.utc(2026, 6, 20, 8),
          authorId: 'host',
          category: category,
          distanceM: 21097,
          isPublic: true,
        ),
        byday: null,
        attendeeCount: attendees.length,
        viewerRsvp: null,
        nextInstanceStart: DateTime.utc(2026, 6, 20, 8),
      );
  @override
  Future<List<AttendeeView>> fetchAttendees(
          String eventId, DateTime instance) async =>
      attendees;
  @override
  Future<List<EventResultView>> fetchEventResults(
          String eventId, DateTime instance) async =>
      const [];
  @override
  Future<RaceSessionRow?> fetchRaceSession(
          String eventId, DateTime instance) async =>
      null;
  @override
  Future<({double lat, double lng})?> fetchEventMeetPoint(
          String eventId) async =>
      null;
  @override
  Future<void> rsvpEvent(String eventId, String status, DateTime instance) async {
    rsvpCalls++;
    lastRsvpStatus = status;
  }

  @override
  Future<void> clearRsvp(String eventId, DateTime instance) async {
    clearCalls++;
  }

  @override
  RealtimeChannel subscribeToEvent(
          String eventId, String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$eventId');
}

/// Drives the Submit-time sheet's failure path: a recent-runs fetch that
/// always throws, so the sheet must show the error + retry affordance
/// instead of spinning forever.
class _RecentRunsFailSocial extends _EventSocial {
  _RecentRunsFailSocial({super.club});
  int fetchRecentRunsCalls = 0;

  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async {
    fetchRecentRunsCalls++;
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

    testWidgets('a long discipline is bounded + ellipsised (no overflow)',
        (tester) async {
      const longDiscipline =
          'Restorative candlelit Vinyasa flow with breathwork and '
          'progressive myofascial release for deep recovery';
      await pumpLabel(tester, longDiscipline);
      final value = tester.widget<Text>(find.text(longDiscipline));
      expect(value.maxLines, 2);
      expect(value.overflow, TextOverflow.ellipsis);
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

  Future<void> pumpEvent(WidgetTester tester, _EventSocial social) async {
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
    // Two Future.wait batches in _load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('EventDetailScreen — RSVP success', () {
    testWidgets('a successful RSVP calls rsvpEvent once + shows no banner',
        (tester) async {
      final social = _EventSocial(club: _club('member'));
      await pumpEvent(tester, social);

      final going = find.widgetWithText(OutlinedButton, "I'm in");
      expect(going, findsOneWidget);
      await tester.tap(going);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(social.rsvpCalls, 1);
      expect(social.lastRsvpStatus, 'going');
      expect(find.textContaining("Couldn't update your RSVP"), findsNothing);
    });
  });

  group('EventDetailScreen — attendee rendering', () {
    testWidgets('attendee names render in the attendees section',
        (tester) async {
      final social = _EventSocial(
        club: _club('member'),
        attendees: const [
          AttendeeView(userId: 'a', status: 'going', displayName: 'Jamie'),
          AttendeeView(userId: 'b', status: 'maybe', displayName: 'Riley'),
        ],
      );
      await pumpEvent(tester, social);
      expect(find.text('Jamie'), findsOneWidget);
      expect(find.text('Riley'), findsOneWidget);
    });

    testWidgets('an event with no RSVPs shows the no-RSVPs hint',
        (tester) async {
      final social = _EventSocial(club: _club('member'), attendees: const []);
      await pumpEvent(tester, social);
      // eventNoRsvps copy.
      expect(find.textContaining('No RSVPs'), findsOneWidget);
    });
  });

  group('EventDetailScreen — Race control permission gating', () {
    testWidgets('a race director sees the Race control panel on an athletic event',
        (tester) async {
      final social = _EventSocial(club: _club('owner'), category: 'run');
      await pumpEvent(tester, social);
      // The race-control status line shows "Not armed" for a fresh race.
      expect(find.text('Not armed'), findsOneWidget);
    });

    testWidgets('a plain member does NOT see the Race control panel',
        (tester) async {
      final social = _EventSocial(club: _club('member'), category: 'run');
      await pumpEvent(tester, social);
      expect(find.text('Not armed'), findsNothing);
    });

    testWidgets('a class event hides Race control even for an organiser',
        (tester) async {
      // A class is attendance-only — no athletic affordances regardless of role.
      final social = _EventSocial(club: _club('owner'), category: 'class');
      await pumpEvent(tester, social);
      expect(find.text('Not armed'), findsNothing);
    });
  });

  group('logWorkoutSeed — session-derived Log-as-workout prefill', () {
    ExpandedSession sampleSession() => expandSessionSteps(SessionPlanInput(
          blocks: const [],
          items: const [
            SessionPlanItemInput(
              id: 'i1',
              blockId: null,
              position: 0,
              movementName: 'Downward Dog',
              kind: SessionItemKind.hold,
              durationS: 30,
            ),
            SessionPlanItemInput(
              id: 'i2',
              blockId: null,
              position: 1,
              movementName: 'Warrior II',
              kind: SessionItemKind.reps,
              reps: 10,
              perSide: true,
            ),
          ],
        ));

    test('no expansion → title-only from the flat gym_template path', () {
      final seed = logWorkoutSeed(
        gymTemplate: null,
        eventTitle: 'Morning Class',
        discipline: null,
      );
      expect(seed.title, 'Morning Class');
      expect(seed.sets, isNull);
    });

    test('no expansion → title prefers the gym_template discipline', () {
      final seed = logWorkoutSeed(
        gymTemplate: parseGymTemplate(const {'discipline': 'HIIT'}),
        eventTitle: 'Morning Class',
        discipline: 'HIIT',
      );
      expect(seed.title, 'HIIT');
      expect(seed.sets, isNull);
    });

    test('with an attached session plan → one seeded set per expanded step',
        () {
      final seed = logWorkoutSeed(
        gymTemplate: null,
        eventTitle: 'Morning Class',
        discipline: 'Vinyasa Yoga',
        expansion: sampleSession(),
        sessionPlanTitle: 'Flow',
      );
      // Title prefers the class discipline over the flat title.
      expect(seed.title, 'Vinyasa Yoga');
      // Hold + per-side reps (left + right) = 3 seeded sets.
      final sets = seed.sets;
      expect(sets, isNotNull);
      expect(sets!.length, 3);
      expect(sets[0].exerciseName, 'Downward Dog');
      expect(sets[0].durationS, 30); // timed hold carries through
      expect(sets[0].reps, isNull);
      // The per-side reps item expands to two rows carrying the reps target.
      expect(sets[1].exerciseName, 'Warrior II');
      expect(sets[1].reps, 10);
      expect(sets[2].exerciseName, 'Warrior II');
      expect(sets[2].reps, 10);
    });

    test('title falls back to the flat gym_template title when no discipline',
        () {
      final seed = logWorkoutSeed(
        gymTemplate: null,
        eventTitle: 'Morning Class',
        discipline: null,
        expansion: sampleSession(),
        sessionPlanTitle: null,
      );
      expect(seed.title, 'Morning Class');
      expect(seed.sets, isNotNull);
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

  group('Submit-time sheet — recent-runs load failure', () {
    testWidgets(
        'a fetchRecentRuns failure shows the error + retry, not a stuck spinner',
        (tester) async {
      final social = _RecentRunsFailSocial(club: _club('member'));
      await pumpEvent(tester, social);

      final submit = find.widgetWithText(FilledButton, 'Submit my time');
      expect(submit, findsOneWidget);
      await tester.tap(submit);
      await tester.pump(); // start the bottom-sheet route transition
      await tester.pump(const Duration(milliseconds: 300));

      expect(social.fetchRecentRunsCalls, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text("Couldn't load your recent runs."), findsOneWidget);

      final retry = find.widgetWithText(TextButton, 'Retry');
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(social.fetchRecentRunsCalls, 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text("Couldn't load your recent runs."), findsOneWidget);
    });
  });
}
