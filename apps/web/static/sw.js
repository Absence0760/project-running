/// Service worker for web push notifications.
///
/// Two events matter: `push` (incoming notification — render a system
/// toast) and `notificationclick` (user clicked it — focus or open the
/// app at the deep-link URL the payload carries).
///
/// Payload contract — what the sender (Edge Function in a follow-up
/// commit) is expected to POST through Web Push:
///
///   { title: string, body?: string, url?: string, tag?: string,
///     icon?: string, data?: object }
///
/// Anything else is ignored. Missing `title` falls back to "Better
/// Runner" so a malformed payload still surfaces something.

self.addEventListener('install', (event) => {
	// Activate as soon as the new SW is installed — don't wait for a
	// reload before push starts working.
	event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
	event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
	let payload = {};
	try {
		payload = event.data ? event.data.json() : {};
	} catch (_e) {
		// Some senders push plain text — preserve it as the body.
		try {
			payload = { body: event.data ? event.data.text() : '' };
		} catch (_e2) {
			payload = {};
		}
	}

	const title = payload.title || 'Better Runner';
	const options = {
		body: payload.body ?? '',
		icon: payload.icon || '/favicon.png',
		badge: payload.badge || '/favicon.png',
		tag: payload.tag,
		data: { url: payload.url || '/dashboard', ...(payload.data || {}) },
	};

	event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
	event.notification.close();
	const url = event.notification?.data?.url || '/dashboard';

	event.waitUntil(
		(async () => {
			// Focus an existing tab if one is already open at this URL,
			// otherwise open a new one. Falls back gracefully when the
			// browser denies focus (e.g. iOS Safari without user gesture).
			const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
			for (const c of clients) {
				if (c.url.includes(url) && 'focus' in c) {
					try {
						await c.focus();
						return;
					} catch (_) {
						/* fall through to openWindow */
					}
				}
			}
			if (self.clients.openWindow) {
				await self.clients.openWindow(url);
			}
		})(),
	);
});
