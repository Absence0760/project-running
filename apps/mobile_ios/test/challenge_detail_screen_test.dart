import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/challenge_detail_screen.dart';
import '../lib/social_service.dart';

class _FakeSocial extends SocialService {
  final ChallengeView? challenge;
  _FakeSocial(this.challenge);

  @override
  String? get currentUserId => 'me';

  @override
  Future<ChallengeView?> fetchChallengeById(String id) async => challenge;

  @override
  Future<List<ChallengeLeaderboardEntry>> fetchChallengeLeaderboard(
    String id, {
    bool byTeam = false,
  }) async =>
      const [];
}

ChallengeView _ch({required num? myValue, num? goalValue = 100000}) {
  final now = DateTime.now();
  return ChallengeView(
    id: 'c1',
    creatorId: 'creator',
    clubId: null,
    title: 'Pace challenge',
    description: null,
    metric: 'distance',
    scope: 'individual',
    goalValue: goalValue,
    activityType: null,
    // 60 % elapsed: 6 days in, 4 to go.
    startsAt: now.subtract(const Duration(days: 6)),
    endsAt: now.add(const Duration(days: 4)),
    isPublic: true,
    joined: true,
    myValue: myValue,
  );
}

Widget _app(SocialService social) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChallengeDetailScreen(social: social, challengeId: 'c1'),
    );

void main() {
  testWidgets('behind-pace joined challenge shows the verdict + required rate',
      (tester) async {
    // 20 km logged against an expected ~60 km at 60 % elapsed → behind.
    await tester.pumpWidget(_app(_FakeSocial(_ch(myValue: 20000))));
    await tester.pump();

    expect(find.text('Behind pace'), findsOneWidget);
    expect(find.textContaining('per day to finish'), findsOneWidget);
  });

  testWidgets('ahead-pace joined challenge shows the ahead verdict only',
      (tester) async {
    // 80 km against ~60 km expected → ahead, no required-rate line.
    await tester.pumpWidget(_app(_FakeSocial(_ch(myValue: 80000))));
    await tester.pump();

    expect(find.text('Ahead of pace'), findsOneWidget);
    expect(find.textContaining('per day to finish'), findsNothing);
  });

  testWidgets('goal-less board renders no pace hint', (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(_ch(myValue: 20000, goalValue: null))));
    await tester.pump();

    expect(find.text('Behind pace'), findsNothing);
    expect(find.text('Ahead of pace'), findsNothing);
    expect(find.text('On pace to finish'), findsNothing);
  });
}
