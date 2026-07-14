/// Off-route → auto-notify-contact detection helper (docs/features/safety.md,
/// persona-woman). The overdue-escalation net only fires on telemetry
/// *silence*; this is the complementary trigger for a runner who is still
/// moving and still pinging but has left — and stayed off — their planned
/// route. It decides WHEN a sustained off-route condition should escalate to
/// the runner's trusted contacts, reusing the same server-side notify path
/// (the `escalate_run_off_route` RPC → `safety_email` / `safety_sms` jobs).
///
/// Pure + stateful (no clock, no I/O): the caller feeds it the per-snapshot
/// off-route distance + a `nowMs`, so it is trivially testable and the run
/// screen can drive it from the recorder's snapshot stream. TS↔Dart parity
/// pair with `apps/web/src/lib/safety/off_route_alert.ts` — keep in lockstep.
///
/// Recording is mobile-only, so the *trigger surface* lives on the run screen;
/// this detector is the twinned decision logic (decisions §24 — the pure core
/// is canonical, the wiring is the platform-additive surface).
library;

/// How far off the planned route (metres) the runner must be for the alert
/// clock to run. Deliberately larger than the 40 m off-route *banner*
/// threshold (`_offRouteThresholdMetres` on the run screen): the banner is a
/// gentle "you've drifted" nudge, this is the stronger "genuinely off course"
/// signal that justifies pinging a contact.
const double offRouteAlertDistanceM = 75;

/// How long (ms) the runner must stay continuously beyond the distance
/// threshold before the alert fires. Debounce: a single GPS spike or a brief
/// corner-cut dips back under the threshold and resets the clock, so only a
/// sustained departure escalates.
const int offRouteAlertSustainMs = 90 * 1000;

/// Stateful sustained-off-route detector. One instance per recording run.
/// [update] returns true EXACTLY ONCE — the first snapshot at which the runner
/// has been continuously off-route beyond the threshold for the sustain
/// window. It latches after firing ([hasFired]), because the escalation is
/// once-per-run (the server stamps `metadata.safety_escalated_at`); a runner
/// who returns on-route and leaves again does not re-alert.
class OffRouteAlertDetector {
  final double thresholdM;
  final int sustainMs;
  int? _sinceMs;
  bool _fired = false;

  OffRouteAlertDetector({
    this.thresholdM = offRouteAlertDistanceM,
    this.sustainMs = offRouteAlertSustainMs,
  });

  bool get hasFired => _fired;

  /// Feed the latest off-route distance (null = on-route / no route selected /
  /// no GPS fix) and the current wall-clock ms. Returns true only on the
  /// transition into "sustained off-route" — false forever after (latched)
  /// and false while on-route or still within the debounce window.
  bool update(double? offRouteDistanceMetres, int nowMs) {
    if (_fired) return false;
    if (offRouteDistanceMetres == null ||
        offRouteDistanceMetres <= thresholdM) {
      // Back on (or near enough) the route — reset the sustain clock.
      _sinceMs = null;
      return false;
    }
    // Beyond the threshold. Start the clock on the first such snapshot.
    final since = _sinceMs;
    if (since == null) {
      _sinceMs = nowMs;
      return false;
    }
    if (nowMs - since >= sustainMs) {
      _fired = true;
      return true;
    }
    return false;
  }

  /// Clear all state (e.g. the run screen re-arming for a fresh recording).
  void reset() {
    _sinceMs = null;
    _fired = false;
  }
}

/// Pure parse of the off-route-escalation deploy flag. Truthy only for an
/// explicit `1` / `true` / `yes` / `on` (case-insensitive, trimmed); anything
/// else — including unset / empty / `false` / `0` — is off. Fail-closed: the
/// whole off-route auto-notify path stays unreachable until owner + CISO +
/// counsel sign-off flips the flag at deploy time. The run screen passes
/// `dotenv.env['OFF_ROUTE_ESCALATION_ENABLED']`; the web binding lives in
/// `off_route_flag.ts` — both call this so the parse can't drift.
bool offRouteEscalationEnabled(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  return v == '1' || v == 'true' || v == 'yes' || v == 'on';
}
