import 'package:flutter_test/flutter_test.dart';

import '../lib/live_hub_client.dart';

class _RecordingFetcher {
  Uri? lastUrl;
  Map<String, dynamic>? lastBody;
  int status;
  int callCount = 0;
  _RecordingFetcher({this.status = 202});
  Future<int> call(Uri url, Map<String, dynamic> body) async {
    lastUrl = url;
    lastBody = body;
    callCount++;
    return status;
  }
}

void main() {
  group('isConfigured', () {
    test('false when baseUrl is empty', () {
      const c = LiveHubClient(baseUrl: '');
      expect(c.isConfigured, isFalse);
    });
    test('true when baseUrl is non-empty', () {
      const c = LiveHubClient(baseUrl: 'https://live.runonward.com');
      expect(c.isConfigured, isTrue);
    });
  });

  group('pushPing', () {
    test('targets /v1/live/{run_id}/push on the configured host',
        () async {
      final f = _RecordingFetcher();
      final c = LiveHubClient(
        baseUrl: 'https://live.runonward.com',
        fetcher: f.call,
      );
      await c.pushPing(runId: 'run-1', lat: 47.37, lng: 8.54);
      expect(f.lastUrl!.host, 'live.runonward.com');
      expect(f.lastUrl!.path, '/v1/live/run-1/push');
    });

    test('URL-encodes the run id', () async {
      final f = _RecordingFetcher();
      final c = LiveHubClient(
        baseUrl: 'https://live.runonward.com',
        fetcher: f.call,
      );
      // Realistic IDs are UUIDs so this normally doesn't matter, but
      // we keep encoding defensive in case a future schema lands
      // alphanumeric handles.
      await c.pushPing(runId: 'a b/c', lat: 0, lng: 0);
      expect(f.lastUrl!.path, '/v1/live/a%20b%2Fc/push');
    });

    test('strips a trailing slash from baseUrl', () async {
      final f = _RecordingFetcher();
      final c = LiveHubClient(
        baseUrl: 'https://live.runonward.com/',
        fetcher: f.call,
      );
      await c.pushPing(runId: 'run-1', lat: 0, lng: 0);
      expect(f.lastUrl!.path, '/v1/live/run-1/push');
    });

    test('omits optional fields when null', () async {
      final f = _RecordingFetcher();
      final c = LiveHubClient(
        baseUrl: 'https://live.runonward.com',
        fetcher: f.call,
      );
      await c.pushPing(runId: 'run-1', lat: 47.37, lng: 8.54);
      expect(f.lastBody!.containsKey('distance_m'), isFalse);
      expect(f.lastBody!.containsKey('elapsed_s'), isFalse);
      expect(f.lastBody!.containsKey('bpm'), isFalse);
      expect(f.lastBody!.containsKey('ele'), isFalse);
      // sent_at_ms always included for end-to-end latency tracking
      // against the spectator's clock.
      expect(f.lastBody!.containsKey('sent_at_ms'), isTrue);
      expect(f.lastBody!['sent_at_ms'], isA<int>());
    });

    test('includes optional fields when set', () async {
      final f = _RecordingFetcher();
      final c = LiveHubClient(
        baseUrl: 'https://live.runonward.com',
        fetcher: f.call,
      );
      await c.pushPing(
        runId: 'run-1',
        lat: 47.37,
        lng: 8.54,
        distanceM: 500,
        elapsedS: 120,
        bpm: 145,
        ele: 410.5,
      );
      expect(f.lastBody!['lat'], 47.37);
      expect(f.lastBody!['lng'], 8.54);
      expect(f.lastBody!['distance_m'], 500);
      expect(f.lastBody!['elapsed_s'], 120);
      expect(f.lastBody!['bpm'], 145);
      expect(f.lastBody!['ele'], 410.5);
    });

    test('returns the fetcher status code', () async {
      final f = _RecordingFetcher(status: 202);
      final c = LiveHubClient(
        baseUrl: 'https://live.runonward.com',
        fetcher: f.call,
      );
      final s = await c.pushPing(runId: 'run-1', lat: 0, lng: 0);
      expect(s, 202);
    });

    test('propagates fetcher errors', () async {
      Future<int> bomb(Uri _, Map<String, dynamic> __) async {
        throw StateError('network down');
      }

      const c = LiveHubClient(baseUrl: 'https://live.runonward.com');
      expect(
        () => LiveHubClient(
                baseUrl: 'https://live.runonward.com', fetcher: bomb)
            .pushPing(runId: 'run-1', lat: 0, lng: 0),
        throwsA(isA<StateError>()),
      );
      // The const c above is kept for the analyzer — unused refs flag.
      expect(c.isConfigured, isTrue);
    });
  });
}
