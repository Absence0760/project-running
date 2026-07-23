/**
 * Feature flag gating the opt-in "runners nearby" discovery surface (issue #466).
 *
 * OFF by default. The whole person-location discovery surface — the nearby
 * list on the People tab and the coarse-area setter in Settings — stays inert
 * in prod until this flag is flipped, which is the owner + CISO/counsel
 * sign-off-gated action (location is Art 9-adjacent data). Fail-closed: an
 * unset / unrecognised value reads as OFF. Mirrors the paid-events + adaptive-
 * fitness pre-prod gates (decisions §139 / §144).
 */
import { isTruthyFlagValue } from '../core/env_flag';

export const NEARBY_RUNNERS_ENABLED = isTruthyFlagValue(
	import.meta.env.PUBLIC_ENABLE_NEARBY_RUNNERS,
);
