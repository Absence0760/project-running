/// Which archive member (if any) a Strava `activities.csv` row promises,
/// and whether the archive kept that promise.
///
/// Split out of `strava-zip.ts`'s `importOne` so the decision is testable
/// without `saveRun` (and therefore without supabase-js). Sibling of
/// `strava-zip-classify.ts` (what a member's extension means) and
/// `strava-zip-disposition.ts` (whether a row is imported at all).

import { classifyStravaMember } from './strava-zip-classify';

export type StravaTrackMember =
	/// The row named no file — nothing to look up, import it trackless.
	| { kind: 'none' }
	/// The archive holds the named member and a parser reads its format.
	| { kind: 'member'; parser: 'route' | 'fit'; gzipped: boolean };

/// Resolve the `Filename` column against the archive's member list.
///
/// An empty `Filename` is not a broken export: Strava leaves it empty for
/// a manually-entered or indoor activity, where the row's own date /
/// distance / time is the whole activity. A filename that NAMES a file is
/// a promise, so an archive that does not hold it — or holds it in a
/// format neither parser reads — throws, and the caller's per-row catch
/// reports it through `ImportFailureReport` rather than importing a
/// summary-only run that reads as complete (decisions.md § 664 / § 676;
/// the mobile importer does the same).
///
/// The thrown wording is load-bearing: `classifyImportFailure` buckets
/// both messages as `unparseable`, which is the honest reason — re-running
/// the import cannot conjure a member the archive does not contain.
export function resolveStravaTrackMember(
	filename: string,
	archiveHas: (name: string) => boolean,
): StravaTrackMember {
	if (!filename) return { kind: 'none' };
	if (!archiveHas(filename)) {
		throw new Error(`Malformed export: track file not found in zip: ${filename}`);
	}
	const { parser, gzipped } = classifyStravaMember(filename);
	if (!parser) {
		throw new Error(`Unsupported file format: ${filename}`);
	}
	return { kind: 'member', parser, gzipped };
}
