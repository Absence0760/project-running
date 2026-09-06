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
///   3. The transient toast must NOT block taps to the UI beneath it.
///      The pill absorbs taps (for its swipe + optional action button),
///      but the empty band on either side of the centred pill is
///      click-through — otherwise a banner near the top of a screen
///      makes the widgets under it unreachable until it auto-dismisses.
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
      'a banner still on screen when the test ends leaves no pending timer',
      (tester) async {
        // No assertion here on purpose: the framework's own
        // `A Timer is still pending even after the widget tree was disposed`
        // is the assertion, and it is raised from inside the test body — after
        // the harness unmounts the tree, before any `tearDown` runs. So a
        // dismissal timer that outlives the pill can only be answered by the
        // widget cancelling its own, which is what this pins.
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'left up'),
        ));
        await tester.pump();
        expect(find.text('left up'), findsOneWidget);
      },
    );

    testWidgets(
      'a banner inserted but never rendered arms no timer at all',
      (tester) async {
        // showTopBanner can only insert an OverlayEntry; the pill is built on
        // the next frame. A caller that shows one on a path the test never
        // pumps again left a timer behind for a banner nobody ever saw.
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'never rendered'),
        ));
      },
    );

    testWidgets(
      'unmounting the tree under a live banner cancels its dismissal timer',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'about to lose its tree'),
        ));
        await tester.pump();
        expect(find.text('about to lose its tree'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(find.text('about to lose its tree'), findsNothing);
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

  group('showTopBanner — taps pass through the empty band', () {
    testWidgets(
      'a tap in the banner band but outside the pill reaches the widget '
      'below',
      (tester) async {
        var underlyingTapped = 0;
        // No AppBar: the banner (topInset ~ 12 with no Scaffold app bar in
        // scope) renders over the top of the body, so the full-area
        // tappable genuinely underlies the pill's band. An AppBar here
        // would sit beneath the pill and absorb the pass-through tap,
        // masking the behaviour under test.
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (ctx) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => showTopBanner(ctx, 'hi'));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => underlyingTapped++,
                child: const SizedBox.expand(),
              );
            },
          ),
        ));
        await tester.pump(); // run the post-frame callback → insert entry
        await tester.pump(); // let the overlay build the pill
        expect(find.text('hi'), findsOneWidget);

        // The pill is centred within the left:16/right:16 band, so there
        // is an empty band to its left. Before the fix the two
        // Dismissibles wrapped the full-width Center, sizing their opaque
        // hit area to the whole band and swallowing this tap; now they
        // wrap only the pill, so the band is click-through.
        final pillRect = tester.getRect(
          find.byKey(const ValueKey('top_banner:up:hi')),
        );
        expect(
          pillRect.left,
          greaterThan(40),
          reason: 'pill should be centred, leaving an empty left band',
        );

        await tester.tapAt(Offset(20, pillRect.center.dy));
        await tester.pump();
        expect(
          underlyingTapped,
          1,
          reason:
              'A tap in the empty banner band must reach the widget beneath '
              'the banner — the transient toast must not block the UI.',
        );

        // A tap ON the pill is absorbed (the Dismissible is opaque over
        // the pill), so it must NOT also fire the widget beneath.
        await tester.tapAt(pillRect.center);
        await tester.pump();
        expect(
          underlyingTapped,
          1,
          reason: 'A tap on the pill itself is absorbed, not passed through.',
        );
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

  group('showTopBanner — accessibility', () {
    testWidgets(
      'the banner message is a live region so screen readers announce it',
      (tester) async {
        await tester.pumpWidget(_BannerHost(
          onReady: (ctx) => showTopBanner(ctx, 'sync failed'),
        ));
        await tester.pump();

        final liveRegion = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        );
        expect(
          liveRegion,
          findsOneWidget,
          reason: 'The transient banner must be a live region — it replaced '
              'Material SnackBar, which auto-announced to TalkBack/VoiceOver; '
              'without it a blind user gets no feedback on the failures that '
              'flow through here.',
        );
        // The announced node carries the message.
        expect(
          find.descendant(of: liveRegion, matching: find.text('sync failed')),
          findsOneWidget,
        );

        // Drain the auto-dismiss timer so no pending timer trips the framework.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await tester.pump();
      },
    );
  });
}
