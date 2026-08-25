import 'package:flutter_test/flutter_test.dart';
import '../lib/export_job.dart';

/// Mirror of `apps/web/src/lib/backup/cloud_export_helpers.test.ts`'s
/// job half. The two clients read the same two endpoints, so they must
/// agree about what every status token means and about what an answer
/// they cannot read means.
void main() {
  test('buildExportJobsUrl / buildExportJobStatusUrl — trailing slashes normalise', () {
    expect(buildExportJobsUrl('https://live.threkir.com//'),
        'https://live.threkir.com/v1/export/jobs');
    expect(buildExportJobStatusUrl('https://live.threkir.com'),
        'https://live.threkir.com/v1/export/jobs/latest');
    expect(buildExportJobsUrl('https://live.threkir.com/'),
        'https://live.threkir.com/v1/export/jobs');
  });

  test('exportJobFromResponse — a ready job carries its URL and counts', () {
    final job = exportJobFromResponse(<String, dynamic>{
      'job_id': 'exp-1',
      'status': 'ready',
      'format': 'backup',
      'url': 'https://signed.example/x',
      'expires_in': 600,
      'count': 5000,
      'total': 7412,
      'complete': false,
    });
    expect(job.status, ExportJobStatus.ready);
    expect(job.url, 'https://signed.example/x');
    expect(job.jobId, 'exp-1');
    expect(job.format, 'backup');
    expect(job.expiresInS, 600);
    final short = exportJobShortfall(job);
    expect(short, isNotNull);
    expect(short!.count, 5000);
    expect(short.total, 7412);
  });

  test('exportJobFromResponse — a status this build does not know is terminal, not a poll forever', () {
    // A client that keeps asking about a status it cannot interpret
    // polls until the battery dies; one that guesses `ready` offers a
    // download it has no URL for. Neither is acceptable, so an unknown
    // token fails closed and names itself.
    final job = exportJobFromResponse(<String, dynamic>{'status': 'compacting'});
    expect(job.status, ExportJobStatus.failed);
    expect(job.errorCode, 'compacting');
    expect(isExportJobActive(job.status), isFalse);
  });

  test('exportJobFromResponse — a ready job with no URL is a failure, not a dead button', () {
    final job = exportJobFromResponse(
        <String, dynamic>{'status': 'ready', 'job_id': 'exp-1'});
    expect(job.status, ExportJobStatus.failed);
    expect(job.errorCode, 'no_url');
  });

  test('exportJobFromResponse — an unreadable body claims nothing', () {
    expect(exportJobFromResponse(null).status, ExportJobStatus.failed);
    expect(exportJobFromResponse('nope').status, ExportJobStatus.failed);
    expect(exportJobFromResponse(null).errorCode, 'unreadable_response');
    expect(exportJobFromResponse(<String, dynamic>{}).errorCode, 'unknown_status');
  });

  test('exportJobFromResponse — non-numeric counts are dropped rather than rendered', () {
    final job = exportJobFromResponse(<String, dynamic>{
      'status': 'ready',
      'url': 'https://signed.example/x',
      'count': 'lots',
      'total': double.nan,
      'complete': 'yes',
    });
    expect(job.count, isNull);
    expect(job.total, isNull);
    expect(job.complete, isNull);
    // And with nothing known, no shortfall is claimed.
    expect(exportJobShortfall(job), isNull);
  });

  test('exportJobShortfall — a job that says complete:false but knows no counts still discloses', () {
    final job = exportJobFromResponse(<String, dynamic>{
      'status': 'ready',
      'url': 'https://signed.example/x',
      'complete': false,
    });
    final short = exportJobShortfall(job);
    expect(short, isNotNull);
    expect(short!.count, 0);
    expect(short.total, 0);
  });

  test('exportJobShortfall — a complete export discloses nothing', () {
    final job = exportJobFromResponse(<String, dynamic>{
      'status': 'ready',
      'url': 'https://signed.example/x',
      'count': 10,
      'total': 10,
      'complete': true,
    });
    expect(exportJobShortfall(job), isNull);
  });

  test('exportJobShortfall — total can never render below count', () {
    final job = exportJobFromResponse(<String, dynamic>{
      'status': 'ready',
      'url': 'https://signed.example/x',
      'count': 12,
      'total': 3,
      'complete': false,
    });
    expect(exportJobShortfall(job)!.total, 12);
  });

  test('isExportJobActive — only queued and running keep the poll alive', () {
    expect(isExportJobActive(ExportJobStatus.queued), isTrue);
    expect(isExportJobActive(ExportJobStatus.running), isTrue);
    for (final s in <ExportJobStatus>[
      ExportJobStatus.none,
      ExportJobStatus.ready,
      ExportJobStatus.failed,
      ExportJobStatus.expired,
      ExportJobStatus.stalled,
    ]) {
      expect(isExportJobActive(s), isFalse, reason: s.name);
    }
  });

  test('exportPollDelayMs — backs off from the floor to the cap and stays there', () {
    expect(exportPollDelayMs(0), kExportPollMinMs);
    expect(exportPollDelayMs(1), kExportPollMinMs);
    expect(exportPollDelayMs(2), 4000);
    expect(exportPollDelayMs(4), 8000);
    expect(exportPollDelayMs(100), kExportPollMaxMs);
    // A nonsense attempt count must not produce a zero-delay hot loop.
    expect(exportPollDelayMs(-1), kExportPollMinMs);
  });

  test('exportJobFromResponse — `none` is a real answer, not an error', () {
    // A subject who has never asked for an export must render as a
    // subject who has never asked for one, so the resume path on a
    // fresh install shows nothing rather than a failure.
    final job = exportJobFromResponse(<String, dynamic>{'status': 'none'});
    expect(job.status, ExportJobStatus.none);
    expect(job.errorCode, isNull);
    expect(isExportJobActive(job.status), isFalse);
  });

  test('exportJobFromResponse — an enqueue answer reads on the same vocabulary', () {
    // POST /v1/export/jobs answers {job_id, status, format, reused} —
    // deliberately the same tokens the status endpoint uses, so one
    // normaliser covers both and the client needs no second shape.
    final job = exportJobFromResponse(<String, dynamic>{
      'job_id': 'exp-9',
      'status': 'queued',
      'format': 'backup',
      'reused': true,
    });
    expect(job.status, ExportJobStatus.queued);
    expect(job.jobId, 'exp-9');
    expect(isExportJobActive(job.status), isTrue);
  });
}
