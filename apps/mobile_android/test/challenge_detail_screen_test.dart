import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/challenge_detail_screen.dart';
import '../lib/social_service.dart';

class _FakeSocial extends SocialService {
  final ChallengeView? challenge;
  final bool throwOnFetch;
  final bool throwOnDelete;
  final List<ChallengeLeaderboardEntry> board;
  final List<ClubView> clubs;
  _FakeSocial(
    this.challenge, {
    this.throwOnFetch = false,
    this.throwOnDelete = false,
    this.board = const [],
    this.clubs = const [],
  });

  @override
  String? get currentUserId => 'me';

  @override
  Future<ChallengeView?> fetchChallengeById(String id) async {
    if (throwOnFetch) throw Exception('network down');
    return challenge;
  }

  @override
  Future<List<ChallengeLeaderboardEntry>> fetchChallengeLeaderboard(
    String id, {
    bool byTeam = false,
  }) async =>
      board;

  @override
  Future<List<ClubView>> fetchMyClubs() async => clubs;

  @override
  Future<void> deleteChallenge(String id) async {
    if (throwOnDelete) throw Exception('delete failed');
  }
}

ChallengeView _ch({
  required num? myValue,
  num? goalValue = 100000,
  String creatorId = 'creator',
  String scope = 'individual',
}) {
  final now = DateTime.now();
  return ChallengeView(
    id: 'c1',
    creatorId: creatorId,
    clubId: null,
    title: 'Pace challenge',
    description: null,
    metric: 'distance',
    scope: scope,
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

ClubView _club(String id, String name) => ClubView(
      row: ClubRow(
        shadowHidden: false,
        id: id,
        ownerId: 'owner',
        name: name,
        slug: name.toLowerCase(),
        isPublic: true,
        joinPolicy: 'open',
        memberCount: 3,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 3,
      viewerRole: 'member',
      viewerStatus: 'active',
      joinPolicy: 'open',
    );

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

  testWidgets('a fetch failure shows the ErrorState + retry, not "not found"',
      (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(null, throwOnFetch: true)));
    await tester.pump(); // resolve the throwing fetch

    // Distinct from the genuine missing-row path.
    expect(find.text("This challenge isn't available."), findsNothing);
    expect(find.text("Couldn't load challenges."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a genuinely missing challenge shows the not-found copy',
      (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(null)));
    await tester.pump();

    expect(find.text("This challenge isn't available."), findsOneWidget);
    expect(find.text("Couldn't load challenges."), findsNothing);
  });

  testWidgets('club-vs-club leaderboard shows club names, not raw UUIDs',
      (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(
      _ch(myValue: null, scope: 'club_vs_club'),
      board: const [
        ChallengeLeaderboardEntry(
          userId: null,
          displayName: null,
          teamClubId: 'club-42',
          value: 5000,
          rank: 1,
        ),
      ],
      clubs: [_club('club-42', 'Track Club')],
    )));
    await tester.pump(); // fetch challenge + board + clubs

    expect(find.text('Track Club'), findsOneWidget);
    expect(find.text('club-42'), findsNothing);
  });

  testWidgets('a failed delete shows the delete-specific message', (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(
      _ch(myValue: 20000, creatorId: 'me'),
      throwOnDelete: true,
    )));
    await tester.pump(); // load

    // Owner sees the delete action.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle(); // open the confirm dialog

    // Confirm the deletion.
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Delete'),
    );
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await tester.pump(); // dialog pop + throwing delete

    expect(find.text("Couldn't delete the challenge."), findsOneWidget);
    // NOT the misleading load-failure copy.
    expect(find.text("Couldn't load challenges."), findsNothing);

    // Drain the showTopBanner auto-dismiss timer.
    await tester.pump(const Duration(seconds: 4));
  });
}
