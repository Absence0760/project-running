import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

RunMatchInfo _info(MatchStatus status, {bool trackUnreachable = false}) =>
    RunMatchInfo(status: status, trackUnreachable: trackUnreachable);

void main() {
  group('isMatchUnreachableError', () {
    test('classifies a SocketException as unreachable', () {
      expect(
        isMatchUnreachableError(
          const SocketException('Failed host lookup: example.com'),
        ),
        isTrue,
      );
    });

    test('classifies a TimeoutException as unreachable', () {
      expect(isMatchUnreachableError(TimeoutException('timed out')), isTrue);
    });

    test('classifies message-only transport failures as unreachable', () {
      expect(
        isMatchUnreachableError(Exception('Connection refused')),
        isTrue,
      );
      expect(
        isMatchUnreachableError(Exception('Network is unreachable')),
        isTrue,
      );
    });

    test('does NOT classify a server/permission error as unreachable', () {
      expect(
        isMatchUnreachableError(Exception('permission denied (42501)')),
        isFalse,
      );
      expect(isMatchUnreachableError(Exception('not found')), isFalse);
      expect(isMatchUnreachableError(FormatException('bad json')), isFalse);
    });
  });

  group('matchPillKind', () {
    test('null info: offline flag drives offline vs hidden', () {
      expect(matchPillKind(null, offline: false), MatchPillKind.hidden);
      expect(matchPillKind(null, offline: true), MatchPillKind.offline);
    });

    test('clean matched is hidden; matched+unreachable is offline', () {
      expect(
        matchPillKind(
          RunMatchInfo(status: MatchStatus.matched),
          offline: false,
        ),
        MatchPillKind.hidden,
      );
      expect(
        matchPillKind(
          _info(MatchStatus.matched, trackUnreachable: true),
          offline: false,
        ),
        MatchPillKind.offline,
      );
    });

    test('pending shows offline only when the offline flag is set', () {
      expect(
        matchPillKind(_info(MatchStatus.pending), offline: false),
        MatchPillKind.pending,
      );
      expect(
        matchPillKind(_info(MatchStatus.pending), offline: true),
        MatchPillKind.offline,
      );
    });

    test('failed/skipped stay terminal even when offline', () {
      expect(
        matchPillKind(_info(MatchStatus.failed), offline: true),
        MatchPillKind.failed,
      );
      expect(
        matchPillKind(_info(MatchStatus.skipped), offline: true),
        MatchPillKind.skipped,
      );
    });
  });

  group('shouldRetryMatchFetch', () {
    test('null info retries only when offline', () {
      expect(shouldRetryMatchFetch(null, offline: true), isTrue);
      expect(shouldRetryMatchFetch(null, offline: false), isFalse);
    });

    test('pending always retries', () {
      expect(
        shouldRetryMatchFetch(_info(MatchStatus.pending), offline: false),
        isTrue,
      );
    });

    test('matched retries only when the track was unreachable', () {
      expect(
        shouldRetryMatchFetch(
          RunMatchInfo(status: MatchStatus.matched),
          offline: false,
        ),
        isFalse,
      );
      expect(
        shouldRetryMatchFetch(
          _info(MatchStatus.matched, trackUnreachable: true),
          offline: false,
        ),
        isTrue,
      );
    });

    test('failed/skipped never retry (terminal verdict)', () {
      expect(
        shouldRetryMatchFetch(_info(MatchStatus.failed), offline: true),
        isFalse,
      );
      expect(
        shouldRetryMatchFetch(_info(MatchStatus.skipped), offline: true),
        isFalse,
      );
    });
  });
}
