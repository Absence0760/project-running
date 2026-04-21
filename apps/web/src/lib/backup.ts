import JSZip from 'jszip';
import { supabase } from './supabase';
import { auth } from './stores/auth.svelte';

/**
 * Backup + restore for a user's runs, routes, and profile. See
 * `docs/backup_restore.md` for the on-disk format.
 *
 * The archive keeps GPS tracks pre-gzipped so restore can upload them
 * straight into the `runs` Storage bucket without a re-encode step.
 */

export const BACKUP_FORMAT = 'run-app-backup';
export const BACKUP_VERSION = 1;

export interface BackupProgress {
	stage: 'runs' | 'tracks' | 'routes' | 'profile' | 'writing' | 'done';
	current: number;
	total: number;
}

export interface RestoreProgress {
	stage: 'reading' | 'profile' | 'tracks' | 'runs' | 'routes' | 'done';
	current: number;
	total: number;
}

export async function createBackup(
	onProgress?: (p: BackupProgress) => void
): Promise<Blob> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	onProgress?.({ stage: 'runs', current: 0, total: 1 });
	const { data: runs, error: runsErr } = await supabase
		.from('runs')
		.select('*')
		.eq('user_id', userId)
		.order('started_at', { ascending: false });
	if (runsErr) throw runsErr;
	const runRows = runs ?? [];

	onProgress?.({ stage: 'routes', current: 0, total: 1 });
	const { data: routes } = await supabase
		.from('routes')
		.select('*')
		.eq('user_id', userId);

	onProgress?.({ stage: 'profile', current: 0, total: 1 });
	const { data: profile } = await supabase
		.from('user_profiles')
		.select('*')
		.eq('id', userId)
		.maybeSingle();
	const { data: userSettings } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();

	const zip = new JSZip();

	// Strip user_id from rows so the archive is re-homeable.
	const runsOut = runRows.map((r) => {
		const { user_id: _uid, ...rest } = r as Record<string, unknown>;
		return rest;
	});
	zip.file('runs.json', JSON.stringify(runsOut, null, 2));

	const routesOut = (routes ?? []).map((r) => {
		const { user_id: _uid, ...rest } = r as Record<string, unknown>;
		return rest;
	});
	zip.file('routes.json', JSON.stringify(routesOut, null, 2));

	zip.file(
		'profile.json',
		JSON.stringify(
			{
				profile: profile ? stripId(profile) : null,
				settings_prefs: userSettings?.prefs ?? {},
			},
			null,
			2
		)
	);

	// Tracks — download each one as the raw gzipped blob and drop it
	// into the archive verbatim. We deliberately keep the .json.gz form
	// so restore is a byte-for-byte upload.
	const tracksFolder = zip.folder('tracks');
	let fetched = 0;
	const runsWithTracks = runRows.filter((r) => typeof r.track_url === 'string' && r.track_url);
	for (const r of runsWithTracks) {
		onProgress?.({ stage: 'tracks', current: fetched, total: runsWithTracks.length });
		try {
			const { data, error } = await supabase.storage
				.from('runs')
				.download(r.track_url as string);
			if (error || !data) {
				console.warn('track download failed', r.id, error);
				fetched++;
				continue;
			}
			const buf = new Uint8Array(await data.arrayBuffer());
			tracksFolder!.file(`${r.id}.json.gz`, buf);
		} catch (e) {
			console.warn('track download threw', r.id, e);
		}
		fetched++;
	}
	onProgress?.({ stage: 'tracks', current: runsWithTracks.length, total: runsWithTracks.length });

	const manifest = {
		format: BACKUP_FORMAT,
		version: BACKUP_VERSION,
		exported_at: new Date().toISOString(),
		exported_by_user_id: userId,
		exported_from: 'web',
		counts: {
			runs: runRows.length,
			routes: (routes ?? []).length,
			goals: 0,
			tracks: runsWithTracks.length,
		},
	};
	zip.file('manifest.json', JSON.stringify(manifest, null, 2));

	onProgress?.({ stage: 'writing', current: 0, total: 1 });
	const blob = await zip.generateAsync({ type: 'blob', compression: 'DEFLATE' });
	onProgress?.({ stage: 'done', current: 1, total: 1 });
	return blob;
}

export interface RestoreResult {
	runsImported: number;
	routesImported: number;
	tracksUploaded: number;
	profileRestored: boolean;
	warnings: string[];
}

