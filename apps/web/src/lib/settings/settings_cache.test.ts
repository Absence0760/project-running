import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	InMemoryPrefsCache,
	LocalStoragePrefsCache,
	applyPrefsChanges,
	type PrefsCache,
} from './settings_cache';

// ───────────────── applyPrefsChanges (pure merge) ─────────────────
//
// Mirrors the Dart `SettingsService.applyPrefsChanges` reference
// (`packages/api_client/lib/src/settings_service.dart`). The two
// implementations are the load-bearing seam that makes a write on web
// and a write on mobile produce identical bag shapes.

test('applyPrefsChanges: empty base + empty changes → empty result', () => {
	assert.deepEqual(applyPrefsChanges({}, {}), {});
});

test('applyPrefsChanges: changes override base on identical keys', () => {
	assert.deepEqual(
		applyPrefsChanges({ a: 1, b: 2 }, { a: 9 }),
		{ a: 9, b: 2 },
	);
});

test('applyPrefsChanges: new keys are added', () => {
	assert.deepEqual(
		applyPrefsChanges({ a: 1 }, { b: 2, c: 3 }),
		{ a: 1, b: 2, c: 3 },
	);
});

test('applyPrefsChanges: null deletes the key (mobile + web parity)', () => {
	assert.deepEqual(
		applyPrefsChanges({ a: 1, b: 2 }, { a: null }),
		{ b: 2 },
	);
});

test('applyPrefsChanges: undefined also deletes (JS-only, treated identically to null)', () => {
	assert.deepEqual(
		applyPrefsChanges({ a: 1, b: 2 }, { a: undefined }),
		{ b: 2 },
	);
});

test('applyPrefsChanges: deleting a missing key is a no-op (no error)', () => {
	assert.deepEqual(applyPrefsChanges({ a: 1 }, { b: null }), { a: 1 });
});

test('applyPrefsChanges: 0 / "" / false are kept (only null+undefined trigger delete)', () => {
	// Persona-hunt-relevant: a user setting `weekly_mileage_goal_m`
	// to 0 must persist as zero, not be deleted. Same for any boolean
	// pref defaulting to off.
	assert.deepEqual(
		applyPrefsChanges({}, { a: 0, b: '', c: false }),
		{ a: 0, b: '', c: false },
	);
});

test('applyPrefsChanges: returns a fresh map; mutating result does not affect base', () => {
	const base = { a: 1 };
	const merged = applyPrefsChanges(base, { b: 2 }) as Record<string, number>;
	merged.b = 999;
	assert.deepEqual(base, { a: 1 });
});

test('applyPrefsChanges: mutating base after the call does not affect result', () => {
	const base: Record<string, number> = { a: 1 };
	const merged = applyPrefsChanges(base, { b: 2 });
	base.a = 999;
	assert.deepEqual(merged, { a: 1, b: 2 });
});

// ───────────────── shared cache contract ─────────────────
//
// Every cache impl must pass this suite. Driven through a fixture so
// both InMemoryPrefsCache and a localStorage-stubbed
// LocalStoragePrefsCache exercise identical behaviour.

