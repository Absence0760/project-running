import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/backup_server_client.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';

/// The queued Art 20 export on the Account screen (decisions.md § 724).
///
/// The case these pin is the ordinary one on a phone: the runner asks
/// for an export and the screen goes dark. Nothing about the job lives
/// on the device, so every one of these drives the same status endpoint
/// the app would read after being killed.
class _ExportApi extends ApiClient {
  @override
  String? get userId => 'u1';
  @override
  String? get userEmail => 'runner@test.com';
  @override
  String? get currentAccessToken => 'tok-1';
  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => null;
  @override
  Future<UserProfileRow?> fetchMyProfile() async =>
      UserProfileRow(shadowHidden: false, id: 'u1', displayName: 'Alex');
}

/// A scripted export service. Records every request so a test can say
/// what the screen asked for, not merely what it rendered.
class _FakeExportService {
  _FakeExportService({required this.latest, this.enqueue, this.enqueueError});

  /// Answers for `GET /v1/export/jobs/latest`, consumed in order; the
  /// last one repeats so a poll can settle.
  List<Map<String, dynamic>> latest;
  Map<String, dynamic>? enqueue;
  BackupServerError? enqueueError;

  final List<String> methods = <String>[];
  final List<Uri> urls = <Uri>[];
  int downloads = 0;
  int _latestReads = 0;

  int get latestReads => _latestReads;

  BackupServerClient get client => BackupServerClient(
        baseUrl: 'https://hub.example',
        requestFetcher: (url, method, token, body) async {
          methods.add(method);
          urls.add(url);
          if (method == 'POST') {
            final err = enqueueError;
            if (err != null) throw err;
            return ExportHttpResponse(
              statusCode: 202,
              body: enqueue ?? <String, dynamic>{'status': 'queued'},
            );
          }
          final i = _latestReads;
          _latestReads++;
          final idx = i < latest.length ? i : latest.length - 1;
          return ExportHttpResponse(statusCode: 200, body: latest[idx]);
        },
        downloadFetcher: (url, file) async {
          downloads++;
          await file.writeAsBytes(<int>[0x50, 0x4B, 0x05, 0x06]);
          return 4;
        },
      );
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final Directory _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp.path;
  @override
  Future<String?> getApplicationSupportPath() async => _tmp.path;
  @override
  Future<String?> getTemporaryPath() async => _tmp.path;
}

const MethodChannel _shareChannel =
    MethodChannel('dev.fluttercommunity.plus/share');

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

