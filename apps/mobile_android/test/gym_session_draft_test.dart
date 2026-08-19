import 'package:flutter_test/flutter_test.dart';
import '../lib/gym_session_draft.dart';

void main() {
  group('hasGymSessionDraft (decisions.md § 662)', () {
    test('a JSON object under the key is an in-flight draft', () {
      expect(
        hasGymSessionDraft({
          'gym_session_draft': {'saved_at': '2026-08-14T10:05:00Z', 'results': []},
        }),
        isTrue,
      );
      expect(hasGymSessionDraft({'gym_session_draft': <String, Object?>{}}), isTrue);
    });

    test('anything that is not a JSON object is not a draft', () {
      // The other two rails ask `jsonb_typeof(...) = 'object'` / `isJsonObject`;
      // an array or a scalar has to read as a session performed here too.
      for (final marker in <Object?>[<dynamic>[], <dynamic>['a'], 'draft', 7, true, null]) {
        expect(hasGymSessionDraft({'gym_session_draft': marker}), isFalse,
            reason: 'marker $marker');
      }
    });

    test('a missing key, or a bag that is not an object, is not a draft', () {
      expect(hasGymSessionDraft(const <String, Object?>{}), isFalse);
      expect(hasGymSessionDraft({'routine_id': 'r1'}), isFalse);
      expect(hasGymSessionDraft(null), isFalse);
      expect(hasGymSessionDraft(<dynamic>['gym_session_draft']), isFalse);
      expect(hasGymSessionDraft('gym_session_draft'), isFalse);
    });
  });
}
