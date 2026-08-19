import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui_kit/ui_kit.dart' show ProgressBar;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/challenges_screen.dart';
import '../lib/social_service.dart';
import '../lib/widgets/error_state.dart';

class _FakeSocial extends SocialService {
  final List<ChallengeView> _challenges;
  _FakeSocial(this._challenges);

  @override
  Future<List<ChallengeView>> fetchChallenges() async => _challenges;
}

class _ThrowingSocial extends SocialService {
  @override
  Future<List<ChallengeView>> fetchChallenges() async =>
      throw Exception('backend down');
}

ChallengeView _ch({
  required String id,
  required String title,
  bool joined = false,
  bool isPublic = true,
  int participantCount = 0,
  num? myValue,
  int? myRank,
  DateTime? completedAt,
  bool future = false,
}) {
  final now = DateTime.now();
  return ChallengeView(
    id: id,
    creatorId: 'creator',
    clubId: null,
    title: title,
    description: null,
    metric: 'distance',
    scope: 'individual',
    goalValue: 100000,
    activityType: null,
    startsAt: future
        ? now.add(const Duration(days: 7))
        : now.subtract(const Duration(days: 1)),
    endsAt: now.add(const Duration(days: 30)),
    isPublic: isPublic,
    joined: joined,
    myValue: myValue,
    myRank: myRank,
    participantCount: participantCount,
    completedAt: completedAt,
  );
}

Widget _app(SocialService social) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ChallengesScreen(social: social, embedded: true)),
    );

void main() {
  testWidgets('renders my-challenges + browse sections with rows', (tester) async {
    final social = _FakeSocial([
      _ch(id: 'a', title: 'June 100k', joined: true, participantCount: 3),
      _ch(id: 'b', title: 'Public 50k', joined: false, participantCount: 8),
    ]);
    await tester.pumpWidget(_app(social));
    await tester.pump();

    expect(find.text('My challenges'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('June 100k'), findsOneWidget);
    expect(find.text('Public 50k'), findsOneWidget);
  });

  testWidgets('self-hides into empty copy when the user is in none', (tester) async {
    final social = _FakeSocial([
      _ch(id: 'b', title: 'Public 50k', joined: false, participantCount: 8),
    ]);
    await tester.pumpWidget(_app(social));
    await tester.pump();

    // My challenges section shows its empty copy; the public one still lists.
    expect(find.text('No challenges yet.'), findsOneWidget);
    expect(find.text('Public 50k'), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
  });

  testWidgets('renders ErrorState with Retry when the fetch throws', (tester) async {
    await tester.pumpWidget(_app(_ThrowingSocial()));
    await tester.pump();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text("Couldn't load challenges."), findsOneWidget);
    // The friendly no-data sections are NOT shown on failure.
    expect(find.text('My challenges'), findsNothing);
    expect(find.text('Browse'), findsNothing);
    // The shared retry affordance is present.
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('renders the friendly empty state (not ErrorState) when the fetch returns no rows',
      (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(const [])));
    await tester.pump();

    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('My challenges'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('No challenges yet.'), findsOneWidget);
  });

  group('joined-row progress signal', () {
    testWidgets('a value from the aggregate renders against the goal', (tester) async {
      await tester.pumpWidget(_app(_FakeSocial([
        _ch(id: 'a', title: 'June 100k', joined: true, myValue: 42000, myRank: 3),
      ])));
      await tester.pump();

      expect(find.textContaining('42.00 km'), findsOneWidget);
      expect(find.byType(ProgressBar), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
      expect(find.text('Progress unavailable — open for your result'), findsNothing);
    });

    testWidgets('an open challenge the aggregate did not cover says so instead of drawing a zero',
        (tester) async {
      // Live window, no value: outside the my_active_challenges page (or its
      // read failed), so the number is unknown — not zero.
      await tester.pumpWidget(_app(_FakeSocial([
        _ch(id: 'a', title: 'June 100k', joined: true),
      ])));
      await tester.pump();

      expect(find.text('Progress unavailable — open for your result'), findsOneWidget);
      expect(find.byType(ProgressBar), findsNothing);
      expect(find.textContaining('0.00 km'), findsNothing);
    });

    testWidgets('a challenge whose window has not opened shows a true zero', (tester) async {
      await tester.pumpWidget(_app(_FakeSocial([
        _ch(id: 'a', title: 'July 100k', joined: true, future: true),
      ])));
      await tester.pump();

      expect(find.byType(ProgressBar), findsOneWidget);
      expect(find.textContaining('0.00 km'), findsOneWidget);
      expect(find.text('Progress unavailable — open for your result'), findsNothing);
    });

    testWidgets('the earned badge shows beside the rank', (tester) async {
      await tester.pumpWidget(_app(_FakeSocial([
        _ch(
          id: 'a',
          title: 'June 100k',
          joined: true,
          myValue: 120000,
          myRank: 1,
          completedAt: DateTime.now(),
        ),
      ])));
      await tester.pump();

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Badge earned'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
    });

    testWidgets('a browse row carries no progress signal at all', (tester) async {
      await tester.pumpWidget(_app(_FakeSocial([
        _ch(id: 'b', title: 'Public 50k', participantCount: 8),
      ])));
      await tester.pump();

      expect(find.text('Public 50k'), findsOneWidget);
      expect(find.byType(ProgressBar), findsNothing);
      expect(find.text('Progress unavailable — open for your result'), findsNothing);
    });
  });
}