function runCacheContract(name: string, factory: () => PrefsCache): void {
	test(`${name}: readUniversal returns null on cache miss`, () => {
		const cache = factory();
		assert.equal(cache.readUniversal('user-a'), null);
	});

	test(`${name}: readDevice returns null on cache miss`, () => {
		const cache = factory();
		assert.equal(cache.readDevice('user-a', 'device-1'), null);
	});

	test(`${name}: writeUniversal + readUniversal round-trips a bag`, () => {
		const cache = factory();
		cache.writeUniversal('user-a', { preferred_unit: 'km', resting_hr_bpm: 52 });
		assert.deepEqual(cache.readUniversal('user-a'), {
			preferred_unit: 'km',
			resting_hr_bpm: 52,
		});
	});

	test(`${name}: writeDevice + readDevice round-trips a bag scoped by deviceId`, () => {
		const cache = factory();
		cache.writeDevice('user-a', 'device-1', { map_style: 'dark' });
		assert.deepEqual(cache.readDevice('user-a', 'device-1'), { map_style: 'dark' });
		// Different device → no read-through.
		assert.equal(cache.readDevice('user-a', 'device-2'), null);
	});

	test(`${name}: separate users do not see each other's universal bags`, () => {
		const cache = factory();
		cache.writeUniversal('user-a', { preferred_unit: 'km' });
		cache.writeUniversal('user-b', { preferred_unit: 'mi' });
		assert.deepEqual(cache.readUniversal('user-a'), { preferred_unit: 'km' });
		assert.deepEqual(cache.readUniversal('user-b'), { preferred_unit: 'mi' });
	});

	test(`${name}: separate users do not see each other's device bags`, () => {
		const cache = factory();
		cache.writeDevice('user-a', 'device-1', { map_style: 'dark' });
		cache.writeDevice('user-b', 'device-1', { map_style: 'light' });
		assert.deepEqual(cache.readDevice('user-a', 'device-1'), { map_style: 'dark' });
		assert.deepEqual(cache.readDevice('user-b', 'device-1'), { map_style: 'light' });
	});

	test(`${name}: appendPending stacks changes in order`, () => {
		const cache = factory();
		cache.appendPending('user-a', 'device-1', { isDevice: false, changes: { a: 1 } });
		cache.appendPending('user-a', 'device-1', { isDevice: true, changes: { b: 2 } });
		const queue = cache.readPending('user-a', 'device-1');
		assert.equal(queue.length, 2);
		assert.deepEqual(queue[0], { isDevice: false, changes: { a: 1 } });
		assert.deepEqual(queue[1], { isDevice: true, changes: { b: 2 } });
	});

	test(`${name}: pending queue is scoped by (userId, deviceId)`, () => {
		const cache = factory();
		cache.appendPending('user-a', 'device-1', { isDevice: false, changes: { a: 1 } });
		cache.appendPending('user-a', 'device-2', { isDevice: false, changes: { b: 2 } });
		assert.deepEqual(cache.readPending('user-a', 'device-1'), [
			{ isDevice: false, changes: { a: 1 } },
		]);
		assert.deepEqual(cache.readPending('user-a', 'device-2'), [
			{ isDevice: false, changes: { b: 2 } },
		]);
	});

	test(`${name}: clearPending wipes only the targeted queue`, () => {
		const cache = factory();
		cache.appendPending('user-a', 'device-1', { isDevice: false, changes: { a: 1 } });
		cache.appendPending('user-a', 'device-2', { isDevice: false, changes: { b: 2 } });
		cache.clearPending('user-a', 'device-1');
		assert.deepEqual(cache.readPending('user-a', 'device-1'), []);
		assert.deepEqual(cache.readPending('user-a', 'device-2'), [
			{ isDevice: false, changes: { b: 2 } },
		]);
	});

	test(`${name}: dropUser clears every entry for that user, leaves others`, () => {
		const cache = factory();
		cache.writeUniversal('user-a', { preferred_unit: 'km' });
		cache.writeDevice('user-a', 'device-1', { map_style: 'dark' });
		cache.appendPending('user-a', 'device-1', { isDevice: false, changes: { a: 1 } });
		cache.writeUniversal('user-b', { preferred_unit: 'mi' });
		cache.writeDevice('user-b', 'device-1', { map_style: 'light' });
		cache.appendPending('user-b', 'device-1', { isDevice: false, changes: { b: 2 } });

		cache.dropUser('user-a');

		assert.equal(cache.readUniversal('user-a'), null);
		assert.equal(cache.readDevice('user-a', 'device-1'), null);
		assert.deepEqual(cache.readPending('user-a', 'device-1'), []);
		// user-b is untouched — the prefix scope is exact.
		assert.deepEqual(cache.readUniversal('user-b'), { preferred_unit: 'mi' });
		assert.deepEqual(cache.readDevice('user-b', 'device-1'), { map_style: 'light' });
		assert.deepEqual(cache.readPending('user-b', 'device-1'), [
			{ isDevice: false, changes: { b: 2 } },
		]);
	});

	test(`${name}: appendPending preserves a deep copy of changes (caller mutation is harmless)`, () => {
		const cache = factory();
		const changes: Record<string, number> = { a: 1 };
		cache.appendPending('user-a', 'device-1', { isDevice: false, changes });
		changes.a = 999;
		assert.deepEqual(cache.readPending('user-a', 'device-1')[0].changes, { a: 1 });
	});

	test(`${name}: writeUniversal preserves a deep copy (caller mutation is harmless)`, () => {
		const cache = factory();
		const prefs: Record<string, number> = { a: 1 };
		cache.writeUniversal('user-a', prefs);
		prefs.a = 999;
		assert.deepEqual(cache.readUniversal('user-a'), { a: 1 });
	});

	test(`${name}: prefix overlap — user "ab" does not leak from user "a" dropUser`, () => {
		// Persona-hunt-relevant: a naive `startsWith(userId)` sweep
		// would clobber a sibling user whose id happens to be a
		// prefix-extension. The key shape `..._<userId>_<deviceId>`
		// guards against this only when the trailing underscore is
		// matched. Verify the contract explicitly.
		const cache = factory();
		cache.writeUniversal('ab', { x: 1 });
		cache.writeDevice('ab', 'd1', { x: 1 });
		cache.appendPending('ab', 'd1', { isDevice: false, changes: { x: 1 } });
		cache.writeUniversal('a', { y: 2 });
		cache.writeDevice('a', 'd1', { y: 2 });
		cache.appendPending('a', 'd1', { isDevice: false, changes: { y: 2 } });

		cache.dropUser('a');

		assert.equal(cache.readUniversal('a'), null);
		assert.equal(cache.readDevice('a', 'd1'), null);
		// "ab" must still be intact — its keys (`..._ab`) survive a
		// dropUser scoped to `a` only when the drop check is anchored
		// at a key boundary (universal: full match on the trailing
		// segment; device + pending: requires the underscore separator).
		assert.deepEqual(cache.readUniversal('ab'), { x: 1 });
		assert.deepEqual(cache.readDevice('ab', 'd1'), { x: 1 });
		assert.deepEqual(cache.readPending('ab', 'd1'), [
			{ isDevice: false, changes: { x: 1 } },
		]);
	});
}

