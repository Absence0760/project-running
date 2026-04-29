import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/run_photos.dart';

void main() {
  group('extensionForFilename', () {
    test('returns lowercase extension for a normal filename', () {
      expect(extensionForFilename('IMG_1234.PNG'), 'png');
      expect(extensionForFilename('photo.webp'), 'webp');
    });

    test('jpeg collapses to jpg', () {
      expect(extensionForFilename('photo.JPEG'), 'jpg');
      expect(extensionForFilename('photo.jpeg'), 'jpg');
    });

    test('heif collapses to heic', () {
      expect(extensionForFilename('IMG.heif'), 'heic');
      expect(extensionForFilename('IMG.HEIF'), 'heic');
    });

    test('files without an extension default to jpg', () {
      expect(extensionForFilename('photo'), 'jpg');
    });

    test('hidden / dotfile-style names default to jpg', () {
      // `.gitkeep` has dot at index 0 — `_extOf` rejected `dot <= 0` for a
      // reason: a leading dot isn't an extension separator.
      expect(extensionForFilename('.gitkeep'), 'jpg');
    });

    test('multi-dot filenames take only the trailing extension', () {
      expect(extensionForFilename('my.run.cover.png'), 'png');
    });
  });

  group('contentTypeForExtension', () {
    test('maps the supported image types', () {
      expect(contentTypeForExtension('png'), 'image/png');
      expect(contentTypeForExtension('webp'), 'image/webp');
      expect(contentTypeForExtension('heic'), 'image/heic');
    });

    test('jpg defaults through the fallback branch', () {
      expect(contentTypeForExtension('jpg'), 'image/jpeg');
    });

    test('unknown / empty extension also falls back to image/jpeg', () {
      expect(contentTypeForExtension(''), 'image/jpeg');
      expect(contentTypeForExtension('avif'), 'image/jpeg');
    });
  });
}
