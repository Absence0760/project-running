/// Streaming section reads for the Art 20 export.
///
/// The old shape collected every row of a section into an array and then
/// `JSON.stringify`'d the lot, which is why `paging.ts` needed a 50,000
/// row ceiling: `live_run_pings` runs into the millions on a deep
/// history and an unbounded collect was an OOM, not a slow export. Here
/// each page is serialised into the archive as it arrives and then
/// dropped, so peak memory is one page — flat in the section's size, and
/// the ceiling is gone.
///
/// Completeness is tracked the same way `manifest.json` already
/// promised: `total` is the database's own count when the server
/// reported one, and `complete` is false whenever the rows written may
/// be short of it — a failed page, or the wall-clock budget expiring
/// mid-walk. A section is never silently truncated.
///
/// `keep` exists because a few sections are read for their VALUES as
/// well as their bytes (the gear ids `run_gear` filters on, the photo
/// paths the blob sweep downloads, the track urls per run). Retaining a
/// few identifiers per row is bounded by a couple of hundred bytes;
/// retaining the rows was not.

import { EXPORT_PAGE_SIZE } from './paging.ts';
import type { ExportBudget } from './export_budget.ts';

export interface SectionPage<T> {
	rows: T[];
	/// The server's authoritative count for the whole filtered set
	/// (PostgREST's `Content-Range` total), or null when this page
	/// didn't ask for one.
	total: number | null;
}

export interface SectionSummary {
	/// Rows serialised into the archive.
	written: number;
	/// The count `manifest.json` publishes: the server's own total when
	/// it reported one, else the rows read.
	total: number;
	/// False whenever `written` may be short of `total`.
	complete: boolean;
}

export interface SectionOptions<T> {
	pageSize?: number;
	/// Projection / redaction applied before serialising.
	shape?: (row: T) => unknown;
	/// Called once per row, in order, before it is serialised.
	keep?: (row: T) => void;
	budget?: ExportBudget;
	/// Name used when the budget cuts the walk short.
	label?: string;
}

export interface JsonSection {
	/// False when the section carries no rows and therefore gets no
	/// archive entry — the convention both export paths share. A section
	/// that failed on its FIRST page is also unopened, but its summary is
	/// incomplete, so the caller still records it: an absent entry must
	/// never be readable as "the subject has none of these".
	opened: boolean;
	/// Live while `body` drains; final once it has.
	summary: SectionSummary;
	body: ReadableStream<Uint8Array>;
}

const ENC = new TextEncoder();

function streamFrom(gen: AsyncGenerator<Uint8Array>): ReadableStream<Uint8Array> {
	return new ReadableStream<Uint8Array>({
		async pull(controller) {
			const { done, value } = await gen.next();
			if (done) controller.close();
			else controller.enqueue(value);
		},
		async cancel() {
			await gen.return(undefined);
		},
	});
}

function emptyStream(): ReadableStream<Uint8Array> {
	return new ReadableStream<Uint8Array>({
		start(controller) {
			controller.close();
		},
	});
}

/// Walk every page, handing each row to `onRow`, without producing an
/// archive entry. For sections the export reduces rather than copies
/// (the jobs count-by-kind summary).
export async function walkPages<T>(
	fetchPage: (offset: number, limit: number) => Promise<SectionPage<T> | null>,
	onRow: (row: T) => void | Promise<void>,
	opts: Pick<SectionOptions<T>, 'pageSize' | 'budget' | 'label'> = {},
): Promise<SectionSummary> {
	const pageSize = opts.pageSize ?? EXPORT_PAGE_SIZE;
	const summary: SectionSummary = { written: 0, total: 0, complete: false };
	let short = false;
	for (let offset = 0;;) {
		if (opts.budget?.expired()) {
			short = true;
			if (opts.label) opts.budget.noteSkipped(opts.label);
			break;
		}
		const page = await fetchPage(offset, pageSize);
		if (!page) {
			short = true;
			break;
		}
		if (page.total != null) summary.total = page.total;
		for (const row of page.rows) {
			await onRow(row);
			summary.written++;
		}
		offset += page.rows.length;
		if (page.rows.length < pageSize) break;
	}
	if (summary.total < summary.written) summary.total = summary.written;
	summary.complete = !short && summary.written >= summary.total;
	return summary;
}

/// Open a section as a JSON-array byte stream that pages as it is read.
/// The first page is fetched eagerly so the caller can tell an empty
/// section (no entry) from a populated one before opening the entry.
export async function openJsonSection<T>(
	fetchPage: (offset: number, limit: number) => Promise<SectionPage<T> | null>,
	opts: SectionOptions<T> = {},
): Promise<JsonSection> {
	const pageSize = opts.pageSize ?? EXPORT_PAGE_SIZE;
	const summary: SectionSummary = { written: 0, total: 0, complete: false };
	// Shed load rather than spend the dying request's last seconds on a
	// count query whose rows will never be written. Reported, not hidden:
	// the section is named in `incomplete` exactly as a cut-off walk is.
	if (opts.budget?.expired()) {
		if (opts.label) opts.budget.noteSkipped(opts.label);
		return { opened: false, summary, body: emptyStream() };
	}
	const first = await fetchPage(0, pageSize);

	if (!first) {
		return { opened: false, summary, body: emptyStream() };
	}
	if (first.total != null) summary.total = first.total;
	if (first.rows.length === 0) {
		summary.complete = summary.written >= summary.total;
		return { opened: false, summary, body: emptyStream() };
	}

	async function* bytes(): AsyncGenerator<Uint8Array> {
		let short = false;
		let page: SectionPage<T> | null = first;
		let offset = 0;
		yield ENC.encode('[');
		for (;;) {
			if (!page) {
				short = true;
				break;
			}
			if (page.total != null) summary.total = page.total;
			for (const row of page.rows) {
				if (opts.keep) opts.keep(row);
				const shaped = opts.shape ? opts.shape(row) : row;
				yield ENC.encode(
					(summary.written === 0 ? '\n' : ',\n') + JSON.stringify(shaped, null, 2),
				);
				summary.written++;
			}
			offset += page.rows.length;
			if (page.rows.length < pageSize) break;
			if (opts.budget?.expired()) {
				short = true;
				if (opts.label) opts.budget.noteSkipped(opts.label);
				break;
			}
			page = await fetchPage(offset, pageSize);
		}
		if (summary.total < summary.written) summary.total = summary.written;
		summary.complete = !short && summary.written >= summary.total;
		yield ENC.encode('\n]\n');
	}

	return { opened: true, summary, body: streamFrom(bytes()) };
}
