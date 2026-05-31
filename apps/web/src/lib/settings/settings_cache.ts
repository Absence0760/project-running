/// localStorage-backed cache for the universal + per-device prefs
/// bags, mirroring the mobile [SharedPrefsSettingsCache]
/// (`apps/mobile_android/lib/settings_cache.dart`) and the
/// [SettingsCache] abstract from
/// `packages/api_client/lib/src/settings_service.dart`.
///
/// Web was network-only until now: every `loadSettings` round-tripped
/// to Supabase, every `updateUniversal` / `updateDevice` did a
/// read-merge-write. That meant the dashboard's Fitness card +
/// Intensity card sat empty under the smallest network blip, and an
/// offline edit was just lost. Mobile already shipped a write-through
/// cache + offline-drain queue (ADR §72) — this module brings web up
/// to parity so the per-key plumbing of the universal bag (HR zones,
/// resting / max HR, weekly goal, week start, preferred unit,
/// activity defaults, etc.) is offline-first too.
///
/// Keys are scoped by `userId` (and by `deviceId` for the device bag)
/// so a sign-out + sign-in as a different user on the same browser
/// can't read a prior user's bag. Pending writes are JSON-encoded so
/// adding a new key to the registry doesn't need a cache migration.

import type { PrefsBag } from './settings_overlay';

export interface PendingChange {
	isDevice: boolean;
	changes: PrefsBag;
}

/// Sync-read async-write interface so the SSR / test fallback can be
/// an in-memory Map and the production impl can be localStorage
/// (which is sync) without forcing every caller through a Promise.
export interface PrefsCache {
	readUniversal(userId: string): PrefsBag | null;
	readDevice(userId: string, deviceId: string): PrefsBag | null;
	writeUniversal(userId: string, prefs: PrefsBag): void;
	writeDevice(userId: string, deviceId: string, prefs: PrefsBag): void;
	readPending(userId: string, deviceId: string): PendingChange[];
	appendPending(userId: string, deviceId: string, change: PendingChange): void;
	clearPending(userId: string, deviceId: string): void;
	dropUser(userId: string): void;
}

const K_UNIVERSAL = 'settings_cache_universal_';
const K_DEVICE = 'settings_cache_device_';
const K_PENDING = 'settings_cache_pending_';

function universalKey(userId: string): string {
	return `${K_UNIVERSAL}${userId}`;
}

function deviceKey(userId: string, deviceId: string): string {
	return `${K_DEVICE}${userId}_${deviceId}`;
}

function pendingKey(userId: string, deviceId: string): string {
	return `${K_PENDING}${userId}_${deviceId}`;
}

function decodeMap(raw: string | null): PrefsBag | null {
	if (!raw) return null;
	try {
		const decoded = JSON.parse(raw);
		if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) {
			return decoded as PrefsBag;
		}
	} catch {
		// Corrupt cached bag — drop it on read so a malformed write
		// from a prior session can't permanently brick the UI.
	}
	return null;
}

function decodeQueue(raw: string | null): PendingChange[] {
	if (!raw) return [];
	try {
		const decoded = JSON.parse(raw);
		if (!Array.isArray(decoded)) return [];
		return decoded
			.filter(
				(e): e is PendingChange =>
					!!e && typeof e === 'object' && typeof e.isDevice === 'boolean' && !!e.changes,
			)
			.map((e) => ({ isDevice: e.isDevice, changes: { ...e.changes } }));
	} catch {
		return [];
	}
}

/// Production cache backed by `window.localStorage`. Storage
/// failures (quota, private-mode lockdown, security policy) are
/// swallowed — the cache is additive, never load-bearing. A failed
/// write just means the next read won't hit cache.
export class LocalStoragePrefsCache implements PrefsCache {
	private get store(): Storage | null {
		try {
			if (typeof localStorage === 'undefined') return null;
			return localStorage;
		} catch {
			return null;
		}
	}

	readUniversal(userId: string): PrefsBag | null {
		try {
			return decodeMap(this.store?.getItem(universalKey(userId)) ?? null);
		} catch {
			return null;
		}
	}

	readDevice(userId: string, deviceId: string): PrefsBag | null {
		try {
			return decodeMap(this.store?.getItem(deviceKey(userId, deviceId)) ?? null);
		} catch {
			return null;
		}
	}

	writeUniversal(userId: string, prefs: PrefsBag): void {
		try {
			this.store?.setItem(universalKey(userId), JSON.stringify(prefs));
		} catch {
			// quota / security — silent
		}
	}

	writeDevice(userId: string, deviceId: string, prefs: PrefsBag): void {
		try {
			this.store?.setItem(deviceKey(userId, deviceId), JSON.stringify(prefs));
		} catch {
			// silent
		}
	}

