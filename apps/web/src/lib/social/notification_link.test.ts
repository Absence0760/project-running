import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { notificationLinkFor, type NotificationLinkInput } from './notification_link';

function make(overrides: {
	kind: string;
	run_id?: string | null;
	actor_id?: string | null;
	event_id?: string | null;
	plan_id?: string | null;
	achievement_id?: string | null;
	challenge_id?: string | null;
	event_club_slug?: string | null;
	club_slug?: string | null;
}): NotificationLinkInput {
	return {
		row: {
			kind: overrides.kind,
			run_id: overrides.run_id ?? null,
			actor_id: overrides.actor_id ?? null,
			event_id: overrides.event_id ?? null,
			plan_id: overrides.plan_id ?? null,
			achievement_id: overrides.achievement_id ?? null,
			challenge_id: overrides.challenge_id ?? null,
		},
		event_club_slug: overrides.event_club_slug ?? null,
		club_slug: overrides.club_slug ?? null,
	};
}

test('run-engagement kinds link to the run detail', () => {
	for (const kind of ['kudos', 'comment', 'comment_reply']) {
		assert.equal(notificationLinkFor(make({ kind, run_id: 'r1' })), '/runs/r1');
		assert.equal(notificationLinkFor(make({ kind })), null, `${kind} with no run_id has no link`);
	}
});

test('follow links to the actor profile', () => {
	assert.equal(notificationLinkFor(make({ kind: 'follow', actor_id: 'u9' })), '/u/u9');
	assert.equal(notificationLinkFor(make({ kind: 'follow' })), null);
});

test('event kinds link to the club event, needing both event id and club slug', () => {
	for (const kind of ['event_rsvp', 'event_cancel', 'event_reminder']) {
		assert.equal(
			notificationLinkFor(make({ kind, event_id: 'e1', event_club_slug: 'trail-club' })),
			'/clubs/trail-club/events/e1',
		);
		// Either half missing → no link (avoids a /clubs/null/events/e1 dead route).
		assert.equal(notificationLinkFor(make({ kind, event_id: 'e1' })), null);
		assert.equal(notificationLinkFor(make({ kind, event_club_slug: 'trail-club' })), null);
	}
});

test('plan kinds link to the plan detail', () => {
	for (const kind of ['plan_update', 'plan_assigned']) {
		assert.equal(notificationLinkFor(make({ kind, plan_id: 'p3' })), '/plans/p3');
		assert.equal(notificationLinkFor(make({ kind })), null);
	}
});

test('message links to the DM thread with the actor', () => {
	assert.equal(notificationLinkFor(make({ kind: 'message', actor_id: 'u2' })), '/messages/u2');
	assert.equal(notificationLinkFor(make({ kind: 'message' })), null);
});

test('club_post links to the club home', () => {
	assert.equal(notificationLinkFor(make({ kind: 'club_post', club_slug: 'road-runners' })), '/clubs/road-runners');
	assert.equal(notificationLinkFor(make({ kind: 'club_post' })), null);
});

test('run_completed links to the public run share page', () => {
	assert.equal(notificationLinkFor(make({ kind: 'run_completed', run_id: 'r7' })), '/share/run/r7');
	assert.equal(notificationLinkFor(make({ kind: 'run_completed' })), null);
});

test('achievement links to the badge share page', () => {
	assert.equal(notificationLinkFor(make({ kind: 'achievement', achievement_id: 'a5' })), '/share/badge/a5');
	assert.equal(notificationLinkFor(make({ kind: 'achievement' })), null);
});

test('challenge_complete links to the challenge', () => {
	assert.equal(notificationLinkFor(make({ kind: 'challenge_complete', challenge_id: 'c8' })), '/challenges/c8');
	assert.equal(notificationLinkFor(make({ kind: 'challenge_complete' })), null);
});

test('content_hidden is informational — never links', () => {
	assert.equal(notificationLinkFor(make({ kind: 'content_hidden' })), null);
});

// The only kind whose link needs no id — and it must not grow one. A signed
// download URL minted when the worker finished would already be expiring by
// the time the subject opened the message, which is the objection that kept
// this notification unbuilt (decisions § 717 + § 729). The page mints it at
// the tap instead, so the link is the page and nothing more.
test('data_export_ready links to the export page, with or without any FK', () => {
	assert.equal(notificationLinkFor(make({ kind: 'data_export_ready' })), '/settings/account');
	assert.equal(
		notificationLinkFor(
			make({ kind: 'data_export_ready', run_id: 'r1', plan_id: 'p1', challenge_id: 'c1' }),
		),
		'/settings/account',
	);
});

