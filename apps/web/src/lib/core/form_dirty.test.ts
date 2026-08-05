import assert from 'node:assert/strict';
import { test } from 'node:test';

import { trackDirty } from './form_dirty';

test('a freshly seeded form is clean', () => {
	const fields = { title: 'Push day', notes: '', isPublic: false };
	const t = trackDirty(() => ({ ...fields }));
	assert.equal(t.isDirty(), false);
});

test('editing a scalar field marks the form dirty', () => {
	const fields = { title: '', notes: '' };
	const t = trackDirty(() => ({ ...fields }));
	fields.title = 'a';
	assert.equal(t.isDirty(), true);
});

test('editing back to the seeded value marks the form clean again', () => {
	const fields = { title: 'Push day' };
	const t = trackDirty(() => ({ ...fields }));
	fields.title = 'Pull day';
	assert.equal(t.isDirty(), true);
	fields.title = 'Push day';
	assert.equal(t.isDirty(), false);
});

test('null and empty string are distinct edits', () => {
	const fields: { note: string | null } = { note: null };
	const t = trackDirty(() => ({ ...fields }));
	fields.note = '';
	assert.equal(t.isDirty(), true);
});

test('a number typed as a string is an edit', () => {
	const fields: { reps: number | string } = { reps: 5 };
	const t = trackDirty(() => ({ ...fields }));
	fields.reps = '5';
	assert.equal(t.isDirty(), true);
});

test('nested rows are compared by value, not identity', () => {
	let rows = [{ name: 'Bench', sets: [{ reps: 5 }] }];
	const t = trackDirty(() => rows.map((r) => ({ ...r, sets: r.sets.map((s) => ({ ...s })) })));
	rows = [{ name: 'Bench', sets: [{ reps: 5 }] }];
	assert.equal(t.isDirty(), false);
	rows = [{ name: 'Bench', sets: [{ reps: 6 }] }];
	assert.equal(t.isDirty(), true);
});

test('adding and removing a row are both dirty', () => {
	let rows = [{ name: 'Bench' }];
	const t = trackDirty(() => rows.map((r) => ({ ...r })));
	rows = [{ name: 'Bench' }, { name: 'Row' }];
	assert.equal(t.isDirty(), true);
	rows = [];
	assert.equal(t.isDirty(), true);
});

test('reordering rows is dirty', () => {
	let rows = [{ name: 'Bench' }, { name: 'Row' }];
	const t = trackDirty(() => rows.map((r) => ({ ...r })));
	rows = [{ name: 'Row' }, { name: 'Bench' }];
	assert.equal(t.isDirty(), true);
});

test('rebaseline clears dirtiness so a saved form does not prompt', () => {
	const fields = { title: '' };
	const t = trackDirty(() => ({ ...fields }));
	fields.title = 'Saved';
	assert.equal(t.isDirty(), true);
	t.rebaseline();
	assert.equal(t.isDirty(), false);
	fields.title = 'Edited again';
	assert.equal(t.isDirty(), true);
});

test('a key present on one side only is an edit', () => {
	let fields: Record<string, unknown> = { a: 1 };
	const t = trackDirty(() => ({ ...fields }));
	fields = { a: 1, b: undefined };
	assert.equal(t.isDirty(), true);
});