runCacheContract('InMemoryPrefsCache', () => new InMemoryPrefsCache());

// LocalStoragePrefsCache contract — driven through a minimal Storage
// stub. We can't import the global localStorage in node, but the
// LocalStoragePrefsCache only reaches for `localStorage` via a typeof
// guard. Re-declaring it as a global stub before instantiating the
// cache is enough to exercise the full path.
function makeStorageStub(): Storage {
	const map = new Map<string, string>();
	const stub: Storage = {
		get length() {
			return map.size;
		},
		key(i: number) {
			return Array.from(map.keys())[i] ?? null;
		},
		getItem(k: string) {
			return map.get(k) ?? null;
		},
		setItem(k: string, v: string) {
			map.set(k, v);
		},
		removeItem(k: string) {
			map.delete(k);
		},
		clear() {
			map.clear();
		},
	};
	return stub;
}

runCacheContract('LocalStoragePrefsCache', () => {
	(globalThis as unknown as { localStorage: Storage }).localStorage = makeStorageStub();
	return new LocalStoragePrefsCache();
});

// ───────────────── LocalStorage-specific resilience ─────────────────

test('LocalStoragePrefsCache: corrupt JSON returns null (read-side recovery)', () => {
	const storage = makeStorageStub();
	(globalThis as unknown as { localStorage: Storage }).localStorage = storage;
	storage.setItem('settings_cache_universal_user-a', '{ this is not json');
	const cache = new LocalStoragePrefsCache();
	assert.equal(cache.readUniversal('user-a'), null);
});

test('LocalStoragePrefsCache: JSON of wrong shape (array) returns null', () => {
	const storage = makeStorageStub();
	(globalThis as unknown as { localStorage: Storage }).localStorage = storage;
	storage.setItem('settings_cache_universal_user-a', '[1,2,3]');
	const cache = new LocalStoragePrefsCache();
	assert.equal(cache.readUniversal('user-a'), null);
});

test('LocalStoragePrefsCache: corrupt pending queue returns [] (drain-from-zero)', () => {
	const storage = makeStorageStub();
	(globalThis as unknown as { localStorage: Storage }).localStorage = storage;
	storage.setItem('settings_cache_pending_user-a_device-1', 'not even json');
	const cache = new LocalStoragePrefsCache();
	assert.deepEqual(cache.readPending('user-a', 'device-1'), []);
});

test('LocalStoragePrefsCache: queue entries missing required fields are dropped on read', () => {
	const storage = makeStorageStub();
	(globalThis as unknown as { localStorage: Storage }).localStorage = storage;
	// Mix one valid + one shape-broken entry; the broken one drops
	// silently so the valid one still drains.
	storage.setItem(
		'settings_cache_pending_user-a_device-1',
		JSON.stringify([
			{ isDevice: false, changes: { a: 1 } },
			{ isDevice: 'not-a-bool' },
			{ changes: { b: 2 } },
		]),
	);
	const cache = new LocalStoragePrefsCache();
	const queue = cache.readPending('user-a', 'device-1');
	assert.equal(queue.length, 1);
	assert.deepEqual(queue[0], { isDevice: false, changes: { a: 1 } });
});

test('LocalStoragePrefsCache: setItem throw is swallowed (quota / private-mode lockdown)', () => {
	const failing: Storage = {
		length: 0,
		key: () => null,
		getItem: () => null,
		setItem: () => {
			throw new Error('QuotaExceeded');
		},
		removeItem: () => undefined,
		clear: () => undefined,
	};
	(globalThis as unknown as { localStorage: Storage }).localStorage = failing;
	const cache = new LocalStoragePrefsCache();
	// Must not throw — caller's call site (settings.ts) treats the
	// cache as additive, never load-bearing.
	cache.writeUniversal('user-a', { a: 1 });
	cache.appendPending('user-a', 'd1', { isDevice: false, changes: {} });
	// And the subsequent read returns null (the write was lost), which
	// just forces a network round-trip on the next loadSettings.
	assert.equal(cache.readUniversal('user-a'), null);
});
