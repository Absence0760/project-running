import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	groupNotifications,
	NOTIFICATION_GROUP_WINDOW_MS,
	type GroupableNotification,
} from './notification_groups';

const NOW = Date.parse('2026-07-12T12:00:00.000Z');

function ago(ms: number): string {
	return new Date(NOW - ms).toISOString();
}

let seq = 0;
function n(overrides: Partial<GroupableNotification>): GroupableNotification {
	seq += 1;
	return {
		id: overrides.id ?? `id-${seq}`,
		kind: overrides.kind ?? 'kudos',
		actor_id: overrides.actor_id ?? null,
		run_id: overrides.run_id ?? null,
		event_id: overrides.event_id ?? null,
		club_id: overrides.club_id ?? null,
		plan_id: overrides.plan_id ?? null,
		achievement_id: overrides.achievement_id ?? null,
		challenge_id: overrides.challenge_id ?? null,
		read_at: overrides.read_at ?? null,
		created_at: overrides.created_at ?? ago(0),
	};
}

test('groupNotifications: empty input yields no groups', () => {
	assert.deepEqual(groupNotifications([], NOW), []);
});

test('groupNotifications: a single notification is a group of one', () => {
	const groups = groupNotifications([n({ id: 'a', kind: 'follow' })], NOW);
	assert.equal(groups.length, 1);
	assert.equal(groups[0].lead.id, 'a');
	assert.equal(groups[0].otherCount, 0);
	assert.deepEqual(groups[0].others, []);
	assert.equal(groups[0].unreadCount, 1);
});

test('groupNotifications: same kind + same run within window collapses, lead is newest', () => {
	const groups = groupNotifications(
		[
			n({ id: 'old', kind: 'kudos', run_id: 'r1', actor_id: 'u1', created_at: ago(2000) }),
			n({ id: 'new', kind: 'kudos', run_id: 'r1', actor_id: 'u2', created_at: ago(1000) }),
		],
		NOW,
	);
	assert.equal(groups.length, 1);
	assert.equal(groups[0].lead.id, 'new');
	assert.equal(groups[0].otherCount, 1);
	assert.deepEqual(groups[0].others.map((o) => o.id), ['old']);
});

test('groupNotifications: same kind on different runs stays separate', () => {
	const groups = groupNotifications(
		[
			n({ id: 'a', kind: 'kudos', run_id: 'r1' }),
			n({ id: 'b', kind: 'kudos', run_id: 'r2' }),
		],
		NOW,
	);
	assert.equal(groups.length, 2);
	assert.deepEqual(groups.map((g) => g.otherCount), [0, 0]);
});

test('groupNotifications: different kinds on the same run do not merge', () => {
	const groups = groupNotifications(
		[
			n({ id: 'k', kind: 'kudos', run_id: 'r1' }),
			n({ id: 'c', kind: 'comment', run_id: 'r1' }),
		],
		NOW,
	);
	assert.equal(groups.length, 2);
});

test('groupNotifications: same run beyond the window opens a fresh group', () => {
	const groups = groupNotifications(
		[
			n({ id: 'new', kind: 'kudos', run_id: 'r1', created_at: ago(1000) }),
			n({
				id: 'old',
				kind: 'kudos',
				run_id: 'r1',
				created_at: ago(NOTIFICATION_GROUP_WINDOW_MS + 5000),
			}),
		],
		NOW,
	);
	assert.equal(groups.length, 2);
	assert.equal(groups[0].lead.id, 'new');
	assert.equal(groups[1].lead.id, 'old');
});

test('groupNotifications: window boundary is inclusive', () => {
	const groups = groupNotifications(
		[
			n({ id: 'new', kind: 'kudos', run_id: 'r1', created_at: ago(0) }),
			n({
				id: 'edge',
				kind: 'kudos',
				run_id: 'r1',
				created_at: ago(NOTIFICATION_GROUP_WINDOW_MS),
			}),
		],
		NOW,
	);
	assert.equal(groups.length, 1);
	assert.equal(groups[0].otherCount, 1);
});

test('groupNotifications: unreadCount counts only unread members', () => {
	const groups = groupNotifications(
		[
			n({ id: 'a', kind: 'kudos', run_id: 'r1', created_at: ago(1000), read_at: null }),
			n({ id: 'b', kind: 'kudos', run_id: 'r1', created_at: ago(2000), read_at: ago(500) }),
			n({ id: 'c', kind: 'kudos', run_id: 'r1', created_at: ago(3000), read_at: null }),
		],
		NOW,
	);
	assert.equal(groups.length, 1);
	assert.equal(groups[0].otherCount, 2);
	assert.equal(groups[0].unreadCount, 2);
});

test('groupNotifications: follows collapse regardless of actor', () => {
	const groups = groupNotifications(
		[
			n({ id: 'f1', kind: 'follow', actor_id: 'u1', created_at: ago(1000) }),
			n({ id: 'f2', kind: 'follow', actor_id: 'u2', created_at: ago(2000) }),
			n({ id: 'f3', kind: 'follow', actor_id: 'u3', created_at: ago(3000) }),
		],
		NOW,
	);
	assert.equal(groups.length, 1);
	assert.equal(groups[0].otherCount, 2);
});

