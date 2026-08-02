// Source-level guards on the plan-generator-v2 P2 fitness direction gate
// (decisions §144, §150). P2 reads health-derived load (CTL/ATL/TSB) into a
// training prescription, and its sign-off rests on two properties that a
// future edit could quietly break:
//
//   1. the gate is FAIL-CLOSED — unset / empty / "false" reads as off, and with
//      it off the engine is passed no fitness at all (exactly shipped P1); and
//   2. the snapshot is NEVER logged or persisted — it flows into one in-memory
//      decision as a call argument and dies there.
//
// The engine half is pinned in plan_adaptive_replan_test.dart; this pins the
// mobile call site. Dart mirror of the web
// `adaptive_fitness_gate_guard.test.ts`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The body of `_adaptiveFitnessInput()` on the plan-detail screen.
String _fitnessInputBody(String screen) {
  final start = screen.indexOf('AdaptiveFitness? _adaptiveFitnessInput()');
  expect(start >= 0, true, reason: 'could not locate _adaptiveFitnessInput — rename?');
  final end = screen.indexOf('void _proposeAdaptiveReplan(', start);
  expect(end > start, true, reason: 'could not locate _proposeAdaptiveReplan after it');
  return screen.substring(start, end);
}

void main() {
  test('the P2 fitness gate is fail-closed and reads ADAPTIVE_FITNESS_GATE', () {
    final screen = _read('lib/screens/plan_detail_screen.dart');
    expect(screen.contains("dotenv.env['ADAPTIVE_FITNESS_GATE']"), true,
        reason: 'the gate must read ADAPTIVE_FITNESS_GATE from dotenv');
    // Delegating to the parity-pair parser is what keeps web and mobile from
    // accepting different values for the same documented flag.
    expect(
        RegExp(r'adaptiveFitnessGateEnabled\(\s*dotenv\.env\[')
            .hasMatch(screen),
        true,
        reason: 'the gate must delegate to the shared adaptiveFitnessGateEnabled parser');
    // dotenv not loaded (widget tests, a stripped build) must read as OFF, not
    // throw its way past the gate.
    expect(RegExp(r'catch \(_\) \{[^}]*return false;').hasMatch(screen), true,
        reason: 'an unreadable dotenv must fail closed');
  });

  test('the plan screen passes no fitness at all while the gate is off', () {
    final body = _fitnessInputBody(_read('lib/screens/plan_detail_screen.dart'));
    expect(body.contains('if (!_adaptiveFitnessGate) return null;'), true,
        reason: '_adaptiveFitnessInput must return null before touching the load series');
    final guardIdx = body.indexOf('_adaptiveFitnessGate');
    final seriesIdx = body.indexOf('computeTrainingLoadSeries');
    expect(seriesIdx > guardIdx, true,
        reason: 'the load series must only be computed after the gate check');
  });

  test('the fitness snapshot is never stored, logged, or persisted by the plan screen', () {
    final screen = _read('lib/screens/plan_detail_screen.dart');

    // It exists only as a call argument — never bound to a field or to widget
    // state, so there is nothing for a later write to pick up.
    final calls = RegExp(r'(?<!AdaptiveFitness\? )_adaptiveFitnessInput\(\)')
        .allMatches(screen)
        .length;
    expect(calls, 1, reason: '_adaptiveFitnessInput() must be called exactly once');
    expect(screen.contains('fitness: _adaptiveFitnessInput(),'), true,
        reason: 'the snapshot must be passed straight into adaptiveReplanRemaining');
    expect(RegExp(r'=\s*_adaptiveFitnessInput\(\)').hasMatch(screen), false,
        reason: 'the snapshot must not be assigned to a field or local');
    expect(RegExp(r'AdaptiveFitness\??\s+_\w+\s*;').hasMatch(screen), false,
        reason: 'the screen must not hold an AdaptiveFitness field');

    final body = _fitnessInputBody(screen);
    expect(RegExp(r'\b(print|debugPrint)\s*\(').hasMatch(body), false,
        reason: 'the snapshot must never be logged');

    // The only thing an applied re-plan writes is the workout distance the
    // shipped engine proposed — no load column, no new field.
    final applyStart = screen.indexOf('Future<void> _applyReplan()');
    expect(applyStart >= 0, true, reason: 'could not locate _applyReplan — rename?');
    final applyBody = screen.substring(
        applyStart, screen.indexOf('await _load();', applyStart));
    expect(applyBody.isNotEmpty, true, reason: 'could not slice _applyReplan');
    expect(
        RegExp(r'updateWorkout\(c\.workoutId,\s*targetDistanceM:\s*c\.toMetres\)')
            .hasMatch(applyBody),
        true,
        reason: 'applying a re-plan must write only targetDistanceM');
    expect(RegExp(r'\b(tsb|atl|ctl)\b').hasMatch(applyBody), false,
        reason: 'the apply path must not carry a load value');
  });
}
