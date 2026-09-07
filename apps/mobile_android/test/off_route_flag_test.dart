import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards on the off-route → auto-notify-contact deploy gate.
/// Dart mirror of the web `safety/off_route_flag.test.ts`.
///
/// `off_route_flag` is a registered parity pair that had no mirror suite on
/// EITHER side, which is the thin end of the § 641 failure: the registration
/// makes divergence detectable, but nothing was pinning what either half is
/// supposed to do. The instrument is the one `adaptive_fitness_gate_guard`
/// already uses for a two-line env binding — SOURCE guards on the gate rather
/// than value tests, because the accepted-affirmative set itself belongs to
/// `env_flag.dart` and is pinned in `env_flag_test.dart`.
///
/// The half that mattered most and had nothing on it: the escalation surface
/// must be unreachable while the flag is off. The flag exists so no runner's
/// off-route departure can auto-notify a trusted contact before owner + CISO +
/// counsel sign it off (decisions § 150), and a detector that is armed is a
/// detector that will fire.
String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the gate is fail-closed and routed through the canonical parse', () {
    final flag = _read('lib/off_route_flag.dart');
    expect(flag.contains("'OFF_ROUTE_ESCALATION_ENABLED'"), true,
        reason: 'the gate must read OFF_ROUTE_ESCALATION_ENABLED from dotenv');
    // Delegating is what keeps web and mobile from accepting different values
    // for the same documented flag (decisions § 709). The named function is
    // off_route_alert.dart's, which delegates in turn to env_flag.dart.
    expect(
        RegExp(r'offRouteEscalationEnabled\(\s*dotenv\.env\[').hasMatch(flag), true,
        reason: 'the gate must delegate to offRouteEscalationEnabled, not carry a parse');
    // dotenv not loaded (a widget test, a second entry point, a stripped
    // build) must read as OFF, not throw its way past the gate.
    expect(RegExp(r'catch \(_\) \{[^}]*return false;').hasMatch(flag), true,
        reason: 'an unreadable dotenv must fail closed');
    expect(RegExp(r'\?\?\s*true').hasMatch(flag), false,
        reason: 'the gate must not default to on');
  });

  test('both surfaces read the gate getter rather than re-spelling the env key', () {
    // A guard written at the call site is only as good as that call site, so
    // what is pinned is that no call site has an env read of its own to get
    // wrong (decisions § 709 — four gates had spelled theirs inline, in two
    // different fail-closed idioms).
    for (final path in const [
      'lib/screens/run_screen.dart',
      'lib/screens/settings_safety_screen.dart',
    ]) {
      final source = _read(path);
      expect(source.contains('offRouteEscalationGate'), true,
          reason: '$path must read the gate getter');
      expect(source.contains("dotenv.env['OFF_ROUTE_ESCALATION_ENABLED']"), false,
          reason: '$path must not re-spell the env read');
    }
  });

  test('the run screen arms the detector only behind the gate and the opt-in', () {
    final screen = _read('lib/screens/run_screen.dart');
    final at = screen.indexOf('_offRouteAlertDetector = OffRouteAlertDetector();');
    expect(at >= 0, true,
        reason: 'the run screen no longer constructs the detector — guard is stale');
    // The construction sits inside the one conditional; everything before the
    // `if` on the same statement must name the gate AND the pref, or an
    // unsigned-off build arms a detector that can notify a contact.
    final ifAt = screen.lastIndexOf('if (_offRouteEscalationEnabled &&', at);
    expect(ifAt >= 0 && ifAt < at, true,
        reason: 'the detector must be constructed under the deploy-gate conditional');
    final condition = screen.substring(ifAt, at);
    expect(condition.contains('_offRouteAlertsPrefEnabled'), true,
        reason: "the runner's own opt-in must gate the detector as well as the flag");
    expect(condition.contains('_selectedRoute != null'), true,
        reason: 'an off-route distance needs a route, so no route means no detector');
    // Fail-closed: the else branch must clear it rather than leave a detector
    // armed from a previous recording.
    // Whitespace-insensitive on purpose: the claim is that the else branch
    // nulls the detector, not that run_screen.dart is indented a particular
    // way. Pinning the indentation would fail a reformat whose behaviour is
    // identical -- a guard anchored to a spelling rather than to a decision.
    final tail = screen.substring(at).replaceAll(RegExp(r'\s+'), ' ');
    expect(
        tail.startsWith(
            '_offRouteAlertDetector = OffRouteAlertDetector(); } else { _offRouteAlertDetector = null;'),
        true,
        reason: 'a gate that is off must null the detector, not leave the last one armed');
  });

  test('the safety screen renders the off-route toggle only behind the gate', () {
    final screen = _read('lib/screens/settings_safety_screen.dart');
    final at = screen.indexOf('l10n.safetyOffRouteTitle');
    expect(at >= 0, true,
        reason: 'the safety screen no longer renders the off-route toggle — guard is stale');
    final guardAt = screen.lastIndexOf('if (_offRouteEnabled)', at);
    expect(guardAt >= 0, true,
        reason: 'the off-route toggle must sit behind if (_offRouteEnabled)');
    // Nothing may sit between the guard and the toggle but the widget opening
    // it — otherwise the guard is on some other subtree.
    expect(screen.substring(guardAt, at).contains('SwitchListTile'), true,
        reason: 'the guard must be the toggle\'s own conditional');
    expect(screen.substring(0, guardAt).contains('l10n.safetyOffRouteSubtitle'), false,
        reason: 'the off-route copy must not also render outside the gate');
  });
}
