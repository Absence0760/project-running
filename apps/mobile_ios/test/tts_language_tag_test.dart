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

    test('each Portuguese tag speaks its own catalogue, not one shared voice', () {
      expect(ttsLanguageTag('pt-BR'), 'pt-BR');
      expect(ttsLanguageTag('pt_BR'), 'pt-BR');
      expect(ttsLanguageTag('pt-PT'), 'pt-PT');
      expect(ttsLanguageTag('pt_PT'), 'pt-PT');
      // Bare `pt` is the European catalogue, the same way `_baseToLocale`
      // resolves it. It spoke Brazilian until decisions 760, so a European
      // reader heard a Brazilian voice reading European text.
      expect(ttsLanguageTag('pt'), 'pt-PT');
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
