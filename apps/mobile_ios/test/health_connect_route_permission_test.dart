import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/health_connect_importer.dart';

HcRoutePoint _p(double lat, double lng, int minute) => (
      lat: lat,
      lng: lng,
      at: DateTime.utc(2026, 6, 1, 8, minute),
      altitudeMetres: null,
    );

Run _hcRun({
  String id = 'run-1',
  String? externalId = 'healthconnect:session-a',
  RunSource source = RunSource.healthconnect,
  List<Waypoint> track = const [],
  Map<String, dynamic>? metadata,
}) =>
    Run(
      id: id,
      startedAt: DateTime.utc(2026, 6, 1, 8),
      duration: const Duration(minutes: 30),
      distanceMetres: 5500,
      track: track,
      source: source,
      externalId: externalId,
      metadata: metadata,
      createdAt: DateTime.utc(2026, 6, 1, 9),
    );

/// ~5.5 km of northward points, one per 30 s — long enough that
/// `enrichMetadataWithEmbeddedBests` finds a 5 km effort inside it.
List<Waypoint> _longTrack() => [
      for (var i = 0; i < 51; i++)
        Waypoint(
          lat: 51.5 + i * 0.001,
          lng: -0.12,
          timestamp: DateTime.utc(2026, 6, 1, 8, 0, i * 30),
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('requestHealthRoutePermission (#664)', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(healthRoutePermissionChannel, null);
    });

    test('off Android it refuses without ever reaching the channel', () async {
      var invocations = 0;
      messenger.setMockMethodCallHandler(healthRoutePermissionChannel,
          (call) async {
        invocations++;
        return true;
      });

      expect(await requestHealthRoutePermission(isAndroid: false), isFalse);
      // Negative control: an iOS build must not even attempt the call. The
      // same WORKOUT_ROUTE type maps to HKSeriesType.workoutRoute() there, so
      // a stray request would widen what the iOS binary collects.
      expect(invocations, 0);
    });

    test('a granted request reports true and asks for exactly one method',
        () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(healthRoutePermissionChannel,
          (call) async {
        methods.add(call.method);
        return true;
      });

      expect(await requestHealthRoutePermission(isAndroid: true), isTrue);
      expect(methods, ['requestRoutePermission']);
    });

    test('a refused request reports false — never throws', () async {
      messenger.setMockMethodCallHandler(
          healthRoutePermissionChannel, (call) async => false);
      expect(await requestHealthRoutePermission(isAndroid: true), isFalse);
    });

    test('a null answer is a refusal, not a grant', () async {
      // The bridge answers false when Health Connect isn't installed; a null
      // can only come from a codec surprise, and must fail closed.
      messenger.setMockMethodCallHandler(
          healthRoutePermissionChannel, (call) async => null);
      expect(await requestHealthRoutePermission(isAndroid: true), isFalse);
    });

    test('a thrown PlatformException is swallowed into a refusal', () async {
      messenger.setMockMethodCallHandler(healthRoutePermissionChannel,
          (call) async {
        throw PlatformException(code: 'in_flight');
      });
      expect(await requestHealthRoutePermission(isAndroid: true), isFalse);
    });

    test('a missing native bridge is a refusal, not a crashed import',
        () async {
      // No handler registered at all — the MissingPluginException path an
      // older APK with new Dart would hit.
      expect(await requestHealthRoutePermission(isAndroid: true), isFalse);
    });
  });

  group('HealthConnectImporter.withheldRouteSessionIds (#664)', () {
    test('a session whose route came back empty is withheld', () {
      // ConsentRequired is rendered by the plugin as a WORKOUT_ROUTE point
      // with zero locations.
      expect(
        HealthConnectImporter.withheldRouteSessionIds([
          (uuid: 'session-a', points: const <HcRoutePoint>[]),
        ]),
        {'session-a'},
      );
    });

    test('a session that released its route is NOT withheld', () {
      expect(
        HealthConnectImporter.withheldRouteSessionIds([
          (uuid: 'session-a', points: [_p(51.5, -0.12, 0), _p(51.51, -0.13, 1)]),
        ]),
        isEmpty,
      );
    });

    test('a released-but-unusable route is not withheld either', () {
      // Negative control against conflating "dropped by the plausibility
      // screen" with "refused by Health Connect": these points exist, so
      // asking for the permission would buy the runner nothing.
      final routes = [
        (
          uuid: 'session-a',
          points: [_p(double.nan, -0.12, 0), _p(51.5, double.infinity, 1)],
        ),
      ];
      expect(HealthConnectImporter.withheldRouteSessionIds(routes), isEmpty);
      expect(HealthConnectImporter.tracksFromRoutePoints(routes), isEmpty);
    });

    test('only the withheld sessions come back from a mixed batch', () {
      expect(
        HealthConnectImporter.withheldRouteSessionIds([
          (uuid: 'has-route', points: [_p(51.5, -0.12, 0), _p(51.51, -0.13, 1)]),
          (uuid: 'withheld-1', points: const <HcRoutePoint>[]),
          (uuid: 'withheld-2', points: const <HcRoutePoint>[]),
        ]),
        {'withheld-1', 'withheld-2'},
      );
    });

    test('no routes at all means nothing to offer', () {
      expect(HealthConnectImporter.withheldRouteSessionIds([]), isEmpty);
    });
  });

  group('HealthConnectImporter.sessionIdOf (#664)', () {
    test('reads the session id back out of a Health Connect external_id', () {
      expect(HealthConnectImporter.sessionIdOf(_hcRun()), 'session-a');
    });

    test('a run from another source is never matched', () {
      // Negative control: the prefix alone must not be enough, or a Strava
      // run that happened to carry it would be rewritten.
      expect(
        HealthConnectImporter.sessionIdOf(
          _hcRun(source: RunSource.strava),
        ),
        isNull,
      );
    });

    test('a foreign prefix is not a Health Connect session', () {
      expect(
        HealthConnectImporter.sessionIdOf(
          _hcRun(externalId: 'strava:12345'),
        ),
        isNull,
      );
    });

    test('a null external_id is not a session', () {
      expect(HealthConnectImporter.sessionIdOf(_hcRun(externalId: null)), isNull);
    });

    test('a bare prefix with no id is not a session', () {
      expect(
        HealthConnectImporter.sessionIdOf(_hcRun(externalId: 'healthconnect:')),
        isNull,
      );
    });
  });

  group('HealthConnectImporter.runsWithBackfilledTracks (#664)', () {
    test('a trackless Health Connect run gains the released track', () {
      final track = _longTrack();
      final filled = HealthConnectImporter.runsWithBackfilledTracks(
        [_hcRun()],
        {'session-a': track},
      );

      expect(filled.length, 1);
      expect(filled.single.track, track);
    });

    test('every other field survives the rewrite', () {
      final filled = HealthConnectImporter.runsWithBackfilledTracks(
        [_hcRun(metadata: const {'imported_from': 'health_connect'})],
        {'session-a': _longTrack()},
      );

      final run = filled.single;
      expect(run.id, 'run-1');
      expect(run.startedAt, DateTime.utc(2026, 6, 1, 8));
      expect(run.duration, const Duration(minutes: 30));
      expect(run.distanceMetres, 5500);
      expect(run.source, RunSource.healthconnect);
      expect(run.externalId, 'healthconnect:session-a');
      expect(run.createdAt, DateTime.utc(2026, 6, 1, 9));
      expect(run.metadata!['imported_from'], 'health_connect');
    });

    test('the embedded bests are recomputed, as a routed import would', () {
      final filled = HealthConnectImporter.runsWithBackfilledTracks(
        [_hcRun()],
        {'session-a': _longTrack()},
      );
      expect(filled.single.metadata!['fastest_5k_s'], isA<int>());
    });

    test('a run that already has a track is left alone', () {
      // Negative control: Health Connect is not authoritative over geometry
      // the runner already has, and rewriting it would mark a synced run
      // dirty for nothing.
      final existing = [
        Waypoint(lat: 1, lng: 2, timestamp: DateTime.utc(2026)),
        Waypoint(lat: 1.1, lng: 2.1, timestamp: DateTime.utc(2026, 1, 1, 0, 1)),
      ];
      expect(
        HealthConnectImporter.runsWithBackfilledTracks(
          [_hcRun(track: existing)],
          {'session-a': _longTrack()},
        ),
        isEmpty,
      );
    });

    test('a run from another source is never rewritten', () {
      expect(
        HealthConnectImporter.runsWithBackfilledTracks(
          [_hcRun(source: RunSource.strava)],
          {'session-a': _longTrack()},
        ),
        isEmpty,
      );
    });

    test('a run whose session released nothing is left alone', () {
      expect(
        HealthConnectImporter.runsWithBackfilledTracks(
          [_hcRun()],
          {'some-other-session': _longTrack()},
        ),
        isEmpty,
      );
    });

    test('an empty released track is not written over a trackless run', () {
      expect(
        HealthConnectImporter.runsWithBackfilledTracks(
          [_hcRun()],
          {'session-a': const <Waypoint>[]},
        ),
        isEmpty,
      );
    });

    test('only the runs that changed come back', () {
      final filled = HealthConnectImporter.runsWithBackfilledTracks(
        [
          _hcRun(id: 'a', externalId: 'healthconnect:session-a'),
          _hcRun(id: 'b', externalId: 'healthconnect:session-b'),
          _hcRun(id: 'c', externalId: 'healthconnect:session-c'),
        ],
        {'session-b': _longTrack()},
      );
      expect(filled.map((r) => r.id), ['b']);
    });
  });

  // The permission string is matched by four files no compiler links: the
  // manifest, the Play-Console permissions XML, the Kotlin bridge and this
  // Dart constant. A mismatch is refused by the platform with no dialog and
  // no error the runner can act on.
  //
  // The iOS twin carries this file byte-identically but has no android/
  // tree, so these assertions run for real only from apps/mobile_android —
  // the same skip idiom the existing health-permission guards use.
  group('route permission agrees across manifest, Kotlin and Dart (#664)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    final permsXml =
        File('android/app/src/main/res/xml/health_permissions.xml');
    final bridge = File(
        'android/app/src/main/kotlin/com/threkir/app/HealthRoutePermissionBridge.kt');
    final mainActivity =
        File('android/app/src/main/kotlin/com/threkir/app/MainActivity.kt');

    test('the Dart constant is the plural read permission', () {
      expect(
        kHealthRoutePermission,
        'android.permission.health.READ_EXERCISE_ROUTES',
      );
    });

    test('the manifest declares exactly that string', () {
      if (!manifest.existsSync()) return;
      expect(manifest.readAsStringSync(), contains(kHealthRoutePermission));
    });

    test('the Play Console permissions XML declares it too', () {
      if (!permsXml.existsSync()) return;
      expect(permsXml.readAsStringSync(), contains(kHealthRoutePermission));
    });

    test('the bridge requests the androidx constant, not a copied literal',
        () {
      if (!bridge.existsSync()) return;
      final source = bridge.readAsStringSync();
      expect(
        source,
        contains('HealthPermission.PERMISSION_READ_EXERCISE_ROUTES'),
        reason:
            'Binding to the library constant is what keeps the requested '
            'string from drifting away from the one androidx sends.',
      );
      expect(
        source,
        contains("const val CHANNEL = \"run_app/health_route_permission\""),
      );
    });

    test('the bridge never asks for background health reads', () {
      if (!bridge.existsSync()) return;
      // Health Connect withholds routes from background reads even when the
      // grant is held, so PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND would buy
      // nothing while adding a permission to the Play declaration.
      expect(
        bridge.readAsStringSync(),
        isNot(contains('READ_HEALTH_DATA_IN_BACKGROUND')),
      );
    });

    test('the Dart channel name matches the Kotlin one', () {
      expect(healthRoutePermissionChannel.name,
          'run_app/health_route_permission');
    });

    test('MainActivity is a FlutterFragmentActivity that wires the bridge',
        () {
      if (!mainActivity.existsSync()) return;
      final source = mainActivity.readAsStringSync();
      // FlutterActivity extends android.app.Activity, so the health plugin's
      // `(activity as ComponentActivity).registerForActivityResult` cast
      // threw, GeneratedPluginRegistrant swallowed it, and every Health
      // Connect permission request answered false with no sheet shown.
      expect(source, contains('FlutterFragmentActivity'));
      expect(source, isNot(contains(': FlutterActivity(')));
      expect(source, contains('HealthRoutePermissionBridge(this)'));
    });
  });
}
