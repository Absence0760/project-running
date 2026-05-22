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
      final count = await c.fetchBackupToFile(
        accessToken: 'tok-abc',
        outputFile: outputFile,
      );

      expect(count, 42);
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

  group('fetchBackupToFile — count extraction', () {
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
      final count = await c.fetchBackupToFile(
        accessToken: 't',
        outputFile: outputFile,
      );
      expect(count, 99);
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
      final count = await c.fetchBackupToFile(
        accessToken: 't',
        outputFile: outputFile,
      );
      expect(count, 7);
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
      final count = await c.fetchBackupToFile(
        accessToken: 't',
        outputFile: outputFile,
      );
      expect(count, 0);
    });
  });
}
