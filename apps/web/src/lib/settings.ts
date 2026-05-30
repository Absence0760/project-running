import { supabase } from './supabase';
import { effective, type LoadedSettings, type PrefsBag } from './settings_overlay';
import {
	InMemoryPrefsCache,
	LocalStoragePrefsCache,
	applyPrefsChanges,
	type PendingChange,
	type PrefsCache,
} from './settings_cache';

/// Typed accessor for `user_settings` + `user_device_settings`.
///
/// The DB stores two opaque jsonb bags; this module is the only place that
/// knows how to merge them. Effective lookup order is:
///
///   1. device override (`user_device_settings.prefs`)
///   2. universal value (`user_settings.prefs`)
///   3. fallback supplied by the caller
///
/// Known keys are registered in `docs/backend/settings.md`. The pure overlay
/// helpers (`effective`, `LoadedSettings`, `PrefsBag`) live in
/// `./settings_overlay`; the offline-first cache primitive lives in
/// `./settings_cache`. Both are re-exported below so existing
/// `import { loadSettings, effective } from '$lib/settings'` callers
/// keep working unchanged.

export { effective };
export type { LoadedSettings, PrefsBag };

const DEVICE_ID_KEY = 'run_app.device_id';

/// Module-level cache. `localStorage` on the client, in-memory on the
/// server (SSR / prerender). Exposed for tests via `__setCacheForTests`.
let cache: PrefsCache =
	typeof localStorage === 'undefined' ? new InMemoryPrefsCache() : new LocalStoragePrefsCache();

/** @internal — test seam */
export function __setCacheForTests(next: PrefsCache): void {
	cache = next;
}

/** @internal — test seam */
export function __resetCacheForTests(): void {
	cache =
		typeof localStorage === 'undefined' ? new InMemoryPrefsCache() : new LocalStoragePrefsCache();
}

/// Stable per-browser device identifier. Minted once and cached in
/// `localStorage` so a return visit in the same browser keeps the same
/// per-device preferences. Clearing site data resets it.
export function getDeviceId(): string {
	if (typeof localStorage === 'undefined') {
		// SSR / prerender — return a throwaway so imports don't crash. Any
		// actual read/write happens from the client after hydration.
		return 'ssr-placeholder';
	}
	const existing = localStorage.getItem(DEVICE_ID_KEY);
	if (existing) return existing;
	const minted = crypto.randomUUID();
	localStorage.setItem(DEVICE_ID_KEY, minted);
	return minted;
}

/// Drop every cached entry for [userId]. Wired into the auth store's
/// `logout()` so a subsequent sign-in as a different user on the same
/// browser can't read the previous user's bag.
export function dropUserCache(userId: string): void {
	cache.dropUser(userId);
}

/// Synchronous cache peek. Returns the cached bags (or empty bags if
/// the cache is cold) without touching the network. Useful for surfaces
/// that want to render bag-backed widgets before the `loadSettings`
/// promise resolves — e.g. the dashboard's Fitness / Intensity cards.
///
/// The hot path on a returning user gives accurate values immediately;
/// the cold path gives empty bags so `effective<T>` falls through to
/// the caller's fallback. The trailing `loadSettings(...)` call
/// reconciles with the server.
export function peekCachedSettings(userId: string): LoadedSettings {
	const deviceId = getDeviceId();
	const cachedU = cache.readUniversal(userId);
	const cachedD = cache.readDevice(userId, deviceId);
	return {
		universal: cachedU !== null ? { ...cachedU } : {},
		device: cachedD !== null ? { ...cachedD } : {},
	};
}

export async function loadSettings(userId: string): Promise<LoadedSettings> {
	const deviceId = getDeviceId();

	// Always attempt the server fetch so external mutations (mobile
	// edit, another tab, service-role write) are visible. The cache is
	// the offline-availability fallback: when the network fails we
	// return cached bags rather than throwing, so a signed-in offline
	// visit still gets a usable Settings + Dashboard. Writes use the
	// cache directly (write-through + pending queue in `updateUniversal`
	// / `updateDevice`), so an offline edit is never lost — it just
	// doesn't show up cross-device until the queue drains.
	try {
		const [universalRes, deviceRes] = await Promise.all([
			supabase.from('user_settings').select('prefs').eq('user_id', userId).maybeSingle(),
			supabase
				.from('user_device_settings')
				.select('prefs')
				.eq('user_id', userId)
				.eq('device_id', deviceId)
				.maybeSingle(),
		]);

		// Distinguish "row absent" (data: null, error: null) from
		// "network failed / RLS denied" (data: null, error: !=null).
		// supabase-js .maybeSingle() does NOT throw on transport
		// errors — it captures them in `error` and returns
		// `data: null`. Without this guard a route.abort or a
		// transient 5xx would look identical to "first sign-in,
		// auto-provision empty row", and the cache would be
		// overwritten with `{}` on every offline reload.
		if (universalRes.error || deviceRes.error) {
			throw universalRes.error ?? deviceRes.error;
		}

		// Auto-provision empty rows on first access so later UPDATEs
		// don't race on insert. Only fires when the read succeeded
		// AND returned no row — i.e. a true first-load, not a network
		// blip.
		if (!universalRes.data) {
			await supabase.from('user_settings').insert({ user_id: userId, prefs: {} });
		}
		if (!deviceRes.data) {
			await supabase.from('user_device_settings').insert({
				user_id: userId,
				device_id: deviceId,
				platform: detectPlatform(),
				label: deviceLabel(),
				prefs: {},
			});
		}

		const universal: PrefsBag = (universalRes.data?.prefs as PrefsBag | null) ?? {};
		const device: PrefsBag = (deviceRes.data?.prefs as PrefsBag | null) ?? {};

		cache.writeUniversal(userId, universal);
		cache.writeDevice(userId, deviceId, device);
		await drainPending(userId, deviceId);

		return { universal, device };
	} catch {
		// Network unreachable. Use cached bags so `effective<T>` lookups
		// resolve to the user's actual settings instead of falling
		// through to defaults that don't match reality. Cold-cache +
		// offline returns empty bags as the conservative default.
		const cachedU = cache.readUniversal(userId);
		const cachedD = cache.readDevice(userId, deviceId);
		return {
			universal: cachedU !== null ? { ...cachedU } : {},
			device: cachedD !== null ? { ...cachedD } : {},
		};
	}
}

