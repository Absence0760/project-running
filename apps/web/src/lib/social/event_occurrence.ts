/// Which occurrences of a recurring event are still ON.
///
/// `event_exceptions` (20261019_001) records a called-off occurrence of a
/// series. Only the event-detail picker ever subtracted them, so every other
/// surface — the club Events tab, the club feed's next-event card, the
/// dashboard "you're going to this" card — kept advertising an occurrence the
/// organiser had already called off. The server side of the same contract
/// (`enqueue_event_reminders`, 20261130_001) has always skipped them.
///
/// The cancelled instant reaches the client in two renderings of the same
/// point in time (PostgREST's `+00:00` vs a client `toISOString()`'s `.000Z`),
/// so every comparison here goes through `sameInstant` rather than string
/// equality — see `event_instance.ts`.

import type { Event } from '../types';
import { expandInstances, nextInstanceAfter } from './recurrence';
import { sameInstant } from './event_instance';

const TEN_YEARS_MS = 10 * 365 * 24 * 3600 * 1000;

/// True when `instanceStart` names one of the cancelled instants.
export function isOccurrenceCancelled(
	cancelledIso: readonly string[],
	instanceStart: string | null | undefined
): boolean {
	return cancelledIso.some((c) => sameInstant(c, instanceStart));
}

/// The next occurrence at or after `after` that has NOT been called off, or
/// null when the series has none left.
///
/// The search budget is `cancelledIso.length + 1` occurrences: at most that
/// many of the expanded ones can be cancelled, so the last candidate is
/// guaranteed live if a live one exists at all. With nothing cancelled this is
/// exactly `nextInstanceAfter`, which is the overwhelmingly common case and
/// stops the walk at the first hit.
export function nextLiveInstance(
	event: Event,
	cancelledIso: readonly string[],
	after: Date = new Date()
): Date | null {
	if (cancelledIso.length === 0) return nextInstanceAfter(event, after);
	const horizon = new Date(after.getTime() + TEN_YEARS_MS);
	const candidates = expandInstances(event, after, horizon, cancelledIso.length + 1);
	return candidates.find((d) => !isOccurrenceCancelled(cancelledIso, d.toISOString())) ?? null;
}

/// The cancelled occurrences that are still ahead, oldest first.
///
/// Without this an organiser can only reinstate the occurrence they happen to
/// be looking at, and the picker hides every cancelled one — so calling off an
/// occurrence further out than the next was irreversible.
export function upcomingCancelledOccurrences(
	cancelledIso: readonly string[],
	after: Date = new Date()
): string[] {
	return cancelledIso
		.filter((c) => {
			const t = Date.parse(c);
			return Number.isFinite(t) && t >= after.getTime();
		})
		.sort((a, b) => Date.parse(a) - Date.parse(b));
}
