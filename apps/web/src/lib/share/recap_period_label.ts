/// Pure period-label builder for a published recap. Lives apart from
/// share_recap_lookup.ts (which imports @supabase/supabase-js) so it is
/// node:test-runnable without the Supabase client in the loop. The og:image
/// + crawler-facing <head> are not per-user, so this is intentionally
/// locale-independent English.
export function recapPeriodLabel(periodKind: string, periodKey: string): string {
	if (periodKind === 'month') {
		const m = /^(\d{4})-(\d{2})$/.exec(periodKey);
		if (m) {
			const months = [
				'January', 'February', 'March', 'April', 'May', 'June',
				'July', 'August', 'September', 'October', 'November', 'December',
			];
			const idx = parseInt(m[2], 10) - 1;
			if (idx >= 0 && idx < 12) return `${months[idx]} ${m[1]}`;
		}
	}
	return periodKey;
}
