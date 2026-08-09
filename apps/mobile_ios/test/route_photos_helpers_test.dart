import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normaliseRoutePhotoCaption', () {
    test('trims and keeps a non-empty caption', () {
      expect(ApiClient.normaliseRoutePhotoCaption('  hi  '), 'hi');
    });

    test('whitespace-only / empty / null collapse to null', () {
      expect(ApiClient.normaliseRoutePhotoCaption('   '), isNull);
      expect(ApiClient.normaliseRoutePhotoCaption(''), isNull);
      expect(ApiClient.normaliseRoutePhotoCaption(null), isNull);
    });
  });
}