/// A tall surface so the whole ListView builds — the account section
/// sits well below a phone-sized fold and its children would otherwise
/// never be created.
void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester,
  _FakeExportService service, {
  LocalRunStore? runStore,
}) async {
  _tallSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsAccountScreen(
        apiClient: _ExportApi(),
        preferences: Preferences(),
        settingsSync: null,
        runStore: runStore ?? LocalRunStore(),
        exportClient: service.client,
      ),
    ),
  );
  // Not pumpAndSettle: showTopBanner leaves a dismissal timer pending.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late Directory tmp;

  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('settings_account_export_');
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            _shareChannel, (call) async => <String, dynamic>{'status': 'success'});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('an export that finished while the app was closed is waiting on mount',
      (tester) async {
    // The resume path, which is the whole reason the rail is queued: the
    // runner asked, the phone went to the lock screen, the app was
    // killed. Nothing was persisted; the status endpoint is asked for
    // their LATEST export and the download is simply there.
    final service = _FakeExportService(latest: [
      <String, dynamic>{
        'job_id': 'exp-1',
        'status': 'ready',
        'format': 'backup',
        'url': 'https://signed.example/a',
        'expires_in': 600,
        'count': 12,
        'total': 12,
        'complete': true,
      },
    ]);
    await _pump(tester, service);

    expect(find.byKey(const Key('account-export-ready')), findsOneWidget);
    expect(find.byKey(const Key('account-export-download')), findsOneWidget);
    expect(service.methods, contains('GET'));
    expect(service.methods, isNot(contains('POST')));
  });

  testWidgets('a subject who never asked for an export is shown nothing about one',
      (tester) async {
    final service = _FakeExportService(
      latest: [<String, dynamic>{'status': 'none'}],
    );
    await _pump(tester, service);

    expect(find.byKey(const Key('account-export-ready')), findsNothing);
    expect(find.byKey(const Key('account-export-building')), findsNothing);
    expect(find.byKey(const Key('account-export-failed')), findsNothing);
    expect(find.byKey(const Key('account-export-tile')), findsOneWidget);
  });

  testWidgets('asking enqueues and says the app can be closed', (tester) async {
    final service = _FakeExportService(
      latest: [
        <String, dynamic>{'status': 'none'},
        <String, dynamic>{'job_id': 'exp-2', 'status': 'running'},
      ],
      enqueue: <String, dynamic>{
        'job_id': 'exp-2',
        'status': 'queued',
        'format': 'backup',
        'reused': false,
      },
    );
    await _pump(tester, service);

    await tester.tap(find.byKey(const Key('account-export-tile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.methods, contains('POST'));
    expect(service.urls.map((u) => u.path), contains('/v1/export/jobs'));
    expect(find.byKey(const Key('account-export-building')), findsOneWidget);
    // Nothing was downloaded: the archive does not exist yet, and the
    // connection that used to build it is gone.
    expect(service.downloads, 0);
    // Let the banner's dismissal timer run out so the test ends clean.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a refused export is surfaced, never demoted to the on-device archive',
      (tester) async {
    // The rail this replaced swallowed every non-200 and quietly built
    // the narrower local archive instead, so a refused data-rights
    // request reached the subject as a smaller file nobody told them
    // was smaller.
    final service = _FakeExportService(
      latest: [<String, dynamic>{'status': 'none'}],
      enqueueError: const BackupServerError('rate limited',
          statusCode: 429, retryAfterSeconds: 900),
    );
    await _pump(tester, service);

    await tester.tap(find.byKey(const Key('account-export-tile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('900 seconds'), findsOneWidget);
    expect(find.byKey(const Key('account-export-building')), findsNothing);
    expect(find.byKey(const Key('backup-on-device')), findsNothing);
    expect(service.downloads, 0);
    // Let the banner's dismissal timer run out so the test ends clean.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a ready job that arrived with no URL is a failure, not a dead button',
      (tester) async {
    final service = _FakeExportService(latest: [
      <String, dynamic>{'job_id': 'exp-3', 'status': 'ready'},
    ]);
    await _pump(tester, service);

    expect(find.byKey(const Key('account-export-download')), findsNothing);
    expect(find.byKey(const Key('account-export-failed')), findsOneWidget);
  });

  testWidgets('a stalled job says so rather than claiming to still be building',
      (tester) async {
    final service = _FakeExportService(latest: [
      <String, dynamic>{'job_id': 'exp-4', 'status': 'stalled'},
    ]);
    await _pump(tester, service);

    expect(find.byKey(const Key('account-export-stalled')), findsOneWidget);
    expect(find.byKey(const Key('account-export-building')), findsNothing);
  });

  testWidgets('a truncated export discloses both counts under the tile',
      (tester) async {
    final service = _FakeExportService(latest: [
      <String, dynamic>{
        'job_id': 'exp-5',
        'status': 'ready',
        'url': 'https://signed.example/a',
        'count': 5000,
        'total': 7412,
        'complete': false,
      },
    ]);
    await _pump(tester, service);

    expect(find.byKey(const Key('account-export-shortfall')), findsOneWidget);
    expect(find.textContaining('5000'), findsWidgets);
    expect(find.textContaining('7412'), findsWidgets);
  });

  testWidgets('downloading re-reads the status endpoint so the URL is freshly signed',
      (tester) async {
    // The card can sit on screen far longer than the ten minutes a
    // signed URL lives. Reusing the URL it was drawn with would hand
    // the runner a dead link exactly when they finally tapped it.
    final ready = <String, dynamic>{
      'job_id': 'exp-6',
      'status': 'ready',
      'format': 'backup',
      'url': 'https://signed.example/fresh',
      'expires_in': 600,
      'count': 3,
      'total': 3,
      'complete': true,
    };
    final service = _FakeExportService(latest: [ready]);
    await _pump(tester, service);
    final readsAfterMount = service.latestReads;

    await tester.tap(find.byKey(const Key('account-export-download')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.latestReads, greaterThan(readsAfterMount));
    expect(service.downloads, 1);
    expect(service.urls.last.path, '/v1/export/jobs/latest');
  });

  testWidgets('an unreachable status endpoint on mount claims nothing',
      (tester) async {
    // A subject who never asked for an export must not be shown an
    // error about one, so a resume read that fails is silent.
    final client = BackupServerClient(
      baseUrl: 'https://hub.example',
      requestFetcher: (_, __, ___, ____) async =>
          throw const SocketException('offline'),
    );
    _tallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsAccountScreen(
          apiClient: _ExportApi(),
          preferences: Preferences(),
          settingsSync: null,
          runStore: LocalRunStore(),
          exportClient: client,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('account-export-failed')), findsNothing);
    expect(find.byKey(const Key('account-export-status-unreadable')),
        findsNothing);
    expect(find.byKey(const Key('account-export-tile')), findsOneWidget);
  });

  testWidgets('a build with no export service says so, standing, and disables the tile',
      (tester) async {
    // Discovering there is no complete archive by pressing a tile is
    // not disclosure: the runner would otherwise take the on-device
    // backup below in the belief that it is the same thing.
    _tallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsAccountScreen(
          apiClient: _ExportApi(),
          preferences: Preferences(),
          settingsSync: null,
          runStore: LocalRunStore(),
          exportClient: const BackupServerClient(baseUrl: ''),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('account-export-unavailable')), findsOneWidget);
    final tile = tester.widget<ListTile>(
        find.byKey(const Key('account-export-tile')));
    expect(tile.enabled, isFalse);
  });

  testWidgets('the on-device disclosure names what that archive does not carry',
      (tester) async {
    // The local writer is not the Art 20 export: runs, routes, profile,
    // prefs, gym and food, but not the account-record set. A runner
    // handed one has to be able to tell which archive they got.
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.settingsAccountBackupOnDeviceNotice, contains('this device'));
    expect(l10n.settingsAccountBackupOnDeviceNotice.toLowerCase(),
        contains('account records'));
    expect(l10n.settingsAccountBackupOnDeviceNotice,
        contains('Account export'));
  });
}
