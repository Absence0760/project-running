import { supabase } from './supabase';
import { effective, type LoadedSettings, type PrefsBag } from './settings_overlay';

/// Typed accessor for `user_settings` + `user_device_settings`.
///
/// The DB stores two opaque jsonb bags; this module is the only place that
/// knows how to merge them. Effective lookup order is:
///
///   1. device override (`user_device_settings.prefs`)
///   2. universal value (`user_settings.prefs`)
///   3. fallback supplied by the caller
///
/// Known keys are registered in `docs/settings.md`. The pure overlay
/// helpers (`effective`, `LoadedSettings`, `PrefsBag`) live in
/// `./settings_overlay` and are re-exported below so existing
/// `import { loadSettings, effective } from '$lib/settings'` callers
/// keep working unchanged.

export { effective };
export type { LoadedSettings, PrefsBag };

const DEVICE_ID_KEY = 'run_app.device_id';

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

export async function loadSettings(userId: string): Promise<LoadedSettings> {
	const deviceId = getDeviceId();

	const [universalRes, deviceRes] = await Promise.all([
		supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', userId)
			.maybeSingle(),
		supabase
			.from('user_device_settings')
			.select('prefs')
			.eq('user_id', userId)
			.eq('device_id', deviceId)
			.maybeSingle(),
	]);

	// Auto-provision empty rows on first access so later UPDATEs don't race
	// on insert.
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

	return {
		universal: (universalRes.data?.prefs as PrefsBag | null) ?? {},
		device: (deviceRes.data?.prefs as PrefsBag | null) ?? {},
	};
}

export async function updateUniversal(
	userId: string,
	changes: PrefsBag
): Promise<PrefsBag> {
	const { data } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	const merged: PrefsBag = { ...((data?.prefs as PrefsBag) ?? {}) };
	for (const [k, v] of Object.entries(changes)) {
		if (v === null || v === undefined) delete merged[k];
		else merged[k] = v;
	}
	await supabase
		.from('user_settings')
		.update({ prefs: merged, updated_at: new Date().toISOString() })
		.eq('user_id', userId);
	return merged;
}

export async function updateDevice(
	userId: string,
	changes: PrefsBag
): Promise<PrefsBag> {
	const deviceId = getDeviceId();
	const { data } = await supabase
		.from('user_device_settings')
		.select('prefs')
		.eq('user_id', userId)
		.eq('device_id', deviceId)
		.maybeSingle();
	const merged: PrefsBag = { ...((data?.prefs as PrefsBag) ?? {}) };
	for (const [k, v] of Object.entries(changes)) {
		if (v === null || v === undefined) delete merged[k];
		else merged[k] = v;
	}
	await supabase
		.from('user_device_settings')
		.update({ prefs: merged, updated_at: new Date().toISOString() })
		.eq('user_id', userId)
		.eq('device_id', deviceId);
	return merged;
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
