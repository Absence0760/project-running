import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'env_flag.dart';

/// The dart-define / dotenv key the gate reads.
///
/// The dropped-`PUBLIC_`-prefix convention the other two deploy gates follow
/// is BROKEN here, and it is broken in the stem rather than the prefix: web
/// reads `PUBLIC_WEIGH_IN_ENABLED` (`apps/web/src/lib/runs/weigh_in_flag.ts`),
/// mobile reads `WEIGH_IN_GATE`. So the two names do not derive from one
/// another and an operator who has set one has NOT set the other -- which
/// matters, because each half is the fail-closed gate on its own platform's
/// Art 9 weigh-in surface. `PUBLIC_WEIGH_IN_GATE`, which this comment used to
/// name, is a variable no file in the repo reads or sets.
const String kWeighInEnvKey = 'WEIGH_IN_GATE';

/// Pure parse of the checkpoint weigh-in deploy flag, delegating to the one
/// canonical [isTruthyFlagValue] so the accepted-affirmative set is a single
/// contract across every gate on both platforms (decisions § 709). This gate
/// used to accept `1` / `true` alone, so an operator who set `WEIGH_IN_GATE=yes`
/// was silently left with the fields off.
bool weighInEnabled(String? raw) => isTruthyFlagValue(raw);

/// The gate as the checkpoint check-in screen reads it — the mobile twin of
/// web's `runs/weigh_in_flag.ts`.
///
/// The read is guarded because `dotenv.env` throws `NotInitializedError` until
/// something has loaded it, and a gate that throws is a gate whose answer
/// depends on the caller's error handling rather than on the flag. Failing
/// closed is the only safe answer here: the P3 weigh-in fields are Art 9
/// health data and stay uncollected until owner + CISO + counsel sign-off
/// flips the flag at deploy time (decisions §150).
bool get weighInGate {
  try {
    return weighInEnabled(dotenv.env[kWeighInEnvKey]);
  } catch (_) {
    return false;
  }
}
