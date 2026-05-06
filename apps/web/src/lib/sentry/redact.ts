// Pure helpers for stripping Supabase Storage signed-URL tokens
// before they land in a Sentry breadcrumb / span / event. Extracted
// from `apps/web/src/hooks.client.ts` so the logic can be unit-
// tested under `tsx --test` (the hooks file imports `$app/environment`
// + `$env/dynamic/public`, which are SvelteKit-only).
//
// Signed URLs embed an HMAC token in the query that grants access to
// a bucket object; we don't want them in the error-reporting tail.
// Match is broad — "/storage/v1/object/sign/" anywhere in the URL —
// so it covers run-photos and any future private bucket.

export function redactSignedUrl(url: string): string {
	if (!url.includes('/storage/v1/object/sign/')) return url;
	const q = url.indexOf('?');
	return q === -1 ? url : url.slice(0, q) + '?<redacted>';
}

export function redactBreadcrumb<
	T extends { category?: string; message?: string; data?: Record<string, unknown> },
>(b: T): T {
	const u = b.data?.url;
	if (typeof u === 'string') {
		b.data!.url = redactSignedUrl(u);
	}
	// `console` breadcrumbs carry the log message in `message` and
	// `data.arguments`. apps/web/src/lib/data.ts logs Storage paths via
	// console.warn on delete-failure paths; redact any occurrence of a
	// signed-URL substring.
	if (b.category === 'console' && typeof b.message === 'string') {
		b.message = redactSignedUrl(b.message);
	}
	return b;
}

export interface SentrySpanLike {
	data?: Record<string, unknown>;
}
export interface SentryEventWithSpans {
	transaction?: string;
	spans?: SentrySpanLike[];
	request?: { url?: string };
}

export function redactEventSignedUrls(event: SentryEventWithSpans): SentryEventWithSpans {
	if (typeof event.transaction === 'string') {
		event.transaction = redactSignedUrl(event.transaction);
	}
	if (event.request?.url) {
		event.request.url = redactSignedUrl(event.request.url);
	}
	if (Array.isArray(event.spans)) {
		for (const s of event.spans) {
			const u = s.data?.url;
			if (typeof u === 'string') {
				s.data!.url = redactSignedUrl(u);
			}
		}
	}
	return event;
}
