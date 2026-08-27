/// Service worker for web push notifications.
///
/// Two events matter: `push` (incoming notification — render a system
/// toast) and `notificationclick` (user clicked it — focus or open the
/// app at the deep-link URL the payload carries).
///
/// Payload contract — what the sender (the Go worker's `web_push` job
/// handler, apps/job_worker/internal/push_render.go) POSTs through Web Push:
///
///   { title: string, body?: string, url?: string, tag?: string,
///     icon?: string, badge?: string, data?: object }
///
/// Anything else is ignored. Missing `title` falls back to "Threkir"
/// so a malformed payload still surfaces something.

/**
 * @typedef {{ title?: string, body?: string, url?: string, tag?: string,
 *   icon?: string, badge?: string, data?: Record<string, unknown> }} PushPayload
 */

// `self` in a service worker is a ServiceWorkerGlobalScope; the WebWorker lib
// types the bare global as the narrower WorkerGlobalScope, which carries
// neither `clients` nor `registration`.
const sw = /** @type {ServiceWorkerGlobalScope} */ (/** @type {unknown} */ (self));

sw.addEventListener('install', (event) => {
	// Activate as soon as the new SW is installed — don't wait for a
	// reload before push starts working.
	event.waitUntil(sw.skipWaiting());
});

sw.addEventListener('activate', (event) => {
	event.waitUntil(sw.clients.claim());
});

sw.addEventListener('push', (event) => {
	/** @type {PushPayload} */
	let payload = {};
	try {
		payload = event.data ? event.data.json() : {};
	} catch {
		// Some senders push plain text — preserve it as the body.
		try {
			payload = { body: event.data ? event.data.text() : '' };
		} catch {
			payload = {};
		}
	}

	const title = payload.title || 'Threkir';
	const options = {
		body: payload.body ?? '',
		icon: payload.icon || '/favicon.png',
		badge: payload.badge || '/favicon.png',
		tag: payload.tag,
		data: { url: payload.url || '/dashboard', ...(payload.data || {}) },
	};

	event.waitUntil(sw.registration.showNotification(title, options));
});

sw.addEventListener('notificationclick', (event) => {
	event.notification.close();
	const url = event.notification?.data?.url || '/dashboard';

	event.waitUntil(
		(async () => {
			// Focus an existing tab if one is already open at this URL,
			// otherwise open a new one. Falls back gracefully when the
			// browser denies focus (e.g. iOS Safari without user gesture).
			const clients = await sw.clients.matchAll({ type: 'window', includeUncontrolled: true });
			for (const c of clients) {
				if (c.url.includes(url) && 'focus' in c) {
					try {
						await c.focus();
						return;
					} catch {
						/* fall through to openWindow */
					}
				}
			}
			if (sw.clients.openWindow) {
				await sw.clients.openWindow(url);
			}
		})(),
	);
});
