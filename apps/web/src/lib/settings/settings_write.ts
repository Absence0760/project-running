/// The queue-or-surface policy behind the offline-first settings writes.
///
/// A settings write fails two materially different ways and the pending
/// queue must only ever replay one of them.
///
/// A TRANSPORT failure — offline, DNS, a proxy that answered with an HTML
/// error page — never reached PostgREST, so the write is still valid:
/// queue it and let a later `loadSettings` drain it. That is the
/// offline-first contract (decisions §79).
///
/// A REJECTION — an RLS denial, a CHECK violation, an expired JWT, an
/// unknown column — is PostgREST refusing this payload, and it will
/// refuse the identical payload again. Queueing one retries a doomed
/// write on every refresh behind a UI that says "Saved". These bags
/// carry `privacy_zones` and `safety_overdue_minutes`, so that lie is a
/// privacy/safety failure, not a lost nicety.
///
/// The two are told apart by the `code`: PostgREST answers a refusal
/// with structured JSON carrying a Postgres SQLSTATE (`42501`, `23514`,
/// `23502`) or a `PGRST*` code, and postgrest-js's own fetch catch —
/// plus any non-JSON error body it could not parse — arrives with no
/// code at all. An HTTP status is the fallback signal for the second
/// case: a 4xx/5xx with an unparseable body is still the server
/// answering, not the network dropping.

export type SettingsWriteFailure = 'transport' | 'rejected';

/// The shape of a `supabase-js` result, narrowed to the two fields the
/// classification reads.
export interface PostgrestFailure {
	error: { message?: string | null; code?: string | null } | null;
	status?: number;
}

function codeOf(result: PostgrestFailure): string {
	const raw = result.error?.code;
	return typeof raw === 'string' ? raw.trim() : '';
}

export function classifyWriteFailure(result: PostgrestFailure): SettingsWriteFailure {
	if (codeOf(result)) return 'rejected';
	if (typeof result.status === 'number' && result.status >= 400) return 'rejected';
	return 'transport';
}

export class SettingsWriteError extends Error {
	readonly failure: SettingsWriteFailure;
	readonly code: string;

	constructor(result: PostgrestFailure) {
		super(result.error?.message?.trim() || 'Settings write failed');
		this.name = 'SettingsWriteError';
		this.code = codeOf(result);
		this.failure = classifyWriteFailure(result);
	}
}

/// Anything that isn't a classified write failure is a bug in our own
/// code, not a network condition — surface it rather than silently
/// queueing it forever.
export function failureOf(err: unknown): SettingsWriteFailure {
	return err instanceof SettingsWriteError ? err.failure : 'rejected';
}

/// Attempt a write; queue it on a transport failure, undo the optimistic
/// local write and rethrow on a rejection so the caller can tell the user.
export async function pushOrQueue(effects: {
	push: () => Promise<void>;
	queue: () => void;
	rollback: () => void;
}): Promise<void> {
	try {
		await effects.push();
	} catch (err) {
		if (failureOf(err) === 'transport') {
			effects.queue();
			return;
		}
		effects.rollback();
		throw err;
	}
}

/// Replay a pending queue in order, returning what still hasn't been
/// sent. A rejected entry is dropped — it can never succeed, and leaving
/// it at the head blocks every later change behind it forever. A
/// transport failure stops the drain and keeps the rest of the queue in
/// order for the next attempt.
export async function drainQueue<T>(
	queue: readonly T[],
	push: (change: T) => Promise<void>,
): Promise<T[]> {
	for (let i = 0; i < queue.length; i++) {
		try {
			await push(queue[i]);
		} catch (err) {
			if (failureOf(err) === 'rejected') continue;
			return queue.slice(i);
		}
	}
	return [];
}
