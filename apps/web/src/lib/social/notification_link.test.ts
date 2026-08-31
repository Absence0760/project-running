import { test } from 'node:test';
import assert from 'node:assert/strict';
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
