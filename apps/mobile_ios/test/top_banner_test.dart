import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/top_banner.dart';

/// Coverage of the top-banner notification primitive.
///
/// The banner is the canonical replacement for `ScaffoldMessenger`
/// SnackBar across the mobile app. Two load-bearing UX properties
/// the user surfaced as bugs:
///
///   1. EVERY banner must eventually disappear on its own (no
///      "stuck on screen" failure mode, even when a caller passes
///      a weird `Duration.zero` or forgets to plumb a dismiss).
///   2. Banners must be swipe-dismissible — Material SnackBar
///      gesture parity, so users don't have to wait if they've
///      already read the message.
class _BannerHost extends StatelessWidget {
  final void Function(BuildContext) onReady;
  const _BannerHost({required this.onReady});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (ctx) {
          // Defer the showTopBanner call to a post-frame callback so
          // an Overlay is wired up by the time we ask for one.
          WidgetsBinding.instance.addPostFrameCallback((_) => onReady(ctx));
          return Scaffold(
            appBar: AppBar(title: const Text('host')),
            body: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

void main() {
  group('showTopBanner — auto-dismiss timer', () {
    testWidgets(
      'banner disappears after the default 3 s duration',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'auto-dismiss me'),
        ));
        await tester.pump();
        // Banner is on screen.
        expect(find.text('auto-dismiss me'), findsOneWidget);
        // Tick past the 3-second default.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await tester.pump(); // let the overlay rebuild
        expect(
          find.text('auto-dismiss me'),
          findsNothing,
          reason: 'Default banner must dismiss after 3 s.',
        );
      },
    );

    testWidgets(
      'banner with custom duration (1 s) dismisses on its own clock',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(
            ctx,
            'short-lived',
            duration: const Duration(seconds: 1),
          ),
        ));
        await tester.pump();
        expect(find.text('short-lived'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        expect(find.text('short-lived'), findsNothing);
      },
    );

    testWidgets(
      'custom duration > max ceiling is clamped — banner never sticks '
      'past kTopBannerMaxDuration',
      (tester) async {
        // The hard ceiling defence against a degenerate caller (a
        // refactor that drops a `Duration(days: 1)` accidentally).
        // The clamp guarantees the banner always disappears in
        // bounded time regardless of caller mistakes.
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(
            ctx,
            'long-but-clamped',
            duration: const Duration(days: 1),
          ),
        ));
        await tester.pump();
        expect(find.text('long-but-clamped'), findsOneWidget);
        // Pump past the max ceiling (6 s + a bit).
        await tester.pump(kTopBannerMaxDuration);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(
          find.text('long-but-clamped'),
          findsNothing,
          reason:
              'Banner must NOT outlive kTopBannerMaxDuration even if the '
              'caller passed a 1-day duration.',
        );
      },
    );

    testWidgets(
      'kTopBannerMaxDuration constant pinned at 6 s',
      (tester) async {
        // Source-pinned so a refactor that silently widens it
        // (defeating the "always eventually dismiss" property) gets
        // caught at test time.
        expect(kTopBannerMaxDuration, const Duration(seconds: 6));
      },
    );

    testWidgets(
      'a new banner coalesces — the old one disappears immediately, '
      'the new one starts its own timer',
      (tester) async {
        late BuildContext savedCtx;
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) {
            savedCtx = ctx;
            showTopBanner(ctx, 'first');
          },
        ));
        await tester.pump();
        expect(find.text('first'), findsOneWidget);

        // Fire a second banner — single-banner semantics mirror
        // SnackBar; the user shouldn't see two stacked.
        showTopBanner(savedCtx, 'second');
        await tester.pump();
        expect(find.text('first'), findsNothing);
        expect(find.text('second'), findsOneWidget);

        // The second banner has its OWN fresh 3 s timer.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await tester.pump();
        expect(find.text('second'), findsNothing);
      },
    );
  });

  group('showTopBanner — swipe-to-dismiss', () {
    testWidgets(
      'horizontal fling dismisses the banner before its timer fires',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(
            ctx,
            'swipe me away',
            duration: const Duration(seconds: 10),
          ),
        ));
        await tester.pump();
        expect(find.text('swipe me away'), findsOneWidget);

        // Fling left across the banner.
        await tester.fling(
          find.text('swipe me away'),
          const Offset(-400, 0),
          1000,
        );
        // Let the Dismissible animation complete.
        await tester.pumpAndSettle();
        expect(
          find.text('swipe me away'),
          findsNothing,
          reason: 'A horizontal fling must dismiss the banner — Material '
              'SnackBar gesture parity.',
        );
      },
    );

    testWidgets(
      'swipe right also dismisses (DismissDirection.horizontal)',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(
            ctx,
            'rightward swipe',
            duration: const Duration(seconds: 10),
          ),
        ));
        await tester.pump();
        await tester.fling(
          find.text('rightward swipe'),
          const Offset(400, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.text('rightward swipe'), findsNothing);
      },
    );
  });

  group('hideTopBanner', () {
    testWidgets('programmatic dismiss works alongside the timer / swipe',
        (tester) async {
      await tester.pumpWidget(_BannerHost(
        onReady: (ctx) {
          showTopBanner(
            ctx,
            'imperative dismiss',
            duration: const Duration(seconds: 10),
          );
        },
      ));
      await tester.pump();
      expect(find.text('imperative dismiss'), findsOneWidget);
      hideTopBanner();
      await tester.pump();
      expect(find.text('imperative dismiss'), findsNothing);
    });

    testWidgets('hideTopBanner is a no-op when nothing is on screen',
        (tester) async {
      await tester.pumpWidget(_BannerHost(onReady: (_) {}));
      await tester.pump();
      // Should not throw.
      hideTopBanner();
      await tester.pump();
    });
  });
}
