/// Detect a P0001 raised by the `enforce_create_rate_limit` trigger
/// (migration 20260907_001) and convert it into a friendlier message
/// for the toast / inline error. The trigger raises an exception of
/// the form `rate limit exceeded for <bucket>, retry in <seconds>s`
/// with SQLSTATE P0001 and the hint
/// `You are creating these too quickly. Please wait and try again.`
///
/// Returns null when the error isn't a rate-limit one — callers should
/// rethrow the original error in that case so unrelated failures (RLS
/// denies, slug collisions, etc.) aren't masked.
///
/// Pure string-in / string-out — no Supabase or fetch dependency — so
/// it's unit-testable without spinning up the stack. Used by data.ts's
/// createClub + saveRoute; mirrored into the `data` layer rather than
/// the form components so every caller (modal + standalone + future
/// mobile-web port) gets the same wording.
export function rateLimitErrorMessage(err: { code?: string; message?: string } | null | undefined):
	string | null {
	if (!err || err.code !== 'P0001' || !err.message) return null;
	const match = err.message.match(/rate limit exceeded for (\w+),\s*retry in\s+(\d+)s/i);
	if (!match) return null;
	const [, bucket, secsStr] = match;
	const secs = Number(secsStr);
	let wait: string;
	if (!Number.isFinite(secs) || secs <= 0) wait = 'a few seconds';
	else if (secs < 90) wait = `${secs} second${secs === 1 ? '' : 's'}`;
	else {
		const mins = Math.ceil(secs / 60);
		wait = `${mins} minute${mins === 1 ? '' : 's'}`;
	}
	const verb =
		bucket === 'create_club' ? 'creating clubs' :
		bucket === 'create_route' ? 'creating routes' :
		bucket === 'create_report' ? 'filing reports' :
		'doing that';
	return `You're ${verb} too quickly — please wait ${wait} and try again.`;
}
