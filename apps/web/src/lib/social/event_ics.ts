// RFC 5545 iCalendar (.ics) builder for a single club-event occurrence, so a
// member can drop an event (or a chosen recurring instance) straight into their
// own calendar. Web-only: mobile clients hand off to the OS calendar via native
// intents, so there is no Dart twin. Pure + locale/unit-agnostic — the SUMMARY /
// DESCRIPTION / LOCATION carry the event's own text, never a translated label.

export interface IcsEventInput {
	/** Stable unique identifier for this occurrence. Re-importing the same value
	 * updates the calendar entry instead of duplicating it. */
	uid: string;
	title: string;
	/** ISO instant for the occurrence's start (an absolute point in time). */
	startIso: string;
	/** Occurrence length in minutes; when set, emits DTEND. */
	durationMin?: number | null;
	description?: string | null;
	location?: string | null;
	url?: string | null;
	/** DTSTAMP source; injectable for deterministic tests. Defaults to now. */
	nowMs?: number;
}

/** Escape a TEXT value per RFC 5545 §3.3.11 (backslash, semicolon, comma,
 * newline). Colon needs no escaping in a TEXT value. */
function escapeText(value: string): string {
	return value
		.replace(/\\/g, '\\\\')
		.replace(/;/g, '\\;')
		.replace(/,/g, '\\,')
		.replace(/\r\n|\r|\n/g, '\\n');
}

/** Format an ISO instant as a UTC iCalendar date-time (`YYYYMMDDTHHMMSSZ`).
 * Emitting UTC sidesteps VTIMEZONE — the instant is unambiguous regardless of
 * the event's stored timezone. Returns null for an unparseable input. */
export function toIcsUtc(iso: string): string | null {
	const d = new Date(iso);
	const ms = d.getTime();
	if (Number.isNaN(ms)) return null;
	const p2 = (n: number) => String(n).padStart(2, '0');
	return (
		`${d.getUTCFullYear()}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}` +
		`T${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}${p2(d.getUTCSeconds())}Z`
	);
}

const encoder = new TextEncoder();

/** Fold a content line to ≤75 octets per RFC 5545 §3.1, breaking on whole
 * code points (never mid-character) and prefixing continuations with a space. */
function foldLine(line: string): string {
	if (encoder.encode(line).length <= 75) return line;
	const out: string[] = [];
	let current = '';
	let currentBytes = 0;
	// Continuation lines carry a leading space, so cap their payload at 74 octets.
	let limit = 75;
	for (const ch of line) {
		const chBytes = encoder.encode(ch).length;
		if (currentBytes + chBytes > limit) {
			out.push(current);
			current = ch;
			currentBytes = chBytes;
			limit = 74;
		} else {
			current += ch;
			currentBytes += chBytes;
		}
	}
	out.push(current);
	return out.join('\r\n ');
}

/** Build a complete VCALENDAR document (CRLF line endings) wrapping one VEVENT
 * for the given occurrence. Returns null when the start instant is invalid. */
export function buildEventIcs(input: IcsEventInput): string | null {
	const dtStart = toIcsUtc(input.startIso);
	if (!dtStart) return null;
	const dtStamp = toIcsUtc(new Date(input.nowMs ?? Date.now()).toISOString());
	if (!dtStamp) return null;

	const lines: string[] = [
		'BEGIN:VCALENDAR',
		'VERSION:2.0',
		'PRODID:-//Threkir//Run App//EN',
		'CALSCALE:GREGORIAN',
		'METHOD:PUBLISH',
		'BEGIN:VEVENT',
		`UID:${input.uid}`,
		`DTSTAMP:${dtStamp}`,
		`DTSTART:${dtStart}`
	];

	if (input.durationMin != null && input.durationMin > 0) {
		const end = toIcsUtc(
			new Date(new Date(input.startIso).getTime() + input.durationMin * 60_000).toISOString()
		);
		if (end) lines.push(`DTEND:${end}`);
	}

	lines.push(`SUMMARY:${escapeText(input.title)}`);
	if (input.description) lines.push(`DESCRIPTION:${escapeText(input.description)}`);
	if (input.location) lines.push(`LOCATION:${escapeText(input.location)}`);
	if (input.url) lines.push(`URL:${input.url}`);

	lines.push('END:VEVENT', 'END:VCALENDAR');

	return lines.map(foldLine).join('\r\n') + '\r\n';
}

/** A filesystem-safe .ics filename derived from the event title. */
export function icsFilename(title: string): string {
	const slug = title
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '')
		.slice(0, 60);
	return `${slug || 'event'}.ics`;
}
