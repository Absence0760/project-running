import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// Parity tests for `ApiClient.normaliseRunPhotoCaption` — the pure
/// helper that backs both `addRunPhoto` and `updateRunPhotoCaption`.
/// Mirrors `apps/web/src/lib/data.ts`'s `input.caption?.trim() || null`
/// contract used in both `addRunPhoto` and `updateRunPhotoCaption`
/// on web.
///
/// History: mobile previously wrote captions through unchanged. A
/// caption like `"   "` would survive to the DB as a non-null
/// whitespace string and break the gallery's `caption !== null`
/// rendering branches (the bubble would show, but blank).
void main() {
  group('normaliseRunPhotoCaption', () {
    test('null caption stays null', () {
      expect(ApiClient.normaliseRunPhotoCaption(null), isNull);
    });

    test('empty string collapses to null', () {
      expect(ApiClient.normaliseRunPhotoCaption(''), isNull);
    });

    test('whitespace-only caption collapses to null', () {
      expect(ApiClient.normaliseRunPhotoCaption('   \t\n  '), isNull);
    });

    test('non-empty caption is trimmed but preserved', () {
      expect(
        ApiClient.normaliseRunPhotoCaption('  Sunset over Hackney Marshes  '),
        'Sunset over Hackney Marshes',
      );
    });

    test('internal whitespace is preserved (only edges trimmed)', () {
      expect(
        ApiClient.normaliseRunPhotoCaption('  one    two\nthree  '),
        'one    two\nthree',
      );
    });

    test('single non-whitespace character round-trips intact', () {
      // A user posting just an emoji caption is a real flow — make
      // sure the over-eager `.trim() || null` doesn't drop it.
      expect(ApiClient.normaliseRunPhotoCaption('🌅'), '🌅');
    });

    test('caption that is "0" stays as "0" — the JS `|| null` trap', () {
      // Web's `caption?.trim() || null` relies on the empty string
      // being falsy. A literal "0" is *truthy* in JS, so web preserves
      // it; the Dart port must do the same. This test pins that the
      // helper doesn't accidentally use Dart's truthy-int semantics
      // (which don't exist for strings, but a future refactor that
      // introduces them would regress this case).
      expect(ApiClient.normaliseRunPhotoCaption('0'), '0');
    });
  });
}
