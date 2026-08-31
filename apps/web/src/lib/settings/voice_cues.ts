/// Per-cue voice toggles — the `voice_cue_types` settings-bag key.
///
/// The map is sparse by design: an id ABSENT from it is ON. That keeps a
/// newly-added cue type audible without a migration, and it means a client
/// that has never heard of an id must not write a value for it. Reads
/// therefore fail open and writes MERGE rather than replace, so an older
/// build editing one toggle can't erase the runner's choice for a cue it
/// doesn't know about.
///
/// The ids are a wire contract shared with the Dart `VoiceCue` class in
/// `apps/mobile_*/lib/preferences.dart` (which is what actually speaks the
/// cues — recording is mobile-only). `voice_cues.test.ts` pins them against
/// that file so the two can't drift.

/// Default for the master `voice_feedback_enabled` gate when the key is
/// absent from both bags. The phone — the only surface that speaks — has
/// defaulted ON since v1 (`Preferences.audioCues` in `preferences.dart`),
/// so this is what a runner who never touched the toggle actually hears;
/// web hard-coded `false` here for months and displayed a switch that
/// contradicted the phone's behaviour. `voice_cues.test.ts` reads the Dart
/// source and the settings.md registry row and fails on drift. Decisions § 474.
export const VOICE_FEEDBACK_ENABLED_DEFAULT = true;

export const VOICE_CUE_IDS = [
	'splits',
	'start_finish',
	'off_route',
	'pace_alerts',
	'workout_steps',
	'cutoff_catch_up',
	'marker_targets',
	'phase_transitions',
	'guided_run',
] as const;

export type VoiceCueId = (typeof VOICE_CUE_IDS)[number];

export type VoiceCueMap = Record<string, boolean>;

/// Coerce the opaque jsonb value into a boolean map, dropping anything that
/// isn't a boolean. A malformed bag can only ever lose a suppression, never
/// silence a cue the runner never turned off.
export function readVoiceCueMap(raw: unknown): VoiceCueMap {
	if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return {};
	const out: VoiceCueMap = {};
	for (const [id, value] of Object.entries(raw as Record<string, unknown>)) {
		if (typeof value === 'boolean') out[id] = value;
	}
	return out;
}

export function isVoiceCueEnabled(map: VoiceCueMap, id: string): boolean {
	return map[id] ?? true;
}

export function setVoiceCueEnabled(map: VoiceCueMap, id: string, on: boolean): VoiceCueMap {
	return { ...map, [id]: on };
}
