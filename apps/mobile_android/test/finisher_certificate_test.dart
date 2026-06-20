import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/finisher_certificate.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/finisher_certificate_card.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('isCertificateEligible', () {
    test('eligible only when finished AND organiser-approved', () {
      expect(
        isCertificateEligible(
            finisherStatus: 'finished', organiserApproved: true),
        isTrue,
      );
      expect(
        isCertificateEligible(
            finisherStatus: 'finished', organiserApproved: false),
        isFalse,
      );
      expect(
        isCertificateEligible(finisherStatus: 'dnf', organiserApproved: true),
        isFalse,
      );
      expect(
        isCertificateEligible(finisherStatus: 'dns', organiserApproved: true),
        isFalse,
      );
    });
  });

  group('formatCertificateTime', () {
    test('sub-hour as m:ss, with-hour as h:mm:ss', () {
      expect(formatCertificateTime(22 * 60 + 9), '22:09');
      expect(formatCertificateTime(3 * 3600 + 25 * 60 + 8), '3:25:08');
    });

    test('clamps negatives to zero', () {
      expect(formatCertificateTime(-5), '0:00');
    });
  });

  group('formatCertificateDistance', () {
    test('km and mi formatting matches web', () {
      expect(formatCertificateDistance(10000, useMiles: false), '10.00 km');
      expect(formatCertificateDistance(10000, useMiles: true), '6.21 mi');
    });
  });

  group('ordinalPlace', () {
    test('matches web ordinal across the tricky cases', () {
      expect(ordinalPlace(1), '1st');
      expect(ordinalPlace(2), '2nd');
      expect(ordinalPlace(3), '3rd');
      expect(ordinalPlace(4), '4th');
      expect(ordinalPlace(11), '11th');
      expect(ordinalPlace(12), '12th');
      expect(ordinalPlace(13), '13th');
      expect(ordinalPlace(21), '21st');
      expect(ordinalPlace(22), '22nd');
      expect(ordinalPlace(23), '23rd');
      expect(ordinalPlace(111), '111th');
    });
  });

  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('certificate card renders the headline facts', (tester) async {
    await tester.pumpWidget(host(
      SizedBox(
        width: 700,
        height: 495,
        child: FinisherCertificateCard(
          eventTitle: 'Riverside 10K',
          finisherName: 'Alex Runner',
          durationS: 3 * 3600 + 25 * 60 + 8,
          distanceM: 10000,
          rank: 3,
          date: DateTime(2026, 6, 12),
          clubName: 'Richmond Run Club',
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Certificate of Completion'), findsOneWidget);
    expect(find.text('Alex Runner'), findsOneWidget);
    expect(find.text('Riverside 10K'), findsOneWidget);
    expect(find.text('Richmond Run Club'), findsOneWidget);
    expect(find.textContaining('3:25:08'), findsOneWidget);
    expect(find.textContaining('3rd place'), findsOneWidget);
  });

  testWidgets('certificate card omits the place line when rank is null',
      (tester) async {
    await tester.pumpWidget(host(
      SizedBox(
        width: 700,
        height: 495,
        child: FinisherCertificateCard(
          eventTitle: 'Riverside 10K',
          finisherName: 'Alex Runner',
          durationS: 1500,
          distanceM: 5000,
          rank: null,
          date: DateTime(2026, 6, 12),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('place'), findsNothing);
  });
}
