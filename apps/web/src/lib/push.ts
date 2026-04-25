/// Web push subscription helpers.
///
/// Stores the subscription on `user_device_settings.prefs.push_subscription`
/// keyed by the browser's persistent device id (`getDeviceId()`). That
/// table is already row-per-device and RLS-scoped to the user, so
/// no schema change is needed; revoking a device on `/settings/devices`
/// also wipes its push registration.
///
/// Server-side push delivery (the Edge Function that POSTs payloads
/// through Web Push) is intentionally out of scope here — it needs
/// the matching VAPID private key, which only you can generate.
/// The subscribe path works end-to-end without it; the Edge Function
/// is a follow-up.

import { env } from '$env/dynamic/public';
import { supabase } from './supabase';
import { auth } from './stores/auth.svelte';
import { getDeviceId } from './settings';

// Pulled via dynamic env so the build doesn't fail when the key
// isn't set — the UI then renders the "not configured" hint.
const PUBLIC_VAPID_PUBLIC_KEY = env.PUBLIC_VAPID_PUBLIC_KEY ?? '';

export interface StoredPushSubscription {
	endpoint: string;
	keys: { p256dh: string; auth: string };
	registered_at: string;
}

/// Whether the current browser exposes Push + Notification APIs and
/// the build was given a `PUBLIC_VAPID_PUBLIC_KEY`. Both gates must
/// be true before the UI offers a subscribe button.
export function isPushSupported(): boolean {
	if (typeof window === 'undefined') return false;
	if (!('serviceWorker' in navigator)) return false;
	if (!('PushManager' in window)) return false;
	if (!('Notification' in window)) return false;
	return !!PUBLIC_VAPID_PUBLIC_KEY;
}

/// Read the current `Notification.permission` — `default` (never
/// asked), `granted`, or `denied`. Used to decide whether to show
/// "Enable" vs "Already on" vs "Blocked — change in browser settings".
export function pushPermission(): NotificationPermission | 'unsupported' {
	if (typeof Notification === 'undefined') return 'unsupported';
	return Notification.permission;
}

/// Register `/sw.js` if it isn't already, and return the active
/// registration. Idempotent — repeat calls reuse the existing one.
async function registerServiceWorker(): Promise<ServiceWorkerRegistration> {
	const existing = await navigator.serviceWorker.getRegistration('/');
	if (existing) return existing;
	return await navigator.serviceWorker.register('/sw.js', { scope: '/' });
}

/// Convert the URL-safe-base64 VAPID public key the sender configured
/// into the `Uint8Array` shape `pushManager.subscribe` expects.
function urlBase64ToUint8Array(input: string): Uint8Array {
	const padding = '='.repeat((4 - (input.length % 4)) % 4);
	const base64 = (input + padding).replace(/-/g, '+').replace(/_/g, '/');
	const raw = atob(base64);
	const out = new Uint8Array(raw.length);
	for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
	return out;
}

/// Subscribe to push if not already, persist the subscription onto
/// `user_device_settings.prefs.push_subscription`, and return the
/// stored shape. Throws on permission denial or registration error
/// so the caller can surface a toast.
export async function subscribeToPush(): Promise<StoredPushSubscription> {
	if (!isPushSupported()) throw new Error('Push not supported on this build');
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const reg = await registerServiceWorker();

	let sub = await reg.pushManager.getSubscription();
	if (!sub) {
		const permission = await Notification.requestPermission();
		if (permission !== 'granted') {
			throw new Error(permission === 'denied' ? 'Notifications blocked in browser' : 'Permission not granted');
		}
		sub = await reg.pushManager.subscribe({
			userVisibleOnly: true,
			applicationServerKey: urlBase64ToUint8Array(PUBLIC_VAPID_PUBLIC_KEY),
		});
	}

	const json = sub.toJSON() as PushSubscriptionJSON;
	const stored: StoredPushSubscription = {
		endpoint: json.endpoint!,
		keys: {
			p256dh: json.keys?.p256dh ?? '',
			auth: json.keys?.auth ?? '',
		},
		registered_at: new Date().toISOString(),
	};

	await persistSubscription(userId, stored);
	return stored;
}

/// Drop the local subscription + clear the entry from device prefs.
/// Best-effort — failures only log because the user's intent is "stop
/// receiving" and a stale row in the table is harmless until the next
/// expiry.
export async function unsubscribeFromPush(): Promise<void> {
	const userId = auth.user?.id;
	if (!('serviceWorker' in navigator) || !userId) return;
	const reg = await navigator.serviceWorker.getRegistration('/');
	const sub = await reg?.pushManager.getSubscription();
	if (sub) {
		try {
			await sub.unsubscribe();
		} catch (e) {
			console.warn('push unsubscribe failed', e);
		}
	}
	try {
		await persistSubscription(userId, null);
	} catch (e) {
		console.warn('push subscription clear failed', e);
	}
}

/// Whether this browser/device currently has a saved subscription.
/// The PushManager reflects the OS-level state; we trust it over our
/// stored copy in case the user purged browser data.
export async function getCurrentSubscription(): Promise<PushSubscription | null> {
	if (!('serviceWorker' in navigator)) return null;
	const reg = await navigator.serviceWorker.getRegistration('/');
	return (await reg?.pushManager.getSubscription()) ?? null;
}

async function persistSubscription(
	userId: string,
	sub: StoredPushSubscription | null,
): Promise<void> {
	const deviceId = getDeviceId();
	// Read–merge–write to avoid clobbering other prefs on the row.
	const { data: existing } = await supabase
		.from('user_device_settings')
		.select('prefs')
		.eq('user_id', userId)
		.eq('device_id', deviceId)
		.maybeSingle();
	const prefs: Record<string, unknown> = (existing?.prefs as Record<string, unknown>) ?? {};
	if (sub) prefs.push_subscription = sub;
	else delete prefs.push_subscription;
	await supabase
		.from('user_device_settings')
		.upsert(
			{
				user_id: userId,
				device_id: deviceId,
				prefs,
				updated_at: new Date().toISOString(),
			},
			{ onConflict: 'user_id,device_id' },
		);
}
