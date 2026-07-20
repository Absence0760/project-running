import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// Mirror of apps/web/src/lib/social/profile_query.test.ts — keep in lockstep.
void main() {
  const uuid = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

  test('bare uuid is returned lowercased', () {
    expect(extractProfileId(uuid), uuid);
    expect(extractProfileId('  $uuid  '), uuid);
  });

  test('an uppercase uuid is normalised to lowercase', () {
    expect(extractProfileId(uuid.toUpperCase()), uuid);
  });

  test('a /u/<uuid> path resolves', () {
    expect(extractProfileId('/u/$uuid'), uuid);
  });

  test('a full profile URL resolves', () {
    expect(extractProfileId('https://threkir.com/u/$uuid'), uuid);
  });

  test('a /u/<uuid> URL with a query/tab or trailing slash resolves', () {
    expect(extractProfileId('https://threkir.com/u/$uuid?tab=runs'), uuid);
    expect(extractProfileId('/u/$uuid/'), uuid);
    expect(extractProfileId('/u/$uuid#top'), uuid);
  });

  test('a plain name is not a profile id', () {
    expect(extractProfileId('Jane Doe'), isNull);
    expect(extractProfileId('janedoe'), isNull);
    expect(extractProfileId('@janedoe'), isNull);
  });

  test('empty / whitespace input is null', () {
    expect(extractProfileId(''), isNull);
    expect(extractProfileId('   '), isNull);
  });

  test('a malformed uuid is not accepted', () {
    expect(extractProfileId('3f2504e0-4f89-41d3-9a0c'), isNull);
    expect(extractProfileId('zzzzzzzz-4f89-41d3-9a0c-0305e82c3301'), isNull);
  });

  test('a uuid embedded in arbitrary text (not after /u/) is ignored', () {
    expect(extractProfileId('hello $uuid world'), isNull);
    expect(extractProfileId('/runs/$uuid'), isNull);
  });
}
