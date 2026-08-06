import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/undo_queue.dart';
import '../lib/widgets/undo_bar.dart';

/// Every semantics label in the compiled tree — what TalkBack / VoiceOver
/// can actually reach, as opposed to what is merely painted.
List<String> _semanticLabels(WidgetTester tester) {
  final labels = <String>[];
  void walk(SemanticsNode n) {
    if (n.label.isNotEmpty) labels.add(n.label);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return labels;
}

Widget _host({required void Function(BuildContext) onDelete}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(
    appBar: AppBar(title: const Text('LIST')),
    body: Center(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => onDelete(context),
          child: const Text('DELETE'),
        ),
      ),
    ),
  ),
);

/// An armed window owns a real `Timer`, and a test that ends while it is
/// pending fails on `!timersPending`. Draining past the window is also the
/// only honest way to assert the commit landed.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 9));

void main() {
  tearDown(debugResetUndo);

  testWidgets('the pill appears and the mutation is held', (tester) async {
    var committed = 0;
    await tester.pumpWidget(
      _host(
        onDelete: (context) => deferDestructive(
          context,
          DeferredDestruction(
            message: 'Porridge removed',
            commit: () async => committed++,
            restore: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    expect(find.text('Porridge removed'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(committed, 0, reason: 'nothing is destroyed while undo is on offer');

    await _drain(tester);
    expect(committed, 1);
    expect(find.text('Porridge removed'), findsNothing);
  });

  testWidgets('tapping Undo cancels the mutation and restores', (tester) async {
    var committed = 0;
    var restored = 0;
    await tester.pumpWidget(
      _host(
        onDelete: (context) => deferDestructive(
          context,
          DeferredDestruction(
            message: 'Porridge removed',
            commit: () async => committed++,
            restore: () => restored++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(committed, 0);
    expect(restored, 1);
    expect(find.text('Porridge removed'), findsNothing);
    expect(find.text('Restored'), findsOneWidget);
    await _drain(tester);
    expect(committed, 0, reason: 'the cancelled timer must not fire later');
  });

  testWidgets('the dismiss button commits immediately', (tester) async {
    var committed = 0;
    await tester.pumpWidget(
      _host(
        onDelete: (context) => deferDestructive(
          context,
          DeferredDestruction(
            message: 'Porridge removed',
            commit: () async => committed++,
            restore: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(committed, 1);
    expect(find.text('Porridge removed'), findsNothing);
  });

  testWidgets('a failed commit restores and reports', (tester) async {
    var restored = 0;
    Object? reported;
    await tester.pumpWidget(
      _host(
        onDelete: (context) => deferDestructive(
          context,
          DeferredDestruction(
            message: 'Porridge removed',
            commit: () async => throw StateError('23503'),
            restore: () => restored++,
            onCommitError: (e) => reported = e,
          ),
        ),
      ),
    );
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    await _drain(tester);
    expect(restored, 1);
    expect(reported, isA<StateError>());
  });

  testWidgets('the offer survives a route pop and the commit still lands', (tester) async {
    var committed = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (outer) => TextButton(
                onPressed: () => Navigator.push(
                  outer,
                  MaterialPageRoute(
                    builder: (inner) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => deferDestructive(
                            inner,
                            DeferredDestruction(
                              message: 'Porridge removed',
                              commit: () async => committed++,
                              restore: () {},
                            ),
                          ),
                          child: const Text('DELETE'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('GO'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    nav.currentState!.pop();
    // Not pumpAndSettle: its argument is the per-frame increment, so it would
    // run the countdown animation to completion and commit before we look.
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Porridge removed'),
      findsOneWidget,
      reason: 'a pop must not discard the offer',
    );
    await _drain(tester);
    expect(committed, 1, reason: 'the row lands, it does not vanish');
  });

  // ---------------------------------------------------------------------------
  // Accessibility: the reason the host is a root Overlay entry and not a
  // SnackBar. A modal route's barrier carries BlockSemantics, which drops the
  // whole route beneath it — including that route's Scaffold, where a SnackBar
  // lives. Both halves are pinned so a later round cannot "simplify" the host
  // back into the dead end.
  // ---------------------------------------------------------------------------

  testWidgets('the pill stays in the semantics tree under a dialog barrier', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        onDelete: (context) {
          showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('DIALOGCONTENT')),
          );
          deferDestructive(
            context,
            DeferredDestruction(
              message: 'Porridge removed',
              commit: () async {},
              restore: () {},
            ),
          );
        },
      ),
    );
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final labels = _semanticLabels(tester);
    expect(labels, contains('DIALOGCONTENT'));
    expect(
      labels.any((l) => l.contains('Porridge removed')),
      isTrue,
      reason:
          'a screen reader must be able to reach the only undo affordance '
          'while a modal is up (WCAG 2.1.1)',
    );
    expect(labels, contains('Undo'));
    handle.dispose();
    await _drain(tester);
  });

  testWidgets('the pill stays in the semantics tree under a bottom sheet', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        onDelete: (context) {
          showModalBottomSheet<void>(
            context: context,
            builder: (_) => const Text('SHEETCONTENT'),
          );
          deferDestructive(
            context,
            DeferredDestruction(
              message: 'Observation removed',
              commit: () async {},
              restore: () {},
            ),
          );
        },
      ),
    );
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final labels = _semanticLabels(tester);
    expect(labels, contains('SHEETCONTENT'));
    expect(labels.any((l) => l.contains('Observation removed')), isTrue);
    expect(labels, contains('Undo'));
    handle.dispose();
    await _drain(tester);
  });

  testWidgets(
    'a SnackBar under the same barrier is NOT in the semantics tree',
    (tester) async {
      final handle = tester.ensureSemantics();
      final messenger = GlobalKey<ScaffoldMessengerState>();
      late BuildContext screenContext;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messenger,
          home: Scaffold(
            body: Builder(
              builder: (c) {
                screenContext = c;
                return const Text('SCREENCONTENT');
              },
            ),
          ),
        ),
      );
      showDialog<void>(
        context: screenContext,
        builder: (_) => const AlertDialog(content: Text('DIALOGCONTENT')),
      );
      await tester.pumpAndSettle();
      messenger.currentState!.showSnackBar(
        const SnackBar(
          content: Text('SNACKCONTENT'),
          duration: Duration(days: 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('SNACKCONTENT'),
        findsOneWidget,
        reason: 'it is painted — that is exactly what makes this trap subtle',
      );
      final labels = _semanticLabels(tester);
      expect(labels, contains('DIALOGCONTENT'));
      expect(labels, isNot(contains('SNACKCONTENT')));
      expect(
        labels,
        isNot(contains('SCREENCONTENT')),
        reason: 'the barrier drops the whole route below it, Scaffold and all',
      );

      messenger.currentState!.removeCurrentSnackBar();
      await tester.pumpAndSettle();
      handle.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // WCAG 2.2.1 — the pref can turn the limit off entirely
  // ---------------------------------------------------------------------------

  testWidgets(
    'undo_window_s = 0 arms no timer — the offer waits for the user',
    (tester) async {
      setUndoWindowS(0);
      var committed = 0;
      await tester.pumpWidget(
        _host(
          onDelete: (context) => deferDestructive(
            context,
            DeferredDestruction(
              message: 'Porridge removed',
              commit: () async => committed++,
              restore: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('DELETE'));
      await tester.pump();
      await tester.pump(const Duration(minutes: 10));
      expect(committed, 0);
      expect(find.text('Porridge removed'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(committed, 1);
    },
  );

  testWidgets('a corrupt undo_window_s falls back to 8 s, never to no-limit', (tester) async {
    setUndoWindowS('forever');
    var committed = 0;
    await tester.pumpWidget(
      _host(
        onDelete: (context) => deferDestructive(
          context,
          DeferredDestruction(
            message: 'Porridge removed',
            commit: () async => committed++,
            restore: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    await _drain(tester);
    expect(committed, 1);
  });

  testWidgets('a second destruction commits the first and takes the slot', (tester) async {
    final committed = <String>[];
    var deferred = 0;
    await tester.pumpWidget(
      _host(
        onDelete: (context) => deferDestructive(
          context,
          DeferredDestruction(
            message: 'Row ${deferred++} removed',
            commit: () async => committed.add('c'),
            restore: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    await tester.tap(find.text('DELETE'));
    await tester.pump();
    expect(committed, hasLength(1));
    expect(find.text('Row 1 removed'), findsOneWidget);
    await _drain(tester);
  });
}
