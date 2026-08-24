/// Canonical parser for a boolean feature-flag env value.
///
/// Every fail-closed deploy gate on this platform reads its dart-define /
/// dotenv string through this one function so the accepted-affirmative set
/// can't drift between flags. It used to: four gates each spelled the chain
/// out, and the weigh-in gate spelled a shorter one, so `WEIGH_IN_GATE=yes`
/// silently left the weigh-in fields off while the same value turned every
/// other gate on (decisions § 709).
///
/// Accepts `1`, `true`, `yes`, `on` — trimmed and case-insensitive — so
/// `TRUE`, ` yes `, `On` all enable, matching operator intuition. An unset /
/// empty / unrecognised value reads as `false`: a flag can only ever be
/// turned ON by an explicit affirmative, never left on by a typo.
///
/// Dart twin of `apps/web/src/lib/core/env_flag.ts` — the accepted set is one
/// contract across both platforms, so keep them in lockstep.
library;

bool isTruthyFlagValue(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  return v == '1' || v == 'true' || v == 'yes' || v == 'on';
}
