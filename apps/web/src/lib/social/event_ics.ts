// RFC 5545 iCalendar (.ics) builder for a club event — either a single
// occurrence or the whole recurring series (RRULE + EXDATE), so a member of a
// weekly club run drops every future Saturday into their calendar once instead
// of re-downloading each week. Web-only: mobile clients hand off to the OS
// calendar via native intents, so there is no Dart twin. Pure +
// locale/unit-agnostic — the SUMMARY / DESCRIPTION / LOCATION carry the event's
// own text, never a translated label.

import type { Event, RecurrenceFreq, Weekday } from '../types';
import { expandInstances } from './recurrence';

// The app's Weekday codes ARE the RFC 5545 weekday abbreviations, so the RRULE
// needs no translation table — only these two orderings of them.
const WEEKDAY_BY_UTC_DAY: readonly Weekday[] = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
const WEEKDAY_ORDER: Weekday[] = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/** The app's (freq, byday[], until, count) recurrence model, restated in the
 * terms an RRULE needs. Every field is expressed against the UTC clock the
 * DTSTART is written in — see `buildEventSeriesIcs`. */
export interface IcsRecurrence {
	freq: RecurrenceFreq;
	/** UTC weekdays the series lands on. Weekly / biweekly only. */
	byday?: readonly Weekday[] | null;
	/** UTC day-of-month. Monthly only. */
	monthDay?: number | null;
	/** Inclusive end instant. Ignored when `count` is set — RFC 5545 §3.3.10
	 * forbids UNTIL and COUNT in the same rule. */
	untilIso?: string | null;
	/** Total occurrences including the DTSTART one. */
	count?: number | null;
}

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
	/** When set, the VEVENT describes a whole series rather than one occurrence.
	 * A recurrence the RRULE grammar cannot express faithfully fails the whole
	 * build (null) rather than degrading to a single occurrence — a calendar
	 * that silently disagrees with the app is worse than no calendar entry. */
	recurrence?: IcsRecurrence | null;
	/** Occurrences to subtract from the series (cancelled `event_exceptions`).
	 * Only emitted alongside `recurrence`. */
	exdatesIso?: readonly string[] | null;
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

/** Render an `IcsRecurrence` as an RRULE value (no `RRULE:` prefix), or null
 * when the series cannot be stated faithfully.
 *
 * The one shape that fails is a monthly series anchored after the 28th: the app
 * clamps a missing day-of-month to the month's last day (Jan 31 → Feb 28), and
 * BYMONTHDAY has no clamp — it skips the short month outright. Emitting it
 * anyway would put a different set of dates in the member's calendar than the
 * one the club page shows, so the series export is withheld for those instead.
 */
export function buildRrule(r: IcsRecurrence): string | null {
	const parts: string[] = [];

	if (r.freq === 'monthly') {
		if (r.monthDay == null || !Number.isInteger(r.monthDay)) return null;
		if (r.monthDay < 1 || r.monthDay > 28) return null;
		parts.push('FREQ=MONTHLY');
	} else {
		parts.push('FREQ=WEEKLY');
		if (r.freq === 'biweekly') parts.push('INTERVAL=2');
	}

	if (r.count != null) {
		if (!Number.isInteger(r.count) || r.count < 1) return null;
		parts.push(`COUNT=${r.count}`);
	} else if (r.untilIso != null) {
		const until = toIcsUtc(r.untilIso);
		if (!until) return null;
		parts.push(`UNTIL=${until}`);
	}

	if (r.freq === 'monthly') {
		parts.push(`BYMONTHDAY=${r.monthDay}`);
	} else if (r.byday?.length) {
		if (r.byday.some((d) => !WEEKDAY_ORDER.includes(d))) return null;
		parts.push(`BYDAY=${WEEKDAY_ORDER.filter((d) => r.byday!.includes(d)).join(',')}`);
	}

	return parts.join(';');
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

	if (input.recurrence) {
		const rrule = buildRrule(input.recurrence);
		if (!rrule) return null;
		lines.push(`RRULE:${rrule}`);
		const exdates = [
			...new Set(
				(input.exdatesIso ?? [])
					.map(toIcsUtc)
					.filter((v): v is string => v !== null)
			)
		].sort();
		// EXDATE takes a value list whose type must match DTSTART's (UTC
		// date-time here), so these are raw values, never TEXT-escaped.
		if (exdates.length) lines.push(`EXDATE:${exdates.join(',')}`);
	}

	lines.push(`SUMMARY:${escapeText(input.title)}`);
	if (input.description) lines.push(`DESCRIPTION:${escapeText(input.description)}`);
	if (input.location) lines.push(`LOCATION:${escapeText(input.location)}`);
	if (input.url) lines.push(`URL:${input.url}`);

	lines.push('END:VEVENT', 'END:VCALENDAR');

	return lines.map(foldLine).join('\r\n') + '\r\n';
}

