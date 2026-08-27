// Widget + unit tests for `lib/widgets/challenge_form_sheet.dart` — the
// mobile create-challenge surface, mirror of the create half of web's
// `ChallengeEditor.svelte`.
//
// The load-bearing pins here are the two things a naive port of that editor
// gets wrong: the goal is typed in a unit the reader is shown, not in the raw
// metres / seconds the column stores; and the create throttle's refusal has to
// name its bucket and its wait rather than collapsing into a generic error
// (decisions § 747).

import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/social_service.dart';
import '../lib/widgets/challenge_form_sheet.dart';

class _Created {
  final String title;
  final String? description;
  final String metric;
  final String scope;
  final num? goalValue;
  final String? activityType;
  final String? clubId;
  final DateTime startsAt;
  final DateTime endsAt;
  _Created({
    required this.title,
    required this.description,
    required this.metric,
    required this.scope,
    required this.goalValue,
    required this.activityType,
    required this.clubId,
    required this.startsAt,
    required this.endsAt,
  });
}

class _FakeSocial extends SocialService {
  final List<ClubView> clubs;
  final Object? throwOnCreate;
  final Completer<void>? hold;
  final calls = <_Created>[];
  _FakeSocial({this.clubs = const [], this.throwOnCreate, this.hold});

  @override
  Future<List<ClubView>> fetchMyClubs() async => clubs;

  @override
  Future<String> createChallenge({
    required String title,
    String? description,
    required String metric,
    required String scope,
    num? goalValue,
    String? activityType,
    String? clubId,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isPublic = true,
  }) async {
    calls.add(_Created(
      title: title,
      description: description,
      metric: metric,
      scope: scope,
      goalValue: goalValue,
      activityType: activityType,
      clubId: clubId,
      startsAt: startsAt,
      endsAt: endsAt,
    ));
    if (hold != null) await hold!.future;
    final err = throwOnCreate;
    if (err != null) throw err;
    return 'new-challenge-id';
  }
}

class _ThrowingClubs extends _FakeSocial {
  @override
  Future<List<ClubView>> fetchMyClubs() async => throw Exception('offline');
}

ClubView _club(String id, String name, {String role = 'owner'}) => ClubView(
      row: ClubRow(
        shadowHidden: false,
        id: id,
        ownerId: 'me',
        name: name,
        slug: name.toLowerCase(),
        isPublic: true,
        joinPolicy: 'open',
        memberCount: 2,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 2,
      viewerRole: role,
      viewerStatus: 'active',
      joinPolicy: 'open',
    );

String? resolved;

Widget _host(SocialService social) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                resolved = await showChallengeFormSheet(ctx, social: social);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

/// The form autofocuses its title field, whose caret animates forever, so
/// `pumpAndSettle` never returns here. Pump a bounded run of frames instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(WidgetTester tester, SocialService social) async {
  resolved = null;
  // A tall portrait surface: the form is longer than the default 800x600 test
  // window, and half of it would sit outside the render tree.
  tester.view.physicalSize = const Size(480, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(social));
  await tester.tap(find.text('open'));
  await _settle(tester);
}

/// Scroll the target into the viewport before tapping it — the form scrolls,
/// so a finder can resolve to a widget that is laid out off-screen.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

Finder get _submit => find.widgetWithText(FilledButton, 'Create challenge');
Finder get _title => find.byKey(const Key('challenge-title'));
Finder get _goal => find.byKey(const Key('challenge-goal'));

