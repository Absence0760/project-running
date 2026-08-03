import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The all-time streak read fails closed to null (decisions § 475): a
/// signed-out client resolves null before any wire call — never zeros,
/// which a caller could not tell apart from a truthful empty history —
/// and any wire failure degrades to the same null, so the streak card
/// suppresses its all-time claim instead of rendering a wrong number.
void main() {
  late SupabaseClient signedOut;

  setUp(() {
    // Port 9 (discard) is never listening — if the method got past the
    // session guard it would surface a socket error, not a clean null.
    signedOut = SupabaseClient('http://127.0.0.1:9', 'eyJ.local.test');
  });

  tearDown(() {
    signedOut.dispose();
  });

  test('fetchRunStreaks resolves null when signed out', () async {
    final api = ApiClient.withClient(signedOut);
    expect(await api.fetchRunStreaks(tz: 'UTC'), isNull);
  });

  test('fetchRunStreaks resolves null with a source filter too', () async {
    final api = ApiClient.withClient(signedOut);
    expect(await api.fetchRunStreaks(tz: 'UTC', source: 'app'), isNull);
  });
}
