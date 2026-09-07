import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

Map<String, dynamic> _participant({Object? joinedAt, Object? completedAt}) =>
    <String, dynamic>{
      'challenge_id': 'ch-1',
      'user_id': 'u-1',
      'team_club_id': null,
      'joined_at': joinedAt,
      'completed_at': completedAt,
    };

Map<String, dynamic> _gear({Object? purchasedAt}) => <String, dynamic>{
      'id': 'g-1',
      'owner_id': 'u-1',
      'name': 'Pegasus 41',
      'kind': 'shoes',
      'purchased_at': purchasedAt,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

void main() {
  group('generated DateTime columns refuse what the platform rolls over', () {
    test('an impossible required instant throws rather than answering', () {
      // `DateTime.parse` reads this as 2027-02-18T04:40:39Z — a confident
      // wrong instant nothing downstream can question.
      expect(DateTime.parse('2026-13-45T99:99:99Z'),
          DateTime.utc(2027, 2, 18, 4, 40, 39));
      expect(
        () => ChallengeParticipantRow.fromJson(
            _participant(joinedAt: '2026-13-45T99:99:99Z')),
        throwsFormatException,
      );
    });

    test('an impossible nullable instant is no answer, not a wrong one', () {
      expect(DateTime.parse('2026-06-32'), DateTime(2026, 7, 2));
      final row = ChallengeParticipantRow.fromJson(
        _participant(joinedAt: '2026-06-14T07:00:00Z', completedAt: '2026-06-32'),
      );
      expect(row.completedAt, isNull);
    });

    test('a date column refuses 29 February outside a leap year', () {
      expect(DateTime.parse('2027-02-29'), DateTime(2027, 3, 1));
      expect(GearRow.fromJson(_gear(purchasedAt: '2027-02-29')).purchasedAt,
          isNull);
      expect(GearRow.fromJson(_gear(purchasedAt: '2028-02-29')).purchasedAt,
          DateTime(2028, 2, 29));
    });

    test('a usable value decodes to exactly what the platform reads', () {
      final row = ChallengeParticipantRow.fromJson(_participant(
        joinedAt: '2026-06-14T07:30:00Z',
        completedAt: '2026-06-14T09:30:00+02:00',
      ));
      expect(row.joinedAt, DateTime.parse('2026-06-14T07:30:00Z'));
      expect(row.joinedAt.isUtc, isTrue);
      expect(row.completedAt, DateTime.parse('2026-06-14T09:30:00+02:00'));
    });

    test('an absent or mistyped required column names the field it failed on',
        () {
      for (final bad in <Object?>[null, '', 42, <String, dynamic>{}]) {
        expect(
          () => ChallengeParticipantRow.fromJson(_participant(joinedAt: bad)),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('joined_at'))),
          reason: '$bad',
        );
      }
    });

    test('an absent or mistyped nullable column stays null', () {
      for (final bad in <Object?>[null, '', 42, <String, dynamic>{}]) {
        expect(
          ChallengeParticipantRow.fromJson(_participant(
                  joinedAt: '2026-06-14T07:00:00Z', completedAt: bad))
              .completedAt,
          isNull,
          reason: '$bad',
        );
      }
    });
  });

  test('no generated DateTime column reads through the rolling parser', () {
    final source = File('lib/src/generated/db_rows.dart').readAsStringSync();
    expect(source.contains('DateTime.parse('), isFalse);
    expect(source.contains('DateTime.tryParse('), isFalse);
    expect(source.contains('parseIsoStrictRequired('), isTrue);
    expect(source.contains('parseIsoStrictValue('), isTrue);
  });
}
