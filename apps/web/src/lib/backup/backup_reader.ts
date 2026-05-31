/**
 * Pure ZIP-archive parsing for the `run-app-backup` v1 format.
 *
 * Extracted from `backup.ts` so the parsing + manifest-validation +
 * profile-field-stripping logic is unit-testable without booting
 * supabase-js. The Supabase upserts that follow stay in
 * `restoreBackup` — those need a live client.
 *
 * Mirrors the writer side at `backup_writer.ts`; both must stay in
 * lockstep on the on-disk format. The manifest validation logic
 * here is the single source of truth for "what is a valid v1
 * backup" on the web; mobile applies the same logic in
 * `apps/mobile_android/lib/backup.dart`.
 */

import JSZip from 'jszip';

import { BACKUP_FORMAT, BACKUP_VERSION } from './backup_writer';

export interface ParsedBackup {
	/** The parsed manifest. Guaranteed `format == BACKUP_FORMAT` and `version <= BACKUP_VERSION`. */
	manifest: { format: string; version: number; [k: string]: unknown };
	/** Rows from `runs.json`. Empty array when the file is absent. */
	runs: Record<string, unknown>[];
	/** Rows from `routes.json`. Empty array when the file is absent. */
	routes: Record<string, unknown>[];
	/** Parsed `profile` field from `profile.json`. Null when absent. */
	profile: Record<string, unknown> | null;
	/** Parsed `settings_prefs` field from `profile.json`. Empty when absent. */
	settingsPrefs: Record<string, unknown>;
	/** Lazy fetch of `tracks/<runId>.json.gz` as raw bytes; null when absent. */
	getTrackBytes(runId: string): Promise<Uint8Array | null>;
}

/**
 * Open + validate a backup archive. Throws on invalid manifest;
 * everything else is best-effort (missing files → empty defaults).
 *
 * Accepts any JSZip-loadable input: production calls hand a `File`
 * or `Blob` from the file picker; tests can pass `Uint8Array` or
 * `ArrayBuffer` directly so `node --test` doesn't need a `Blob`
 * polyfill round-trip.
 */
export async function parseBackupArchive(
	file: File | Blob | Uint8Array | ArrayBuffer
): Promise<ParsedBackup> {
	const zip = await JSZip.loadAsync(file as Parameters<typeof JSZip.loadAsync>[0]);

	const manifestFile = zip.file('manifest.json');
	if (!manifestFile) {
		throw new Error('Not a valid backup — missing manifest.json');
	}
	const manifest = JSON.parse(await manifestFile.async('string')) as {
		format?: unknown;
		version?: unknown;
		[k: string]: unknown;
	};
	if (manifest.format !== BACKUP_FORMAT) {
		throw new Error(`Unexpected format: ${String(manifest.format)}`);
	}
	const version = typeof manifest.version === 'number' ? manifest.version : 0;
	if (version > BACKUP_VERSION) {
		throw new Error(
			`Backup is from a newer version (${version}). Update the app before restoring.`
		);
	}

	const runsFile = zip.file('runs.json');
	const runs = runsFile
		? (JSON.parse(await runsFile.async('string')) as Record<string, unknown>[])
		: [];

	const routesFile = zip.file('routes.json');
	const routes = routesFile
		? (JSON.parse(await routesFile.async('string')) as Record<string, unknown>[])
		: [];

	let profile: Record<string, unknown> | null = null;
	let settingsPrefs: Record<string, unknown> = {};
	const profileFile = zip.file('profile.json');
	if (profileFile) {
		const parsed = JSON.parse(await profileFile.async('string')) as {
			profile?: unknown;
			settings_prefs?: unknown;
		};
		if (parsed.profile && typeof parsed.profile === 'object') {
			profile = parsed.profile as Record<string, unknown>;
		}
		if (parsed.settings_prefs && typeof parsed.settings_prefs === 'object') {
			settingsPrefs = parsed.settings_prefs as Record<string, unknown>;
		}
	}

	return {
		manifest: {
			...manifest,
			format: manifest.format as string,
			version
		},
		runs,
		routes,
		profile,
		settingsPrefs,
		async getTrackBytes(runId: string): Promise<Uint8Array | null> {
			const entry = zip.file(`tracks/${runId}.json.gz`);
			if (!entry) return null;
			return entry.async('uint8array');
		}
	};
}

/**
 * Strip server-managed fields a client-controlled archive must not
 * round-trip. The 20260718_001 INSERT WITH CHECK + 20260624_001
 * UPDATE trigger reject these for non-service-role callers anyway;
 * stripping here means the rest of the profile (display_name,
 * avatar_url, preferred_unit, etc.) upserts cleanly instead of
 * failing the whole row.
 */
export function stripServerManagedProfileFields(
	profile: Record<string, unknown>
): Record<string, unknown> {
	const {
		subscription_tier: _tier,
		subscription_at: _subAt,
		parkrun_number: _parkrun,
		...rest
	} = profile;
	void _tier;
	void _subAt;
	void _parkrun;
	return rest;
}

/**
 * Older backups (pre-Apr 2026) may lack `metadata.activity_type`.
 * The DB CHECK trigger requires it on insert, so coalesce to
 * `'run'` on restore. The user can still edit it afterwards.
 */
export function coalesceActivityType(metadata: unknown): Record<string, unknown> {
	const md =
		metadata && typeof metadata === 'object'
			? { ...(metadata as Record<string, unknown>) }
			: ({} as Record<string, unknown>);
	if (typeof md.activity_type !== 'string') {
		md.activity_type = 'run';
	}
	return md;
}

/**
 * Distinct `event_id` strings across a list of run rows. Used to
 * pre-resolve which `event_id`s the destination account actually
 * owns — restore nulls any that don't resolve to avoid FK failures
 * on cross-account imports.
 */
export function extractEventIds(runs: Record<string, unknown>[]): string[] {
	return [
		...new Set(
			runs
				.map((r) => r.event_id)
				.filter((v): v is string => typeof v === 'string' && v.length > 0)
		)
	];
}
