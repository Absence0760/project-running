import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'off_route_alert.dart';

/// The dart-define / dotenv key the gate reads. Web spells the same flag
/// `PUBLIC_OFF_ROUTE_ESCALATION_ENABLED`; mobile drops the web-only `PUBLIC_`
/// prefix, as every other mobile deploy flag does.
const String kOffRouteEscalationEnvKey = 'OFF_ROUTE_ESCALATION_ENABLED';

/// The off-route auto-notify deploy gate as the surfaces read it — the mobile
/// twin of web's `safety/off_route_flag.ts`, keeping the env binding out of
/// the `off_route_alert` parity pair.
///
/// The read is guarded because `dotenv.env` throws `NotInitializedError` until
/// something has loaded it, and a gate that throws is a gate whose answer
/// depends on the caller's error handling rather than on the flag. Failing
/// closed is the only safe answer: the whole escalation path stays inert until
/// owner + CISO + counsel sign-off flips the flag at deploy time.
bool get offRouteEscalationGate {
  try {
    return offRouteEscalationEnabled(dotenv.env[kOffRouteEscalationEnvKey]);
  } catch (_) {
    return false;
  }
}
