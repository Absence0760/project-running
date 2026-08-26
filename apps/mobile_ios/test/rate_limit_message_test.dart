// Renders the rate-limit refusal out of the real ARB catalogues, in
// every locale the app ships. Dart companion of web's
// i18n/rate_limit_message.test.ts.
//
// The English assertions are the pre-§744 strings verbatim: moving the
// prose out of the parity pair and into the catalogue must not change a
// single character of what an English reader sees.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/rate_limit_errors.dart';
import '../lib/rate_limit_message.dart';

const _buckets = <String>[
  'create_club',
  'create_route',
  'create_report',
  'clone_plan_template',
  'clone_public_plan',
  'clone_session_template',
  'clone_gym_routine_template',
  'publish_gym_routine_as_template',
  'send_direct_message',
  'send_direct_message_burst',
];

/// Every locale `AppLocalizations.supportedLocales` actually serves —
/// taken from the delegate rather than listed, so a locale added to the
/// ARB set is covered here the day it lands.
Iterable<Locale> get _locales => AppLocalizations.supportedLocales;

String _render(AppLocalizations l10n, String bucket, int? seconds) =>
    rateLimitMessage(l10n, RateLimitInfo(bucket: bucket, seconds: seconds));

String? _fromError(AppLocalizations l10n, String bucket, int seconds) =>
    rateLimitErrorMessage(
      l10n,
      code: 'P0001',
      message: 'rate limit exceeded for $bucket, retry in ${seconds}s',
    );

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('en — the sentences are unchanged from before the copy moved', () {
    test('every bucket keeps its exact wording', () {
      expect(_fromError(en, 'create_club', 42),
          "You're creating clubs too quickly — please wait 42 seconds and try again.");
      expect(_fromError(en, 'create_route', 1234),
          "You're creating routes too quickly — please wait 21 minutes and try again.");
      expect(_fromError(en, 'create_report', 600),
          "You're filing reports too quickly — please wait 10 minutes and try again.");
      expect(_fromError(en, 'clone_plan_template', 300),
          "You're adopting plans too quickly — please wait 5 minutes and try again.");
      expect(_fromError(en, 'clone_public_plan', 45),
          "You're adopting plans too quickly — please wait 45 seconds and try again.");
      expect(_fromError(en, 'clone_session_template', 30),
          "You're adopting session plans too quickly — please wait 30 seconds and try again.");
      expect(_fromError(en, 'clone_gym_routine_template', 30),
          "You're adopting gym routines too quickly — please wait 30 seconds and try again.");
      expect(_fromError(en, 'publish_gym_routine_as_template', 120),
          "You're publishing routines too quickly — please wait 2 minutes and try again.");
    });

    test('both direct-message buckets read as "sending messages", not '
        '"doing that"', () {
      // The live defect § 744 was opened on: neither platform mapped the
      // two buckets migration 20270608_001 added, so a throttled sender
      // was told "You're doing that too quickly" about a message.
      expect(_fromError(en, 'send_direct_message', 1800),
          "You're sending messages too quickly — please wait 30 minutes and try again.");
      expect(_fromError(en, 'send_direct_message_burst', 41),
          "You're sending messages too quickly — please wait 41 seconds and try again.");
    });

    test('an unrecognised bucket degrades to the generic sentence', () {
      expect(_fromError(en, 'create_widget', 30),
          "You're doing that too quickly — please wait 30 seconds and try again.");
    });

    test('the wait pluralises and rounds at the 90-second cutoff', () {
      String wait(int seconds) => _fromError(en, 'create_club', seconds)!
          .replaceFirst("You're creating clubs too quickly — please wait ", '')
          .replaceFirst(' and try again.', '');
      expect(wait(1), '1 second');
      expect(wait(42), '42 seconds');
      expect(wait(89), '89 seconds');
      expect(wait(90), '2 minutes');
      expect(wait(120), '2 minutes');
      expect(wait(3540), '59 minutes');
      expect(wait(3600), '60 minutes');
    });

    test('a non-positive wait reads as "a few seconds", never "0 seconds"', () {
      expect(_fromError(en, 'create_club', 0),
          "You're creating clubs too quickly — please wait a few seconds and try again.");
    });

    test('a non-rate-limit error renders nothing, so the caller falls through',
        () {
      expect(
        rateLimitErrorMessage(en,
            code: '42501', message: 'permission denied for table routes'),
        isNull,
      );
      expect(rateLimitErrorMessage(en), isNull);
    });
  });

  test('every shipped locale renders complete copy for every bucket', () {
    expect(_locales, isNotEmpty);
    for (final locale in _locales) {
      final l10n = lookupAppLocalizations(locale);
      for (final bucket in [..._buckets, 'create_widget']) {
        for (final seconds in <int?>[null, 1, 42, 90, 3600]) {
          final rendered = _render(l10n, bucket, seconds);
          expect(rendered.trim(), isNotEmpty,
              reason: '$locale/$bucket/$seconds is empty');
          expect(rendered.contains('{'), isFalse,
              reason: '$locale/$bucket/$seconds left a slot: $rendered');
        }
      }
      // The wait is a slot, so a locale that dropped {wait} would render
      // the same sentence for a 1-second and a 1-hour refusal.
      expect(
        _render(l10n, 'create_club', 1),
        isNot(_render(l10n, 'create_club', 3600)),
        reason: '$locale renders the same sentence for a 1 s and a 1 h wait',
      );
      expect(
        _render(l10n, 'create_club', null),
        isNot(_render(l10n, 'create_club', 42)),
        reason: '$locale does not distinguish the non-positive wait',
      );
    }
  });

  test('every shipped locale gives each distinct activity its own sentence',
      () {
    // The two plan-adopt buckets deliberately share one; the two DM
    // buckets likewise. Everything else must be distinguishable, or a
    // locale has pasted one translation over several keys.
    for (final locale in _locales) {
      final l10n = lookupAppLocalizations(locale);
      final distinct = <String>{
        for (final bucket in const [
          'create_club',
          'create_route',
          'create_report',
          'clone_plan_template',
          'clone_session_template',
          'clone_gym_routine_template',
          'publish_gym_routine_as_template',
          'send_direct_message',
          'create_widget',
        ])
          _render(l10n, bucket, 42),
      };
      expect(distinct.length, 9,
          reason: '$locale reuses one sentence for two different activities');
      expect(
        _render(l10n, 'clone_plan_template', 42),
        _render(l10n, 'clone_public_plan', 42),
        reason: '$locale: the two plan-adopt buckets are one act',
      );
      expect(
        _render(l10n, 'send_direct_message', 42),
        _render(l10n, 'send_direct_message_burst', 42),
        reason: '$locale: which send window refused is our accounting, not '
            "the sender's",
      );
    }
  });

  test('a non-English locale actually gets non-English copy', () {
    // The point of the whole change. Pinned against the English string so
    // a catalogue that fell back to `en` fails here rather than shipping.
    final de = lookupAppLocalizations(const Locale('de'));
    final ja = lookupAppLocalizations(const Locale('ja'));
    for (final l10n in [de, ja]) {
      expect(_render(l10n, 'send_direct_message_burst', 41),
          isNot(_render(en, 'send_direct_message_burst', 41)));
      expect(_render(l10n, 'create_club', 42).contains('too quickly'), isFalse);
    }
  });
}
