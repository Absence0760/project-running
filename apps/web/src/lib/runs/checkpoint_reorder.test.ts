import assert from 'node:assert/strict';
import { test } from 'node:test';

import { swapCheckpointOrdinals, type OrdinalCheckpoint } from './checkpoint_reorder';

const checkpoints: OrdinalCheckpoint[] = [
	{ id: 'cp1', ordinal: 1 },
	{ id: 'cp2', ordinal: 2 },
	{ id: 'cp3', ordinal: 3 }
];

test('swaps adjacent ordinals via a temp slot, then reloads on success', async () => {
	const calls: Array<[string, number]> = [];
	let reloads = 0;
	await swapCheckpointOrdinals(checkpoints, 0, 1, {
		update: async (id, patch) => {
			calls.push([id, patch.ordinal]);
		},
		reload: async () => {
			reloads += 1;
		}
	});
	assert.deepEqual(calls, [
		['cp1', 1003],
		['cp2', 1],
		['cp1', 2]
	]);
	assert.equal(reloads, 1);
});

test('re-syncs via reload when the 2nd write fails mid-sequence', async () => {
	const calls: Array<[string, number]> = [];
	let reloads = 0;
	await assert.rejects(
		swapCheckpointOrdinals(checkpoints, 0, 1, {
			update: async (id, patch) => {
				calls.push([id, patch.ordinal]);
				if (calls.length === 2) throw new Error('boom');
			},
			reload: async () => {
				reloads += 1;
			}
		}),
		/boom/
	);
	assert.equal(calls.length, 2);
	assert.equal(reloads, 1);
});

test('re-syncs via reload when the 3rd write fails mid-sequence', async () => {
	let reloads = 0;
	let writes = 0;
	await assert.rejects(
		swapCheckpointOrdinals(checkpoints, 1, 1, {
			update: async () => {
				writes += 1;
				if (writes === 3) throw new Error('boom');
			},
			reload: async () => {
				reloads += 1;
			}
		}),
		/boom/
	);
	assert.equal(writes, 3);
	assert.equal(reloads, 1);
});
