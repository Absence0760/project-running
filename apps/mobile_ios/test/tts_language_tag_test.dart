// Unit tests for `ttsLanguageTag` — maps an app-locale tag to the BCP-47
// language tag the platform TTS engine expects. A wrong mapping means a
// German user hears an American voice (the bug this closes).

import 'package:flutter_test/flutter_test.dart';

import '../lib/audio_cues.dart';

void main() {
  group('ttsLanguageTag', () {
    test('en → en-US', () {
      expect(ttsLanguageTag('en'), 'en-US');
    });

    test('de → de-DE', () {
      expect(ttsLanguageTag('de'), 'de-DE');
    });

    test('fr → fr-FR', () {
      expect(ttsLanguageTag('fr'), 'fr-FR');
    });

    test('es → es-ES', () {
      expect(ttsLanguageTag('es'), 'es-ES');
    });

    test('ja → ja-JP', () {
      expect(ttsLanguageTag('ja'), 'ja-JP');
    });

    test('pt-BR → pt-BR (country code preserved)', () {
      expect(ttsLanguageTag('pt-BR'), 'pt-BR');
      expect(ttsLanguageTag('pt_BR'), 'pt-BR');
      // Bare pt also routes to the one Portuguese voice we ship.
      expect(ttsLanguageTag('pt'), 'pt-BR');
    });

    test('case-insensitive on the input tag', () {
      expect(ttsLanguageTag('DE'), 'de-DE');
      expect(ttsLanguageTag('Pt-Br'), 'pt-BR');
    });

    test('unknown tag falls back to en-US (never silent)', () {
      expect(ttsLanguageTag('zz'), 'en-US');
      expect(ttsLanguageTag(''), 'en-US');
      expect(ttsLanguageTag('xx-YY'), 'en-US');
    });
  });
}