export async function updateUniversal(userId: string, changes: PrefsBag): Promise<PrefsBag> {
	const deviceId = getDeviceId();

	// Read current cached bag; fall back to {} so an offline-first
	// write before any successful load still produces the right merged
	// shape locally.
	const base = cache.readUniversal(userId) ?? {};
	const merged = applyPrefsChanges(base, changes);
	cache.writeUniversal(userId, merged);

	try {
		await pushUniversal(userId, changes);
	} catch {
		// Server unreachable — queue the change verbatim so a future
		// `loadSettings` drains it against a fresh server bag. Storing
		// the *changes* (not the merged result) means a concurrent
		// write from another device isn't clobbered on replay.
		cache.appendPending(userId, deviceId, { isDevice: false, changes });
	}

	return merged;
}

export async function updateDevice(userId: string, changes: PrefsBag): Promise<PrefsBag> {
	const deviceId = getDeviceId();

	const base = cache.readDevice(userId, deviceId) ?? {};
	const merged = applyPrefsChanges(base, changes);
	cache.writeDevice(userId, deviceId, merged);

	try {
		await pushDevice(userId, deviceId, changes);
	} catch {
		cache.appendPending(userId, deviceId, { isDevice: true, changes });
	}

	return merged;
}

async function pushUniversal(userId: string, changes: PrefsBag): Promise<void> {
	// Read-merge-write against the server bag so a concurrent edit
	// from another device isn't silently overwritten.
	const { data, error } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	if (error) throw error;
	const merged = applyPrefsChanges((data?.prefs as PrefsBag) ?? {}, changes);
	const updRes = await supabase
		.from('user_settings')
		.update({ prefs: merged, updated_at: new Date().toISOString() })
		.eq('user_id', userId);
	if (updRes.error) throw updRes.error;
	// Stamp the cache with the canonical server-merged value so a
	// device with a stale base picks up the union, not just its own
	// delta.
	cache.writeUniversal(userId, merged);
}

async function pushDevice(userId: string, deviceId: string, changes: PrefsBag): Promise<void> {
	const { data, error } = await supabase
		.from('user_device_settings')
		.select('prefs')
		.eq('user_id', userId)
		.eq('device_id', deviceId)
		.maybeSingle();
	if (error) throw error;
	const merged = applyPrefsChanges((data?.prefs as PrefsBag) ?? {}, changes);
	const updRes = await supabase
		.from('user_device_settings')
		.update({ prefs: merged, updated_at: new Date().toISOString() })
		.eq('user_id', userId)
		.eq('device_id', deviceId);
	if (updRes.error) throw updRes.error;
	cache.writeDevice(userId, deviceId, merged);
}

async function drainPending(userId: string, deviceId: string): Promise<void> {
	const queue = cache.readPending(userId, deviceId);
	if (queue.length === 0) return;
	for (const change of queue) {
		try {
			if (change.isDevice) {
				await pushDevice(userId, deviceId, change.changes);
			} else {
				await pushUniversal(userId, change.changes);
			}
		} catch {
			// Stop draining on the first failure — preserving order so
			// a later successful drain replays the rest. Don't clear
			// the queue; the next refresh will retry.
			return;
		}
	}
	cache.clearPending(userId, deviceId);
}

function detectPlatform(): string {
	if (typeof navigator === 'undefined') return 'web';
	const ua = navigator.userAgent.toLowerCase();
	if (ua.includes('android')) return 'web-android';
	if (ua.includes('iphone') || ua.includes('ipad')) return 'web-ios';
	if (ua.includes('mac')) return 'web-mac';
	if (ua.includes('windows')) return 'web-windows';
	if (ua.includes('linux')) return 'web-linux';
	return 'web';
}

function deviceLabel(): string {
	if (typeof navigator === 'undefined') return 'Web';
	// Best-effort readable label — shown in the per-device list. Falls
	// back to a short UA fragment if the UA is unparseable.
	const ua = navigator.userAgent;
	const match = ua.match(/\(([^)]+)\)/);
	return match ? match[1].split(';')[0].trim() : 'Web';
}

// Re-exported so dependent callers (sign-out hook, tests) don't have
// to import from two modules.
export type { PendingChange };
