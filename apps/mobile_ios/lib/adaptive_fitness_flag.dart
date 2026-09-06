import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'plan_adaptive_replan.dart';

/// The dart-define / dotenv key the gate reads. Web spells the same flag
/// `PUBLIC_ADAPTIVE_FITNESS_GATE`; mobile drops the web-only `PUBLIC_` prefix,
/// as every other mobile deploy flag does.
const String kAdaptiveFitnessGateEnvKey = 'ADAPTIVE_FITNESS_GATE';

/// The plan-generator-v2 P2 fitness-direction gate as the surfaces read it —
/// the Dart twin of `apps/web/src/lib/training/adaptive_fitness_flag.ts`,
/// keeping the env binding out of the `plan_adaptive_replan` parity pair.
///
/// The read is guarded because `dotenv.env` throws `NotInitializedError` until
/// something has loaded it, and a gate that throws is a gate whose answer
/// depends on the caller's error handling rather than on the flag. Failing
/// closed is the only safe answer: the health-derived-load → prescription path
/// stays inert until CISO / Security-Analyst sign-off flips the flag at deploy
/// time (decisions §144 + §150).
bool get adaptiveFitnessGate {
  try {
    return adaptiveFitnessGateEnabled(dotenv.env[kAdaptiveFitnessGateEnvKey]);
  } catch (_) {
    return false;
  }
}
