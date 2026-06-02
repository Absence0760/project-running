import 'package:flutter_test/flutter_test.dart';

import '../lib/guided_runs.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';

final AppLocalizations _l10n = AppLocalizationsEn();

GuidedRun _mkRun(List<int> ats) => GuidedRun(
      id: 'test',
      title: 't',
      subtitle: 's',
      durationSec: (ats.isEmpty ? 0 : ats.reduce((a, b) => a > b ? a : b)) + 10,
      description: 'd',
      cues: [for (final at in ats) GuidedCue(atSec: at, text: 'cue at $at')],
    );

void main() {
  group('cuesDue', () {
    test('no cues in range → empty', () {
      final g = _mkRun(const [10, 60, 120]);
      expect(cuesDue(g, 30, 50), isEmpty);
    });

    test('cue at boundary fires on the tick it crosses', () {
      final g = _mkRun(const [60]);
      expect(cuesDue(g, 59, 60), hasLength(1));
      expect(cuesDue(g, 60, 61), isEmpty);
    });

    test('multiple cues in the same window all fire', () {
      final g = _mkRun(const [10, 11, 12]);
      final out = cuesDue(g, 9, 12);
      expect(out, hasLength(3));
      expect(out.map((c) => c.atSec), [10, 11, 12]);
    });

    test('prev == now → empty (idempotent)', () {
      final g = _mkRun(const [60]);
      expect(cuesDue(g, 60, 60), isEmpty);
    });

    test('now < prev → empty', () {
      final g = _mkRun(const [60]);
      expect(cuesDue(g, 120, 60), isEmpty);
    });

    test('cue at 0 fires when prev is -1 (first tick)', () {
      final g = _mkRun(const [0]);
      expect(cuesDue(g, -1, 0), hasLength(1));
    });
  });

  group('isGuidedRunValid', () {
    test('well-formed run passes', () {
      final g = _mkRun(const [0, 60, 300]);
      expect(isGuidedRunValid(g), isTrue);
    });

    test('out-of-order cues fail', () {
      const g = GuidedRun(
        id: 'x',
        title: 'x',
        subtitle: 'x',
        durationSec: 600,
        description: 'x',
        cues: [
          GuidedCue(atSec: 60, text: 'a'),
          GuidedCue(atSec: 30, text: 'b'),
        ],
      );
      expect(isGuidedRunValid(g), isFalse);
    });

    test('cue beyond duration fails', () {
      const g = GuidedRun(
        id: 'x',
        title: 'x',
        subtitle: 'x',
        durationSec: 60,
        description: 'x',
        cues: [GuidedCue(atSec: 120, text: 'late')],
      );
      expect(isGuidedRunValid(g), isFalse);
    });

    test('blank cue text fails', () {
      const g = GuidedRun(
        id: 'x',
        title: 'x',
        subtitle: 'x',
        durationSec: 60,
        description: 'x',
        cues: [GuidedCue(atSec: 30, text: '   ')],
      );
      expect(isGuidedRunValid(g), isFalse);
    });
  });

  group('guidedRunLibrary', () {
    final library = guidedRunLibrary(_l10n);

    test('every entry is valid', () {
      expect(library.length, greaterThanOrEqualTo(3));
      for (final g in library) {
        expect(isGuidedRunValid(g), isTrue, reason: '${g.id} is malformed');
      }
    });

    test('ids are unique', () {
      final ids = library.map((g) => g.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('durations are sensible (5-90 min)', () {
      for (final g in library) {
        expect(g.durationSec, greaterThanOrEqualTo(5 * 60));
        expect(g.durationSec, lessThanOrEqualTo(90 * 60));
      }
    });

    test('every run has a kickoff cue at or near 0', () {
      for (final g in library) {
        expect(g.cues.isNotEmpty && g.cues.first.atSec <= 5, isTrue,
            reason: '${g.id} missing a kickoff cue in the first 5s');
      }
    });

    test('every run has a finish cue at exactly duration', () {
      for (final g in library) {
        expect(g.cues.last.atSec, g.durationSec,
            reason: '${g.id} missing a finish cue at duration');
      }
    });

    test('cue + title text is populated (localized, non-empty)', () {
      for (final g in library) {
        expect(g.title.trim(), isNotEmpty);
        expect(g.description.trim(), isNotEmpty);
        for (final c in g.cues) {
          expect(c.text.trim(), isNotEmpty);
        }
      }
    });
  });

  test('findGuidedRun: returns null for unknown id', () {
    expect(findGuidedRun(_l10n, 'nope'), isNull);
  });

  test('findGuidedRun: returns the run for a known id', () {
    final id = guidedRunLibrary(_l10n).first.id;
    expect(findGuidedRun(_l10n, id), isNotNull);
    expect(findGuidedRun(_l10n, id)!.id, id);
  });
}
