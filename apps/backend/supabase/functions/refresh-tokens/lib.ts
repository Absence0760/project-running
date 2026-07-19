import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { refreshStravaToken } from '../_shared/strava.ts';

/// Proactively refresh Strava integrations whose access token expires within
/// the hour. Deprecated rollback path — production runs the Go worker's
/// `token_refresh` dispatch (migration 20260821_001) — but kept in lockstep
/// with the CAS-protected on-demand + webhook paths by delegating each
/// per-integration refresh to `refreshStravaToken`. That helper's
/// compare-and-swap (keyed on the refresh token we read pre-Strava-call) is
/// what stops a concurrent refresh from overwriting the winner's freshly
/// rotated vault row with a stale-old token. The disconnect-on-4xx side effect
/// is wired through the helper's `onPermanentFailure` callback.
export async function refreshExpiringStravaTokens(
	supabase: ReturnType<typeof createClient>,
): Promise<{ refreshed: number }> {
	const { data: expiring } = await supabase
		.from('integrations')
		.select('id, user_id')
		.eq('provider', 'strava')
		.lt('token_expiry', new Date(Date.now() + 3600_000).toISOString())
		.order('token_expiry', { ascending: true })
		.limit(500);

	let refreshed = 0;

	for (const integration of expiring ?? []) {
		const { data: tokenRows, error: tokenErr } = await supabase.rpc('get_integration_tokens', {
			p_user_id: integration.user_id,
			p_provider: 'strava',
		});
		if (tokenErr || !tokenRows || tokenRows.length === 0) continue;
		const refreshToken = tokenRows[0]?.refresh_token;
		if (!refreshToken) continue;

		const accessToken = await refreshStravaToken(
			supabase,
			integration.user_id,
			refreshToken,
			async (reason) => {
				await supabase
					.from('integrations')
					.update({
						disconnected_at: new Date().toISOString(),
						disconnected_reason: reason,
					})
					.eq('user_id', integration.user_id)
					.eq('provider', 'strava');
			},
		);
		if (accessToken) refreshed++;
	}

	return { refreshed };
}
