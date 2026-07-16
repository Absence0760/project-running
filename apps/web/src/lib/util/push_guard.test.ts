// Source-level guard pinning the issue #235 fix. The web-push persist used
// to read-merge-write the WHOLE user_device_settings.prefs bag with an
// unchecked upsert: a failed write left the browser subscribed while the
// server never learned about it (push enabled forever, nothing delivered),
// and a failed merge-base read started the merge from {} so the upsert
// wiped every other per-device pref. The persist must stay a single call
// to the atomic set_push_subscription RPC (single-key jsonb_set/minus,
// migration 20270419_001) with its result checked, and neither
// subscribeToPush nor unsubscribeFromPush may swallow the persist failure
// — the devices page's failure toast is the only way the user learns the
// toggle is lying.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const source = readFileSync(resolve('src/lib/util/push.ts'), 'utf-8');

function fnBody(name: string): string {
	const start = source.indexOf(`async function ${name}(`);
	assert.notEqual(start, -1, `${name} missing from push.ts`);
	const next = source.indexOf('\nasync function ', start + 1);
	return next === -1 ? source.slice(start) : source.slice(start, next);
}

test('persistSubscription writes through the atomic RPC and checks the result', () => {
	const body = fnBody('persistSubscription');
	assert.match(
		body,
		/\.rpc\('set_push_subscription'/,
		'persistSubscription must call the set_push_subscription RPC',
	);
	assert.match(body, /if \(error\) throw error/, 'the RPC result must be checked and thrown');
});

test('push.ts carries no whole-bag read-merge-write of user_device_settings', () => {
	assert.doesNotMatch(
		source,
		/from\('user_device_settings'\)/,
		'no direct table access — a read-merge-write can clobber the device prefs bag',
	);
	assert.doesNotMatch(source, /\.upsert\(/, 'no whole-bag upsert');
});

test('unsubscribeFromPush does not swallow the server-side clear failure', () => {
	const body = fnBody('unsubscribeFromPush');
	const persistAt = body.indexOf('await persistSubscription');
	assert.notEqual(persistAt, -1, 'unsubscribeFromPush must clear the stored subscription');
	assert.doesNotMatch(
		body.slice(persistAt),
		/catch/,
		'the persist clear must propagate so the caller toast fires',
	);
});
