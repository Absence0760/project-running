import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// Parity tests for `SettingsService.applyPrefsChanges` — the pure
/// merge helper that backs both `updateUniversal` and `updateDevice`.
///
/// Mirrors the merge loop in
/// `apps/web/src/lib/settings.ts:updateUniversal` / `updateDevice`,
/// which does the same key-level overlay on a `PrefsBag`. Pinning
/// the helper output across the same set of inputs both clients see
/// in production keeps the two prefs bags converging when read from
/// either platform.
///
/// History: mobile's `SettingsService.updateUniversal` previously
/// merged onto a CACHED `_universal` snapshot, so any pref another
/// device wrote between sign-in and the next mobile update was
/// silently overwritten. The fix is two-part: refactor to re-fetch
/// from the DB before merging (matches web), and lift the merge
/// itself into this pure helper so the contract is unit-testable.
void main() {
  group('applyPrefsChanges — basic overlay semantics', () {
    test('empty base + empty changes → empty result', () {
      expect(SettingsService.applyPrefsChanges(const {}, const {}), isEmpty);
    });

    test('empty base + non-empty changes → changes copied through', () {
      final result = SettingsService.applyPrefsChanges(const {}, {
        'preferred_unit': 'km',
        'split_interval': 1000,
      });
      expect(result, {
        'preferred_unit': 'km',
        'split_interval': 1000,
      });
    });

    test('base preserved when changes omit a key', () {
      // The load-bearing concurrency property: keys NOT touched by
      // this update must be left intact. Before the re-fetch fix
      // landed, mobile would silently drop another device's writes
      // that landed between this client's load and update.
      final result = SettingsService.applyPrefsChanges(
        {'a': 1, 'b': 2, 'c': 3},
        {'b': 20},
      );
      expect(result, {'a': 1, 'b': 20, 'c': 3});
    });
  });

  group('applyPrefsChanges — null-as-delete semantics', () {
    test('null value in changes REMOVES the key from base', () {
      final result = SettingsService.applyPrefsChanges(
        {'a': 1, 'b': 2},
        {'a': null},
      );
      expect(result, {'b': 2});
      expect(result.containsKey('a'), isFalse,
          reason: 'null value must DELETE the key, not store null.');
    });

    test('null on a key that doesn\'t exist in base is a no-op', () {
      final result = SettingsService.applyPrefsChanges(
        {'b': 2},
        {'ghost': null},
      );
      expect(result, {'b': 2});
    });

    test('mixed: some keys updated, some deleted, some untouched', () {
      final result = SettingsService.applyPrefsChanges(
        {'a': 1, 'b': 2, 'c': 3, 'd': 4},
        {'a': 10, 'b': null, 'e': 5},
      );
      // 'a' updated, 'b' deleted, 'c' + 'd' untouched, 'e' added.
      expect(result, {'a': 10, 'c': 3, 'd': 4, 'e': 5});
    });
  });

  group('applyPrefsChanges — value-type round-trips', () {
    test('non-null value 0 (the falsy-int trap) is preserved, not dropped',
        () {
      // Dart doesn't have JS-style truthiness for ints, but a sloppy
      // refactor could conflate `value == 0` with "absent". Pin it.
      final result = SettingsService.applyPrefsChanges(const {}, {
        'split_interval_m': 0,
      });
      expect(result['split_interval_m'], 0);
    });

    test('non-null false is preserved, not dropped', () {
      // Same trap, for bool. Mobile's voice-cues pref is a bool that
      // can legitimately be `false`.
      final result = SettingsService.applyPrefsChanges(const {}, {
        'voice_cues_enabled': false,
      });
      expect(result['voice_cues_enabled'], false);
    });

    test('empty string is preserved (only `null` triggers delete)', () {
      // Web's `if (v === null || v === undefined) delete merged[k]`
      // does NOT include empty string. Mobile's Dart equivalent only
      // checks `entry.value == null`. Pin the parity — empty string
      // stays.
      final result = SettingsService.applyPrefsChanges(const {}, {
        'parkrun_number': '',
      });
      expect(result['parkrun_number'], '');
    });

    test('nested map values round-trip (jsonb sub-objects)', () {
      // Privacy zones, hr_zones, etc. land here as nested Maps.
      final hrZones = {'z1': 120, 'z2': 145, 'z3': 165};
      final result = SettingsService.applyPrefsChanges(const {}, {
        'hr_zones': hrZones,
      });
      expect(result['hr_zones'], equals(hrZones));
    });
  });

  group('applyPrefsChanges — purity / non-mutation', () {
    test('returns a fresh map — does NOT mutate the base argument', () {
      final base = <String, dynamic>{'a': 1};
      final result = SettingsService.applyPrefsChanges(base, {'a': 2});
      expect(base, {'a': 1},
          reason: 'helper must not mutate the caller\'s base — '
              'a future undo / retry flow may rely on it.');
      expect(result, {'a': 2});
    });

    test('returns a fresh map — does NOT mutate the changes argument', () {
      final changes = <String, dynamic>{'a': 1, 'b': null};
      final result =
          SettingsService.applyPrefsChanges(const {}, changes);
      // changes argument should still contain the null entry.
      expect(changes, {'a': 1, 'b': null});
      expect(result, {'a': 1});
    });
  });
}
