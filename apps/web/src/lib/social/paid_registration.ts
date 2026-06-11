/// Pure fee / sales-window / refund-policy helpers for paid event
/// registration (club_events.md slice P1). No Supabase, no Stripe, no
/// I/O — everything here is deterministic so it can be unit-tested
/// without a network or a database (paid_registration.test.ts).
///
/// Web-first per decisions.md §24. The Dart twin lands with mobile
/// register (P3); like nutrition_budget.ts / hydration.ts this file is
/// web-only for now (no parity-pair obligation yet).

import type { RefundPolicy } from '$lib/types';

/// The platform's application fee for a destination charge, in cents.
///
/// `platformFeeBps` is basis points (1% = 100 bps). The fee is floored
/// (Stripe wants an integer cent amount and we never round *up* — that
/// would skim more than the configured rate), clamped to be non-negative,
/// and never allowed to exceed the charge itself (`application_fee_amount`
/// > the amount is a Stripe error, and a 100%+ fee would zero the host's
/// payout). A 0-bps platform (the seed-adoption default) yields 0.
export function applicationFeeCents(amountCents: number, platformFeeBps: number): number {
	if (!Number.isFinite(amountCents) || !Number.isFinite(platformFeeBps)) return 0;
	if (amountCents <= 0 || platformFeeBps <= 0) return 0;
	const fee = Math.floor((amountCents * platformFeeBps) / 10000);
	return Math.max(0, Math.min(fee, amountCents));
}

/// When sales close for an instance: `offsetMinutes` before its start.
/// A 0 offset means sales stay open right up to the start time. Returns
/// the absolute close instant as an ISO string, or null if the instance
/// start is unparseable (caller treats null as "no window enforced").
export function salesCloseAt(instanceStartIso: string, offsetMinutes: number): string | null {
	const startMs = Date.parse(instanceStartIso);
	if (Number.isNaN(startMs)) return null;
	const offset = Number.isFinite(offsetMinutes) ? offsetMinutes : 0;
	return new Date(startMs - offset * 60_000).toISOString();
}

export type RegistrationState =
	| 'open'
	| 'sales_closed'
	| 'sold_out'
	| 'already_registered';

/// Resolve whether registration is open for a viewer on a priced event.
///
/// Precedence is deliberate and pinned by tests:
///   1. `already_registered` — if the viewer already holds a paid slot,
///      that wins over everything (we show "You're registered", never
///      "sold out", to someone who already has a seat).
///   2. `sold_out` — capacity reached (a null/0 capacity means unlimited).
///   3. `sales_closed` — past the sales-close instant.
///   4. `open`.
///
/// `goingCount` should already include pending soft-reservations that
/// count toward capacity (the server holds them); the client passes the
/// confirmed-plus-reserved count it has.
export function registrationOpen(
	now: Date,
	instanceStartIso: string,
	offsetMinutes: number,
	capacity: number | null,
	goingCount: number,
	viewerHasPaidOrder: boolean,
): RegistrationState {
	if (viewerHasPaidOrder) return 'already_registered';
	if (capacity != null && capacity > 0 && goingCount >= capacity) return 'sold_out';
	const closeIso = salesCloseAt(instanceStartIso, offsetMinutes);
	if (closeIso != null && now.getTime() >= Date.parse(closeIso)) return 'sales_closed';
	return 'open';
}

export interface RefundEligibility {
	eligible: boolean;
	/// Whether a full (vs partial) refund is owed. In P1 a refund is
	/// always full-or-nothing per policy (no proration), so `fullRefund`
	/// equals `eligible`; it's a distinct field so a future partial-refund
	/// policy can diverge without changing call sites.
	fullRefund: boolean;
}

/// Resolve a buyer self-cancel refund per the event's policy. Honoured in
/// P2 (P1 refunds are manual via the Stripe dashboard), but the rule is
/// pure and pinned now so the automation can lean on it later.
///   - 'no_refund' — never eligible.
///   - 'full_until_start' — eligible up to the instance start.
///   - 'full_until_24h' — eligible up to 24h before the instance start.
export function resolveRefundEligibility(
	policy: RefundPolicy,
	now: Date,
	instanceStartIso: string,
): RefundEligibility {
	const startMs = Date.parse(instanceStartIso);
	if (Number.isNaN(startMs)) return { eligible: false, fullRefund: false };
	const nowMs = now.getTime();
	let cutoffMs: number;
	switch (policy) {
		case 'no_refund':
			return { eligible: false, fullRefund: false };
		case 'full_until_start':
			cutoffMs = startMs;
			break;
		case 'full_until_24h':
			cutoffMs = startMs - 24 * 60 * 60_000;
			break;
		default:
			return { eligible: false, fullRefund: false };
	}
	const eligible = nowMs < cutoffMs;
	return { eligible, fullRefund: eligible };
}
