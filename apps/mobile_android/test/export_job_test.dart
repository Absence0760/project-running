import 'dart:io';

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

  test('exportJobFromResponse — a format this build does not know is dropped, not carried', () {
    // The web twin types this field as one of three tokens and used to
    // reach it through a cast, so the type asserted a vocabulary the
    // value had never been checked against. Both halves now grade it.
    // An unreadable label is no reason to refuse an archive that built,
    // so the status survives and only the name goes.
    final job = exportJobFromResponse(<String, dynamic>{
      'status': 'ready',
      'format': 'zip',
      'url': 'https://signed.example/x',
    });
    expect(job.status, ExportJobStatus.ready);
    expect(job.format, isNull);
    for (final known in <String>['csv', 'gpx', 'backup']) {
      final ok = exportJobFromResponse(<String, dynamic>{
        'status': 'ready',
        'format': known,
        'url': 'https://signed.example/x',
      });
      expect(ok.format, known);
    }
    expect(
      exportJobFromResponse(<String, dynamic>{
        'status': 'queued',
        'format': 7,
      }).format,
      isNull,
    );
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

  group('the status vocabulary is one vocabulary', () {
    // Both clients read the SAME two endpoints, so an unrecognised token on
    // one and a recognised one on the other is a phone that keeps polling a
    // job the browser has already called finished, or offers a download the
    // browser will not. The pair is registered in both parity registries,
    // and that registry says the two files must agree — nothing until now
    // read them against each other.
    const webHelper = '../web/src/lib/backup/cloud_export_helpers.ts';

    String webSource() {
      final f = File(webHelper);
      expect(f.existsSync(), isTrue,
          reason: '$webHelper is gone — repoint this guard rather than '
              'letting the two halves drift unwatched');
      return f.readAsStringSync();
    }

    List<String> literalList(String src, String marker) {
      final at = src.indexOf(marker);
      expect(at, isNonNegative, reason: 'could not find "$marker" in $webHelper');
      // The marker itself contains a `[` (`readonly string[]`), so the
      // closing bracket has to be looked for past it.
      final open = at + marker.length;
      final close = src.indexOf(']', open);
      return RegExp(r"'([a-z_]+)'")
          .allMatches(src.substring(open, close))
          .map((m) => m.group(1)!)
          .toList();
    }

    test('every status web knows, the phone knows, and no more', () {
      final web = literalList(
          webSource(), 'const KNOWN_JOB_STATUSES: readonly string[] = [');
      expect(web, isNotEmpty, reason: 'the extractor found no statuses');
      expect(
        ExportJobStatus.values.map((s) => s.name).toSet(),
        web.toSet(),
        reason: 'a token one client resolves and the other does not is the '
            'poll-for-ever / dead-button pair this normalisation exists to '
            'prevent',
      );
    });

    test('and every one of them actually PARSES on the phone', () {
      // The enum carrying the name is not the same claim as the parser
      // resolving the wire token: a token missing from the lookup makes a
      // real server status arrive as `failed`, and the enum still reads
      // complete. `ready` needs a URL to survive its own guard.
      final web = literalList(
          webSource(), 'const KNOWN_JOB_STATUSES: readonly string[] = [');
      for (final token in web) {
        final job = exportJobFromResponse(<String, Object?>{
          'status': token,
          if (token == 'ready') 'url': 'https://signed.example/a',
        });
        expect(job.status.name, token,
            reason: '"$token" is a status the server can send and the phone '
                'resolved it as ${job.status.name}');
      }
    });

    test('the active set is the same two statuses on both rails', () {
      final src = webSource();
      final at = src.indexOf('export function isCloudExportJobActive');
      expect(at, isNonNegative);
      final body = src.substring(at, src.indexOf('}', at));
      for (final s in ExportJobStatus.values) {
        final webActive = body.contains("'${s.name}'");
        expect(isExportJobActive(s), webActive,
            reason: '${s.name} is ${webActive ? '' : 'not '}active on web and '
                'the opposite on the phone');
      }
    });

    test('the poll floor and cap are the same numbers on both rails', () {
      final src = webSource();
      int number(String marker) {
        final m = RegExp('$marker = ([0-9_]+)').firstMatch(src);
        expect(m, isNotNull, reason: 'could not read $marker from $webHelper');
        return int.parse(m!.group(1)!.replaceAll('_', ''));
      }

      expect(kExportPollMinMs, number('CLOUD_EXPORT_POLL_MIN_MS'));
      expect(kExportPollMaxMs, number('CLOUD_EXPORT_POLL_MAX_MS'));
    });
  });

  group('exportJobFromResponse — the shapes a server can actually send', () {
    test('a null body claims nothing', () {
      final job = exportJobFromResponse(null);
      expect(job.status, ExportJobStatus.failed);
      expect(job.errorCode, 'unreadable_response');
    });

    test('a list, a string and a number are all unreadable', () {
      for (final raw in <Object>[<int>[1], 'ready', 7]) {
        expect(exportJobFromResponse(raw).status, ExportJobStatus.failed,
            reason: '$raw must not resolve to a usable job');
      }
    });

    test('a non-string status is unknown, not silently absent', () {
      final job = exportJobFromResponse(<String, Object?>{'status': 3});
      expect(job.status, ExportJobStatus.failed);
      expect(job.errorCode, 'unknown_status',
          reason: 'a client that guessed here would either poll for ever or '
              'offer a download it has no URL for');
    });

    test('an empty-string URL on a ready job is no URL', () {
      final job = exportJobFromResponse(<String, Object?>{
        'status': 'ready',
        'url': '',
      });
      expect(job.status, ExportJobStatus.failed);
      expect(job.errorCode, 'no_url',
          reason: 'an empty string renders as a dead download button');
    });

    test('a status token is matched exactly, not loosely', () {
      for (final token in const ['READY', ' ready', 'ready ', 'read']) {
        final job = exportJobFromResponse(<String, Object?>{'status': token});
        expect(job.status, ExportJobStatus.failed,
            reason: '"$token" is not a status this build knows');
        expect(job.errorCode, token);
      }
    });

    test('a non-finite count is dropped rather than rendered', () {
      final job = exportJobFromResponse(<String, Object?>{
        'status': 'ready',
        'url': 'https://x/y',
        'count': double.nan,
        'total': double.infinity,
      });
      expect(job.count, isNull);
      expect(job.total, isNull);
    });

    test('a complete:true job discloses no shortfall even with counts', () {
      final job = exportJobFromResponse(<String, Object?>{
        'status': 'ready',
        'url': 'https://x/y',
        'count': 10,
        'total': 99,
        'complete': true,
      });
      expect(exportJobShortfall(job), isNull,
          reason: 'only an explicit complete:false claims a shortfall');
    });

    test('a non-boolean complete is not a shortfall claim', () {
      final job = exportJobFromResponse(<String, Object?>{
        'status': 'ready',
        'url': 'https://x/y',
        'complete': 'false',
      });
      expect(job.complete, isNull);
      expect(exportJobShortfall(job), isNull,
          reason: 'warning on every export because a field arrived as the '
              'wrong type is its own dishonesty');
    });
  });

  group('exportPollDelayMs — a ladder, never a spike', () {
    test('it never dips below the floor or past the cap', () {
      for (var attempt = -5; attempt < 200; attempt++) {
        final ms = exportPollDelayMs(attempt);
        expect(ms, greaterThanOrEqualTo(kExportPollMinMs),
            reason: 'attempt $attempt asked for $ms ms');
        expect(ms, lessThanOrEqualTo(kExportPollMaxMs),
            reason: 'attempt $attempt asked for $ms ms');
      }
    });

    test('it never goes backwards as the attempt grows', () {
      var previous = 0;
      for (var attempt = 0; attempt < 100; attempt++) {
        final ms = exportPollDelayMs(attempt);
        expect(ms, greaterThanOrEqualTo(previous),
            reason: 'the backoff dipped at attempt $attempt');
        previous = ms;
      }
    });

    test('a caller that never stops incrementing cannot overflow it', () {
      expect(exportPollDelayMs(1 << 20), kExportPollMaxMs);
      expect(exportPollDelayMs(0x7fffffff), kExportPollMaxMs);
    });
  });

  group('the endpoint URLs', () {
    test('a base with many trailing slashes still joins once', () {
      expect(buildExportJobsUrl('https://hub.example///'),
          'https://hub.example/v1/export/jobs');
      expect(buildExportJobStatusUrl('https://hub.example///'),
          'https://hub.example/v1/export/jobs/latest');
    });

    test('the status endpoint is the latest one, not one keyed by id', () {
      // The resume path is the server, not a file on the device: a job id
      // written to disk is a second source of truth a reinstall loses.
      expect(buildExportJobStatusUrl('https://hub.example'), endsWith('/latest'));
    });
  });
}