Future<void> _useUnit({required bool miles}) async {
  SharedPreferences.setMockInitialValues({'use_miles': miles});
  final prefs = Preferences();
  await prefs.init();
  registerActivePreferences(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeDateFormatting();
    await _useUnit(miles: false);
  });
  tearDownAll(resetActivePreferencesForTest);

  group('goal units', () {
    test('a distance goal is typed in the reader unit, stored in metres', () {
      expect(challengeGoalToStored(100, 'distance', DistanceUnit.km), 100000);
      expect(
        challengeGoalToStored(100, 'distance', DistanceUnit.mi),
        closeTo(160934.4, 0.01),
      );
    });

    test('a time goal is typed in hours, stored in seconds', () {
      expect(challengeGoalToStored(20, 'duration', DistanceUnit.km), 72000);
      // The distance pref does not touch a clock.
      expect(challengeGoalToStored(20, 'duration', DistanceUnit.mi), 72000);
    });

    test('an elevation goal round-trips through the factor the display '
        'formatter uses', () {
      final stored =
          challengeGoalToStored(1000, 'vert', DistanceUnit.mi).toDouble();
      final rendered = UnitFormat.elevation(stored, DistanceUnit.mi);
      // A second copy of the feet-per-metre factor would drift here.
      expect(rendered.replaceAll(RegExp(r'[^0-9]'), ''), '1000');
      expect(rendered, endsWith('ft'));
      expect(challengeGoalToStored(1000, 'vert', DistanceUnit.km), 1000);
    });

    test('a count goal is stored verbatim in either unit', () {
      for (final unit in DistanceUnit.values) {
        expect(challengeGoalToStored(12, 'activity_count', unit), 12);
        expect(challengeGoalToStored(12, 'streak_days', unit), 12);
      }
    });

    test('an unknown metric is measured as a distance, matching the fallback '
        'every other challenge surface takes', () {
      expect(challengeGoalToStored(5, 'not_a_metric', DistanceUnit.km), 5000);
    });

    testWidgets('the suffix names the unit the number is read in',
        (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (ctx) {
          l10n = AppLocalizations.of(ctx);
          return const SizedBox.shrink();
        }),
      ));
      expect(challengeGoalSuffix(l10n, 'distance', DistanceUnit.mi), 'mi');
      expect(challengeGoalSuffix(l10n, 'distance', DistanceUnit.km), 'km');
      expect(challengeGoalSuffix(l10n, 'vert', DistanceUnit.mi), 'ft');
      expect(challengeGoalSuffix(l10n, 'vert', DistanceUnit.km), 'm');
      expect(challengeGoalSuffix(l10n, 'duration', DistanceUnit.km), 'h');
      expect(challengeGoalSuffix(l10n, 'activity_count', DistanceUnit.km),
          'activities');
      expect(challengeGoalSuffix(l10n, 'streak_days', DistanceUnit.km), 'days');
    });
  });

  testWidgets('the form renders every field the web editor carries',
      (tester) async {
    await _open(tester, _FakeSocial());

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Metric'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Goal (optional)'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Starts'), findsOneWidget);
    expect(find.text('Ends'), findsOneWidget);
    for (final metric in [
      'Distance',
      'Time',
      'Elevation',
      'Activities',
      'Active days'
    ]) {
      expect(find.widgetWithText(ChoiceChip, metric), findsOneWidget);
    }
    for (final scope in ['Individual', 'Club vs club', 'Group goal']) {
      expect(find.widgetWithText(ChoiceChip, scope), findsOneWidget);
    }
    // km, because the seeded pref is metric.
    expect(find.text('km'), findsOneWidget);
  });

  testWidgets('a 100 km goal is sent as 100000, not as 100', (tester) async {
    final social = _FakeSocial();
    await _open(tester, social);

    await tester.enterText(_title, 'June 100k');
    await tester.enterText(_goal, '100');
    await _tap(tester, _submit);

    expect(social.calls, hasLength(1));
    expect(social.calls.single.goalValue, 100000);
    expect(social.calls.single.title, 'June 100k');
    expect(social.calls.single.metric, 'distance');
    expect(social.calls.single.scope, 'individual');
    expect(social.calls.single.endsAt.isAfter(social.calls.single.startsAt),
        isTrue);
    expect(resolved, 'new-challenge-id');
  });

  testWidgets('a mile-unit reader 100 is sent as 160934.4 m', (tester) async {
    await _useUnit(miles: true);
    final social = _FakeSocial();
    await _open(tester, social);

    expect(find.text('mi'), findsOneWidget);
    await tester.enterText(_title, 'Century');
    await tester.enterText(_goal, '100');
    await _tap(tester, _submit);

    expect(social.calls.single.goalValue, closeTo(160934.4, 0.01));
  });

  testWidgets('switching the metric clears a goal typed in the old unit',
      (tester) async {
    final social = _FakeSocial();
    await _open(tester, social);

    await tester.enterText(_title, 'Mixed');
    await tester.enterText(_goal, '100');
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Time'));

    // A 100 that meant kilometres must not become 100 hours.
    expect(tester.widget<TextField>(_goal).controller!.text, '');
    expect(find.text('h'), findsOneWidget);

    await _tap(tester, _submit);
    expect(social.calls.single.metric, 'duration');
    expect(social.calls.single.goalValue, isNull);
  });

  testWidgets('an empty title flags the field and sends nothing',
      (tester) async {
    final social = _FakeSocial();
    await _open(tester, social);

    await _tap(tester, _submit);

    expect(find.text('Give the challenge a title.'), findsOneWidget);
    expect(social.calls, isEmpty);
    expect(resolved, isNull);
  });

  testWidgets('a non-positive goal flags the field and sends nothing',
      (tester) async {
    final social = _FakeSocial();
    await _open(tester, social);

    await tester.enterText(_title, 'Zero goal');
    await tester.enterText(_goal, '0');
    await _tap(tester, _submit);

    expect(find.text('Goal: enter a positive number'), findsOneWidget);
    expect(social.calls, isEmpty);
  });

  testWidgets('a start pushed past the end is refused inline, not by a 23514',
      (tester) async {
    // `challenges_window_ck` raises a check_violation naming neither bound, so
    // the author would be told only that something went wrong. Push the start
    // a year out — past the default 30-day end — through the real picker.
    final social = _FakeSocial();
    await _open(tester, social);
    await tester.enterText(_title, 'Backwards');

    await _tap(
        tester,
        find.ancestor(
            of: find.text('Starts'), matching: find.byType(InkWell)));
    // Calendar header toggle -> year grid -> next year -> the 15th -> OK.
    await tester.tap(find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byIcon(Icons.arrow_drop_down),
    ));
    await _settle(tester);
    await tester.tap(find.text('${DateTime.now().year + 1}'));
    await _settle(tester);
    await tester.tap(find.text('15').first);
    await _settle(tester);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    // Accept the time the picker opened on.
    await tester.tap(find.text('OK'));
    await _settle(tester);

    await _tap(tester, _submit);

    expect(find.text('The end must be after the start.'), findsOneWidget);
    expect(social.calls, isEmpty);
  });

  testWidgets('a throttled create names the bucket and the wait',
      (tester) async {
    // decisions § 747: the generic branch would collapse this into "something
    // went wrong", which is the swallow that ADR fixed on web — on the one
    // class of failure whose whole remedy is knowing how long to wait.
    final social = _FakeSocial(
      throwOnCreate: const PostgrestException(
        message: 'rate limit exceeded for create_challenge, retry in 900s',
        code: 'P0001',
      ),
    );
    await _open(tester, social);

    await tester.enterText(_title, 'Too many');
    await _tap(tester, _submit);

    expect(
      find.text("You're creating challenges too quickly — please wait "
          "15 minutes and try again."),
      findsOneWidget,
    );
    expect(find.text('Something went wrong. Please try again.'), findsNothing);
    expect(resolved, isNull);
  });

  testWidgets('an unrelated failure gets the friendly generic message',
      (tester) async {
    final social = _FakeSocial(throwOnCreate: Exception('boom'));
    await _open(tester, social);

    await tester.enterText(_title, 'Broken');
    await _tap(tester, _submit);

    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('a second tap while the first create is in flight sends nothing',
      (tester) async {
    final hold = Completer<void>();
    final social = _FakeSocial(hold: hold);
    await _open(tester, social);

    await tester.enterText(_title, 'Once');
    await _tap(tester, _submit);

    // While the create is in flight the label is replaced by a spinner and
    // the button reports no callback at all, so a second tap cannot land.
    final busy = find.byType(FilledButton);
    expect(
      find.descendant(of: busy, matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(busy).onPressed, isNull);
    await tester.tap(busy, warnIfMissed: false);
    await _settle(tester);
    expect(social.calls, hasLength(1));

    hold.complete();
    await _settle(tester);
    expect(resolved, 'new-challenge-id');
  });

  group('club anchor', () {
    testWidgets('only clubs the author administers are offered',
        (tester) async {
      final social = _FakeSocial(clubs: [
        _club('c1', 'Owned'),
        _club('c2', 'Joined', role: 'member'),
      ]);
      await _open(tester, social);

      expect(find.text('Club'), findsOneWidget);
      await _tap(tester, find.text('Open (anyone)'));
      expect(find.text('Owned'), findsWidgets);
      expect(find.text('Joined'), findsNothing);
    });

    testWidgets('the picker is absent when the author administers none',
        (tester) async {
      await _open(tester,
          _FakeSocial(clubs: [_club('c2', 'Joined', role: 'member')]));
      expect(find.text('Club'), findsNothing);
    });

    testWidgets('a failed club read leaves the form usable', (tester) async {
      final social = _ThrowingClubs();
      await _open(tester, social);

      expect(find.text('Club'), findsNothing);
      await tester.enterText(_title, 'Still works');
      await tester.tap(_submit);
      await _settle(tester);
      expect(social.calls, hasLength(1));
    });

    testWidgets('club_vs_club drops the anchor, matching the scope CHECK',
        (tester) async {
      final social = _FakeSocial(clubs: [_club('c1', 'Owned')]);
      await _open(tester, social);

      await _tap(tester, find.text('Open (anyone)'));
      await _tap(tester, find.text('Owned').last);

      await _tap(tester, find.widgetWithText(ChoiceChip, 'Club vs club'));
      expect(find.text('Club'), findsNothing);

      await tester.enterText(_title, 'Derby');
      await tester.tap(_submit);
      await _settle(tester);

      expect(social.calls.single.scope, 'club_vs_club');
      expect(social.calls.single.clubId, isNull);
    });
  });
}
