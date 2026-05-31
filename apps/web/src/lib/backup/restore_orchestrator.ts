/**
 * Pure-logic orchestrator extracted from `restoreBackup` so the
 * profile / runs / routes / tracks upsert loop is unit-testable
 * without booting supabase-js. The Supabase-bound surface lives
 * behind the [RestoreBackend] interface; production wires a
 * thin adapter, tests wire a counting fake.
 *
 * Mirrors the mobile shape — the load-bearing logic is the same,
 * but the wire to Supabase differs (JS supabase-js vs Dart
 * supabase_flutter). Cross-platform on-disk format is pinned by
 * `apps/mobile_android/test/backup_format_compat_test.dart`.
 */

import {
	coalesceActivityType,
	extractEventIds,
	stripServerManagedProfileFields,
	type ParsedBackup
} from './backup_reader';

export interface RestoreProgress {
	stage: 'reading' | 'profile' | 'tracks' | 'runs' | 'routes' | 'done';
	current: number;
	total: number;
}

export interface RestoreResult {
	runsImported: number;
	routesImported: number;
	tracksUploaded: number;
	profileRestored: boolean;
	warnings: string[];
}

/**
 * Minimal interface the orchestrator needs to talk to Supabase.
 * Production wires a real supabase-js adapter; tests substitute a
 * counter-tracking fake.
 *
 * Every method may reject — the orchestrator catches and records
 * the failure as a `warning` rather than aborting the whole
 * restore. A backup that lands 95 of 100 runs is far more useful
 * than one that fails entirely on the 6th.
 */
export interface RestoreBackend {
	upsertProfile(row: Record<string, unknown>): Promise<void>;
	upsertSettings(prefs: Record<string, unknown>): Promise<void>;
	uploadTrack(path: string, bytes: Uint8Array): Promise<void>;
	upsertRun(row: Record<string, unknown>): Promise<void>;
	upsertRoute(row: Record<string, unknown>): Promise<void>;
	/**
	 * Returns the subset of `ids` that exist in the destination
	 * `events` table. Runs whose `event_id` doesn't resolve get
	 * their event_id nulled so a cross-account import doesn't
	 * FK-fail.
	 */
	fetchValidEventIds(ids: string[]): Promise<Set<string>>;
}

export interface RestoreOrchestrateOptions {
	generateNewIds?: boolean;
	onProgress?: (p: RestoreProgress) => void;
	/** Test seam: override `crypto.randomUUID()` for deterministic ids. */
	randomUUID?: () => string;
}

export async function restoreOrchestrate(
	parsed: ParsedBackup,
	userId: string,
	backend: RestoreBackend,
	opts: RestoreOrchestrateOptions = {}
): Promise<RestoreResult> {
	const onProgress = opts.onProgress;
	const newUUID = opts.randomUUID ?? (() => crypto.randomUUID());
	const result: RestoreResult = {
		runsImported: 0,
		routesImported: 0,
		tracksUploaded: 0,
		profileRestored: false,
		warnings: []
	};

	// Profile + settings first — later rows may reference preferences.
	if (parsed.profile) {
		onProgress?.({ stage: 'profile', current: 0, total: 1 });
		try {
			const portableProfile = stripServerManagedProfileFields(parsed.profile);
			await backend.upsertProfile({ ...portableProfile, id: userId });
			result.profileRestored = true;
		} catch (e) {
			result.warnings.push(`profile: ${(e as Error).message}`);
		}
	}
	if (Object.keys(parsed.settingsPrefs).length > 0) {
		try {
			await backend.upsertSettings(parsed.settingsPrefs);
		} catch (e) {
			result.warnings.push(`settings_prefs: ${(e as Error).message}`);
		}
	}

	// Runs + tracks.
	if (parsed.runs.length > 0) {
		const runs = parsed.runs;
		const incomingEventIds = extractEventIds(runs);
		const validEventIds =
			incomingEventIds.length > 0
				? await backend.fetchValidEventIds(incomingEventIds)
				: new Set<string>();

		let i = 0;
		for (const r of runs) {
			onProgress?.({ stage: 'runs', current: i, total: runs.length });
			const origId = r.id as string;
			const newId = opts.generateNewIds ? newUUID() : origId;

			let trackUrl: string | null = null;
			const trackBytes = await parsed.getTrackBytes(origId);
			if (trackBytes) {
				const path = `${userId}/${newId}.json.gz`;
				try {
					await backend.uploadTrack(path, trackBytes);
					trackUrl = path;
					result.tracksUploaded++;
				} catch (e) {
					result.warnings.push(`track ${origId}: ${(e as Error).message}`);
				}
			}

			const eventId =
				typeof r.event_id === 'string' && validEventIds.has(r.event_id)
					? r.event_id
					: null;

			const row = {
				...r,
				id: newId,
				user_id: userId,
				event_id: eventId,
				track_url: trackUrl,
				metadata: coalesceActivityType(r.metadata)
			};

			try {
				await backend.upsertRun(row);
				result.runsImported++;
			} catch (e) {
				result.warnings.push(`run ${origId}: ${(e as Error).message}`);
			}
			i++;
		}
	}

	// Routes.
	if (parsed.routes.length > 0) {
		const routes = parsed.routes;
		let i = 0;
		for (const r of routes) {
			onProgress?.({ stage: 'routes', current: i, total: routes.length });
			const newId = opts.generateNewIds ? newUUID() : (r.id as string);
			try {
				await backend.upsertRoute({ ...r, id: newId, user_id: userId });
				result.routesImported++;
			} catch (e) {
				result.warnings.push(`route ${r.id}: ${(e as Error).message}`);
			}
			i++;
		}
	}

	onProgress?.({ stage: 'done', current: 1, total: 1 });
	return result;
}
