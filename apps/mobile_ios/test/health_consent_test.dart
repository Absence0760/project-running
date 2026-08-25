import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/health_consent.dart';

UserProfileRow _row({DateTime? dob, DateTime? consentAt}) => UserProfileRow(
      id: 'u1',
      shadowHidden: false,
      dateOfBirth: dob,
      healthDataConsentAt: consentAt,
    );

void main() {
  final consented = _row(
    dob: DateTime.utc(1978, 4, 9),
    consentAt: DateTime.utc(2026, 8, 1, 9),
  );
  final noConsent = _row(dob: DateTime.utc(1978, 4, 9));

  test('a date on record under consent is usable', () {
    expect(healthUseDobState(consented), HealthUseDobState.usable);
    expect(healthUseDob(consented), '1978-04-09');
  });

  test('a date on record without the Art 9 stamp is withheld from health use',
      () {
    // The column is still populated — the under-18 search floor depends on it
    // (§ 718) — but a masters calibration or an age grade is an Art 9 use.
    expect(healthUseDobState(noConsent), HealthUseDobState.consentWithheld);
    expect(healthUseDob(noConsent), isNull);
  });

  test('consentWithheld is a distinct state so a surface can say why', () {
    // Not folded into `absent`: "you never told us" and "you told us and asked
    // us not to use it" are different sentences to show the runner.
    expect(healthUseDobState(noConsent),
        isNot(equals(healthUseDobState(_row()))));
  });

  test('no date on record grades absent, consented or not', () {
    expect(healthUseDobState(_row()), HealthUseDobState.absent);
    expect(healthUseDobState(_row(consentAt: DateTime.utc(2026, 8, 1, 9))),
        HealthUseDobState.absent);
    expect(healthUseDob(_row()), isNull);
  });

  test('a missing row grades absent and yields no date', () {
    expect(healthUseDobState(null), HealthUseDobState.absent);
    expect(healthUseDob(null), isNull);
  });

  test('a full timestamp normalises to the leading YYYY-MM-DD', () {
    // `ageOnDate` reads only the leading date; handing it a timestamp would
    // still work, but both platforms return the same 10 characters so a
    // divergence in the column's rendering can never become a divergence here.
    expect(
      healthUseDob(_row(
        dob: DateTime.utc(1978, 4, 9, 13, 30),
        consentAt: DateTime.utc(2026, 8, 1, 9),
      )),
      '1978-04-09',
    );
  });
}
