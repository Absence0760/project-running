import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/social_service.dart';
import '../lib/widgets/fundraiser_section.dart';

class _FakeSocial extends SocialService {
  final FundraiserView fundraiser;
  final FundraiserTotalsView totals;
  final List<DonationFeedEntry> feed;

  _FakeSocial({
    required this.fundraiser,
    required this.totals,
    required this.feed,
  });

  @override
  bool get isReady => true;

  @override
  Future<FundraiserView?> fetchFundraiserForRun(String runId) async =>
      fundraiser;

  @override
  Future<FundraiserTotalsView?> fetchFundraiserTotals(String id) async =>
      totals;

  @override
  Future<List<DonationFeedEntry>> fetchFundraiserFeed(
    String id, {
    int limit = 50,
  }) async =>
      feed;
}

FundraiserView _fundraiser({String title = 'Charity run'}) => FundraiserView(
      id: 'f1',
      title: title,
      charityName: 'Charity',
      charityUrl: null,
      story: null,
      goalCents: 100000,
      currency: 'usd',
      status: 'active',
    );

DonationFeedEntry _entry({String? displayName, String? message}) =>
    DonationFeedEntry(
      displayName: displayName,
      message: message,
      amountCents: 2500,
      currency: 'usd',
      isAnonymous: false,
      paidAt: DateTime(2026, 6, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required _FakeSocial social,
  double width = 320,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: FundraiserSection(social: social, runId: 'r1'),
            ),
          ),
        ),
      ),
    ),
  );
  // Let the initState fetch chain (fundraiser → totals → feed) resolve.
  await tester.pump();
  await tester.pump();
}

void main() {
  group('FundraiserSection', () {
    testWidgets('renders the thermometer + donation feed', (tester) async {
      final social = _FakeSocial(
        fundraiser: _fundraiser(),
        totals: const FundraiserTotalsView(
          raisedCents: 50000,
          donorCount: 3,
          goalCents: 100000,
          currency: 'usd',
        ),
        feed: [_entry(displayName: 'Alice', message: 'Go go go')],
      );
      await _pump(tester, social: social);
      expect(find.text('Charity run'), findsOneWidget);
      expect(find.text('3 supporters'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Go go go'), findsOneWidget);
    });

    testWidgets('a long donor name survives a narrow width without '
        'overflowing', (tester) async {
      const longName =
          'Bartholomew Archibald Montgomery Fitzgerald-Featherstonehaugh '
          'the Third of Ashby-de-la-Zouch';
      final social = _FakeSocial(
        fundraiser: _fundraiser(),
        totals: const FundraiserTotalsView(
          raisedCents: 120000,
          donorCount: 12,
          goalCents: 100000,
          currency: 'usd',
        ),
        feed: [_entry(displayName: longName, message: 'Well done')],
      );
      await _pump(tester, social: social);
      // The donor name shares its row with the amount; it must ellipsize
      // instead of throwing a RenderFlex overflow (the harness fails the
      // test on one). The over-goal badge row must survive too.
      expect(find.text(longName), findsOneWidget);
      expect(find.text('Over goal!'), findsOneWidget);
    });
  });
}
