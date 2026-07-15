@TestOn('vm')
library;

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Wire-level pin for issue #233's second half: `user_profiles` rows are
/// client-provisioned (no signup trigger), so a plain
/// `.update().eq(id, uid)` against a user whose row doesn't exist yet
/// matches 0 rows and reports success — the withdrawal is "confirmed"
/// while nothing is stored. The writers now UPSERT, so the write must
/// land a row carrying the withdrawn (null) consent even when no profile
/// row existed.
///
/// **Skipped unless `SUPABASE_TEST_URL` is set** — same harness contract
/// as `api_client_integration_test.dart`. Signs up a fresh throwaway user
/// (local config has `enable_confirmations = false`, so the session is
/// immediate) precisely because a fresh user is the no-profile-row case.
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
      'consent withdrawal integration tests — skipped (SUPABASE_TEST_URL not set)',
      () {},
    );
    return;
  }

  late SupabaseClient client;
  late ApiClient api;

  // get_my_profile() `returns user_profiles`, so a missing row comes back
  // as an all-null composite (id == null), not as SQL NULL.
  Map<String, dynamic>? profileRow(dynamic res) {
    final row = (res is List ? (res.isEmpty ? null : res.first) : res)
        as Map<String, dynamic>?;
    if (row == null || row['id'] == null) return null;
    return row;
  }

  setUpAll(() async {
    // Implicit flow: the default PKCE flow asserts on a missing
    // asyncStorage inside signUp under the plain test harness.
    client = SupabaseClient(
      url,
      anonKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    api = ApiClient.withClient(client);
    final email =
        'consent-it-${DateTime.now().millisecondsSinceEpoch}@test.local';
    final res = await client.auth.signUp(email: email, password: 'testtest');
    expect(res.session, isNotNull,
        reason: 'local signUp must return an immediate session '
            '(enable_confirmations = false)');
  });

  tearDownAll(() async {
    await client.auth.signOut();
    client.dispose();
  });

  test('withdrawHealthDataConsent lands a row when no profile row exists',
      () async {
    final before = profileRow(await client.rpc('get_my_profile'));
    expect(before, isNull,
        reason: 'fresh user must have no client-provisioned profile row — '
            'the 0-row trigger this test exists for');

    await api.withdrawHealthDataConsent();

    final after = profileRow(await client.rpc('get_my_profile'));
    expect(after, isNotNull,
        reason: 'the RPC must land a row, not 0-row no-op');
    expect(after!['health_data_consent_at'], isNull);
    expect(after['height_cm'], isNull);
  });

  test(
      'grant + height + weight round-trip; the withdrawal RPC erases all of it',
      () async {
    final stamped = await api.grantHealthDataConsent();
    expect(stamped, isNotNull,
        reason: 'grant must insert-or-update, not 0-row no-op, even when '
            'the profile row was only just provisioned');
    await api.setMyHeightCm(181.5);
    await api.recordBodyWeightKg(72.5);

    final granted = profileRow(await client.rpc('get_my_profile'))!;
    expect(granted['health_data_consent_at'], isNotNull);
    expect((granted['height_cm'] as num).toDouble(), closeTo(181.5, 0.01));
    expect(await api.fetchLatestBodyWeightKg(), closeTo(72.5, 0.01));

    await api.withdrawHealthDataConsent();

    final withdrawn = profileRow(await client.rpc('get_my_profile'))!;
    expect(withdrawn['health_data_consent_at'], isNull);
    expect(withdrawn['height_cm'], isNull);
    expect(await api.fetchLatestBodyWeightKg(), isNull,
        reason: 'the withdrawal RPC must erase the body_metrics series '
            'in the same transaction');
  });

  test('withdrawCoachConsent reaches the RPC (no client-side silent bail)',
      () async {
    // The RPC itself raises 42501 when unauthenticated; with a live
    // session it must complete without the old `uid == null → return`
    // path ever mattering.
    await api.withdrawCoachConsent();
    final row = profileRow(await client.rpc('get_my_profile'))!;
    expect(row['coach_consent_at'], isNull);
  });
}
