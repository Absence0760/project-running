// Chip-timing CSV parser for the organiser bulk-results import (persona
// #43). A timing CSV is keyed on bib + printed name + finish time, for
// finishers who mostly have no account. Pure + framework-free so it can be
// unit-tested directly; the data layer (`bulkImportEventResults`) maps the
// output onto account-optional `event_results` rows.

export interface ParsedResultRow {
	bib: string;
	finisherName: string;
	durationS: number;
	distanceM: number;
	finisherStatus: 'finished' | 'dnf' | 'dns';
}

export interface ParsedResultCsv {
	rows: ParsedResultRow[];
	errors: string[];
}

const HEADER_ALIASES: Record<keyof Omit<ParsedResultRow, never>, string[]> = {
	bib: ['bib', 'bib number', 'bib no', 'number', 'race number', 'bibno'],
	finisherName: ['name', 'finisher', 'athlete', 'runner', 'full name'],
	durationS: ['time', 'duration', 'finish time', 'chip time', 'net time', 'gun time', 'result'],
	distanceM: ['distance', 'distance km', 'distance m', 'km', 'metres', 'meters'],
	finisherStatus: ['status', 'finisher status', 'result status']
};

// RFC-4180-ish tokenizer (quotes, escaped quotes, CRLF). Same shape as the
// Strava-export reader's private `parseCsv`, kept local so the two importers
// can evolve independently.
function tokenize(text: string): string[][] {
	const out: string[][] = [];
	let row: string[] = [];
	let field = '';
	let inQuotes = false;
	for (let i = 0; i < text.length; i++) {
		const c = text[i];
		if (inQuotes) {
			if (c === '"') {
				if (text[i + 1] === '"') {
					field += '"';
					i++;
				} else {
					inQuotes = false;
				}
			} else {
				field += c;
			}
		} else if (c === '"') {
			inQuotes = true;
		} else if (c === ',') {
			row.push(field);
			field = '';
		} else if (c === '\n') {
			row.push(field);
			out.push(row);
			row = [];
			field = '';
		} else if (c === '\r') {
			// swallow — handled on the following \n
		} else {
			field += c;
		}
	}
	if (field.length > 0 || row.length > 0) {
		row.push(field);
		out.push(row);
	}
	return out;
}

function indexHeader(header: string[]): Partial<Record<keyof ParsedResultRow, number>> {
	const idx: Partial<Record<keyof ParsedResultRow, number>> = {};
	for (const key of Object.keys(HEADER_ALIASES) as (keyof ParsedResultRow)[]) {
		const aliases = HEADER_ALIASES[key];
		const found = header.findIndex((h) => aliases.includes(h.trim().toLowerCase()));
		if (found >= 0) idx[key] = found;
	}
	return idx;
}

// Accepts "HH:MM:SS", "MM:SS", a bare seconds count, or a decimal — anything
// a timing system or a hand-typed sheet is likely to emit. Returns null on
// anything unparseable so the caller can report the offending row.
export function parseDurationToSeconds(raw: string | undefined): number | null {
	if (raw == null) return null;
	const s = raw.trim();
	if (s === '') return null;
	if (s.includes(':')) {
		const parts = s.split(':');
		if (parts.length > 3) return null;
		let total = 0;
		for (const p of parts) {
			const n = Number(p);
			if (!Number.isFinite(n) || n < 0) return null;
			total = total * 60 + n;
		}
		return Math.round(total);
	}
	const n = Number(s);
	if (!Number.isFinite(n) || n < 0) return null;
	return Math.round(n);
}

function parseStatus(raw: string | undefined): 'finished' | 'dnf' | 'dns' {
	const s = (raw ?? '').trim().toLowerCase();
	if (s === 'dnf') return 'dnf';
	if (s === 'dns') return 'dns';
	return 'finished';
}

// `eventDistanceM` is the per-event distance the organiser is importing
// against — used when the CSV omits a distance column (the common case for a
// fixed-distance race). A non-finished row (DNF/DNS) keeps a 0 duration.
export function parseChipTimingCsv(text: string, eventDistanceM: number): ParsedResultCsv {
	const errors: string[] = [];
	// Excel and many timing exports prepend a UTF-8 BOM; left in place it
	// corrupts the first header ("﻿bib" never matches "bib").
	const clean = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
	const table = tokenize(clean).filter((r) => r.some((c) => c.trim() !== ''));
	if (table.length === 0) return { rows: [], errors: ['The file is empty.'] };

	const header = table[0];
	const idx = indexHeader(header);
	if (idx.bib === undefined) errors.push('No bib column found (expected a "bib" or "number" header).');
	if (idx.finisherName === undefined) errors.push('No name column found (expected a "name" header).');
	if (idx.durationS === undefined) errors.push('No time column found (expected a "time" or "duration" header).');
	if (errors.length > 0) return { rows: [], errors };

	const rows: ParsedResultRow[] = [];
	const seenBibs = new Set<string>();
	for (let r = 1; r < table.length; r++) {
		const cells = table[r];
		const line = r + 1;
		const bib = (cells[idx.bib!] ?? '').trim();
		const finisherName = (cells[idx.finisherName!] ?? '').trim();
		if (bib === '' && finisherName === '') continue;
		if (bib === '') {
			errors.push(`Row ${line}: missing bib.`);
			continue;
		}
		if (finisherName === '') {
			errors.push(`Row ${line}: missing name for bib ${bib}.`);
			continue;
		}
		if (seenBibs.has(bib)) {
			errors.push(`Row ${line}: duplicate bib ${bib} in file.`);
			continue;
		}
		const status = parseStatus(idx.finisherStatus !== undefined ? cells[idx.finisherStatus] : undefined);
		let durationS = 0;
		if (status === 'finished') {
			const parsed = parseDurationToSeconds(cells[idx.durationS!]);
			if (parsed === null) {
				errors.push(`Row ${line}: unparseable time "${(cells[idx.durationS!] ?? '').trim()}" for bib ${bib}.`);
				continue;
			}
			durationS = parsed;
		}
		let distanceM = eventDistanceM;
		if (idx.distanceM !== undefined) {
			const rawDist = (cells[idx.distanceM] ?? '').trim();
			if (rawDist !== '') {
				const n = Number(rawDist.replace(/,/g, ''));
				if (Number.isFinite(n) && n > 0) {
					// A "distance km" header means kilometres; a bare "distance"
					// or "distance m" header means metres.
					const headerName = header[idx.distanceM].trim().toLowerCase();
					distanceM = headerName.includes('km') ? n * 1000 : n;
				}
			}
		}
		seenBibs.add(bib);
		rows.push({ bib, finisherName, durationS, distanceM, finisherStatus: status });
	}
	if (rows.length === 0 && errors.length === 0) errors.push('No result rows found.');
	return { rows, errors };
}