export async function restoreBackup(
	file: File | Blob,
	opts: { generateNewIds?: boolean; onProgress?: (p: RestoreProgress) => void } = {}
): Promise<RestoreResult> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const onProgress = opts.onProgress;

	onProgress?.({ stage: 'reading', current: 0, total: 1 });
	const zip = await JSZip.loadAsync(file);

	const manifestFile = zip.file('manifest.json');
	if (!manifestFile) throw new Error('Not a valid backup — missing manifest.json');
	const manifest = JSON.parse(await manifestFile.async('string'));
	if (manifest.format !== BACKUP_FORMAT) {
		throw new Error(`Unexpected format: ${manifest.format}`);
	}
	if (manifest.version > BACKUP_VERSION) {
		throw new Error(
			`Backup is from a newer version (${manifest.version}). Update the app before restoring.`
		);
	}

	const result: RestoreResult = {
		runsImported: 0,
		routesImported: 0,
		tracksUploaded: 0,
		profileRestored: false,
		warnings: [],
	};

	// Profile + settings first — later rows may reference preferences.
	const profileFile = zip.file('profile.json');
	if (profileFile) {
		onProgress?.({ stage: 'profile', current: 0, total: 1 });
		try {
			const parsed = JSON.parse(await profileFile.async('string'));
			if (parsed.profile) {
				await supabase.from('user_profiles').upsert({
					...parsed.profile,
					id: userId,
				});
				result.profileRestored = true;
			}
			if (parsed.settings_prefs && Object.keys(parsed.settings_prefs).length > 0) {
				await supabase.from('user_settings').upsert({
					user_id: userId,
					prefs: parsed.settings_prefs,
					updated_at: new Date().toISOString(),
				});
			}
		} catch (e) {
			result.warnings.push(`profile: ${(e as Error).message}`);
		}
	}

	// Runs + tracks. We upload the track first, then insert the row with
	// a track_url pointing at the freshly-uploaded file. If the track is
	// missing in the archive we still insert the row without it.
	const runsFile = zip.file('runs.json');
	if (runsFile) {
		const runs = JSON.parse(await runsFile.async('string')) as Record<string, unknown>[];
		const idMap = new Map<string, string>();

		// Resolve valid event ids up front — we null any `event_id` that
		// doesn't resolve, so a cross-account import doesn't FK-fail.
		const incomingEventIds = [
			...new Set(
				runs
					.map((r) => r.event_id)
					.filter((v): v is string => typeof v === 'string' && v.length > 0)
			),
		];
		const validEventIds = new Set<string>();
		if (incomingEventIds.length > 0) {
			const { data } = await supabase
				.from('events')
				.select('id')
				.in('id', incomingEventIds);
			for (const e of data ?? []) validEventIds.add(e.id);
		}

		let i = 0;
		for (const r of runs) {
			onProgress?.({ stage: 'runs', current: i, total: runs.length });
			const origId = r.id as string;
			const newId = opts.generateNewIds ? crypto.randomUUID() : origId;
			idMap.set(origId, newId);

			// Track upload.
			let trackUrl: string | null = null;
			const trackEntry = zip.file(`tracks/${origId}.json.gz`);
			if (trackEntry) {
				try {
					const bytes = await trackEntry.async('uint8array');
					const path = `${userId}/${newId}.json.gz`;
					const { error } = await supabase.storage
						.from('runs')
						.upload(path, bytes, {
							contentType: 'application/json',
							upsert: true,
							cacheControl: '0',
						});
					if (error) throw error;
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
			};

			try {
				const { error } = await supabase
					.from('runs')
					.upsert(row, { onConflict: 'id' });
				if (error) throw error;
				result.runsImported++;
			} catch (e) {
				result.warnings.push(`run ${origId}: ${(e as Error).message}`);
			}
			i++;
		}
	}

	// Routes — simpler, no Storage dependency.
	const routesFile = zip.file('routes.json');
	if (routesFile) {
		const routes = JSON.parse(await routesFile.async('string')) as Record<string, unknown>[];
		let i = 0;
		for (const r of routes) {
			onProgress?.({ stage: 'routes', current: i, total: routes.length });
			const newId = opts.generateNewIds ? crypto.randomUUID() : (r.id as string);
			try {
				const { error } = await supabase
					.from('routes')
					.upsert({ ...r, id: newId, user_id: userId }, { onConflict: 'id' });
				if (error) throw error;
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

function stripId(row: Record<string, unknown>): Record<string, unknown> {
	const { id: _id, ...rest } = row;
	return rest;
}
