import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/challenges_screen.dart';
import '../lib/social_service.dart';

class _FakeSocial extends SocialService {
  final List<ChallengeView> _challenges;
  _FakeSocial(this._challenges);

  @override
  Future<List<ChallengeView>> fetchChallenges() async => _challenges;
}

ChallengeView _ch({
  required String id,
  required String title,
  bool joined = false,
  bool isPublic = true,
  int participantCount = 0,
}) {
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
    startsAt: DateTime.now().subtract(const Duration(days: 1)),
    endsAt: DateTime.now().add(const Duration(days: 30)),
    isPublic: isPublic,
    joined: joined,
    participantCount: participantCount,
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
  });
}
