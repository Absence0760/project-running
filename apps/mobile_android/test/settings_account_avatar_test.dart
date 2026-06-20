import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';

// A 1x1 transparent PNG so the avatar tile's NetworkImage decodes instead of
// throwing a load error during pumpAndSettle (no network in widget tests).
final _transparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82, //
]);

class _ImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _transparentPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable([_transparentPng]).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _AvatarApi extends ApiClient {
  _AvatarApi({this.avatar});
  String? avatar;
  int removeCalls = 0;

  @override
  String? get userId => 'u1';
  @override
  String? get userEmail => 'runner@test.com';
  @override
  Future<DateTime?> fetchCoachConsentAt() async => null;
  @override
  Future<UserProfileRow?> fetchMyProfile() async =>
      UserProfileRow(shadowHidden: false, id: 'u1', displayName: 'Runner', avatarUrl: avatar);
  @override
  Future<void> removeAvatar() async {
    removeCalls++;
    avatar = null;
  }
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

Future<void> _pump(WidgetTester tester, _AvatarApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsAccountScreen(
        apiClient: api,
        preferences: Preferences(),
        settingsSync: null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => HttpOverrides.global = _ImageHttpOverrides());

  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('avatar tile shows a Remove control when an avatar is set',
      (tester) async {
    final api = _AvatarApi(avatar: 'https://example.invalid/u1/avatar.png');
    await _pump(tester, api);

    expect(find.text('Profile photo'), findsOneWidget);
    // A set avatar surfaces the remove (delete) affordance.
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
  });

  testWidgets('tapping Remove calls removeAvatar and drops the control',
      (tester) async {
    final api = _AvatarApi(avatar: 'https://example.invalid/u1/avatar.png');
    await _pump(tester, api);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump(); // start _removeAvatar
    await tester.pump(const Duration(milliseconds: 100)); // future + setState

    expect(api.removeCalls, 1);
    // Once removed the tile falls back to the pick (camera) affordance.
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);

    // Drain the showTopBanner auto-dismiss timer so no pending-timer error.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('avatar tile shows the pick control when no avatar is set',
      (tester) async {
    final api = _AvatarApi(avatar: null);
    await _pump(tester, api);

    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
