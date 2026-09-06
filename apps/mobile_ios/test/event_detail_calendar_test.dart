import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/calendar_intent.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/social_service.dart';
import 'realtime_drain.dart';

ClubView _club() => ClubView(
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
  viewerRole: 'member',
  viewerStatus: 'active',
  joinPolicy: 'open',
);

/// One club event whose start is expressed relative to the real clock, so the
/// screen's "is this occurrence still ahead" gate and the one-year expansion
/// horizon both behave the way they will in the field however long this suite
/// lives.
class _CalendarSocial extends SocialService {
  _CalendarSocial({
    required this.startsAt,
    this.freq,
    this.durationMin,
    this.cancelled = const {},
  });

  final DateTime startsAt;
  final String? freq;
  final int? durationMin;
  final Set<DateTime> cancelled;

  @override
  String? get currentUserId => 'u-viewer';
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _club();
  @override
  Future<EventView?> fetchEventById(String eventId) async => EventView(
    row: EventRow(
      id: 'e1',
      clubId: 'club-1',
      title: 'Saturday Long Run',
      description: 'Meet by the bridge',
      meetLabel: 'Riverside Park',
      startsAt: startsAt,
      durationMin: durationMin,
      authorId: 'host',
      category: 'run',
      recurrenceFreq: freq,
      timezone: 'UTC',
      isPublic: true,
    ),
    byday: null,
    attendeeCount: 0,
    viewerRsvp: null,
    nextInstanceStart: startsAt,
  );
  @override
  Future<Set<DateTime>> fetchCancelledInstances(String eventId) async =>
      cancelled;
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
  RealtimeChannel subscribeToEvent(
    String eventId,
    String clubId,
    void Function() onChange,
  ) => Supabase.instance.client.channel('test-$eventId');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_ensureSupabase);

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late bool nativeAccepts;

  setUp(() {
    calls = [];
    nativeAccepts = true;
    messenger.setMockMethodCallHandler(calendarChannel, (call) async {
      calls.add(call);
      return nativeAccepts;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(calendarChannel, null);
  });

  Future<void> pump(WidgetTester tester, _CalendarSocial social) async {
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
    await tester.pumpAndSettle();
  }

  // Whole seconds: the expansion stamps occurrences at that resolution and a
  // cancelled instant is one of them, so a sub-second fixture would compare
  // unequal to its own occurrence. (The sub-second start itself is pinned in
  // calendar_intent_test.dart.)
  DateTime aheadBy(int days) {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day + days, now.hour,
        now.minute, now.second);
  }

  // The body is a lazy ListView and a year of occurrence chips sits above the
  // calendar row, so a recurring event's actions are not built until scrolled to.
  Future<void> reveal(WidgetTester tester, Finder target) => tester
      .scrollUntilVisible(target, 300, scrollable: find.byType(Scrollable).first);

  group('EventDetailScreen — add to calendar', () {
    realtimeWidgetTest('a one-off event offers only the single-date hand-off', (
      tester,
    ) async {
      await pump(tester, _CalendarSocial(startsAt: aheadBy(7)));

      expect(find.byKey(const Key('add-to-calendar')), findsOneWidget);
      expect(find.byKey(const Key('add-series-to-calendar')), findsNothing);
    });

    realtimeWidgetTest('the hand-off carries the occurrence, not a rule', (
      tester,
    ) async {
      final start = aheadBy(7);
      await pump(
        tester,
        _CalendarSocial(startsAt: start, durationMin: 90),
      );
      await tester.tap(find.byKey(const Key('add-to-calendar')));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      final args = calls.single.arguments as Map;
      expect(args['title'], 'Saturday Long Run');
      expect(args['startMs'], start.millisecondsSinceEpoch);
      expect(
        args['endMs'],
        start.add(const Duration(minutes: 90)).millisecondsSinceEpoch,
      );
      expect(args['location'], 'Riverside Park');
      expect(args['description'], 'Meet by the bridge');
      expect(args['url'], endsWith('/share/event/e1'));
      expect(args['rrule'], isNull);
    });

    realtimeWidgetTest('a recurring event also offers the whole series', (
      tester,
    ) async {
      final start = aheadBy(7);
      await pump(tester, _CalendarSocial(startsAt: start, freq: 'weekly'));
      await reveal(tester, find.byKey(const Key('add-series-to-calendar')));

      expect(find.byKey(const Key('add-series-to-calendar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-series-to-calendar')));
      await tester.pumpAndSettle();

      final args = calls.single.arguments as Map;
      expect(args['startMs'], start.millisecondsSinceEpoch);
      expect(args['rrule'], startsWith('FREQ=WEEKLY;BYDAY='));
    });

    realtimeWidgetTest(
      'called-off occurrences the rule cannot subtract are disclosed',
      (tester) async {
        final start = aheadBy(7);
        await pump(
          tester,
          _CalendarSocial(
            startsAt: start,
            freq: 'weekly',
            cancelled: {start.add(const Duration(days: 14))},
          ),
        );
        await reveal(tester, find.byKey(const Key('add-series-to-calendar')));

        expect(
          find.textContaining("Your calendar can't skip called-off dates"),
          findsOneWidget,
        );
      },
    );

    realtimeWidgetTest('nothing called off says nothing about cancellations', (
      tester,
    ) async {
      await pump(
        tester,
        _CalendarSocial(startsAt: aheadBy(7), freq: 'weekly'),
      );

      expect(
        find.textContaining("Your calendar can't skip called-off dates"),
        findsNothing,
      );
    });

    realtimeWidgetTest('a past occurrence offers no calendar hand-off', (
      tester,
    ) async {
      await pump(tester, _CalendarSocial(startsAt: aheadBy(-7)));

      expect(find.byKey(const Key('add-to-calendar')), findsNothing);
    });

    realtimeWidgetTest('a called-off occurrence offers no calendar hand-off', (
      tester,
    ) async {
      final start = aheadBy(7);
      await pump(
        tester,
        _CalendarSocial(startsAt: start, cancelled: {start}),
      );

      expect(find.byKey(const Key('add-to-calendar')), findsNothing);
    });

    realtimeWidgetTest('a refused hand-off is surfaced, not swallowed', (
      tester,
    ) async {
      nativeAccepts = false;
      await pump(tester, _CalendarSocial(startsAt: aheadBy(7)));
      await tester.tap(find.byKey(const Key('add-to-calendar')));
      await tester.pump();

      expect(find.text("Couldn't open your calendar app."), findsOneWidget);
    });
  });
}
