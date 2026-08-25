import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/backup_server_client.dart';
import '../lib/export_job.dart';

ExportHttpResponse _ok(Map<String, dynamic> body) =>
    ExportHttpResponse(statusCode: 200, body: body);

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

  group('preconditions', () {
    test('enqueueExport throws BackupServerError when unconfigured', () async {
      final c = BackupServerClient(baseUrl: '');
      await expectLater(
        () => c.enqueueExport(accessToken: 'tok'),
        throwsA(isA<BackupServerError>()),
      );
    });

    test('enqueueExport throws BackupServerError when the token is empty',
        () async {
      final c = BackupServerClient(baseUrl: 'https://x.example');
      await expectLater(
        () => c.enqueueExport(accessToken: ''),
        throwsA(isA<BackupServerError>()),
      );
    });

    test('fetchLatestExportJob throws BackupServerError when unconfigured',
        () async {
      final c = BackupServerClient(baseUrl: '');
      await expectLater(
        () => c.fetchLatestExportJob(accessToken: 'tok'),
        throwsA(isA<BackupServerError>()),
      );
    });
  });

  group('enqueueExport', () {
    test('POSTs format=backup with the bearer token and returns at once',
        () async {
      late Uri capturedUrl;
      late String capturedMethod;
      late String capturedToken;
      late Map<String, dynamic>? capturedBody;

      final c = BackupServerClient(
        baseUrl: 'https://live.threkir.com/',
        requestFetcher: (url, method, token, body) async {
          capturedUrl = url;
          capturedMethod = method;
          capturedToken = token;
          capturedBody = body;
          // The server answers 202: the archive has NOT been built.
          return ExportHttpResponse(
            statusCode: 202,
            body: <String, dynamic>{
              'job_id': 'exp-1',
              'status': 'queued',
              'format': 'backup',
              'reused': false,
            },
          );
        },
      );
      final job = await c.enqueueExport(accessToken: 'tok-abc');

      expect(job.status, ExportJobStatus.queued);
      expect(job.jobId, 'exp-1');
      expect(capturedUrl.toString(), 'https://live.threkir.com/v1/export/jobs');
      expect(capturedMethod, 'POST');
      expect(capturedToken, 'tok-abc');
      expect(capturedBody!['format'], 'backup');
    });

    test('a 429 is carried as a rate limit the subject can act on', () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___, ____) async => const ExportHttpResponse(
          statusCode: 429,
          body: <String, dynamic>{'error': 'rate_limited'},
          retryAfter: '1800',
        ),
      );
      try {
        await c.enqueueExport(accessToken: 't');
        fail('expected a BackupServerError');
      } on BackupServerError catch (e) {
        expect(e.isRateLimited, isTrue);
        expect(e.retryAfterSeconds, 1800);
      }
    });

    test('an HTTP-date Retry-After is not guessed at', () async {
      // The date form is legal and the server does not send it. Showing
      // a subject a wrong wait is worse than showing none.
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___, ____) async => const ExportHttpResponse(
          statusCode: 429,
          body: <String, dynamic>{},
          retryAfter: 'Wed, 21 Oct 2026 07:28:00 GMT',
        ),
      );
      try {
        await c.enqueueExport(accessToken: 't');
        fail('expected a BackupServerError');
      } on BackupServerError catch (e) {
        expect(e.isRateLimited, isTrue);
        expect(e.retryAfterSeconds, isNull);
      }
    });

    test('a 500 surfaces rather than being swallowed', () async {
      // The old synchronous rail swallowed every non-200 and quietly
      // built the on-device archive instead. A refused data-rights
      // request the subject is never told about is the failure this
      // whole change exists to remove.
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___, ____) async => const ExportHttpResponse(
          statusCode: 500,
          body: <String, dynamic>{'error': 'enqueue_failed'},
        ),
      );
      try {
        await c.enqueueExport(accessToken: 't');
        fail('expected a BackupServerError');
      } on BackupServerError catch (e) {
        expect(e.isRateLimited, isFalse);
        expect(e.statusCode, 500);
      }
    });
  });

  group('fetchLatestExportJob', () {
    test('GETs the latest endpoint and normalises the body', () async {
      late Uri capturedUrl;
      late String capturedMethod;
      late Map<String, dynamic>? capturedBody;
      final c = BackupServerClient(
        baseUrl: 'https://live.threkir.com',
        requestFetcher: (url, method, _, body) async {
          capturedUrl = url;
          capturedMethod = method;
          capturedBody = body;
          return _ok(<String, dynamic>{
            'job_id': 'exp-1',
            'status': 'ready',
            'format': 'backup',
            'url': 'https://signed.example/x',
            'expires_in': 600,
            'count': 42,
            'total': 42,
            'complete': true,
          });
        },
      );
      final job = await c.fetchLatestExportJob(accessToken: 't');
      expect(capturedUrl.toString(),
          'https://live.threkir.com/v1/export/jobs/latest');
      expect(capturedMethod, 'GET');
      expect(capturedBody, isNull);
      expect(job.status, ExportJobStatus.ready);
      expect(job.url, 'https://signed.example/x');
      expect(job.count, 42);
    });

    test('a subject who never asked reads as `none`, not as an error',
        () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___, ____) async =>
            _ok(<String, dynamic>{'status': 'none'}),
      );
      final job = await c.fetchLatestExportJob(accessToken: 't');
      expect(job.status, ExportJobStatus.none);
    });

    test('a non-2xx status read surfaces rather than reading as `none`',
        () async {
      // Reporting an unreachable status endpoint as "you have never
      // asked for an export" would erase an export that is building.
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        requestFetcher: (_, __, ___, ____) async => const ExportHttpResponse(
          statusCode: 503,
          body: <String, dynamic>{'error': 'export_not_configured'},
        ),
      );
      await expectLater(
        () => c.fetchLatestExportJob(accessToken: 't'),
        throwsA(isA<BackupServerError>()),
      );
    });
  });

  group('downloadToFile', () {
    test('streams the signed URL to the output file', () async {
      late Uri capturedSignedUrl;
      late File capturedOutputFile;
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        downloadFetcher: (url, file) async {
          capturedSignedUrl = url;
          capturedOutputFile = file;
          await file.writeAsBytes([0x50, 0x4B, 0x05, 0x06]);
          return 4;
        },
      );
      final bytes = await c.downloadToFile(
        url: Uri.parse('https://signed.example/x?token=y'),
        outputFile: outputFile,
      );
      expect(bytes, 4);
      expect(capturedSignedUrl.toString(), 'https://signed.example/x?token=y');
      expect(capturedOutputFile.path, outputFile.path);
      expect(outputFile.existsSync(), isTrue);
    });

    test('a download failure propagates to the caller', () async {
      final c = BackupServerClient(
        baseUrl: 'https://x.example',
        downloadFetcher: (_, __) async {
          throw const HttpException('connection reset by peer');
        },
      );
      await expectLater(
        () => c.downloadToFile(
          url: Uri.parse('https://signed/x'),
          outputFile: outputFile,
        ),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