test('groupNotifications: event RSVPs collapse per event, distinct events split', () => {
	const groups = groupNotifications(
		[
			n({ id: 'e1a', kind: 'event_rsvp', event_id: 'ev1', created_at: ago(1000) }),
			n({ id: 'e1b', kind: 'event_rsvp', event_id: 'ev1', created_at: ago(2000) }),
			n({ id: 'e2a', kind: 'event_rsvp', event_id: 'ev2', created_at: ago(1500) }),
		],
		NOW,
	);
	assert.equal(groups.length, 2);
	const ev1 = groups.find((g) => g.lead.event_id === 'ev1');
	assert.ok(ev1);
	assert.equal(ev1.otherCount, 1);
});

test('groupNotifications: club posts collapse per club', () => {
	const groups = groupNotifications(
		[
			n({ id: 'p1', kind: 'club_post', club_id: 'c1', created_at: ago(1000) }),
			n({ id: 'p2', kind: 'club_post', club_id: 'c1', created_at: ago(2000) }),
		],
		NOW,
	);
	assert.equal(groups.length, 1);
	assert.equal(groups[0].otherCount, 1);
});

test('groupNotifications: messages collapse per actor, distinct actors split', () => {
	const groups = groupNotifications(
		[
			n({ id: 'm1', kind: 'message', actor_id: 'u1', created_at: ago(1000) }),
			n({ id: 'm2', kind: 'message', actor_id: 'u1', created_at: ago(2000) }),
			n({ id: 'm3', kind: 'message', actor_id: 'u2', created_at: ago(1500) }),
		],
		NOW,
	);
	assert.equal(groups.length, 2);
	const u1 = groups.find((g) => g.lead.actor_id === 'u1');
	assert.ok(u1);
	assert.equal(u1.otherCount, 1);
});

test('groupNotifications: a null target never merges two rows', () => {
	const groups = groupNotifications(
		[
			n({ id: 'a', kind: 'kudos', run_id: null, created_at: ago(1000) }),
			n({ id: 'b', kind: 'kudos', run_id: null, created_at: ago(2000) }),
		],
		NOW,
	);
	assert.equal(groups.length, 2);
	assert.deepEqual(groups.map((g) => g.otherCount), [0, 0]);
});

test('groupNotifications: groups are ordered newest-lead first', () => {
	const groups = groupNotifications(
		[
			n({ id: 'older', kind: 'kudos', run_id: 'r1', created_at: ago(5000) }),
			n({ id: 'newer', kind: 'comment', run_id: 'r2', created_at: ago(1000) }),
		],
		NOW,
	);
	assert.deepEqual(groups.map((g) => g.lead.id), ['newer', 'older']);
});

test('groupNotifications: a clock-skewed future row clamps to now and leads the burst', () => {
	const groups = groupNotifications(
		[
			n({ id: 'past', kind: 'kudos', run_id: 'r1', created_at: ago(2000) }),
			n({
				id: 'future',
				kind: 'kudos',
				run_id: 'r1',
				created_at: new Date(NOW + 60_000).toISOString(),
			}),
		],
		NOW,
	);
	assert.equal(groups.length, 1);
	assert.equal(groups[0].lead.id, 'future');
	assert.equal(groups[0].otherCount, 1);
});

test('groupNotifications: unsorted input still finds the true newest lead', () => {
	const groups = groupNotifications(
		[
			n({ id: 'mid', kind: 'kudos', run_id: 'r1', created_at: ago(2000) }),
			n({ id: 'newest', kind: 'kudos', run_id: 'r1', created_at: ago(500) }),
			n({ id: 'oldest', kind: 'kudos', run_id: 'r1', created_at: ago(4000) }),
		],
		NOW,
	);
	assert.equal(groups.length, 1);
	assert.equal(groups[0].lead.id, 'newest');
	assert.deepEqual(groups[0].others.map((o) => o.id), ['mid', 'oldest']);
});

test('groupNotifications: achievements group by id, a null id stays solo', () => {
	const groups = groupNotifications(
		[
			n({ id: 'a1', kind: 'achievement', achievement_id: 'ach1', created_at: ago(1000) }),
			n({ id: 'a2', kind: 'achievement', achievement_id: 'ach1', created_at: ago(2000) }),
			n({ id: 'a3', kind: 'achievement', achievement_id: null, created_at: ago(1500) }),
			n({ id: 'a4', kind: 'achievement', achievement_id: null, created_at: ago(2500) }),
		],
		NOW,
	);
	// ach1 collapses to one group; the two null-id rows stay solo → 3 groups.
	assert.equal(groups.length, 3);
	const ach1 = groups.find((g) => g.lead.achievement_id === 'ach1');
	assert.ok(ach1);
	assert.equal(ach1.otherCount, 1);
});
