import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	COMPARE_SECTIONS,
	COMPARE_HEADLINE,
	type FeatureSupport,
} from './compare_features';

test('COMPARE_SECTIONS: every row has all three product columns set', () => {
	for (const section of COMPARE_SECTIONS) {
		for (const row of section.rows) {
			const cols: Array<['ours' | 'free' | 'pro', FeatureSupport]> = [
				['ours', row.ours],
				['free', row.stravaFree],
				['pro', row.stravaPro],
			];
			for (const [col, v] of cols) {
				assert.ok(
					v === 'yes' || v === 'no' || v === 'partial',
					`${section.title}: ${row.name} has invalid ${col}: ${v}`,
				);
			}
		}
	}
});

test('COMPARE_SECTIONS: at least one row per section', () => {
	for (const section of COMPARE_SECTIONS) {
		assert.ok(section.rows.length > 0, `${section.title} has no rows`);
	}
});

test('COMPARE_SECTIONS: row names are unique within a section', () => {
	for (const section of COMPARE_SECTIONS) {
		const seen = new Set<string>();
		for (const row of section.rows) {
			assert.ok(!seen.has(row.name), `${section.title} duplicates ${row.name}`);
			seen.add(row.name);
		}
	}
});

test('COMPARE_SECTIONS: section titles are unique', () => {
	const titles = COMPARE_SECTIONS.map((s) => s.title);
	const set = new Set(titles);
	assert.equal(set.size, titles.length);
});

test('COMPARE_SECTIONS: our column is "yes" everywhere except where we are honest about partial gaps', () => {
	// The product positioning is "everything Strava Pro has, free". A
	// "no" in our column would contradict that claim and should be
	// caught by code review. "partial" is fine where the feature ships
	// in scaffold or read-only form.
	for (const section of COMPARE_SECTIONS) {
		for (const row of section.rows) {
			assert.notEqual(
				row.ours,
				'no',
				`${section.title}: ${row.name} is "no" in our column — either ship it or remove the row`,
			);
		}
	}
});

test('COMPARE_SECTIONS: at least one row has us=yes / Strava Free=no (showcases our value)', () => {
	let count = 0;
	for (const section of COMPARE_SECTIONS) {
		for (const row of section.rows) {
			if (row.ours === 'yes' && row.stravaFree === 'no') count += 1;
		}
	}
	assert.ok(count >= 5, `expected at least 5 rows where we beat Strava Free, got ${count}`);
});

test('COMPARE_HEADLINE: us = Free', () => {
	assert.equal(COMPARE_HEADLINE.usPrice, 'Free');
});

test('COMPARE_HEADLINE: Strava Pro pricing is non-empty', () => {
	assert.ok(COMPARE_HEADLINE.stravaProPrice.length > 0);
});

test('COMPARE_SECTIONS: note field, if present, is non-empty', () => {
	for (const section of COMPARE_SECTIONS) {
		for (const row of section.rows) {
			if (row.note != null) {
				assert.ok(row.note.length > 0, `empty note on ${row.name}`);
			}
		}
	}
});
