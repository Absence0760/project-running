import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/coach_screen.dart';

void main() {
  group('coachTitleFromMessage', () {
    test('returns the message verbatim when it fits in 48 chars', () {
      expect(coachTitleFromMessage('How was my last run?'),
          'How was my last run?');
    });

    test('collapses runs of whitespace to a single space', () {
      expect(
        coachTitleFromMessage('What\nshould\tI   focus  on?'),
        'What should I focus on?',
      );
    });

    test('trims leading and trailing whitespace', () {
      expect(coachTitleFromMessage('   easy run pace?\n'), 'easy run pace?');
    });

    test('caps at 48 chars and adds an ellipsis past the limit', () {
      // 60 chars → cap at 48 visible chars, "47 + …".
      const long = 'Why is this week long run so much harder than last week';
      final out = coachTitleFromMessage(long);
      expect(out.length, lessThanOrEqualTo(48));
      expect(out.endsWith('…'), isTrue);
      expect(out.startsWith('Why is this week long run'), isTrue);
    });

    test('exactly 48 chars stays verbatim (no ellipsis)', () {
      const exactly48 = 'a' * 48;
      expect(coachTitleFromMessage(exactly48), exactly48);
    });

    test('49 chars triggers truncation with ellipsis', () {
      const fortyNine = 'a' * 49;
      final out = coachTitleFromMessage(fortyNine);
      expect(out, '${'a' * 47}…');
    });
  });

  group('coachArchiveLabel', () {
    final now = DateTime.utc(2026, 4, 28, 12, 0);

    test('returns Today for the same day', () {
      expect(coachArchiveLabel(now, now: now), 'Today');
      expect(
        coachArchiveLabel(now.subtract(const Duration(hours: 6)), now: now),
        'Today',
      );
    });

    test('returns Yesterday for 1 day ago', () {
      expect(
        coachArchiveLabel(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
    });

    test('returns N days ago for 2..6 days ago', () {
      for (var days = 2; days < 7; days++) {
        expect(
          coachArchiveLabel(now.subtract(Duration(days: days)), now: now),
          '$days days ago',
        );
      }
    });

    test('returns YYYY-MM-DD beyond a week', () {
      final twoWeeks = now.subtract(const Duration(days: 14));
      expect(coachArchiveLabel(twoWeeks, now: now), '2026-04-14');
    });

    test('zero-pads month and day', () {
      final earlyJan = DateTime.utc(2026, 1, 3, 12, 0);
      final muchLater = earlyJan.add(const Duration(days: 30));
      expect(coachArchiveLabel(earlyJan, now: muchLater), '2026-01-03');
    });
  });

  group('parseCoachSseEvent', () {
    test('parses a meta block with event + data lines', () {
      const block =
          'event: meta\ndata: ${'{"user_message_id":"u1","tier":"pro"}'}';
      final parsed = parseCoachSseEvent(block);
      expect(parsed, isNotNull);
      expect(parsed!.event, 'meta');
      expect(parsed.data['user_message_id'], 'u1');
      expect(parsed.data['tier'], 'pro');
    });

    test('parses a token block with the streamed text payload', () {
      final block = 'event: token\ndata: ${jsonEncode({'text': 'Hello'})}';
      final parsed = parseCoachSseEvent(block);
      expect(parsed, isNotNull);
      expect(parsed!.event, 'token');
      expect(parsed.data['text'], 'Hello');
    });

    test('returns null when the block has no data line', () {
      const block = 'event: token';
      expect(parseCoachSseEvent(block), isNull);
    });

    test('returns null when the data payload is invalid JSON', () {
      const block = 'event: token\ndata: not-json{';
      expect(parseCoachSseEvent(block), isNull);
    });

    test('returns null when the data payload is non-Map JSON', () {
      const block = 'event: token\ndata: [1, 2, 3]';
      expect(parseCoachSseEvent(block), isNull);
    });

    test('defaults event to "message" when no event line is present', () {
      final block = 'data: ${jsonEncode({'text': 'no header'})}';
      final parsed = parseCoachSseEvent(block);
      expect(parsed, isNotNull);
      expect(parsed!.event, 'message');
      expect(parsed.data['text'], 'no header');
    });

    test('concatenates multi-line data fields the spec allows', () {
      // SSE spec lets a single event use multiple data: lines that get
      // concatenated; the parser implements the simpler "string concat"
      // form (no inserted newline) which matches the server's emitter.
      final block =
          'event: done\ndata: {"assistant_message_id":\ndata: "a1"}';
      final parsed = parseCoachSseEvent(block);
      expect(parsed, isNotNull);
      expect(parsed!.event, 'done');
      expect(parsed.data['assistant_message_id'], 'a1');
    });

    test('parses a done block with usage cache stats', () {
      final block = 'event: done\ndata: ${jsonEncode({
            'assistant_message_id': 'a1',
            'cache': {
              'cache_read_input_tokens': 100,
              'cache_creation_input_tokens': 50,
              'input_tokens': 10,
              'output_tokens': 20,
            },
          })}';
      final parsed = parseCoachSseEvent(block);
      expect(parsed, isNotNull);
      expect(parsed!.event, 'done');
      expect(parsed.data['assistant_message_id'], 'a1');
      expect(parsed.data['cache']['output_tokens'], 20);
    });
  });
}
