import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/club_photos.dart';

void main() {
  group('clubPhotoExtensionForFilename', () {
    test('returns lowercase extension for a normal filename', () {
      expect(clubPhotoExtensionForFilename('IMG_1234.PNG'), 'png');
      expect(clubPhotoExtensionForFilename('photo.webp'), 'webp');
    });

    test('jpeg collapses to jpg', () {
      expect(clubPhotoExtensionForFilename('photo.JPEG'), 'jpg');
      expect(clubPhotoExtensionForFilename('photo.jpeg'), 'jpg');
    });

    test('heif collapses to heic', () {
      expect(clubPhotoExtensionForFilename('IMG.heif'), 'heic');
      expect(clubPhotoExtensionForFilename('IMG.HEIF'), 'heic');
    });

    test('files without an extension default to jpg', () {
      expect(clubPhotoExtensionForFilename('photo'), 'jpg');
    });

    test('hidden / dotfile-style names default to jpg', () {
      expect(clubPhotoExtensionForFilename('.gitkeep'), 'jpg');
    });

    test('multi-dot filenames take only the trailing extension', () {
      expect(clubPhotoExtensionForFilename('my.club.cover.png'), 'png');
    });
  });

  group('clubPhotoContentTypeForExtension', () {
    test('maps the supported image types', () {
      expect(clubPhotoContentTypeForExtension('png'), 'image/png');
      expect(clubPhotoContentTypeForExtension('webp'), 'image/webp');
      expect(clubPhotoContentTypeForExtension('heic'), 'image/heic');
    });

    test('jpg defaults through the fallback branch', () {
      expect(clubPhotoContentTypeForExtension('jpg'), 'image/jpeg');
    });

    test('unknown / empty extension also falls back to image/jpeg', () {
      expect(clubPhotoContentTypeForExtension(''), 'image/jpeg');
      expect(clubPhotoContentTypeForExtension('avif'), 'image/jpeg');
    });
  });
}
