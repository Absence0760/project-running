// Mirror suite for the `club_slug` TS↔Dart parity pair. Every case here has a
// twin in `apps/web/src/lib/social/club_slug.test.ts`; the two must answer
// identically, which is the whole reason the module exists (decisions § 1279).

import 'package:flutter_test/flutter_test.dart';

import '../lib/club_slug.dart';

void main() {
  test('lower-cases and hyphenates a plain name', () {
    expect(clubSlug('Brighton Road Runners'), 'brighton-road-runners');
  });

  test('U+0130 folds to a bare i, so `İzmir` is `izmir` on both runtimes', () {
    // The one code point reachable in Latin text where the two runtimes'
    // `toLowerCase` disagree (decisions § 1251). Dart folded it to `i` and JS
    // to `i` + U+0307, which the strip below used to turn into a separator:
    // `izmir` on the phone against `i-zmir` on the web, for the same name.
    expect(clubSlug('İzmir'), 'izmir');
    expect(clubSlug('İzmir Koşu Kulübü'), 'izmir-kosu-kulubu');
  });

  test('a stripped diacritic leaves its base letter rather than a separator',
      () {
    // The reason the fold is the right instrument and not merely a parity
    // patch: `z-rich-runners` is a worse URL than `zurich-runners`.
    expect(clubSlug('Zürich Runners'), 'zurich-runners');
    expect(clubSlug('Café des Coureurs'), 'cafe-des-coureurs');
  });

  test('a letter with no canonical decomposition still strips', () {
    // The fold deliberately does not transliterate `ß` / `ø` / `đ` —
    // inventing an equivalence Unicode does not have is out of scope (§ 856).
    expect(clubSlug('Straße Läufer'), 'stra-e-laufer');
  });

  test('a run of separators collapses to one hyphen', () {
    expect(clubSlug('Run   Club --- 2026'), 'run-club-2026');
  });

  test('leading and trailing separators are stripped', () {
    expect(clubSlug('  ...Trail Club!!!  '), 'trail-club');
  });

  test('digits survive', () {
    expect(clubSlug('5k Every Day'), '5k-every-day');
  });

  test('a name with no character that survives the fold yields the empty string',
      () {
    // Both callers act on empty: the phone refuses the save and blames the
    // name field, the web substitutes a literal `club`.
    expect(clubSlug('!!!'), '');
    expect(clubSlug(''), '');
    expect(clubSlug('   '), '');
  });

  test('a script the fold does not romanise yields the empty string', () {
    // Folding is accent + case only, so a name written entirely outside
    // [a-z0-9] has no slug — the same answer on both platforms, which is what
    // keeps the phone's "no usable characters" refusal honest.
    expect(clubSlug('Ελλάδα'), '');
    expect(clubSlug('Бегуны'), '');
  });

  test('the slug is capped at kClubSlugMaxLen', () {
    // The phone had no cap at all before this module, so a long name produced
    // a 48-character URL from one client and an unbounded one from the other.
    final slug = clubSlug('a' * 200);
    expect(slug.length, kClubSlugMaxLen);
    expect(slug, 'a' * kClubSlugMaxLen);
  });

  test('the cap never leaves a trailing hyphen', () {
    // The cut can land on a separator, and a slug ending in a hyphen is the
    // one shape the edge strip exists to prevent.
    final name = '${'a' * (kClubSlugMaxLen - 1)} bravo';
    expect(clubSlug(name), 'a' * (kClubSlugMaxLen - 1));
  });

  test('the cap counts folded characters, not input characters', () {
    // `Ü` is one input character and one folded character; a cap applied
    // before the fold would count the combining mark NFD produces.
    expect(clubSlug('Ü' * 60), 'u' * kClubSlugMaxLen);
  });
}
