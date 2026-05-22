import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Unit tests for the generated `ClubRow` row class — specifically
/// the JSON ↔ Dart roundtrip for the `is_verified` field added in
/// migration 20260909_001. Defending against:
///   1. Schema codegen drift where a regen drops the field
///   2. A regression that flips the default from false → true
///      (which would mark every club as official until manual
///      moderation says otherwise — catastrophic)
///   3. A column rename that silently breaks the wire format
void main() {
  group('ClubRow.is_verified', () {
    test('defaults to false when the column is absent from the JSON', () {
      // Wire compatibility: rows fetched from an older PostgREST
      // cache or a test fixture that pre-dates the migration must
      // round-trip with the safe `false` default, NOT crash on the
      // null cast. This is the "the badge is the explicit opt-in,
      // not the implicit default" contract.
      final row = ClubRow.fromJson({
        'id': '00000000-0000-0000-0000-000000000000',
        'owner_id': '00000000-0000-0000-0000-000000000000',
        'name': 'Old fixture without is_verified',
        'slug': 'old-fixture',
        'join_policy': 'open',
        'member_count': 0,
      });
      expect(
        row.isVerified,
        isFalse,
        reason: 'A row without the `is_verified` key must default to '
            'FALSE — never grant the badge implicitly.',
      );
    });

    test('parses true when the column is present and true', () {
      final row = ClubRow.fromJson({
        'id': '00000000-0000-0000-0000-000000000001',
        'owner_id': '00000000-0000-0000-0000-000000000000',
        'name': 'Official Marathon',
        'slug': 'official-marathon',
        'is_verified': true,
        'join_policy': 'open',
        'member_count': 100,
      });
      expect(row.isVerified, isTrue);
    });

    test('parses false when the column is present and false', () {
      final row = ClubRow.fromJson({
        'id': '00000000-0000-0000-0000-000000000002',
        'owner_id': '00000000-0000-0000-0000-000000000000',
        'name': 'Fan Marathon',
        'slug': 'fan-marathon',
        'is_verified': false,
        'join_policy': 'open',
        'member_count': 1,
      });
      expect(row.isVerified, isFalse);
    });

    test(
        'toJson serialises is_verified to the wire-format key '
        '(snake_case) for roundtrip stability',
        () {
      // PostgREST expects snake_case; the Dart field is camelCase
      // (`isVerified`) but the JSON key is `is_verified`. Pin so
      // a refactor that drops the explicit `colIsVerified` constant
      // doesn't silently serialise to the wrong key.
      const row = ClubRow(
        id: 'id1',
        ownerId: 'owner1',
        name: 'name',
        slug: 'slug',
        joinPolicy: 'open',
        memberCount: 0,
        isVerified: true,
      );
      final json = row.toJson();
      expect(json.containsKey('is_verified'), isTrue);
      expect(json['is_verified'], true);
      // Negative pin: the camelCase key must NOT be in the JSON
      // (PostgREST would reject the column).
      expect(json.containsKey('isVerified'), isFalse);
    });

    test(
        'fromJson(toJson(row)) is identity for a row with isVerified=true',
        () {
      const original = ClubRow(
        id: '11111111-1111-1111-1111-111111111111',
        ownerId: '22222222-2222-2222-2222-222222222222',
        name: 'Roundtrip Club',
        slug: 'roundtrip-club',
        joinPolicy: 'open',
        memberCount: 42,
        isVerified: true,
      );
      final roundTripped = ClubRow.fromJson(original.toJson());
      expect(roundTripped.id, original.id);
      expect(roundTripped.name, original.name);
      expect(roundTripped.slug, original.slug);
      expect(roundTripped.isVerified, original.isVerified);
      expect(roundTripped.memberCount, original.memberCount);
    });

    test('colIsVerified constant is pinned at "is_verified"', () {
      // Source-pinned so a refactor that renames the constant
      // doesn\'t silently miss any callsite that referenced it.
      expect(ClubRow.colIsVerified, 'is_verified');
    });
  });
}
