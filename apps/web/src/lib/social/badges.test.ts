import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	BADGE_CATALOGUE,
	TIER_ORDER,
	evaluateBadges,
	tierFor,
	type BadgeInput,
} from './badges';

const ZERO: BadgeInput = {
	longestRunM: 0,
	lifetimeDistanceM: 0,
	bestStreakDays: 0,
	prCount: 0,
	completedPlanCount: 0,
};

function earned(input: Partial<BadgeInput>) {
	return evaluateBadges({ ...ZERO, ...input });
}

function find(input: Partial<BadgeInput>, badgeKey: string) {
	return earned(input).find((e) => e.badgeKey === badgeKey);
}

test('no milestones → no badges', () => {
	assert.deepEqual(evaluateBadges(ZERO), []);
});

test('catalogue ids are unique and tiers ascend by threshold', () => {
	const ids = new Set<string>();
	for (const b of BADGE_CATALOGUE) {
		assert.equal(ids.has(b.id), false, `duplicate id ${b.id}`);
		ids.add(b.id);
		for (let i = 1; i < b.tiers.length; i++) {
			assert.ok(
				b.tiers[i].threshold > b.tiers[i - 1].threshold,
				`${b.id} tiers not ascending`,
			);
			assert.ok(
				TIER_ORDER.indexOf(b.tiers[i].tier) > TIER_ORDER.indexOf(b.tiers[i - 1].tier),
				`${b.id} tier order wrong`,
			);
		}
	}
});

test('single-run distance: 5k earns bronze, exact boundary inclusive', () => {
	const e = find({ longestRunM: 5000 }, 'distance_single');
	assert.equal(e?.tier, 'bronze');
	assert.equal(e?.valueNum, 5000);
});

test('single-run distance: just under 5k earns nothing', () => {
	assert.equal(find({ longestRunM: 4999 }, 'distance_single'), undefined);
});

test('single-run distance: marathon earns gold, not also bronze/silver', () => {
	const all = earned({ longestRunM: 42195 });
	const single = all.filter((e) => e.badgeKey === 'distance_single');
	assert.equal(single.length, 1);
	assert.equal(single[0].tier, 'gold');
});

test('single-run distance: 50k+ earns platinum (ultra)', () => {
	assert.equal(find({ longestRunM: 60000 }, 'distance_single')?.tier, 'platinum');
});

test('lifetime distance: 100km bronze, 1000km gold', () => {
	assert.equal(find({ lifetimeDistanceM: 100000 }, 'distance_lifetime')?.tier, 'bronze');
	assert.equal(find({ lifetimeDistanceM: 1_000_000 }, 'distance_lifetime')?.tier, 'gold');
});

test('lifetime distance: 5000km platinum is the cap', () => {
	assert.equal(find({ lifetimeDistanceM: 9_000_000 }, 'distance_lifetime')?.tier, 'platinum');
});

test('streak: 7 days bronze, 30 silver, 100 gold, 365 platinum', () => {
	assert.equal(find({ bestStreakDays: 7 }, 'streak')?.tier, 'bronze');
	assert.equal(find({ bestStreakDays: 30 }, 'streak')?.tier, 'silver');
	assert.equal(find({ bestStreakDays: 100 }, 'streak')?.tier, 'gold');
	assert.equal(find({ bestStreakDays: 365 }, 'streak')?.tier, 'platinum');
});

test('streak: 6 days earns nothing', () => {
	assert.equal(find({ bestStreakDays: 6 }, 'streak'), undefined);
});

test('pr: first PR bronze, 3 silver, all-5 gold', () => {
	assert.equal(find({ prCount: 1 }, 'pr')?.tier, 'bronze');
	assert.equal(find({ prCount: 3 }, 'pr')?.tier, 'silver');
	assert.equal(find({ prCount: 5 }, 'pr')?.tier, 'gold');
});

test('plan finisher: 1 bronze, 3 silver, 10 gold', () => {
	assert.equal(find({ completedPlanCount: 1 }, 'plan_finisher')?.tier, 'bronze');
	assert.equal(find({ completedPlanCount: 3 }, 'plan_finisher')?.tier, 'silver');
	assert.equal(find({ completedPlanCount: 10 }, 'plan_finisher')?.tier, 'gold');
});

test('a maxed-out user earns one badge per family at the top tier', () => {
	const all = earned({
		longestRunM: 100000,
		lifetimeDistanceM: 6_000_000,
		bestStreakDays: 400,
		prCount: 5,
		completedPlanCount: 12,
	});
	assert.equal(all.length, BADGE_CATALOGUE.length);
	for (const b of BADGE_CATALOGUE) {
		const e = all.filter((x) => x.badgeKey === b.id);
		assert.equal(e.length, 1, `${b.id} should appear once`);
	}
	assert.equal(all.find((e) => e.badgeKey === 'distance_single')?.tier, 'platinum');
	assert.equal(all.find((e) => e.badgeKey === 'pr')?.tier, 'gold');
});

test('output order follows catalogue order', () => {
	const all = earned({
		longestRunM: 5000,
		lifetimeDistanceM: 100000,
		bestStreakDays: 7,
		prCount: 1,
		completedPlanCount: 1,
	});
	assert.deepEqual(
		all.map((e) => e.badgeKey),
		BADGE_CATALOGUE.map((b) => b.id),
	);
});

test('tierFor resolves a stored award to its catalogue tier', () => {
	const t = tierFor('streak', 'gold');
	assert.equal(t?.threshold, 100);
	assert.equal(tierFor('nope', 'bronze'), null);
	assert.equal(tierFor('streak', 'platinum')?.threshold, 365);
});