	readPending(userId: string, deviceId: string): PendingChange[] {
		try {
			return decodeQueue(this.store?.getItem(pendingKey(userId, deviceId)) ?? null);
		} catch {
			return [];
		}
	}

	appendPending(userId: string, deviceId: string, change: PendingChange): void {
		try {
			const queue = this.readPending(userId, deviceId);
			queue.push({ isDevice: change.isDevice, changes: { ...change.changes } });
			this.store?.setItem(pendingKey(userId, deviceId), JSON.stringify(queue));
		} catch {
			// silent
		}
	}

	clearPending(userId: string, deviceId: string): void {
		try {
			this.store?.removeItem(pendingKey(userId, deviceId));
		} catch {
			// silent
		}
	}

	dropUser(userId: string): void {
		const store = this.store;
		if (!store) return;
		try {
			const stale: string[] = [];
			// Boundary match matters: a `startsWith` sweep against
			// `settings_cache_universal_a` would also catch
			// `settings_cache_universal_ab`. Universal is a single
			// key per user, so match exactly; device + pending always
			// carry a `_<deviceId>` suffix, so anchor on the trailing
			// underscore.
			const exactUniversal = `${K_UNIVERSAL}${userId}`;
			const devicePrefix = `${K_DEVICE}${userId}_`;
			const pendingPrefix = `${K_PENDING}${userId}_`;
			for (let i = 0; i < store.length; i++) {
				const k = store.key(i);
				if (!k) continue;
				if (k === exactUniversal || k.startsWith(devicePrefix) || k.startsWith(pendingPrefix)) {
					stale.push(k);
				}
			}
			for (const k of stale) store.removeItem(k);
		} catch {
			// silent
		}
	}
}

/// In-memory cache used in two paths: server-side rendering (no
/// `localStorage` global) and unit tests. Same contract as the
/// localStorage impl — `dropUser` only sweeps this user's entries.
export class InMemoryPrefsCache implements PrefsCache {
	private universal = new Map<string, PrefsBag>();
	private device = new Map<string, PrefsBag>();
	private pending = new Map<string, PendingChange[]>();

	readUniversal(userId: string): PrefsBag | null {
		const v = this.universal.get(userId);
		return v ? { ...v } : null;
	}

	readDevice(userId: string, deviceId: string): PrefsBag | null {
		const v = this.device.get(deviceKey(userId, deviceId));
		return v ? { ...v } : null;
	}

	writeUniversal(userId: string, prefs: PrefsBag): void {
		this.universal.set(userId, { ...prefs });
	}

	writeDevice(userId: string, deviceId: string, prefs: PrefsBag): void {
		this.device.set(deviceKey(userId, deviceId), { ...prefs });
	}

	readPending(userId: string, deviceId: string): PendingChange[] {
		const q = this.pending.get(pendingKey(userId, deviceId));
		return q ? q.map((c) => ({ isDevice: c.isDevice, changes: { ...c.changes } })) : [];
	}

	appendPending(userId: string, deviceId: string, change: PendingChange): void {
		const key = pendingKey(userId, deviceId);
		const q = this.pending.get(key) ?? [];
		q.push({ isDevice: change.isDevice, changes: { ...change.changes } });
		this.pending.set(key, q);
	}

	clearPending(userId: string, deviceId: string): void {
		this.pending.delete(pendingKey(userId, deviceId));
	}

	dropUser(userId: string): void {
		this.universal.delete(userId);
		// Device + pending maps are keyed by the full
		// `<K_DEVICE>${userId}_${deviceId}` / `<K_PENDING>...` strings
		// produced by `deviceKey` / `pendingKey`. Anchor on the trailing
		// underscore so a sibling user whose id happens to be a prefix
		// (e.g. `'a'` vs `'ab'`) doesn't get swept.
		const devicePrefix = `${K_DEVICE}${userId}_`;
		const pendingPrefix = `${K_PENDING}${userId}_`;
		for (const k of Array.from(this.device.keys())) {
			if (k.startsWith(devicePrefix)) this.device.delete(k);
		}
		for (const k of Array.from(this.pending.keys())) {
			if (k.startsWith(pendingPrefix)) this.pending.delete(k);
		}
	}
}

/// Pure merge helper. Mirrors the in-place loop in the prior
/// `settings.ts: updateUniversal` and the Dart
/// `SettingsService.applyPrefsChanges`. Keys whose `changes` value is
/// `null` or `undefined` are removed from the resulting bag; any
/// concrete value (including `0`, `''`, `false`) wins. Always returns
/// a fresh map so callers can store it without aliasing the input.
export function applyPrefsChanges(base: PrefsBag, changes: PrefsBag): PrefsBag {
	const merged: PrefsBag = { ...base };
	for (const [k, v] of Object.entries(changes)) {
		if (v === null || v === undefined) delete merged[k];
		else merged[k] = v;
	}
	return merged;
}
