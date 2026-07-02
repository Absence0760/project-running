import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_photos.dart';

/// Owner-scoped fake so the Add-photo affordance renders; the photo list
/// is empty so `_load` never touches Supabase storage.
class _PhotosApi extends ApiClient {
  @override
  String? get userId => 'owner-1';

  @override
  Future<List<RunPhotoRow>> fetchRunPhotos(String runId, {int limit = 50}) async =>
      const [];
}

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

Future<void> _pump(
  WidgetTester tester, {
  required Future<XFile?> Function() pick,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RunPhotos(
          api: _PhotosApi(),
          runId: 'r1',
          runOwnerId: 'owner-1',
          pickImageOverride: pick,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_ensureSupabase);

  testWidgets(
      'permission-denied pick shows friendly copy + an open-settings action',
      (tester) async {
    await _pump(
      tester,
      pick: () async =>
          throw PlatformException(code: 'photo_access_denied'),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Add photo'));
    await tester.pump();

    expect(
      find.text(
          'Photo access is needed to add a photo. You can allow it in Settings.'),
      findsOneWidget,
    );
    expect(find.text('Open settings'), findsOneWidget);
    // Never dump the raw exception code into the banner.
    expect(find.textContaining('photo_access_denied'), findsNothing);

    // Drain the banner's auto-dismiss timer before teardown.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a non-permission failure shows a generic message, not the raw error',
      (tester) async {
    await _pump(
      tester,
      pick: () async => throw StateError('weird-internal-detail'),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Add photo'));
    await tester.pump();

    expect(
      find.text('Could not open the photo picker. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('weird-internal-detail'), findsNothing);
    expect(find.text('Open settings'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });
}
