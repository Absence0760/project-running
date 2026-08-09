import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show TextLane;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';
import '../lib/event_category.dart';
import '../lib/event_gym_template.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/session_steps.dart';
import '../lib/social_service.dart';
import 'realtime_drain.dart';

ClubView _club(String? viewerRole) => ClubView(
  row: ClubRow(
    shadowHidden: false,
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

  /// The screen gates on the viewer id, so a fake must declare who is
  /// looking rather than falling through to a real Supabase read.
  @override
  String? get currentUserId => 'u-viewer';
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
  Future<List<AttendeeView>> fetchAttendees(
    String eventId,
    DateTime instance,
  ) async => const [];
  @override
  Future<List<EventResultView>> fetchEventResults(
    String eventId,
    DateTime instance,
  ) async => const [];
  @override
  Future<RaceSessionRow?> fetchRaceSession(
    String eventId,
    DateTime instance,
  ) async => null;
  @override
  Future<({double lat, double lng})?> fetchEventMeetPoint(
    String eventId,
  ) async => null;
  @override
  Future<void> rsvpEvent(
    String eventId,
    String status,
    DateTime instance,
  ) async {
    rsvpCalls++;
    throw Exception('network down');
  }
}

/// Configurable fake that drives the happy paths: a club (role configurable),
/// an athletic event, a canned attendee list, and a recording RSVP write.
class _EventSocial extends SocialService {
  /// The screen gates on the viewer id, so a fake must declare who is
  /// looking rather than falling through to a real Supabase read.
  @override
  String? get currentUserId => 'u-viewer';

  _EventSocial({
    this.club,
    this.category = 'run',
    this.attendees = const [],
    this.viewerRsvp,
    this.cancelled = const {},
    this.paceTargetSec,
  });
  ClubView? club;
  String category;
  List<AttendeeView> attendees;
  String? viewerRsvp;
  Set<DateTime> cancelled;
  int? paceTargetSec;
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
      paceTargetSec: paceTargetSec,
      isPublic: true,
    ),
    byday: null,
    attendeeCount: attendees.length,
    viewerRsvp: viewerRsvp,
    nextInstanceStart: DateTime.utc(2026, 6, 20, 8),
  );
  @override
  Future<Set<DateTime>> fetchCancelledInstances(String eventId) async =>
      cancelled;

  @override
  Future<List<AttendeeView>> fetchAttendees(
    String eventId,
    DateTime instance,
  ) async => attendees;
  @override
  Future<List<EventResultView>> fetchEventResults(
    String eventId,
    DateTime instance,
  ) async => const [];
  @override
  Future<RaceSessionRow?> fetchRaceSession(
    String eventId,
    DateTime instance,
  ) async => null;
  @override
  Future<({double lat, double lng})?> fetchEventMeetPoint(
    String eventId,
  ) async => null;
  @override
  Future<void> rsvpEvent(
    String eventId,
    String status,
    DateTime instance,
  ) async {
    rsvpCalls++;
    lastRsvpStatus = status;
  }

  @override
  Future<void> clearRsvp(String eventId, DateTime instance) async {
    clearCalls++;
  }

  @override
  RealtimeChannel subscribeToEvent(
    String eventId,
    String clubId,
    void Function() onChange,
  ) => Supabase.instance.client.channel('test-$eventId');
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

