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

/// Drives auth transitions for the AuthChangeAware seam (#232): user A
/// (avatar + coach consent) signs out, then B (neither) signs in.
class _AuthSwitchApi extends ApiClient {
  String? uid = 'a';
  String? email = 'a@test.com';
  final _controller = StreamController<String?>.broadcast();

  @override
  String? get userId => uid;

  @override
  String? get userEmail => email;

  @override
  Stream<String?> get authUserChanges => _controller.stream;

  @override
  Future<DateTime?> fetchCoachConsentAt() async =>
      uid == 'a' ? DateTime.utc(2026, 1, 1) : null;

  @override
  Future<UserProfileRow?> fetchMyProfile() async => uid == null
      ? null
      : UserProfileRow(
          shadowHidden: false,
          id: uid!,
          displayName: 'Runner',
          avatarUrl: uid == 'a' ? 'https://example.invalid/a/avatar.png' : null,
        );

  void emit() => _controller.add(uid);
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

Future<void> _pump(WidgetTester tester, ApiClient api) async {
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

// Scope icon finders to the Profile-photo tile: the same screen carries a red
// Icons.delete_outline on the Delete-account tile, and whether that tile is
// built depends on how much fits the lazy ListView's test viewport (removing
// an unrelated tile above it broke the unscoped finders in run 28864778110).
Finder _avatarTileIcon(IconData icon) => find.descendant(
      of: find.ancestor(
        of: find.text('Profile photo'),
        matching: find.byType(ListTile),
      ),
      matching: find.byIcon(icon),
    );

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
    expect(_avatarTileIcon(Icons.delete_outline), findsOneWidget);
    expect(_avatarTileIcon(Icons.photo_camera_outlined), findsNothing);
  });

  testWidgets('Remove prompts a confirm before calling removeAvatar',
      (tester) async {
    final api = _AvatarApi(avatar: 'https://example.invalid/u1/avatar.png');
    await _pump(tester, api);

    await tester.tap(_avatarTileIcon(Icons.delete_outline));
    await tester.pumpAndSettle(); // open the confirm dialog

    // The confirm dialog is shown; nothing deleted yet.
    expect(find.text('Remove profile photo?'), findsOneWidget);
    expect(api.removeCalls, 0);

    // Confirm.
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Remove photo'),
    );
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await tester.pump(); // dialog pop + start _removeAvatar
    await tester.pump(const Duration(milliseconds: 100)); // future + setState

    expect(api.removeCalls, 1);
    // Once removed the tile falls back to the pick (camera) affordance.
    expect(_avatarTileIcon(Icons.delete_outline), findsNothing);
    expect(_avatarTileIcon(Icons.photo_camera_outlined), findsOneWidget);

    // Drain the showTopBanner auto-dismiss timer so no pending-timer error.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('cancelling the confirm keeps the avatar', (tester) async {
    final api = _AvatarApi(avatar: 'https://example.invalid/u1/avatar.png');
    await _pump(tester, api);

    await tester.tap(_avatarTileIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Cancel'),
    ));
    await tester.pumpAndSettle();

    expect(api.removeCalls, 0);
    // The remove affordance is still present — nothing was deleted.
    expect(_avatarTileIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('avatar tile shows the pick control when no avatar is set',
      (tester) async {
    final api = _AvatarApi(avatar: null);
    await _pump(tester, api);

    expect(find.text('Profile photo'), findsOneWidget);
    expect(_avatarTileIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(_avatarTileIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets(
      'avatar + coach-consent state clears on sign-out and reloads for the next account (#232)',
      (tester) async {
    final api = _AuthSwitchApi();
    await _pump(tester, api);

    expect(find.text('a@test.com'), findsOneWidget);
    expect(find.byIcon(Icons.block), findsOneWidget);
    expect(_avatarTileIcon(Icons.delete_outline), findsOneWidget);

    // Sign out on this very screen: A's consent tile must not keep
    // rendering (it used to stay visible even while signed out), and
    // A's avatar must not survive for whoever signs in next.
    api.uid = null;
    api.email = null;
    api.emit();
    await tester.pumpAndSettle();
    expect(find.text('a@test.com'), findsNothing);
    expect(find.byIcon(Icons.block), findsNothing);
    expect(find.text('Profile photo'), findsNothing);

    // Sign in as B (no consent, no avatar): B's state, not A's.
    api.uid = 'b';
    api.email = 'b@test.com';
    api.emit();
    await tester.pumpAndSettle();
    expect(find.text('b@test.com'), findsOneWidget);
    expect(find.byIcon(Icons.block), findsNothing);
    expect(_avatarTileIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(_avatarTileIcon(Icons.delete_outline), findsNothing);
  });
}
