import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards on the Art 9 weigh-in deploy gate, and on whether the
/// surface it gates is actually behind it. Dart mirror of the web
/// `runs/weigh_in_flag.test.ts`, which had no counterpart here.
///
/// The flag exists so no Art 9 health data can be collected before owner +
/// CISO + counsel sign it off (decisions § 150), and the DB is only the other
/// half of the pair — a crossing's health columns persist only when the
/// checkpoint requires a weigh-in AND the RPC caller passes consent. A surface
/// that renders is a surface that asks, which is why the coverage that matters
/// is on the SCREEN and not only on the parse.
String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the gate is fail-closed and routed through the canonical parse', () {
    final flag = _read('lib/weigh_in_flag.dart');
    expect(flag.contains("'WEIGH_IN_GATE'"), true,
        reason: 'the gate must read WEIGH_IN_GATE from dotenv');
    // The affirmative set itself lives in env_flag.dart and is pinned there;
    // what this asserts is that the gate delegates rather than carrying a copy
    // (decisions § 709 — this gate used to accept `1` / `true` alone, so an
    // operator who set WEIGH_IN_GATE=yes silently got the fields off).
    expect(flag.contains('isTruthyFlagValue(raw)'), true,
        reason: 'the parse must delegate to isTruthyFlagValue');
    expect(RegExp(r'catch \(_\) \{[^}]*return false;').hasMatch(flag), true,
        reason: 'an unreadable dotenv must fail closed');
    expect(RegExp(r'\?\?\s*true').hasMatch(flag), false,
        reason: 'the gate must not default to on');
  });

  test('every Art 9 weigh-in affordance on the check-in screen is behind the gate', () {
    final screen = _read('lib/screens/checkpoint_checkin_screen.dart');
    expect(screen.contains("dotenv.env['WEIGH_IN_GATE']"), false,
        reason: 'the screen must read the gate getter, not the env key — a guard '
            'written at the call site is only as good as that call site');

    // The sheet that collects body weight, the medical-hold flag and the
    // organiser consent tick.
    final sheetAt = screen.indexOf('await _showWeighInSheet();');
    expect(sheetAt >= 0, true,
        reason: 'the screen no longer opens the weigh-in sheet — guard is stale');
    final guardAt = screen.lastIndexOf('if (weighInGate && cp.requiresWeighIn) {', sheetAt);
    expect(guardAt >= 0 && sheetAt - guardAt < 200, true,
        reason: 'the weigh-in sheet must open only under the deploy gate AND the '
            "checkpoint's own requiresWeighIn");

    // The checkpoint picker's weigh-in marker, the one other place the surface
    // announces itself before anything is collected.
    final markerAt = screen.indexOf("'\${cp.name}  ⚖'");
    expect(markerAt >= 0, true,
        reason: 'the screen no longer marks weigh-in checkpoints — guard is stale');
    expect(screen.lastIndexOf('cp.requiresWeighIn && weighInGate', markerAt) >= 0, true,
        reason: 'the weigh-in marker must render only under the gate');

    // Nothing may read the gate a third time without this guard being told:
    // an ungated third affordance is exactly what the guard exists to catch.
    expect('weighInGate'.allMatches(screen).length, 2,
        reason: 'a new weighInGate read has appeared — add it to this guard, or it '
            'is an Art 9 affordance nothing checks');
  });

  test('the consent term is only sent from behind an explicit tick', () {
    final screen = _read('lib/screens/checkpoint_checkin_screen.dart');
    final consentAt = screen.indexOf('healthConsent: healthConsent');
    expect(consentAt >= 0, true,
        reason: 'the upsert must still carry the consent term — guard is stale');
    // `healthConsent` starts false and is only ever raised from the sheet's own
    // result, which the gate above already fences. A default of true, or a
    // second writer, would send p_health_consent for a runner who never ticked.
    final written = RegExp(r'healthConsent = ([^;]+);')
        .allMatches(screen)
        .map((m) => m.group(1)!)
        .toSet();
    expect(written, {'false', 'result.consent'},
        reason: 'the consent term starts false and is raised only from the '
            'sheet result the gate above fences; any other writer sends '
            'p_health_consent for a runner who never ticked');
  });
}