export interface EventSeriesIcsOptions {
	/** `event_exceptions.instance_start` values — the cancelled occurrences,
	 * subtracted from the series via EXDATE. */
	cancelledIso?: readonly string[] | null;
	url?: string | null;
	nowMs?: number;
}

// A weekly series' first occurrence is at most 7 days past starts_at, a
// biweekly's 14, a monthly's 0 — but a series bounded by recurrence_until can
// legitimately have none at all, so the search window is generous and the
// no-occurrence case is handled rather than assumed away.
const SERIES_ANCHOR_WINDOW_MS = 400 * 24 * 3600 * 1000;

/** Build a whole-series .ics for a recurring club event: one VEVENT carrying an
 * RRULE, so the member's calendar maintains every future occurrence itself.
 * Returns null for a one-off event, or when the series cannot be expressed as
 * an RRULE without diverging from what the app shows. */
export function buildEventSeriesIcs(
	event: Event,
	opts: EventSeriesIcsOptions = {}
): string | null {
	if (!event.recurrence_freq) return null;
	const seriesStart = new Date(event.starts_at);
	if (Number.isNaN(seriesStart.getTime())) return null;

	// DTSTART has to be a real member of the recurrence set (RFC 5545 §3.8.5.3):
	// when starts_at falls on a weekday outside recurrence_byday the series
	// begins at the first expanded occurrence, and anchoring on starts_at would
	// add a phantom occurrence the club page never shows.
	const [anchor] = expandInstances(
		event,
		seriesStart,
		new Date(seriesStart.getTime() + SERIES_ANCHOR_WINDOW_MS),
		1
	);
	if (!anchor) return null;

	return buildEventIcs({
		uid: `event-${event.id}-series@threkir.com`,
		title: event.title,
		startIso: anchor.toISOString(),
		durationMin: event.duration_min,
		description: event.description,
		location: event.meet_label,
		url: opts.url ?? null,
		nowMs: opts.nowMs,
		recurrence: {
			freq: event.recurrence_freq,
			...resolveSeriesEnd(event, seriesStart),
			...(event.recurrence_freq === 'monthly'
				? { monthDay: anchor.getUTCDate() }
				: { byday: seriesWeekdays(event, seriesStart, anchor) })
		},
		exdatesIso: opts.cancelledIso ?? null
	});
}

/** The app applies `recurrence_until` and `recurrence_count` together; an RRULE
 * may carry only one. Where both are set, count the real occurrences inside the
 * until-bound so whichever binds first survives the translation. */
function resolveSeriesEnd(
	event: Event,
	seriesStart: Date
): { count?: number; untilIso?: string } {
	const { recurrence_count: count, recurrence_until: untilIso } = event;
	if (count != null && untilIso != null) {
		const until = new Date(untilIso);
		if (Number.isNaN(until.getTime())) return { count };
		return { count: expandInstances(event, seriesStart, until, count).length };
	}
	if (count != null) return { count };
	if (untilIso != null) return { untilIso };
	return {};
}

/** The BYDAY set, read off the expansion rather than translated from
 * `recurrence_byday`: the stored codes are wall-clock in the event's own zone
 * while DTSTART is UTC, so a late-evening event sits on a different UTC weekday
 * than the code the organiser picked. One cycle is enough to see every weekday
 * the series lands on. */
function seriesWeekdays(event: Event, seriesStart: Date, anchor: Date): Weekday[] {
	const cycleDays = event.recurrence_freq === 'biweekly' ? 15 : 8;
	const cycle = expandInstances(
		event,
		seriesStart,
		new Date(anchor.getTime() + cycleDays * 24 * 3600 * 1000),
		20
	);
	const seen = new Set<Weekday>(
		cycle.map((d) => WEEKDAY_BY_UTC_DAY[d.getUTCDay()])
	);
	if (seen.size === 0) seen.add(WEEKDAY_BY_UTC_DAY[anchor.getUTCDay()]);
	return WEEKDAY_ORDER.filter((d) => seen.has(d));
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
