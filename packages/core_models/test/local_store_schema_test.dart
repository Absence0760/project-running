import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  group('localStoreRecordVersion', () {
    test('reads the stamped version', () {
      expect(
        localStoreRecordVersion({kLocalStoreVersionKey: 3, 'row': {}}),
        3,
      );
    });

    test('an unstamped (legacy) record is version 0', () {
      expect(localStoreRecordVersion({'row': {}}), kLocalStoreLegacyVersion);
      expect(kLocalStoreLegacyVersion, 0);
    });

    test('a non-numeric version stamp is treated as legacy', () {
      expect(
        localStoreRecordVersion({kLocalStoreVersionKey: 'oops'}),
        kLocalStoreLegacyVersion,
      );
    });

    test('the current schema version is positive', () {
      expect(kLocalStoreSchemaVersion, greaterThan(kLocalStoreLegacyVersion));
    });
  });
}
