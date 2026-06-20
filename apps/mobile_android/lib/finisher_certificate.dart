/// Pure finisher-certificate shaping. Dart twin of the web
/// `apps/web/src/lib/runs/finisher_certificate.ts` formatting + eligibility
/// logic. Web renders an SVG string it rasterises to a PNG download; mobile
/// renders the same facts natively (RepaintBoundary -> PNG share, the
/// run-share-card idiom) so these helpers carry only the unit/locale-agnostic
/// shaping the two surfaces must agree on.
library;

/// A finisher result is certificate-eligible iff they actually finished and an
/// organiser approved the result — the same gate web's leaderboard applies
/// before showing its Download-certificate button.
bool isCertificateEligible({
  required String finisherStatus,
  required bool organiserApproved,
}) =>
    finisherStatus == 'finished' && organiserApproved;

String formatCertificateTime(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

String formatCertificateDistance(double metres, {required bool useMiles}) {
  if (useMiles) {
    return '${(metres / 1609.344).toStringAsFixed(2)} mi';
  }
  return '${(metres / 1000).toStringAsFixed(2)} km';
}

/// English ordinal — "1st" / "2nd" / "3rd" / "11th" / "21st". Mirrors web's
/// `ordinal`. The placing line on the card is the only ordinal use and web
/// keeps it English on the certificate itself.
String ordinalPlace(int n) {
  const suffixes = ['th', 'st', 'nd', 'rd'];
  final v = n % 100;
  // JS `%` keeps the sign of the dividend, so `(v - 20) % 10` is negative for
  // v < 20 and indexes out of range -> the web's `?? s[v] ?? s[0]` fallthrough
  // picks "th". Dart's `remainder` matches JS's sign behaviour; `%` does not.
  final idx = (v - 20).remainder(10);
  final suffix = (idx >= 0 && idx < suffixes.length ? suffixes[idx] : null) ??
      (v >= 0 && v < suffixes.length ? suffixes[v] : null) ??
      suffixes[0];
  return '$n$suffix';
}
