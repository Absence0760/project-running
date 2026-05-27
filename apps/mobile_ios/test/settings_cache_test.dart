import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/settings_cache.dart';

/// Tests for [SharedPrefsSettingsCache] — the on-disk implementation
/// that backs the offline-bag-prefs flow on mobile. Pins both the
/// round-trip JSON shape (so a future package upgrade can't quietly
/// drop the queue) AND the per-user scoping rules (so a sign-out
/// followed by a sign-in as a different user on the same device can't
/// surface another user's settings).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('read* returns null on cache miss', () async {
    final sp = await SharedPreferences.getInstance();
    final cache = SharedPrefsSettingsCache(sp);
    expect(cache.readUniversal('u1'), isNull);
    expect(cache.readDevice('u1', 'd1'), isNull);
  });

  test('write + read round-trip preserves nested values', () async {
    final sp = await SharedPreferences.getInstance();
    final cache = SharedPrefsSettingsCache(sp);
    await cache.writeUniversal('u1', {
      'hr_zones': {'z1': 130, 'z2': 145, 'z3': 160, 'z4': 175, 'z5': 190},
      'date_of_birth': '1990-01-15',
    });
    final round = cache.readUniversal('u1')!;
    expect(round['hr_zones'], isA<Map>());
    expect((round['hr_zones'] as Map)['z3'], 160);
    expect(round['date_of_birth'], '1990-01-15');
  });

  test('device cache scopes by (userId, deviceId)', () async {
    final sp = await SharedPreferences.getInstance();
    final cache = SharedPrefsSettingsCache(sp);
    await cache.writeDevice('u1', 'phone', {'keep_screen_on': true});
    await cache.writeDevice('u1', 'watch', {'keep_screen_on': false});
    expect(cache.readDevice('u1', 'phone'), {'keep_screen_on': true});
    expect(cache.readDevice('u1', 'watch'), {'keep_screen_on': false});
  });

  test('pending queue round-trips multiple writes in order', () async {
    final sp = await SharedPreferences.getInstance();
    final cache = SharedPrefsSettingsCache(sp);
    await cache.appendPending('u1', 'd1',
        PendingSettingsChange(isDevice: false, changes: {'a': 1}));
    await cache.appendPending('u1', 'd1',
        PendingSettingsChange(isDevice: true, changes: {'b': 2}));
    final q = cache.readPending('u1', 'd1');
    expect(q, hasLength(2));
    expect(q[0].changes['a'], 1);
    expect(q[1].isDevice, isTrue);
  });

  test('clearPending empties queue but leaves cached bags alive', () async {
    final sp = await SharedPreferences.getInstance();
    final cache = SharedPrefsSettingsCache(sp);
    await cache.writeUniversal('u1', {'preferred_unit': 'mi'});
    await cache.appendPending('u1', 'd1',
        PendingSettingsChange(isDevice: false, changes: {'a': 1}));
    await cache.clearPending('u1', 'd1');
    expect(cache.readPending('u1', 'd1'), isEmpty);
    expect(cache.readUniversal('u1'), {'preferred_unit': 'mi'},
        reason:
            'clearPending must scope to the queue only — not the cached bag.');
  });

  test('dropUser drops universal + device + pending for that user only',
      () async {
    final sp = await SharedPreferences.getInstance();
    final cache = SharedPrefsSettingsCache(sp);
    await cache.writeUniversal('u1', {'a': 1});
    await cache.writeUniversal('u2', {'a': 2});
    await cache.writeDevice('u1', 'd1', {'k': 'v'});
    await cache.appendPending('u1', 'd1',
        PendingSettingsChange(isDevice: false, changes: {'a': 1}));
    await cache.dropUser('u1');
    expect(cache.readUniversal('u1'), isNull);
    expect(cache.readDevice('u1', 'd1'), isNull);
    expect(cache.readPending('u1', 'd1'), isEmpty);
    expect(cache.readUniversal('u2'), {'a': 2},
        reason: 'dropUser must not touch other users\' rows.');
  });

  test('corrupt JSON in storage is dropped silently (returns null/empty)',
      () async {
    SharedPreferences.setMockInitialValues({
      'settings_cache_universal_u1': '{not valid json',
      'settings_cache_pending_u1_d1': '[also not valid',
    });
    final sp = await SharedPreferences.getInstance();
    final cache = SharedPrefsSettingsCache(sp);
    expect(cache.readUniversal('u1'), isNull);
    expect(cache.readPending('u1', 'd1'), isEmpty);
  });
}