// The two ledgers give this kind two shapes. An event order carries the FKs
// and lands on the page whose banner explains the same thing at length; a
// donation carries neither — `donations` has no client SELECT policy, so there
// is no donor-facing row to point at — and the message is the whole message.
test('refund_failed links to the event when it has one, and to nothing when it does not', () => {
	assert.equal(
		notificationLinkFor(
			make({ kind: 'refund_failed', event_id: 'e1', event_club_slug: 'richmond' }),
		),
		'/clubs/richmond/events/e1',
	);
	assert.equal(notificationLinkFor(make({ kind: 'refund_failed' })), null);
	// Half the pair is not a link: an id with no slug cannot address the route.
	assert.equal(notificationLinkFor(make({ kind: 'refund_failed', event_id: 'e1' })), null);
});

test('an unknown future kind falls through to null, never undefined', () => {
	const href = notificationLinkFor(make({ kind: 'brand_new_kind' }));
	assert.equal(href, null);
	assert.notEqual(href, undefined);
});

// ─────────── the CHECK rail ───────────
//
// `row.kind` is typed `string` on purpose, so this module stays free of a
// runtime import from core/data.ts — which also means `tsc` gives no
// exhaustiveness here, and `notification_link.ts` is not one of the rails
// scripts/check_constraint_unions.mjs registers for `notifications.kind`.
// Nothing anywhere compares the switch to the column. An eighteenth kind
// therefore lands on `default: null` — a notification the reader cannot
// click — with every guard in the tree green.

const MIGRATIONS = resolve('../backend/supabase/migrations');

/// Every value the LIVE `notifications_kind_check` admits. The constraint
/// is dropped and re-added as the set widens, so the last migration that
/// mentions it is the one in force.
function notificationKinds(): string[] {
	const files = readdirSync(MIGRATIONS)
		.filter((f) => f.endsWith('.sql'))
		.sort();
	let latest: string | null = null;
	for (const f of files) {
		const sql = readFileSync(resolve(MIGRATIONS, f), 'utf-8');
		const at = sql.lastIndexOf('add constraint notifications_kind_check');
		if (at === -1) continue;
		const open = sql.indexOf('kind in (', at);
		const close = sql.indexOf(')', open);
		assert.ok(open !== -1 && close !== -1, `unreadable kind list in ${f}`);
		latest = sql.slice(open, close);
	}
	assert.ok(latest, 'no migration defines notifications_kind_check any more');
	const kinds = [...latest.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
	assert.ok(kinds.length >= 17, `parsed only ${kinds.length} kinds — the reader is stale`);
	return kinds;
}

/// The kinds that deliberately carry no destination, each with its reason.
/// Anything else the column can hold must route somewhere.
const DELIBERATELY_UNLINKED: Record<string, string> = {
	content_hidden:
		'a moderation notice about the reader\'s own content — there is nothing to open',
};

test('every kind the column can hold is routed by name, not by the default arm', () => {
	const source = readFileSync(resolve('src/lib/social/notification_link.ts'), 'utf-8');
	const unhandled = notificationKinds().filter(
		(kind) => !source.includes(`case '${kind}':`),
	);
	assert.deepEqual(
		unhandled,
		[],
		`notifications.kind admits ${unhandled.join(', ')} and notificationLinkFor has no ` +
			'case for it, so the row renders as an unclickable notification. Add a case — ' +
			'or, if it genuinely has nowhere to go, add it to DELIBERATELY_UNLINKED with a reason.',
	);
});

test('every routed kind reaches a destination when it has its ids', () => {
	const fullyPopulated = {
		run_id: 'r-1',
		actor_id: 'u-1',
		event_id: 'e-1',
		plan_id: 'p-1',
		achievement_id: 'a-1',
		challenge_id: 'c-1',
		event_club_slug: 'club',
		club_slug: 'club',
	};
	for (const kind of notificationKinds()) {
		const href = notificationLinkFor(make({ kind, ...fullyPopulated }));
		if (kind in DELIBERATELY_UNLINKED) {
			assert.equal(
				href,
				null,
				`${kind} is registered as unlinked (${DELIBERATELY_UNLINKED[kind]}) but now links to ${href}`,
			);
			continue;
		}
		assert.ok(
			typeof href === 'string' && href.startsWith('/'),
			`${kind} carried every id and still routed nowhere`,
		);
	}
});

test('the unlinked register does not name a kind the column dropped', () => {
	const kinds = new Set(notificationKinds());
	for (const kind of Object.keys(DELIBERATELY_UNLINKED)) {
		assert.ok(
			kinds.has(kind),
			`${kind} is registered as deliberately unlinked but notifications.kind no ` +
				'longer admits it — the exemption is covering nothing',
		);
	}
});

