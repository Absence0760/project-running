import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/backup_server_client.dart';

void main() {
  late Directory tempDir;
  late File outputFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('backup_server_client_test_');
    outputFile = File('${tempDir.path}/backup.zip');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('isConfigured', () {
    test('empty baseUrl → false', () {
      final c = BackupServerClient(baseUrl: '');
      expect(c.isConfigured, isFalse);
    });

    test('non-empty baseUrl → true', () {
      final c = BackupServerClient(baseUrl: 'https://live.threkir.com');
      expect(c.isConfigured, isTrue);
    });
  });

  group('fetchBackupToFile — preconditions', () {
    test('throws BackupServerError when unconfigured', () async {
      final c = BackupServerClient(baseUrl: '');
      await expectLater(
        () => c.fetchBackupToFile(accessToken: 'tok', outputFile: outputFile),
        throwsA(isA<BackupServerError>()),
      );
    });

    test('throws BackupServerError when access token is empty', () async {
      final c = BackupServerClient(baseUrl: 'https://x.example');
      await expectLater(
        () => c.fetchBackupToFile(accessToken: '', outputFile: outputFile),
        throwsA(isA<BackupServerError>()),
      );
    });
  });

  group('fetchBackupToFile — round-trip', () {
    test('POSTs format=backup with the bearer token then downloads the signed URL',
        () async {
      late Uri capturedExportUrl;
      late String capturedToken;
      late Map<String, dynamic> capturedBody;
      late Uri capturedSignedUrl;
      late File capturedOutputFile;

      Future<({int statusCode, Map<String, dynamic> body})> request(
          Uri url, String token, Map<String, dynamic> body) async {
        capturedExportUrl = url;
        capturedToken = token;
        capturedBody = body;
        return (
          statusCode: 200,
          body: <String, dynamic>{
            'url': 'https://signed.example/runs/exports/abc?token=xyz',
            'expires_in': 600,
            'count': 42,
            'format': 'backup',
          },
        );
      }

      Future<int> download(Uri url, File outputFile) async {
        capturedSignedUrl = url;
        capturedOutputFile = outputFile;
        await outputFile.writeAsBytes([0x50, 0x4B, 0x05, 0x06]); // empty-ZIP sentinel
        return 4;
      }

      final c = BackupServerClient(
        baseUrl: 'https://live.threkir.com/',
        requestFetcher: request,
        downloadFetcher: download,
      );
      final summary = await c.fetchBackupToFile(
        accessToken: 'tok-abc',
        outputFile: outputFile,
      );

      expect(summary.count, 42);
      expect(capturedExportUrl.toString(),
          'https://live.threkir.com/v1/export');
      expect(capturedToken, 'tok-abc');
      expect(capturedBody['format'], 'backup');
      expect(capturedSignedUrl.toString(),
          'https://signed.example/runs/exports/abc?token=xyz');
      expect(capturedOutputFile.path, outputFile.path);
      expect(outputFile.existsSync(), isTrue);
    });

    test('trims trailing slash on baseUrl', () async {
      late Uri capturedExportUrl;
      final c = BackupServerClient(
        baseUrl: 'https://live.threkir.com/',
        requestFetcher: (url, _, __) async {
          capturedExportUrl = url;
          return (statusCode: 200, body: {'url': 'https://x/y', 'count': 0});
        },
        downloadFetcher: (_, f) async {
          await f.writeAsBytes([0]);
          return 1;
        },
      );
      await c.fetchBackupToFile(accessToken: 't', outputFile: outputFile);
      expect(capturedExportUrl.path, '/v1/export');
    });
  });

  group('fetchBackupToFile — failure modes', () {
    test('non-200 export response surfaces a BackupServerError', () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___) async => (
          statusCode: 429,
          body: <String, dynamic>{'error': 'rate_limited'},
        ),
        downloadFetcher: (_, __) async => 0,
      );
      await expectLater(
        () => c.fetchBackupToFile(accessToken: 't', outputFile: outputFile),
        throwsA(isA<BackupServerError>()),
      );
    });

    test('200 response with missing signed URL surfaces a BackupServerError',
        () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'count': 5},
        ),
        downloadFetcher: (_, __) async => 0,
      );
      await expectLater(
        () => c.fetchBackupToFile(accessToken: 't', outputFile: outputFile),
        throwsA(isA<BackupServerError>()),
      );
    });

    test('200 with empty-string signed URL surfaces a BackupServerError',
        () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'url': '', 'count': 5},
        ),
        downloadFetcher: (_, __) async => 0,
      );
      await expectLater(
        () => c.fetchBackupToFile(accessToken: 't', outputFile: outputFile),
        throwsA(isA<BackupServerError>()),
      );
    });

    test('downloadFetcher exception propagates (caller falls back to local)',
        () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'url': 'https://signed/x', 'count': 1},
        ),
        downloadFetcher: (_, __) async {
          throw const HttpException('connection reset by peer');
        },
      );
      await expectLater(
        () => c.fetchBackupToFile(accessToken: 't', outputFile: outputFile),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('fetchBackupToFile — completeness extraction', () {
    test('count: int round-trips', () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'url': 'https://signed/x', 'count': 99},
        ),
        downloadFetcher: (_, f) async {
          await f.writeAsBytes([0]);
          return 1;
        },
      );
      final summary = await c.fetchBackupToFile(
        accessToken: 't',
        outputFile: outputFile,
      );
      expect(summary.count, 99);
    });

    test('count: double (some JSON parsers emit num) coerces to int', () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'url': 'https://signed/x', 'count': 7.0},
        ),
        downloadFetcher: (_, f) async {
          await f.writeAsBytes([0]);
          return 1;
        },
      );
      final summary = await c.fetchBackupToFile(
        accessToken: 't',
        outputFile: outputFile,
      );
      expect(summary.count, 7);
    });

    test('missing count defaults to 0', () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'url': 'https://signed/x'},
        ),
        downloadFetcher: (_, f) async {
          await f.writeAsBytes([0]);
          return 1;
        },
      );
      final summary = await c.fetchBackupToFile(
        accessToken: 't',
        outputFile: outputFile,
      );
      expect(summary.count, 0);
    });
  });

  // The completeness fields the screen discloses. `count` alone cannot
  // say "this archive is short" — a runner past the server's per-export
  // run ceiling otherwise sees only "your export is ready".
  group('ServerBackupSummary.fromJson', () {
    test('a whole archive reports complete', () {
      final s = ServerBackupSummary.fromJson(
        <String, dynamic>{'count': 12, 'total': 12, 'complete': true},
      );
      expect(s.count, 12);
      expect(s.total, 12);
      expect(s.complete, isTrue);
    });

    test('a truncated archive carries both counts', () {
      final s = ServerBackupSummary.fromJson(
        <String, dynamic>{'count': 5000, 'total': 7412, 'complete': false},
      );
      expect(s.count, 5000);
      expect(s.total, 7412);
      expect(s.complete, isFalse);
    });

    test('a body without `complete` claims nothing', () {
      // An older deployment of either transport omits the field.
      // Absence is not evidence of truncation, and a shortfall banner
      // on every export would be its own lie.
      final s = ServerBackupSummary.fromJson(
        <String, dynamic>{'count': 12},
      );
      expect(s.complete, isTrue);
    });

    test('a non-bool `complete` claims nothing either', () {
      final s = ServerBackupSummary.fromJson(
        <String, dynamic>{'count': 12, 'complete': 'no'},
      );
      expect(s.complete, isTrue);
    });

    test('total is floored at count so it can never read "12 of 3"', () {
      final s = ServerBackupSummary.fromJson(
        <String, dynamic>{'count': 12, 'total': 3, 'complete': false},
      );
      expect(s.total, 12);
    });

    test('a missing total falls back to the archive count', () {
      final s = ServerBackupSummary.fromJson(
        <String, dynamic>{'count': 40, 'complete': false},
      );
      expect(s.total, 40);
    });

    test('a num total coerces to int', () {
      final s = ServerBackupSummary.fromJson(
        <String, dynamic>{'count': 7.0, 'total': 9.0, 'complete': false},
      );
      expect(s.count, 7);
      expect(s.total, 9);
    });
  });
}
