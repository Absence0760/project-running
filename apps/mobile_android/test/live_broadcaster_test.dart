import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/live_broadcaster.dart';
import '../lib/live_hub_client.dart';
import '../lib/privacy.dart';

class _FakeApiClient extends ApiClient {
  int callCount = 0;
  final List<Map<String, dynamic>> calls = [];
  Object? errorToThrow;

  @override
  Future<void> insertLivePing({
    required String runId,
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
    double? ele,
  }) async {
    callCount++;
    calls.add({
      'run_id': runId,
      'lat': lat,
      'lng': lng,
      'distance_m': distanceM,
      'elapsed_s': elapsedS,
      'bpm': bpm,
      'ele': ele,
    });
    if (errorToThrow != null) throw errorToThrow!;
  }
}

void main() {
  group('LiveBroadcaster', () {
    test('starts inactive', () {
      final lb = LiveBroadcaster(_FakeApiClient());
      expect(lb.isActive, false);
      expect(lb.runId, isNull);
    });

    test('pushPing is a no-op when inactive', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      await lb.pushPing(lat: 1, lng: 2);
      expect(api.callCount, 0);
    });

    test('attach flips isActive and exposes the run id', () {
      final lb = LiveBroadcaster(_FakeApiClient());
      lb.attach('run-1');
      expect(lb.isActive, true);
      expect(lb.runId, 'run-1');
    });

    test('first ping after attach goes through', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      await lb.pushPing(lat: 1, lng: 2, distanceM: 10, elapsedS: 5, bpm: 130, ele: 12);
      expect(api.callCount, 1);
      expect(api.calls.single, {
        'run_id': 'run-1',
        'lat': 1,
        'lng': 2,
        'distance_m': 10,
        'elapsed_s': 5,
        'bpm': 130,
        'ele': 12,
      });
    });

    test('throttles back-to-back pings within the 5s window', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      await lb.pushPing(lat: 1, lng: 2);
      await lb.pushPing(lat: 1, lng: 2); // immediate — throttled
      await lb.pushPing(lat: 1, lng: 2); // immediate — throttled
      expect(api.callCount, 1, reason: 'throttle window must drop the 2nd and 3rd same-tick calls');
    });

    test('detach silences future pings', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      lb.detach();
      expect(lb.isActive, false);
      expect(lb.runId, isNull);
      await lb.pushPing(lat: 1, lng: 2);
      expect(api.callCount, 0);
    });

    test('swallows api errors so the recorder stays untouched', () async {
      final api = _FakeApiClient()..errorToThrow = StateError('network down');
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      // Must not throw — L4 per docs/architecture/conventions.md § Layered resilience.
      await lb.pushPing(lat: 1, lng: 2);
      expect(api.callCount, 1);
    });

    test('re-attach resets the throttle timer so the next ping fires immediately', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      await lb.pushPing(lat: 1, lng: 2);
      lb.detach();
      lb.attach('run-2');
      await lb.pushPing(lat: 3, lng: 4);
      expect(api.callCount, 2);
      expect(api.calls.last['run_id'], 'run-2');
    });
  });

  group('LiveBroadcaster transport selection', () {
    test('routes pings through the Go hub when hubClient is configured',
        () async {
      // hubClient configured → API insert path should NOT fire.
      final api = _FakeApiClient();
      Uri? hubUrl;
      Map<String, dynamic>? hubBody;
      final hub = LiveHubClient(
        baseUrl: 'https://live.threkir.com',
        fetcher: (u, b, _) async {
          hubUrl = u;
          hubBody = b;
          return 202;
        },
      );
      final lb = LiveBroadcaster(api, hubClient: hub);
      lb.attach('run-1');
      await lb.pushPing(
        lat: 47.37,
        lng: 8.54,
        distanceM: 500,
        elapsedS: 60,
      );
      expect(api.callCount, 0,
          reason: 'hub path must not fall through to insertLivePing');
      expect(hubUrl!.path, '/v1/live/run-1/push');
      expect(hubBody!['lat'], 47.37);
      expect(hubBody!['distance_m'], 500);
    });

    test('falls back to insertLivePing when hubClient is null',
        () async {
      // Default (unconfigured) path — the Supabase insert still works
      // so the feature stays usable on every build before the hub
      // deploys.
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api);
      lb.attach('run-1');
      await lb.pushPing(lat: 1, lng: 1);
      expect(api.callCount, 1);
    });

    test('falls back to insertLivePing when hubClient.isConfigured = false',
        () async {
      // baseUrl: '' → hub.isConfigured = false → broadcaster picks
      // the legacy path. Same as null hubClient, just expressed via
      // an unconfigured client (matches what run_screen does today
      // when LIVE_HUB_URL is absent).
      final api = _FakeApiClient();
      final hub = LiveHubClient(
        baseUrl: '',
        fetcher: (_, __, ___) async => fail('hub must not be hit'),
      );
      final lb = LiveBroadcaster(api, hubClient: hub);
      lb.attach('run-1');
      await lb.pushPing(lat: 1, lng: 1);
      expect(api.callCount, 1);
    });

    test('hub HTTP failure does not bubble — L4 best-effort contract',
        () async {
      final api = _FakeApiClient();
      final hub = LiveHubClient(
        baseUrl: 'https://live.threkir.com',
        fetcher: (_, __, ___) async => throw StateError('hub down'),
      );
      final lb = LiveBroadcaster(api, hubClient: hub);
      lb.attach('run-1');
      // Must not throw — the broadcaster swallows so the recorder's
      // L0/L1 stays untouched.
      await lb.pushPing(lat: 1, lng: 1);
      // And it didn't silently fall through to the Supabase path
      // either — failure is just a missed ping; next 5 s tick takes
      // its place.
      expect(api.callCount, 0);
    });
  });

  group('LiveBroadcaster privacy-zone drop', () {
    // The headline guarantee. The Supabase trigger
    // `live_run_pings_drop_in_zone` only fires on the legacy
    // insert path; the Go hub bypasses Postgres entirely. Without
    // a client-side drop, a runner with a privacy zone around
    // their home leaks every in-zone fix to anonymous spectators
    // when the hub transport is wired. The trip-wire is the
    // privacyZonesProvider — when set, in-zone pings must be
    // dropped before reaching either transport.
    PrivacyZone home() => const PrivacyZone(
          lat: 47.37,
          lng: 8.54,
          radiusM: 200,
        );

    test('in-zone ping is NOT forwarded to the Go hub', () async {
      final api = _FakeApiClient();
      var hubCalls = 0;
      final hub = LiveHubClient(
        baseUrl: 'https://live.threkir.com',
        fetcher: (u, b, _) async {
          hubCalls++;
          return 202;
        },
      );
      final lb = LiveBroadcaster(
        api,
        hubClient: hub,
        privacyZonesProvider: () => [home()],
      );
      lb.attach('run-1');
      // Ping at the zone center — must be dropped.
      await lb.pushPing(lat: 47.37, lng: 8.54);
      expect(hubCalls, 0,
          reason: 'in-zone ping must NOT reach the Go hub — the '
              'hub bypasses the Supabase trigger so the client-side '
              'drop is the only privacy enforcement on this path');
      expect(api.callCount, 0,
          reason: 'and must not fall through to the legacy path '
              'either — the drop is transport-agnostic');
    });

    test('in-zone ping is NOT forwarded to the Supabase path',
        () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(
        api,
        privacyZonesProvider: () => [home()],
      );
      lb.attach('run-1');
      await lb.pushPing(lat: 47.37, lng: 8.54);
      expect(api.callCount, 0,
          reason: 'even though the Supabase trigger would drop the '
              'row server-side, sending only to have it dropped is '
              'wasted bandwidth — the client-side gate fires first');
    });

    test('out-of-zone ping is forwarded normally', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(
        api,
        privacyZonesProvider: () => [home()],
      );
      lb.attach('run-1');
      // ~1 km north of the zone center — well outside the 200 m
      // radius (every degree of latitude is ~111 km).
      await lb.pushPing(lat: 47.38, lng: 8.54);
      expect(api.callCount, 1,
          reason: 'a fix outside every zone must pass through');
    });

    test('dropped ping does NOT burn the throttle window', () async {
      // The throttle update must happen AFTER the zone check, so the
      // very next out-of-zone fix fires immediately instead of waiting
      // out the full 5 s interval. Without this, a runner who finishes
      // their cool-down inside the zone and then steps outside has to
      // wait 5 s before the spectator UI updates.
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(
        api,
        privacyZonesProvider: () => [home()],
      );
      lb.attach('run-1');
      // Drop one in-zone ping.
      await lb.pushPing(lat: 47.37, lng: 8.54);
      expect(api.callCount, 0);
      // Immediately ping out of zone — should fire, not wait the
      // throttle window.
      await lb.pushPing(lat: 47.38, lng: 8.54);
      expect(api.callCount, 1,
          reason: 'dropped pings must not consume the throttle slot');
    });

    test('null provider → no client-side clipping (legacy behaviour '
        'preserved when settings aren\'t wired)', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(api); // no provider
      lb.attach('run-1');
      // Without a provider, every fix passes — the Supabase trigger
      // is the sole enforcement, matching pre-fix behaviour for the
      // tests + the no-settings code path.
      await lb.pushPing(lat: 47.37, lng: 8.54);
      expect(api.callCount, 1);
    });

    test('provider returning empty list → no clipping (matches "no '
        'zones configured")', () async {
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(
        api,
        privacyZonesProvider: () => const <PrivacyZone>[],
      );
      lb.attach('run-1');
      await lb.pushPing(lat: 47.37, lng: 8.54);
      expect(api.callCount, 1,
          reason: 'an empty zone list is the user opting out of the '
              'privacy gate — must not block any pings');
    });

    test('provider is re-evaluated on EVERY pushPing (mid-run zone '
        'changes take effect immediately)', () async {
      // The user can add a privacy zone in Settings while a broadcast
      // is in flight. The provider must be re-read each push so the
      // new zone applies to the next fix, not the next run.
      var zones = <PrivacyZone>[];
      final api = _FakeApiClient();
      final lb = LiveBroadcaster(
        api,
        privacyZonesProvider: () => zones,
      );
      lb.attach('run-1');

      // First ping with NO zones — passes.
      await lb.pushPing(lat: 47.37, lng: 8.54);
      expect(api.callCount, 1);

      // User adds a zone covering the same coordinates.
      zones = [home()];

      // Bypass the throttle by waiting (or using a fresh broadcaster
      // — simpler). The throttle counts dropped pings as well? No,
      // we tested that dropped don't burn it. So we just need to
      // wait the throttle window.
      await Future.delayed(const Duration(seconds: 6));
      await lb.pushPing(lat: 47.37, lng: 8.54);
      expect(api.callCount, 1,
          reason: 'after the zone is added mid-run, the next in-zone '
              'fix must be dropped — provider read must NOT be '
              'memoised across pushes');
    });
  });
}
