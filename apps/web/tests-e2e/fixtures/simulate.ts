import { getAdminClient } from './local-supabase';

/**
 * Service-role helpers for actions only mobile / watch can do on the
 * canonical web stack. Web is the canonical feature surface (decisions
 * §24) but recording, live broadcasting, and a few HealthKit / Garmin
 * sync paths only exist on device — saga tests need them as setup
 * steps without spinning up a real recorder.
 *
 * Each helper bypasses RLS via the service-role client. Keep them
 * narrow — anything a real user could do via the web UI should go
 * through the UI in the saga, not here.
 *
 * Today: just `insertRun()`. Future helpers as sagas demand them:
 *   - `startLiveBroadcast(runId, points)` — insert live_run_pings
 *     so /live/[id] receives data without a real broadcaster.
 *   - `insertEvent(clubId, ...)` — bypass the create-event modal
 *     for sagas where the event isn't the test subject.
 *   - `insertClubMember(clubId, userId, role)` — pre-populate
 *     members for cluster-of-N tests where joining via UI per
 *     user is too slow.
 */

export async function insertRun(opts: {
	user_id: string;
	started_at?: string;
	duration_s: number;
	distance_m: number;
	source?: 'app' | 'strava' | 'parkrun' | 'healthkit';
	is_public?: boolean;
	metadata?: Record<string, unknown>;
}): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('runs')
		.insert({
			user_id: opts.user_id,
			started_at: opts.started_at ?? new Date().toISOString(),
			duration_s: opts.duration_s,
			distance_m: opts.distance_m,
			source: opts.source ?? 'app',
			is_public: opts.is_public ?? false,
			metadata: opts.metadata ?? { activity_type: 'run' }
		})
		.select('id')
		.single();
	if (error || !data) {
		throw new Error(`simulate.insertRun failed: ${error?.message ?? 'no row returned'}`);
	}
	return data.id as string;
}

export async function deleteRun(runId: string): Promise<void> {
	const { error } = await getAdminClient().from('runs').delete().eq('id', runId);
	if (error) {
		throw new Error(`simulate.deleteRun failed: ${error.message}`);
	}
}
