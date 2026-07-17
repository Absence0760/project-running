/// Web push subscription helpers (client subscribe/unsubscribe leg).
///
/// Stores the subscription on `user_device_settings.prefs.push_subscription`
/// keyed by the browser's persistent device id (`getDeviceId()`). That
/// table is already row-per-device and RLS-scoped to the user, so
/// no schema change is needed; revoking a device on `/settings/devices`
/// also wipes its push registration. Writes go through the atomic
/// `set_push_subscription` RPC (migration 20270419_001) — a single-key
/// jsonb_set/minus on the row — so persisting a subscription can never
/// clobber the device's other prefs the way a whole-bag read-merge-write
/// could (issue #235), and its result is checked so a failed registration
/// surfaces to the caller instead of leaving the toggle lying.
///
/// Server-side delivery (the other leg) ships in the Go worker's `web_push`
/// job handler (apps/job_worker/internal/handler_web_push.go, migration
/// 20261219_001): the notifications AFTER INSERT trigger enqueues one
/// `web_push` job per recipient who has a subscription, the handler reads THIS
/// row's `endpoint` + `keys.{p256dh,auth}`, and POSTs an encrypted Web Push
/// message (RFC 8291) signed with the operator's VAPID private key (the
/// private half of `PUBLIC_VAPID_PUBLIC_KEY`). Keep `StoredPushSubscription`
/// in lockstep with that handler's `FetchPushSubscriptions` projection.

import { env } from '$env/dynamic/public';
import { supabase } from '../core/supabase';
import { auth } from '../stores/auth.svelte';
import { detectPlatform, deviceLabel, getDeviceId } from '../settings/settings';
import type { Json } from '../database.types';

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
/// stored shape. Throws on permission denial, registration error, or a
/// failed server persist so the caller can surface a toast — a
/// subscription the server never learned about would deliver nothing
/// while the toggle claims push is on.
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
			// TS 6 widened Uint8Array.buffer to ArrayBufferLike; pushManager
			// accepts BufferSource which requires the concrete ArrayBuffer
			// shape. The runtime value is a real ArrayBuffer-backed view.
			applicationServerKey: urlBase64ToUint8Array(PUBLIC_VAPID_PUBLIC_KEY) as BufferSource,
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

	await persistSubscription(stored);
	return stored;
}

/// Drop the local subscription + clear the entry from device prefs.
/// The browser-side unsubscribe stays best-effort (a dead endpoint
/// self-prunes when the worker's send 404/410s), but the server-side
/// clear throws on failure so the caller can surface it — the enqueue
/// trigger keys off the stored row, so a stale registration keeps
/// manufacturing doomed web_push jobs until it's actually cleared.
export async function unsubscribeFromPush(): Promise<void> {
	if (!('serviceWorker' in navigator) || !auth.user?.id) return;
	const reg = await navigator.serviceWorker.getRegistration('/');
	const sub = await reg?.pushManager.getSubscription();
	if (sub) {
		try {
			await sub.unsubscribe();
		} catch (e) {
			console.warn('push unsubscribe failed', e);
		}
	}
	await persistSubscription(null);
}

/// Whether this browser/device currently has a saved subscription.
/// The PushManager reflects the OS-level state; we trust it over our
/// stored copy in case the user purged browser data.
export async function getCurrentSubscription(): Promise<PushSubscription | null> {
	if (!('serviceWorker' in navigator)) return null;
	const reg = await navigator.serviceWorker.getRegistration('/');
	return (await reg?.pushManager.getSubscription()) ?? null;
}

async function persistSubscription(sub: StoredPushSubscription | null): Promise<void> {
	const { error } = await supabase.rpc('set_push_subscription', {
		p_device_id: getDeviceId(),
		p_subscription: sub as unknown as Json,
		p_platform: detectPlatform(),
		p_label: deviceLabel(),
	});
	if (error) throw error;
}
