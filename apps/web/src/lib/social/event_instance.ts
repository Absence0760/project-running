/// Comparing one recurring-event occurrence to another.
///
/// An instance is identified by its start timestamp, and that timestamp
/// reaches the client in two different renderings of the SAME instant:
/// PostgREST serialises `timestamptz` through Postgres' own JSON cast
/// (`2026-06-01T18:00:00+00:00`), while anything the client derives from a
/// `Date` is `toISOString()` (`2026-06-01T18:00:00.000Z`). String equality
/// between them is always false, so `===` on an instance timestamp silently
/// decides "different occurrence" for what is one and the same.
///
/// Every client-side instance comparison goes through `sameInstant`. The
/// server-side filters (`.eq('instance_start', …)`) are unaffected — Postgres
/// parses both renderings into the same value.
///
/// Twin: `apps/backend/supabase/functions/_shared/event_instance.ts`, which
/// the paid-events Edge Functions use for the same decision on money.

/// True when both sides name the same point in time. A null / absent /
/// unparseable side never matches — an unknown instant is not "equal", it is
/// unknown, and for pricing that means falling through to the series default
/// rather than silently charging an override's price.
export function sameInstant(
	a: string | null | undefined,
	b: string | null | undefined
): boolean {
	if (a == null || b == null) return false;
	const left = Date.parse(a);
	const right = Date.parse(b);
	if (!Number.isFinite(left) || !Number.isFinite(right)) return false;
	return left === right;
}

/// The pricing row that governs one occurrence: a per-instance override if one
/// exists for that exact instant, else the series default (`instance_start` is
/// null), else nothing.
export function selectEffectivePricing<T extends { instance_start: string | null }>(
	rows: readonly T[],
	instanceStart: string | null | undefined
): T | null {
	const override = rows.find((r) => sameInstant(r.instance_start, instanceStart));
	if (override) return override;
	return rows.find((r) => r.instance_start == null) ?? null;
}
