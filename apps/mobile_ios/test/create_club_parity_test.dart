import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../lib/social_service.dart';

/// Parity tests for `SocialService.createClub` — the insert-body
/// shape must match `apps/web/src/lib/data.ts:createClub` so a club
/// created on either platform stores identically.
///
/// History: mobile + web diverged in four ways before this round
///   1. Mobile didn't trim `name` — web does `input.name.trim()`.
///   2. Mobile didn't normalise `description` or `locationLabel` to
///      "trim → empty becomes null", so whitespace-only inputs
///      survived to the DB on the mobile path.
///   3. Mobile never generated `invite_token`. The column has no
///      DB-side default, so invite-only clubs created from mobile
///      shipped with a null token and could not be shared via a
///      join link.
///   4. Mobile didn't retry on slug collisions (23505). Two users
///      creating the same-named club at the same time would have
///      the second one fail with a raw Postgres error.
///
/// The retry is a network interaction, so this file pins the rest of
/// the parity via the pure `buildCreateClubBody` + `genInviteToken`
/// helpers. The retry itself is observed at the integration-test
/// layer (`services_integration_test.dart`).
void main() {
  const ownerId = 'user-abc-123';

  group('buildCreateClubBody — name normalisation', () {
    test('name is trimmed', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: '  Hackney Half  ',
        slug: 'hackney-half',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(body['name'], 'Hackney Half');
    });

    test('internal whitespace inside name is preserved', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: '  Hackney   Half  ',
        slug: 'hackney-half',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(body['name'], 'Hackney   Half');
    });
  });

  group('buildCreateClubBody — description / locationLabel normalisation', () {
    test('null description stays null', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'C',
        slug: 'c',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(body['description'], isNull);
    });

    test('empty description collapses to null', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'C',
        slug: 'c',
        description: '',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(body['description'], isNull);
    });

    test('whitespace-only description collapses to null', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'C',
        slug: 'c',
        description: '   \t\n  ',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(body['description'], isNull);
    });

    test('non-empty description is trimmed but preserved', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'C',
        slug: 'c',
        description: '  Weekly long run from London Fields  ',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(body['description'], 'Weekly long run from London Fields');
    });

    test('locationLabel trim + empty→null follows the same contract', () {
      final blank = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'C',
        slug: 'c',
        locationLabel: '   ',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(blank['location_label'], isNull);

      final populated = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'C',
        slug: 'c',
        locationLabel: '  London Fields  ',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(populated['location_label'], 'London Fields');
    });
  });

  group('buildCreateClubBody — column set', () {
    test('every canonical column is present', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'Hackney Half',
        slug: 'hackney-half',
        description: 'desc',
        locationLabel: 'London Fields',
        isPublic: false,
        joinPolicy: 'invite',
        inviteToken: 'a' * 32,
      );
      expect(body['owner_id'], ownerId);
      expect(body['name'], 'Hackney Half');
      expect(body['slug'], 'hackney-half');
      expect(body['description'], 'desc');
      expect(body['location_label'], 'London Fields');
      expect(body['is_public'], false);
      expect(body['join_policy'], 'invite');
      expect(body['invite_token'], 'a' * 32);
    });

    test('inviteToken=null is preserved as null (open/request policies)', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'C',
        slug: 'c',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(body.containsKey('invite_token'), isTrue);
      expect(body['invite_token'], isNull);
    });
  });

  group('genInviteToken — parity with web genToken()', () {
    test('produces a 32-hex-character string', () {
      final token = SocialService.genInviteToken();
      expect(token, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(token), isTrue,
          reason: 'Token must be lowercase hex, same as web.');
    });

    test('two unseeded calls produce different tokens '
        '(no static buffer / no shared rng reuse)', () {
      final a = SocialService.genInviteToken();
      final b = SocialService.genInviteToken();
      expect(a, isNot(equals(b)));
    });

    test('deterministic with a seeded Random — every byte renders to two '
        'hex chars (no missing leading zeros)', () {
      // Pin the format: 16 bytes → 32 hex chars, with leading zeros
      // preserved. A naive `b.toRadixString(16)` would drop the leading
      // zero on bytes < 0x10, producing a 31-char token that the
      // server's unique-index would still accept but that would diverge
      // from web's `padStart(2, '0')` output.
      final seeded = SocialService.genInviteToken(rng: Random(0));
      expect(seeded, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(seeded), isTrue);
    });

    test('handles a zero-emitting Random — every byte renders as "00"',
        () {
      // Construct a Random that always returns 0 by hand-rolling a tiny
      // fake (Dart's Random doesn't expose a "fixed-value" mode). The
      // test asserts the padding behaviour, the bit most likely to
      // regress when porting from web's `padStart(2, '0')`.
      final token = SocialService.genInviteToken(rng: _ZeroRandom());
      expect(token, '0' * 32);
    });
  });

  group('normaliseClubLink — XSS gate (web parity)', () {
    test('keeps http(s) URLs, trimmed', () {
      expect(SocialService.normaliseClubLink('https://example.com'),
          'https://example.com');
      expect(SocialService.normaliseClubLink('  http://example.com  '),
          'http://example.com');
    });

    test('drops empty / whitespace to null', () {
      expect(SocialService.normaliseClubLink(null), isNull);
      expect(SocialService.normaliseClubLink(''), isNull);
      expect(SocialService.normaliseClubLink('   '), isNull);
    });

    test('drops non-http(s) schemes (javascript:/data:/ftp:)', () {
      expect(SocialService.normaliseClubLink('javascript:alert(1)'), isNull);
      expect(SocialService.normaliseClubLink('data:text/html,x'), isNull);
      expect(SocialService.normaliseClubLink('ftp://example.com'), isNull);
      expect(SocialService.normaliseClubLink('example.com'), isNull);
    });

    test('buildCreateClubBody normalises every link column', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: ownerId,
        name: 'Club',
        slug: 'club',
        isPublic: true,
        joinPolicy: 'open',
        websiteUrl: 'https://club.example',
        instagramUrl: 'javascript:alert(1)',
        stravaUrl: '  ',
        facebookUrl: 'http://fb.example/club',
      );
      expect(body['website_url'], 'https://club.example');
      expect(body['instagram_url'], isNull);
      expect(body['strava_url'], isNull);
      expect(body['facebook_url'], 'http://fb.example/club');
    });
  });
}

class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}
