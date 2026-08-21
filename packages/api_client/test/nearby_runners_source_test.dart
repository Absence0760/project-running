import 'dart:io';

import 'package:test/test.dart';

/// Source guards on the opt-in "runners nearby" data layer (issue #466,
/// decisions §270).
///
/// The privacy design lives entirely inside the `discoverable_runners_near`
/// SECURITY DEFINER reader: it centres on the caller's own stored area, applies
/// every eligibility filter, and returns a coarse distance BUCKET rather than a
/// coordinate or exact metres. The client's whole job is to not go around it.
/// These are the properties a future refactor could quietly break, and they
/// are static — a client-side read of `user_settings.discoverable_area` is
/// well-formed and would simply return the caller's own row, so a wire test
/// against a single-account local stack would not catch it.
void main() {
  final src = File('lib/src/api_client.dart').readAsStringSync();
  final start = src.indexOf('Future<List<NearbyRunner>> fetchNearbyRunners(');
  final end = start < 0
      ? -1
      : src.indexOf('Future<String?> setDiscoverableArea(', start);
  final fetch = start < 0
      ? ''
      : src.substring(start, end == -1 ? src.length : end);

  test('fetchNearbyRunners exists', () {
    expect(fetch, isNotEmpty, reason: 'the method moved or was renamed');
  });

  test('the nearby list comes from the definer RPC, not from a table read', () {
    expect(
      fetch.contains("rpc('discoverable_runners_near'"),
      isTrue,
      reason: 'only the SECURITY DEFINER reader applies the opt-in, minor, '
          'shadow_hidden, search-opt-out and block filters',
    );
    expect(
      fetch.contains("from('user_settings')"),
      isFalse,
      reason: 'no client read of user_settings belongs on this path',
    );
    expect(
      fetch.contains('discoverable_area'),
      isFalse,
      reason: 'the coarse centroid must never be selected by a client — the '
          'RPC returns a bucket precisely so no coordinate crosses the wire',
    );
  });

  test('a signed-out caller never reaches the RPC', () {
    final guard = fetch.indexOf('if (viewerId == null) return const [];');
    final rpc = fetch.indexOf("rpc('discoverable_runners_near'");
    expect(guard, greaterThan(0),
        reason: 'the signed-out early return must be present');
    expect(rpc, greaterThan(guard),
        reason: 'the RPC call must sit after the signed-out guard');
  });

  test('only the coarse bucket is carried into the model', () {
    expect(fetch.contains("row['bucket']"), isTrue);
    expect(
      RegExp(r"row\['(distance|distance_m|lat|lng|longitude|latitude)'\]")
          .hasMatch(fetch),
      isFalse,
      reason: 'a distance or coordinate field must not be read off the row',
    );
  });

  test('the area writers go through their definer RPCs', () {
    for (final rpc in [
      'set_discoverable_area',
      'clear_discoverable_area',
      'my_discoverable_area',
    ]) {
      expect(src.contains("rpc('$rpc'"), isTrue,
          reason: '$rpc must be called through the RPC, not a column write');
    }
  });

  test('the settings key is registered, not spelled inline', () {
    final settings = File('lib/src/settings_service.dart').readAsStringSync();
    expect(
      settings.contains("discoverableNearby = 'discoverable_nearby'"),
      isTrue,
      reason: 'the pref the reader gates on must be a registered SettingsKey',
    );
  });
}
