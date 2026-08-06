import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/devices_screen.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DevicesScreen(
        api: ApiClient(),
        currentDeviceId: 'this-device-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('DevicesScreen — initial render', () {
    testWidgets('renders the Signed-in devices app-bar title', (tester) async {
      await _pump(tester);
      expect(find.text('Signed-in devices'), findsOneWidget);
    });

    testWidgets('first frame shows the list skeleton', (tester) async {
      await _pump(tester);
      expect(find.byType(ListSkeleton), findsOneWidget);
    });
  });

  group('overrideKeyRegistry', () {
    test('covers exactly the D + UD scoped keys from docs/backend/settings.md', () {
      // UD scope.
      final ud = [
        'preferred_unit',
        'default_activity_type',
        'map_style',
        'units_pace_format',
      ];
      // D scope.
      final d = [
        'voice_feedback_enabled',
        'voice_feedback_interval_km',
        'haptic_feedback_enabled',
        'keep_screen_on',
      ];
      final expected = {...ud, ...d};
      final actual = overrideKeyRegistry.map((s) => s.key).toSet();
      expect(actual, expected,
          reason: 'registry must include every D/UD key from settings.md '
              'and exclude purely-universal keys (hr_zones, weekly goal, '
              'privacy_default, etc.) that have no device-scope semantics');
    });

    test('every spec resolves a non-empty localized label + hint in every '
        'locale', () {
      // The registry carries l10n key identifiers, not strings (issue #666
      // U4). overrideKeyText falls back to the raw identifier for an unknown
      // key, so equality with the identifier means the switch is missing a
      // case — an untranslatable spec.
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        for (final s in overrideKeyRegistry) {
          final label = overrideKeyLabel(l10n, s);
          expect(label.trim(), isNotEmpty,
              reason: '${s.key} must resolve a UI label in $locale');
          expect(label, isNot(s.labelKey),
              reason: '${s.key} labelKey "${s.labelKey}" fell back to the '
                  'raw identifier in $locale — add it to overrideKeyText');
          final hint = overrideKeyHint(l10n, s);
          expect(hint.trim(), isNotEmpty,
              reason: '${s.key} must resolve a hint in $locale');
          expect(hint, isNot(s.hintKey),
              reason: '${s.key} hintKey "${s.hintKey}" fell back to the '
                  'raw identifier in $locale — add it to overrideKeyText');
        }
      }
    });

    test('enum specs always declare a non-empty options list', () {
      for (final s in overrideKeyRegistry.where((s) => s.kind == 'enum')) {
        expect(s.options, isNotNull,
            reason: 'enum-kind spec ${s.key} must declare options');
        expect(s.options, isNotEmpty,
            reason: 'enum-kind spec ${s.key} must have at least one option');
      }
    });

    test('non-enum specs do not declare options', () {
      for (final s in overrideKeyRegistry.where((s) => s.kind != 'enum')) {
        expect(s.options, isNull,
            reason: '${s.kind}-kind spec ${s.key} should not declare options');
      }
    });

    test('every spec.kind is one of the editor-supported types', () {
      const supported = {'bool', 'enum', 'int', 'double'};
      for (final s in overrideKeyRegistry) {
        expect(supported.contains(s.kind), isTrue,
            reason: '${s.key} kind="${s.kind}" must be one of $supported '
                '(those are the only branches _AddOverrideSheet._buildEditor '
                'handles)');
      }
    });
  });
}
