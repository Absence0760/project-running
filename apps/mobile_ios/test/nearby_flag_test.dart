import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/nearby_flag.dart';

void main() {
  group('nearbyRunnersEnabled — pure parse', () {
    test('truthy only for the explicit affirmatives web accepts', () {
      for (final v in [
        '1',
        'true',
        'TRUE',
        ' True ',
        'yes',
        'YES',
        'on',
        'On',
      ]) {
        expect(nearbyRunnersEnabled(v), isTrue, reason: '"$v" should enable');
      }
    });

    test('fail-closed for unset / empty / negative / unrecognised', () {
      for (final v in [
        null,
        '',
        '  ',
        '0',
        'false',
        'off',
        'no',
        'enabled',
        'truthy',
        '2',
      ]) {
        expect(nearbyRunnersEnabled(v), isFalse,
            reason: '"${v ?? '<null>'}" must stay off');
      }
    });
  });

  group('nearbyRunnersGate — env binding', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      dotenv.loadFromString(isOptional: true);
    });

    setUp(() => dotenv.env.remove(kNearbyRunnersEnvKey));

    test('off when the flag is unset', () {
      expect(nearbyRunnersGate, isFalse);
    });

    test('on only for an explicit affirmative', () {
      dotenv.env[kNearbyRunnersEnvKey] = 'false';
      expect(nearbyRunnersGate, isFalse);
      dotenv.env[kNearbyRunnersEnvKey] = 'true';
      expect(nearbyRunnersGate, isTrue);
    });
  });

  test('main.dart forwards the flag from --dart-define into dotenv', () {
    // Release builds never load .env.development, so a flag missing from the
    // String.fromEnvironment block in main.dart is unreachable in prod — the
    // deploy gate could never be flipped on.
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main.contains("String.fromEnvironment('$kNearbyRunnersEnvKey')"),
      isTrue,
      reason: '$kNearbyRunnersEnvKey must be read as a dart-define',
    );
    expect(
      main.contains("'$kNearbyRunnersEnvKey=\$enableNearbyRunnersDef'"),
      isTrue,
      reason: '$kNearbyRunnersEnvKey must be merged into the dotenv string',
    );
  });
}
