import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/run_detail_screen.dart'
    show applyRunMetadataEdit, applyDnfFlag;

/// Parity tests for `applyRunMetadataEdit` — mobile's run-detail edit
/// dialog metadata normalisation. The matching web implementation
/// lives in `apps/web/src/lib/data_normalise.ts:applyRunMetadataPatch`;
/// the shared contract is:
///   - Trim the user's input.
///   - If empty-after-trim, REMOVE the key from the bag (so a cleared
///     field actually disappears, not lingers as `""`).
///   - Otherwise write the trimmed value.
///
/// The previous behaviour wrote `metadata.notes = ""` when the user
/// cleared the notes field, breaking the render-when-present UI on
/// both platforms. Pinned here so a future refactor doesn't quietly
/// reintroduce it.
void main() {
  group('applyRunMetadataEdit — null/empty input', () {
    test('null base + empty inputs → empty map', () {
      final out = applyRunMetadataEdit(null, title: '', notes: '');
      expect(out, isEmpty);
    });

    test('null base + whitespace inputs → empty map', () {
      final out = applyRunMetadataEdit(null, title: '   ', notes: '\t\n  ');
      expect(out, isEmpty);
    });

    test('null base + populated inputs → trimmed entries', () {
      final out = applyRunMetadataEdit(
        null,
        title: '  Tempo  ',
        notes: '  Cruise pace  ',
      );
      expect(out, equals({'title': 'Tempo', 'notes': 'Cruise pace'}));
    });
  });

  group('applyRunMetadataEdit — preserves unrelated keys', () {
    test('keeps `activity_type` and `strava_id` untouched', () {
      final out = applyRunMetadataEdit(
        {'activity_type': 'run', 'strava_id': 12345},
        title: 'A',
        notes: 'B',
      );
      expect(out['activity_type'], 'run');
      expect(out['strava_id'], 12345);
      expect(out['title'], 'A');
      expect(out['notes'], 'B');
    });

    test('does not mutate the caller\'s map (returns a copy)', () {
      // Defensive: a future caller might rely on the original
      // metadata being intact for an undo / re-edit flow. Make sure
      // the helper builds a fresh map.
      final original = {'title': 'Old', 'activity_type': 'run'};
      final out = applyRunMetadataEdit(original, title: 'New', notes: '');
      expect(original, equals({'title': 'Old', 'activity_type': 'run'}),
          reason: 'helper must not mutate the caller\'s metadata.');
      expect(out['title'], 'New');
    });
  });

  group('applyRunMetadataEdit — clearing fields (the bug fix)', () {
    test('whitespace title REMOVES the title key', () {
      final out = applyRunMetadataEdit(
        {'title': 'Old title', 'notes': 'Keep'},
        title: '   ',
        notes: 'Keep',
      );
      expect(out.containsKey('title'), isFalse,
          reason: 'Clearing the title field must remove the key, '
              'not leave `title: ""`.');
      expect(out['notes'], 'Keep');
    });

    test('whitespace notes REMOVES the notes key', () {
      final out = applyRunMetadataEdit(
        {'title': 'Keep', 'notes': 'Old notes'},
        title: 'Keep',
        notes: '\t\n  ',
      );
      expect(out.containsKey('notes'), isFalse);
      expect(out['title'], 'Keep');
    });

    test('clearing BOTH fields drops both keys, leaves other metadata', () {
      final out = applyRunMetadataEdit(
        {
          'title': 'Old',
          'notes': 'Old',
          'activity_type': 'walk',
        },
        title: '',
        notes: '',
      );
      expect(out.containsKey('title'), isFalse);
      expect(out.containsKey('notes'), isFalse);
      expect(out['activity_type'], 'walk');
    });
  });

  group('applyRunMetadataEdit — whitespace + edge content', () {
    test('internal whitespace preserved', () {
      final out = applyRunMetadataEdit(
        null,
        title: 'one   two  three',
        notes: '',
      );
      expect(out['title'], 'one   two  three');
    });

    test('single non-whitespace character round-trips intact', () {
      final out = applyRunMetadataEdit(null, title: '🏃', notes: '');
      expect(out['title'], '🏃');
    });

    test('"0" stays as "0" — JS truthiness pin', () {
      final out = applyRunMetadataEdit(null, title: '0', notes: '0');
      expect(out['title'], '0');
      expect(out['notes'], '0');
    });
  });

  group('applyDnfFlag — DNF toggle (mirrors web run-detail edit)', () {
    test('setting DNF writes is_dnf: true', () {
      final meta = <String, dynamic>{'title': 'Ultra attempt'};
      applyDnfFlag(meta, true);
      expect(meta['is_dnf'], true);
      expect(meta['title'], 'Ultra attempt');
    });

    test('clearing DNF removes the key (not is_dnf: false)', () {
      final meta = <String, dynamic>{'is_dnf': true, 'activity_type': 'run'};
      applyDnfFlag(meta, false);
      expect(meta.containsKey('is_dnf'), isFalse,
          reason: 'metadata bag stores presence, not a false value');
      expect(meta['activity_type'], 'run');
    });

    test('clearing DNF on a run that never had it is a no-op', () {
      final meta = <String, dynamic>{'title': 'Easy'};
      applyDnfFlag(meta, false);
      expect(meta, equals({'title': 'Easy'}));
    });
  });
}
