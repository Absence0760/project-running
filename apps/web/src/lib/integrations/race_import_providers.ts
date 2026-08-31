import type { MessageKey } from '$lib/i18n/messages';
import type { ImportRaceResultInput } from '$lib/core/data';
import type { RaceProvider } from '$lib/types';

/// Every provider the `race-results-import` Edge Function has a leg for, read
/// off the call it accepts rather than spelled out again.
export type RaceImportProvider = ImportRaceResultInput['provider'];

/// The listing providers whose result import can be reached from a race in the
/// calendar. Derived from the two vocabularies because they are different sets
/// that merely overlap: `paste` is a leg with no listing behind it, and
/// `parkrun` / `manual` / `raceresult` are listings with no leg — those fall
/// through to the manual paste form, which is the correct answer for them.
export type RaceImportLeg = Extract<RaceProvider, Exclude<RaceImportProvider, 'paste'>>;

export interface RaceImportLegSpec {
	/// The `ImportRaceResultInput` field that scopes the pull to this runner.
	/// A bib is a race number; UltraSignup instead reads one athlete's history,
	/// so its scope is an account id and not a bib.
	scopeField: 'bib' | 'ultraSignUpAthleteId';
	/// Whether the Edge Function refuses the call without it. All three legs
	/// reject an unscoped request 400 before any upstream fetch — UltraSignup
	/// only since `ultraSignUpScopeGate`, which replaced a fallback that read
	/// the listing's `provider_race_id` as an athlete id.
	scopeRequired: boolean;
	labelKey: MessageKey;
	hintKey: MessageKey;
	/// Shown in place of the form when the leg's credentials are unset
	/// server-side. Per leg: a runner told "RunSignUp import isn't available"
	/// about a ChronoTrack race learns nothing true.
	unavailableKey: MessageKey;
	inputTestId: string;
	submitTestId: string;
	unavailableTestId: string;
}

export const RACE_IMPORT_LEGS: Record<RaceImportLeg, RaceImportLegSpec> = {
	runsignup: {
		scopeField: 'bib',
		scopeRequired: true,
		labelKey: 'races.bib',
		hintKey: 'races.runSignUpBibHint',
		unavailableKey: 'integrations.runsignupUnavailable',
		inputTestId: 'runsignup-bib',
		submitTestId: 'race-import-runsignup',
		unavailableTestId: 'race-runsignup-unavailable'
	},
	ultrasignup: {
		scopeField: 'ultraSignUpAthleteId',
		scopeRequired: true,
		labelKey: 'races.ultraSignUpAthleteId',
		hintKey: 'races.ultraSignUpAthleteHint',
		unavailableKey: 'integrations.ultrasignupUnavailable',
		inputTestId: 'ultrasignup-athlete',
		submitTestId: 'race-import-ultrasignup',
		unavailableTestId: 'race-ultrasignup-unavailable'
	},
	chronotrack: {
		scopeField: 'bib',
		scopeRequired: true,
		labelKey: 'races.bib',
		hintKey: 'races.chronoTrackBibHint',
		unavailableKey: 'integrations.chronotrackUnavailable',
		inputTestId: 'chronotrack-bib',
		submitTestId: 'race-import-chronotrack',
		unavailableTestId: 'race-chronotrack-unavailable'
	}
};

export const RACE_IMPORT_LEG_NAMES = Object.keys(RACE_IMPORT_LEGS) as RaceImportLeg[];

/// The leg a listing's `provider` reaches, or null when it has none.
/// `RaceListingResult.provider` arrives from the RPC as a bare string, so the
/// narrowing happens here rather than at every call site.
export function raceImportLegFor(provider: string): RaceImportLeg | null {
	return Object.hasOwn(RACE_IMPORT_LEGS, provider) ? (provider as RaceImportLeg) : null;
}
