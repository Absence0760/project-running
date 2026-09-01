/// What the download surface has to say about an archive that came up short.
///
/// `buildBackupZip` merges two very different shortfalls into one
/// `incomplete` list: a track blob whose download failed, and a row read
/// the CALLER already knew was short before the writer ever ran (`runs`,
/// `routes`, the profile). The disclosure on /settings/account spoke only
/// the first, so an archive short of two thousand runs rendered "missing
/// 0 of 0 GPS tracks" — a sentence that reads as nothing being wrong,
/// about the file someone wipes a device on.
///
/// Splitting it here rather than in the page keeps the decision testable:
/// which sentence a shortfall earns is the thing that was wrong, and a
/// Svelte template is the one place this repo cannot measure it.

import type { BackupArchive } from './backup_writer';

/// The one section whose shortfall carries a count worth stating.
export const TRACKS_SECTION = 'tracks';

export interface BackupShortfall {
	/// Track blobs the writer wanted and could not fetch. Zero when the
	/// tracks section is whole — in which case the count sentence must
	/// not be rendered at all.
	missingTracks: number;
	/// Track blobs the writer wanted at all.
	wantedTracks: number;
	/// Every other short section, in the manifest's own vocabulary,
	/// deduped and sorted. `tracks` joins this list when the writer named
	/// it but the counts cannot state a number, so a shortfall is never
	/// disclosed as silence.
	sections: string[];
}

function nonNegative(value: number): number {
	return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}

/// Grade a finished archive into what the surface should disclose, or
/// `null` when it is whole and there is nothing to say.
export function backupShortfall(
	archive: Pick<BackupArchive, 'incomplete' | 'blobsWanted' | 'blobsWritten'>,
): BackupShortfall | null {
	const named = [...new Set(archive.incomplete)].sort();
	if (named.length === 0) return null;

	const wantedTracks = nonNegative(archive.blobsWanted);
	const missingTracks = nonNegative(wantedTracks - nonNegative(archive.blobsWritten));

	// `tracks` earns the count sentence only when there IS a count. Named
	// with none — a caller that reported the section itself — it falls
	// back to being listed, because "we could not write some of your
	// tracks" is still more than the surface used to manage.
	const sections = named.filter(
		(s) => !(s === TRACKS_SECTION && missingTracks > 0),
	);
	return { missingTracks, wantedTracks, sections };
}
