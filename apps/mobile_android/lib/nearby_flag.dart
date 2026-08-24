import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'env_flag.dart';

/// The dart-define / dotenv key the gate reads. Web spells the same flag
/// `PUBLIC_ENABLE_NEARBY_RUNNERS`; mobile drops the web-only `PUBLIC_` prefix,
/// as every other mobile deploy flag does.
const String kNearbyRunnersEnvKey = 'ENABLE_NEARBY_RUNNERS';

/// Pure parse of the "runners nearby" deploy flag (issue #466, decisions
/// §270), delegating to the one canonical [isTruthyFlagValue] so the
/// accepted-affirmative set is a single contract across every gate on both
/// platforms (decisions § 709).
///
/// Fail-closed because this is the product's only person-location surface:
/// the nearby list on the People tab and the coarse-area setter in Settings
/// stay unreachable until owner + CISO/counsel sign-off flips the flag at
/// deploy time (location is Art 9-adjacent). The flip is the sign-off-gated
/// action — the code path itself is complete and reviewable either way.
bool nearbyRunnersEnabled(String? raw) => isTruthyFlagValue(raw);

/// The gate as the surfaces read it. An unreadable dotenv — a widget test that
/// never loaded it, a build that ships no env — fails closed rather than
/// throwing its way past the gate.
bool get nearbyRunnersGate {
  try {
    return nearbyRunnersEnabled(dotenv.env[kNearbyRunnersEnvKey]);
  } catch (_) {
    return false;
  }
}