/// The result WRITE always fails — drives the submit-failure banner and
/// its Retry action (which must re-send the picked result, not re-open
/// the sheet).
class _SubmitFailSocial extends _EventSocial {
  _SubmitFailSocial({super.club});
  int submitCalls = 0;

  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];

  @override
  Future<void> submitEventResult({
    required String eventId,
    required DateTime instance,
    required int durationS,
    required double distanceM,
    String? runId,
    String finisherStatus = 'finished',
    double? ageGradePct,
    String? note,
  }) async {
    submitCalls++;
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
    realtimeWidgetTest('first frame shows the full-body loader', (
      tester,
    ) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold carrying nothing but the loader.
      await _pump(tester);
      expect(find.byType(FullBodyLoader), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    realtimeWidgetTest('initial Scaffold has no AppBar yet', (tester) async {
      await _pump(tester);
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('EventDetailScreen — cancelled occurrence', () {
    Future<_EventSocial> pumpWith(
      WidgetTester tester,
      Set<DateTime> cancelled,
    ) async {
      final social = _EventSocial(club: _club('member'), cancelled: cancelled);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: social,
            clubSlug: 'fake-slug',
            eventId: 'fake-event-id',
          ),
        ),
      );
      await tester.pumpAndSettle();
      return social;
    }

    realtimeWidgetTest(
      'a cancelled occurrence says so and withholds the RSVP row',
      (tester) async {
        // event_exceptions was never read on mobile, so a cancelled occurrence
        // stayed selectable and RSVP-able with nothing saying it was called off.
        await pumpWith(tester, {DateTime.utc(2026, 6, 20, 8)});
        expect(find.text('This occurrence was cancelled.'), findsOneWidget);
        expect(find.text("I'm in"), findsNothing);
      },
    );

    realtimeWidgetTest('a live occurrence keeps the RSVP row', (tester) async {
      await pumpWith(tester, const {});
      expect(find.text('This occurrence was cancelled.'), findsNothing);
      expect(find.text("I'm in"), findsOneWidget);
    });
  });

  group('EventDetailScreen — waitlisted RSVP', () {
    Future<void> pumpWith(WidgetTester tester, String? rsvp) async {
      final social = _EventSocial(club: _club('member'), viewerRsvp: rsvp);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: social,
            clubSlug: 'fake-slug',
            eventId: 'fake-event-id',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    realtimeWidgetTest('a demoted RSVP reads as waitlisted, not as no answer', (
      tester,
    ) async {
      // enforce_event_capacity silently rewrites a full event's `going` to
      // `waitlisted`. That matches none of the three chips, so the row looked
      // exactly like it does for someone who never responded.
      await pumpWith(tester, 'waitlisted');
      expect(find.text('Waitlisted'), findsOneWidget);
    });

    realtimeWidgetTest('an ordinary RSVP shows no waitlist line', (
      tester,
    ) async {
      await pumpWith(tester, 'going');
      expect(find.text('Waitlisted'), findsNothing);
    });

    realtimeWidgetTest('no RSVP shows no waitlist line', (tester) async {
      await pumpWith(tester, null);
      expect(find.text('Waitlisted'), findsNothing);
    });
  });

  group('EventDetailScreen — RSVP failure', () {
    realtimeWidgetTest(
      'a failed RSVP surfaces a banner instead of silently reverting',
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
        expect(
          find.textContaining("Couldn't update your RSVP"),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 4)); // drain banner timer
      },
    );
  });

  group('EventDisciplineLabel — slice E class display', () {
    Future<void> pumpLabel(WidgetTester tester, String discipline) {
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: EventDisciplineLabel(discipline: discipline)),
        ),
      );
    }

    realtimeWidgetTest('shows the CLASS eyebrow and the free-text discipline', (
      tester,
    ) async {
      await pumpLabel(tester, 'Vinyasa Yoga');
      expect(find.text('CLASS'), findsOneWidget);
      expect(find.text('Vinyasa Yoga'), findsOneWidget);
    });

    realtimeWidgetTest('renders no athletic affordances', (tester) async {
      await pumpLabel(tester, 'Pilates');
      // A class label is attendance-only: no distance / target-pace metric,
      // no results leaderboard, no Submit-my-time button.
      expect(find.text('Target pace'), findsNothing);
      expect(find.text('Submit my time'), findsNothing);
      expect(find.byType(EventResultsSection), findsNothing);
    });

    realtimeWidgetTest(
      'a long discipline is bounded + ellipsised (no overflow)',
      (tester) async {
        const longDiscipline =
            'Restorative candlelit Vinyasa flow with breathwork and '
            'progressive myofascial release for deep recovery';
        await pumpLabel(tester, longDiscipline);
        final value = tester.widget<Text>(find.text(longDiscipline));
        expect(value.maxLines, 2);
        expect(value.overflow, TextOverflow.ellipsis);
      },
    );
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
    realtimeWidgetTest(
      'a successful RSVP calls rsvpEvent once + shows no banner',
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
      },
    );
  });

  group('EventDetailScreen — attendee rendering', () {
    realtimeWidgetTest('attendee names render in the attendees section', (
      tester,
    ) async {
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
      expect(find.byType(IdentityAvatar), findsNWidgets(2));
    });

    realtimeWidgetTest('an event with no RSVPs shows the no-RSVPs hint', (
      tester,
    ) async {
      final social = _EventSocial(club: _club('member'), attendees: const []);
      await pumpEvent(tester, social);
      // eventNoRsvps copy.
      expect(find.textContaining('No RSVPs'), findsOneWidget);
    });
  });

  group('EventDetailScreen — Race control permission gating', () {
    realtimeWidgetTest(
      'a race director sees the Race control panel on an athletic event',
      (tester) async {
        final social = _EventSocial(club: _club('owner'), category: 'run');
        await pumpEvent(tester, social);
        // The race-control status line shows "Not armed" for a fresh race.
        expect(find.text('Not armed'), findsOneWidget);
      },
    );

    realtimeWidgetTest('a plain member does NOT see the Race control panel', (
      tester,
    ) async {
      final social = _EventSocial(club: _club('member'), category: 'run');
      await pumpEvent(tester, social);
      expect(find.text('Not armed'), findsNothing);
    });

    realtimeWidgetTest('a class event hides Race control even for an organiser', (
      tester,
    ) async {
      // A class is attendance-only — no athletic affordances regardless of role.
      final social = _EventSocial(club: _club('owner'), category: 'class');
      await pumpEvent(tester, social);
      expect(find.text('Not armed'), findsNothing);
    });
  });

  group('logWorkoutSeed — session-derived Log-as-workout prefill', () {
    ExpandedSession sampleSession() => expandSessionSteps(
      SessionPlanInput(
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
      ),
    );

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

    test(
      'with an attached session plan → one seeded set per expanded step',
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
      },
    );

    test(
      'title falls back to the flat gym_template title when no discipline',
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
      },
    );
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
    realtimeWidgetTest(
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
      },
    );
  });

  group('EventDetailScreen — result submit failure retry (issue #666 U8)', () {
    realtimeWidgetTest(
      'a failed submit shows a Retry banner that re-sends the picked '
      'result without re-opening the sheet',
      (tester) async {
        final social = _SubmitFailSocial(club: _club('member'));
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
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final submit = find.widgetWithText(FilledButton, 'Submit my time');
        expect(submit, findsOneWidget);
        await tester.tap(submit);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Pick the DNF shortcut so the sheet pops with a concrete choice.
        await tester.tap(find.widgetWithText(TextButton, 'Record DNF'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(social.submitCalls, 1);
        expect(find.textContaining('Submit failed'), findsOneWidget);
        final retry = find.widgetWithText(TextButton, 'Retry');
        expect(retry, findsOneWidget);
        // The sheet must not have re-opened.
        expect(find.text('Submit your time'), findsNothing);

        await tester.tap(retry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(social.submitCalls, 2);
        expect(find.text('Submit your time'), findsNothing);
        // Drain the replacement banner's auto-dismiss timer.
        await tester.pump(const Duration(seconds: 6));
      },
    );
  });

  group('EventDetailScreen — narrow-width overflow (issue #666 V7)', () {
    realtimeWidgetTest(
      'renders at a narrow width with the RSVP buttons in a Wrap so '
      'long localized labels flow to a second line instead of striping',
      (tester) async {
        // 400, not 320: below ~400 the EventPhotos add-photo row (a separate
        // widget file outside this fix's scope) still overflows under the
        // test Ahem font and would fail this test for an unrelated reason.
        tester.view.physicalSize = const Size(400, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final social = _EventSocial(club: _club('member'));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EventDetailScreen(
              social: social,
              clubSlug: 'fake-slug',
              eventId: 'fake-event-id',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.ancestor(
            of: find.widgetWithText(OutlinedButton, "I'm in"),
            matching: find.byType(Wrap),
          ),
          findsWidgets,
        );
      },
    );
  });

  group('EventDetailScreen — the results rank lane', () {
    // The finishing position sat in a 28px box. "999" needs 36.1px in real
    // Roboto at titleMedium w700 once the OS text scale reaches 1.5x and 48.2
    // at 2x, and a rank has no break opportunity, so it painted over the
    // finisher's name beside it. A four-digit field clears the box at 1.0x.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so a lane whose floor tracks
    // the scale here tracks it on a device too.
    Future<void> pumpResults(WidgetTester tester, {double scale = 1.0}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(children: [
              EventResultsSection(
                results: [
                  EventResultView(
                    userId: 'u-1',
                    displayName: 'Backmarker',
                    runId: null,
                    durationS: 18000,
                    distanceM: 42195,
                    rank: 999,
                    finisherStatus: 'finished',
                    organiserApproved: true,
                    ageGradePct: null,
                    note: null,
                    createdAt: DateTime.utc(2026, 3, 28),
                  ),
                ],
                myUserId: null,
                submitting: false,
                onSubmit: () {},
                onRemove: () {},
                eventTitle: 'Spring Marathon',
                clubName: null,
                certificateDate: DateTime.utc(2026, 3, 28),
              ),
            ]),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the lane widens to the rank instead of overpainting',
        (tester) async {
      await pumpResults(tester);
      final lane = find.ancestor(
        of: find.text('999'),
        matching: find.byType(TextLane),
      );
      expect(lane, findsOneWidget);
      final rank = tester.renderObject<RenderParagraph>(find.text('999'));
      expect(
        tester.getSize(lane).width,
        greaterThanOrEqualTo(rank.getMaxIntrinsicWidth(double.infinity)),
      );
    });

    testWidgets('the lane floor grows with the OS text scale', (tester) async {
      await pumpResults(tester, scale: 2.0);
      final lane = find.byType(TextLane).first;
      expect(tester.getSize(lane).width,
          greaterThanOrEqualTo(tester.widget<TextLane>(lane).width * 2));
    });

    testWidgets('a finisher row states the distance in the runner\'s unit',
        (tester) async {
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      addTearDown(resetActivePreferencesForTest);

      await pumpResults(tester);
      expect(find.text('26.22 mi'), findsOneWidget);
      expect(find.text('42.20 km'), findsNothing);
    });
  });

  group('EventDetailScreen — the event metrics row', () {
    realtimeWidgetTest('distance and target pace follow the unit pref', (
      tester,
    ) async {
      // The target-pace metric read through a second, km-hardcoded fmtPace
      // that lived in social_service.dart, so a mile-unit runner saw the
      // event's target as a per-kilometre pace beside a distance in miles.
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      addTearDown(resetActivePreferencesForTest);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: _EventSocial(club: _club('member'), paceTargetSec: 300),
            clubSlug: 'fake-slug',
            eventId: 'fake-event-id',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('13.11 mi'), findsOneWidget);
      // 300 s/km -> 300 * 1.609344 = 482.8 s/mi -> rounds to 483 -> 8:03.
      expect(find.text('8:03 /mi'), findsOneWidget);
      expect(find.text('5:00 /km'), findsNothing);
    });
  });
}
