import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/route_photos.dart';

void main() {
  group('routePhotoExtensionForFilename', () {
    test('returns lowercase extension for a normal filename', () {
      expect(routePhotoExtensionForFilename('IMG_1234.PNG'), 'png');
      expect(routePhotoExtensionForFilename('photo.webp'), 'webp');
    });

    test('jpeg collapses to jpg', () {
      expect(routePhotoExtensionForFilename('photo.JPEG'), 'jpg');
      expect(routePhotoExtensionForFilename('photo.jpeg'), 'jpg');
    });

    test('heif collapses to heic', () {
      expect(routePhotoExtensionForFilename('IMG.heif'), 'heic');
      expect(routePhotoExtensionForFilename('IMG.HEIF'), 'heic');
    });

    test('files without an extension default to jpg', () {
      expect(routePhotoExtensionForFilename('photo'), 'jpg');
    });

    test('hidden / dotfile-style names default to jpg', () {
      expect(routePhotoExtensionForFilename('.gitkeep'), 'jpg');
    });

    test('multi-dot filenames take only the trailing extension', () {
      expect(routePhotoExtensionForFilename('my.route.cover.png'), 'png');
    });
  });

  group('routePhotoContentTypeForExtension', () {
    test('maps the supported image types', () {
      expect(routePhotoContentTypeForExtension('png'), 'image/png');
      expect(routePhotoContentTypeForExtension('webp'), 'image/webp');
      expect(routePhotoContentTypeForExtension('heic'), 'image/heic');
    });

    test('jpg defaults through the fallback branch', () {
      expect(routePhotoContentTypeForExtension('jpg'), 'image/jpeg');
    });

    test('unknown / empty extension also falls back to image/jpeg', () {
      expect(routePhotoContentTypeForExtension(''), 'image/jpeg');
      expect(routePhotoContentTypeForExtension('avif'), 'image/jpeg');
    });
  });

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
