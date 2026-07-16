@TestOn('vm')
library;

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Wire-level pin for issue #234: the settings push had a 0-row hole —
/// `user_settings` / `user_device_settings` rows are client-provisioned,
/// so a push before the row exists (a write before any successful load(),
/// an explicitly supported path) made the read-merge-WRITE match 0 rows
/// and report success. The change was neither stored nor queued, the
/// local cache was stamped as pushed, and the next load reverted it.
/// These bags carry privacy_zones + safety_overdue_minutes, so the drop
/// is a privacy/safety failure. The push is now an upsert; a write
/// against a missing row must LAND the row.
///
/// **Skipped unless `SUPABASE_TEST_URL` is set** — same harness contract
/// as `api_client_integration_test.dart`. Signs up a fresh throwaway user
/// precisely because a fresh user has neither settings row.
const _testUrl = String.fromEnvironment('SUPABASE_TEST_URL');
const _testAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');

void main() {
  final url = _testUrl.isNotEmpty
      ? _testUrl
      : Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final anonKey = _testAnonKey.isNotEmpty
      ? _testAnonKey
      : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    test(
      'settings push integration tests — skipped (SUPABASE_TEST_URL not set)',
      () {},
    );
    return;
  }

  late SupabaseClient client;
  late SettingsService settings;
  late String uid;

  setUpAll(() async {
    client = SupabaseClient(
      url,
      anonKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    final email =
        'settings-it-${DateTime.now().millisecondsSinceEpoch}@test.local';
    final res = await client.auth.signUp(email: email, password: 'testtest');
    expect(res.session, isNotNull);
    uid = res.user!.id;
    settings = SettingsService.withClient(
      client,
      deviceId: 'it-device-1',
      platform: 'android',
      label: 'integration test',
    );
  });

  tearDownAll(() async {
    await client.auth.signOut();
    client.dispose();
  });

  test('universal push before any load() lands the missing row', () async {
    final before = await client
        .from('user_settings')
        .select('user_id')
        .eq('user_id', uid)
        .maybeSingle();
    expect(before, isNull,
        reason: 'fresh user must have no user_settings row — '
            'the 0-row trigger this test exists for');

    await settings.updateUniversal({'privacy_default': 'private'});

    final after = await client
        .from('user_settings')
        .select('prefs')
        .eq('user_id', uid)
        .maybeSingle();
    expect(after, isNotNull,
        reason: 'the push must land the row, not 0-row no-op');
    expect((after!['prefs'] as Map)['privacy_default'], 'private');
  });

  test('a second universal push merges into the now-existing row', () async {
    await settings.updateUniversal({'week_start_day': 1});
    final row = await client
        .from('user_settings')
        .select('prefs')
        .eq('user_id', uid)
        .single();
    final prefs = row['prefs'] as Map;
    expect(prefs['privacy_default'], 'private',
        reason: 'the upsert conflict arm must merge, not clobber');
    expect(prefs['week_start_day'], 1);
  });

  test('device push before any load() lands the missing row', () async {
    await settings.updateDevice({'map_style': 'terrain'});
    final row = await client
        .from('user_device_settings')
        .select('platform, label, prefs')
        .eq('user_id', uid)
        .eq('device_id', 'it-device-1')
        .maybeSingle();
    expect(row, isNotNull,
        reason: 'the device push must land the row, not 0-row no-op');
    expect(row!['platform'], 'android');
    expect((row['prefs'] as Map)['map_style'], 'terrain');
  });
}
